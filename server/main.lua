-- timeclock/server/main.lua

-- ─────────────────────────────────────────────────────────
--  Debug helper
-- ─────────────────────────────────────────────────────────

local function debugPrint(...)
    if Config.Debug then
        local args = { ... }
        for i, v in ipairs(args) do args[i] = tostring(v) end
        print('[timeclock][SERVER] ' .. table.concat(args, ' '))
    end
end

local playerCitizenids = {} -- { [src] = citizenid }

local function getPlayerData(src)
    local player = exports.qbx_core:GetPlayer(src)
    if not player then
        debugPrint('getPlayerData: GetPlayer returned nil for src =', src)
        return nil
    end
    local pd = player.PlayerData
    if pd and src and not playerCitizenids[src] then
        playerCitizenids[src] = pd.citizenid
        debugPrint('playerCitizenids: auto-cached', pd.citizenid, 'for src', src)
    end
    return pd
end

local function findOnlineSource(targetCitizenid)
    debugPrint('findOnlineSource: searching for citizenid =', targetCitizenid)
    for _, playerId in ipairs(GetPlayers()) do
        local tpd = getPlayerData(tonumber(playerId))
        if tpd and tpd.citizenid == targetCitizenid then
            debugPrint('findOnlineSource: found src =', playerId, 'for', targetCitizenid)
            return tonumber(playerId)
        end
    end
    debugPrint('findOnlineSource: not online —', targetCitizenid)
    return nil
end

local function isInMulticharacter(src)
    local ok, result = pcall(function()
        return exports[Config.multiCharacter]:isPlayerInsideMulticharacter(src)
    end)
    local inMulti = ok and result == true
    debugPrint('isInMulticharacter: src =', src, '| result =', tostring(inMulti), '| pcall ok =', tostring(ok))
    return inMulti
end

local function secondsToHMS(secs)
    secs = math.floor(secs or 0)
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    local s = secs % 60
    return string.format('%02dh %02dm %02ds', h, m, s)
end

local function toUnix(dtStr)
    if not dtStr then return os.time() end
    if type(dtStr) == 'number' then return math.floor(dtStr / 1000) end
    local y,mo,d,h,mi,s = dtStr:match('(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)')
    if not y then
        debugPrint('toUnix: failed to parse datetime string =', tostring(dtStr))
        return os.time()
    end
    return os.time({
        year  = tonumber(y),
        month = tonumber(mo),
        day   = tonumber(d),
        hour  = tonumber(h),
        min   = tonumber(mi),
        sec   = tonumber(s),
    })
end

-- ─────────────────────────────────────────────────────────
--  Multijob data
-- ─────────────────────────────────────────────────────────

local function getMultijobData(citizenid)
    debugPrint('getMultijobData: fetching for citizenid =', citizenid)
    if not Config.Multijob or not Config.Multijob.enabled then
        debugPrint('getMultijobData: multijob disabled — returning empty')
        return {}
    end

    local ok, result = pcall(function()
        return exports['ps-multijob']:GetJobs(citizenid)
    end)

    if ok and result and type(result) == 'table' then
        local jobs = {}
        for _, entry in ipairs(result) do
            if entry.job then
                jobs[entry.job] = tonumber(entry.grade) or 0
                debugPrint('getMultijobData: ps-multijob export —', entry.job, 'grade =', jobs[entry.job])
            end
        end
        debugPrint('getMultijobData: ps-multijob export returned', #result, 'job(s) for', citizenid)
        return jobs
    else
        debugPrint('getMultijobData: ps-multijob export failed or no result — falling back to DB query. pcall ok =', tostring(ok))
    end

    local tbl     = Config.Multijob.table
    local cidCol  = Config.Multijob.citizenidColumn
    local dataCol = Config.Multijob.dataColumn

    debugPrint('getMultijobData: querying table =', tbl, 'cidCol =', cidCol, 'dataCol =', dataCol)

    local dbOk, dbResult = pcall(function()
        return exports.oxmysql:executeSync(
            ('SELECT `%s` FROM `%s` WHERE `%s` = ? LIMIT 1'):format(dataCol, tbl, cidCol),
            { citizenid }
        )
    end)

    if not dbOk then
        print(('[timeclock] WARNING: multijob query failed for %s'):format(citizenid))
        debugPrint('getMultijobData: DB query pcall failed for', citizenid)
        return {}
    end

    if not dbResult or not dbResult[1] or not dbResult[1][dataCol] then
        debugPrint('getMultijobData: DB returned no rows or empty dataCol for', citizenid)
        return {}
    end

    local decodeOk, decoded = pcall(json.decode, dbResult[1][dataCol])
    if not decodeOk or type(decoded) ~= 'table' then
        debugPrint('getMultijobData: json.decode failed for', citizenid)
        return {}
    end

    local jobs = {}
    for jobName, grade in pairs(decoded) do
        jobs[jobName] = tonumber(grade) or 0
        debugPrint('getMultijobData: DB fallback —', jobName, 'grade =', jobs[jobName])
    end
    debugPrint('getMultijobData: DB fallback complete for', citizenid)
    return jobs
end

local function getAllPlayerJobGrades(pd)
    debugPrint('getAllPlayerJobGrades: building job grades for citizenid =', pd.citizenid)
    local grades = {}

    if pd.job and pd.job.name then
        grades[pd.job.name] = pd.job.grade and pd.job.grade.level or 0
        debugPrint('getAllPlayerJobGrades: primary job =', pd.job.name, 'grade =', grades[pd.job.name])
    else
        debugPrint('getAllPlayerJobGrades: no primary job in PlayerData')
    end

    local mjData = getMultijobData(pd.citizenid)
    for jobName, grade in pairs(mjData) do
        if not grades[jobName] then
            grades[jobName] = grade
            debugPrint('getAllPlayerJobGrades: added from multijob —', jobName, 'grade =', grade)
        else
            debugPrint('getAllPlayerJobGrades: skipped multijob —', jobName, '(primary job grade takes priority)')
        end
    end

    return grades
end

local function gradeIsBoss(jobName, gradeLevel)
    local result = exports.qbx_core:IsGradeBoss(jobName, gradeLevel)
    debugPrint('gradeIsBoss:', jobName, 'gradeLevel =', gradeLevel, '| isBoss =', tostring(result))
    return result
end

local function checkIsBoss(pd, job)
    if not Config.Jobs[job] then
        debugPrint('checkIsBoss: job not configured —', job)
        return false
    end

    local grade = nil
    if pd.job and pd.job.name == job then
        grade = pd.job.grade and pd.job.grade.level or 0
        debugPrint('checkIsBoss: grade from primary job =', grade, 'for', job)
    else
        local mjData = getMultijobData(pd.citizenid)
        grade = mjData[job]
        debugPrint('checkIsBoss: grade from multijob =', tostring(grade), 'for', job)
    end

    if grade == nil then
        debugPrint('checkIsBoss: grade is nil — not boss for', job)
        return false
    end

    local result = exports.qbx_core:IsGradeBoss(job, grade)
    debugPrint('checkIsBoss:', job, 'grade =', grade, '| isBoss =', tostring(result))
    return result
end

local function getConfiguredJobNames(pd)
    local allGrades = getAllPlayerJobGrades(pd)
    local result    = {}
    for jobName, _ in pairs(allGrades) do
        if Config.Jobs[jobName] then
            result[#result + 1] = jobName
            debugPrint('getConfiguredJobNames: included job =', jobName)
        else
            debugPrint('getConfiguredJobNames: skipped (not in Config.Jobs) =', jobName)
        end
    end
    debugPrint('getConfiguredJobNames: total configured jobs =', #result, 'for', pd.citizenid)
    return result
end

-- ─────────────────────────────────────────────────────────
--  Discord Webhook
-- ─────────────────────────────────────────────────────────

local function sendWebhook(webhook, embed)
    debugPrint('sendWebhook: firing to webhook (title =', tostring(embed and embed.title), ')')
    PerformHttpRequest(webhook, function() end, 'POST',
        json.encode({ embeds = { embed } }),
        { ['Content-Type'] = 'application/json' }
    )
end

local function sendMail(citizenid, sender, subject, message)
    if not Config.Mail or not Config.Mail.enabled then
        debugPrint('sendMail: mail disabled — skipping for', citizenid)
        return
    end
    debugPrint('sendMail: sending to', citizenid, 'subject =', subject)
    exports[Config.Mail.resource]:sendNewMailToOffline(citizenid, {
        sender  = sender  or Config.Mail.defaultSender,
        subject = subject,
        message = message,
    })
end

local function buildEmbed(title, description, color, fields)
    debugPrint('buildEmbed: title =', title)
    local embed = {
        title       = title,
        description = description,
        color       = color,
        timestamp   = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        footer      = { text = '• Time Clock •' },
    }
    if fields then embed.fields = fields end
    return embed
end

-- ─────────────────────────────────────────────────────────
--  DB helpers
-- ─────────────────────────────────────────────────────────

local function isPlayerClockedIn(citizenid, job)
    debugPrint('isPlayerClockedIn: checking citizenid =', citizenid, 'job =', job)
    local result = exports.oxmysql:executeSync(
        'SELECT id FROM timeclock_sessions WHERE citizenid = ? AND job = ? AND clock_out IS NULL LIMIT 1',
        { citizenid, job }
    )
    local sessionId = result and result[1] and result[1].id or nil
    debugPrint('isPlayerClockedIn: result =', tostring(sessionId))
    return sessionId
end

local function getTotalSeconds(citizenid, job)
    debugPrint('getTotalSeconds: citizenid =', citizenid, 'job =', job)
    local result = exports.oxmysql:executeSync(
        'SELECT COALESCE(SUM(duration_secs), 0) AS total FROM timeclock_sessions WHERE citizenid = ? AND job = ? AND clock_out IS NOT NULL',
        { citizenid, job }
    )
    local total = (result and result[1] and tonumber(result[1].total)) or 0
    debugPrint('getTotalSeconds: total =', total, 'secs for', citizenid, job)
    return total
end

local function getPlaytimeMinutes(citizenid, job)
    debugPrint('getPlaytimeMinutes: citizenid =', citizenid, 'job =', job)
    local result = exports.oxmysql:executeSync(
        'SELECT total_minutes FROM job_playtime WHERE citizenid = ? AND job = ? LIMIT 1',
        { citizenid, job }
    )
    local mins = (result and result[1] and tonumber(result[1].total_minutes)) or 0
    debugPrint('getPlaytimeMinutes: total =', mins, 'min for', citizenid, job)
    return mins
end

local function getWeeklySeconds(citizenid, job)
    debugPrint('getWeeklySeconds: citizenid =', citizenid, 'job =', job)
    local result = exports.oxmysql:executeSync([[
        SELECT COALESCE(SUM(duration_secs), 0) AS weekly
        FROM timeclock_sessions
        WHERE citizenid = ?
          AND job = ?
          AND clock_out IS NOT NULL
          AND clock_in >= DATE(NOW() - INTERVAL WEEKDAY(NOW()) DAY)
    ]], { citizenid, job })
    local secs = (result and result[1] and tonumber(result[1].weekly)) or 0
    debugPrint('getWeeklySeconds: weekly =', secs, 'secs for', citizenid, job)
    return secs
end

local function getLastClockIn(citizenid, job)
    debugPrint('getLastClockIn: citizenid =', citizenid, 'job =', job)
    local result = exports.oxmysql:executeSync([[
        SELECT clock_in FROM timeclock_sessions
        WHERE citizenid = ? AND job = ?
        ORDER BY clock_in DESC LIMIT 1
    ]], { citizenid, job })
    local val = result and result[1] and result[1].clock_in or nil
    debugPrint('getLastClockIn: result =', tostring(val))
    return val
end

local function getClockInTime(citizenid, job)
    debugPrint('getClockInTime: citizenid =', citizenid, 'job =', job)
    local result = exports.oxmysql:executeSync(
        'SELECT id, clock_in FROM timeclock_sessions WHERE citizenid = ? AND job = ? AND clock_out IS NULL LIMIT 1',
        { citizenid, job }
    )
    if result and result[1] then
        debugPrint('getClockInTime: open session found id =', result[1].id, 'clock_in =', tostring(result[1].clock_in))
        return result[1].id, result[1].clock_in
    end
    debugPrint('getClockInTime: no open session for', citizenid, job)
    return nil, nil
end

-- ─────────────────────────────────────────────────────────
--  Auto close open sessions
-- ─────────────────────────────────────────────────────────

local function closeOpenSessions(citizenid)
        if not Config.AutoClock then return end

    debugPrint('closeOpenSessions: checking for open sessions —', citizenid)
    local openSessions = exports.oxmysql:executeSync([[
        SELECT job, clock_in FROM timeclock_sessions
        WHERE citizenid = ? AND clock_out IS NULL
    ]], { citizenid })

    if not openSessions or #openSessions == 0 then
        debugPrint('closeOpenSessions: no open sessions found for', citizenid)
    else
        debugPrint('closeOpenSessions: found', #openSessions, 'open session(s) for', citizenid)
    end

    exports.oxmysql:execute([[
        UPDATE timeclock_sessions
        SET clock_out = NOW(),
            duration_secs = TIMESTAMPDIFF(SECOND, clock_in, NOW())
        WHERE citizenid = ? AND clock_out IS NULL
    ]], { citizenid })

    for _, session in ipairs(openSessions or {}) do
        debugPrint('closeOpenSessions: closing session for job =', session.job, 'clock_in =', tostring(session.clock_in))
        local cfg = Config.Jobs[session.job]
        if cfg then
            local total = getTotalSeconds(citizenid, session.job)
            local hms   = secondsToHMS(total)
            sendWebhook(cfg.webhook, buildEmbed(
                '🔴 Shift Auto-Ended — ' .. cfg.label,
                ('**%s** was automatically clocked out (disconnect/multicharacter) | Total: **%s**'):format(citizenid, hms),
                Config.Colors.clockOut
            ))
            sendMail(citizenid, Config.Mail.senders.clockOut,
                '🔴 Shift Auto-Ended — ' .. cfg.label,
                ('Your shift for **%s** was automatically ended due to disconnecting.\n\nTotal hours on record: **%s**'):format(cfg.label, hms)
            )
        else
            debugPrint('closeOpenSessions: job', session.job, 'not in Config.Jobs — skipping webhook/mail')
        end
    end

    print(('[timeclock] Auto closed open sessions for %s'):format(citizenid))
end

AddEventHandler('qbx_core:server:playerLoggedOut', function(src)
        if not Config.AutoClock then return end

    debugPrint('event: qbx_core:server:playerLoggedOut | src =', src)
    if isInMulticharacter(src) then
        debugPrint('playerLoggedOut: src', src, 'is in multicharacter — skipping closeOpenSessions')
        return
    end
    local pd = getPlayerData(src)
    if not pd then
        debugPrint('playerLoggedOut: no PlayerData for src', src, '— skipping')
        return
    end
    debugPrint('playerLoggedOut: closing open sessions for', pd.citizenid)
    closeOpenSessions(pd.citizenid)
end)

AddEventHandler('playerDropped', function()
    local src = source
    debugPrint('event: playerDropped | src =', src)

    local citizenid = playerCitizenids[src]
    if citizenid then
        debugPrint('playerDropped: closing open sessions for cached citizenid', citizenid)
        closeOpenSessions(citizenid)
        playerCitizenids[src] = nil
        return
    end

    debugPrint('playerDropped: no cached citizenid — trying GetOfflinePlayer')
    local ok, result = pcall(function()
        return exports.qbx_core:GetOfflinePlayer(src)
    end)
    if ok and result and result.PlayerData and Config.AutoClock then
        if not isInMulticharacter(src) then
            debugPrint('playerDropped: closing open sessions for', result.PlayerData.citizenid)
            closeOpenSessions(result.PlayerData.citizenid)
        else
            debugPrint('playerDropped: src', src, 'in multicharacter — skipping')
        end
    else
        debugPrint('playerDropped: GetOfflinePlayer failed or no PlayerData | pcall ok =', tostring(ok))
    end
end)


-- ─────────────────────────────────────────────────────────
--  ps-multijob: auto clock out old job on job swap
-- ─────────────────────────────────────────────────────────

AddEventHandler('ps-multijob:server:JobChanged', function(src, newJob, oldJob)
        if not Config.AutoClock then return end  -- ADD THIS
    debugPrint('event: ps-multijob:server:JobChanged | src =', src, '| oldJob =', tostring(oldJob), '| newJob =', tostring(newJob))
    local pd = getPlayerData(src)
    if not pd then
        debugPrint('JobChanged: no PlayerData for src', src, '— skipping')
        return
    end
    if isInMulticharacter(src) then
        debugPrint('JobChanged: src', src, 'in multicharacter — skipping')
        return
    end

    if oldJob and Config.Jobs[oldJob] then
        local sessionId, _ = getClockInTime(pd.citizenid, oldJob)
        if sessionId then
            debugPrint('JobChanged: clocking out of old job =', oldJob, 'sessionId =', sessionId)
            exports.oxmysql:execute(
                'UPDATE timeclock_sessions SET clock_out = NOW(), duration_secs = TIMESTAMPDIFF(SECOND, clock_in, NOW()), forced_by = COALESCE(forced_by, ?) WHERE id = ?',
                { 'job_swap', sessionId }
            )
            local totalSecs = getTotalSeconds(pd.citizenid, oldJob)
            local hms       = secondsToHMS(totalSecs)
            local cfg       = Config.Jobs[oldJob]
            local name      = pd.charinfo and (pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname) or pd.citizenid
            debugPrint('JobChanged: old job clock-out total =', hms, 'for', pd.citizenid)
            TriggerClientEvent('ox_lib:notify', src, {
                type        = 'inform',
                description = ('Auto clocked out of %s. Total: %s'):format(cfg.label, hms),
                duration    = 5000,
            })
            TriggerClientEvent('timeclock:client:updateStatus', src, oldJob, false)
            sendWebhook(cfg.webhook, buildEmbed(
                '🔄 Job Swap — Shift Ended — ' .. cfg.label,
                ('**%s** clocked out of %s (job swap) | Total: **%s**'):format(name, cfg.label, hms),
                Config.Colors.clockOut,
                {
                    { name = 'CitizenID',  value = pd.citizenid,                          inline = true  },
                    { name = 'Swapped to', value = newJob or 'unknown',                   inline = true  },
                    { name = 'Time',       value = ('<t:%d:t>'):format(os.time()),         inline = true  },
                    { name = 'Total',      value = hms,                                   inline = false },
                }
            ))
        else
            debugPrint('JobChanged: no open session for old job =', oldJob, '— skipping clock out')
        end
    else
        debugPrint('JobChanged: oldJob not configured or nil —', tostring(oldJob))
    end

    if newJob and Config.Jobs[newJob] then
        if not isPlayerClockedIn(pd.citizenid, newJob) then
            debugPrint('JobChanged: clocking in to new job =', newJob)
            exports.oxmysql:execute(
                'INSERT INTO timeclock_sessions (citizenid, job, clock_in, forced_by) VALUES (?, ?, NOW(), ?)',
                { pd.citizenid, newJob, 'job_swap' }
            )
            local cfg  = Config.Jobs[newJob]
            local name = pd.charinfo and (pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname) or pd.citizenid
            TriggerClientEvent('ox_lib:notify', src, {
                type        = 'success',
                description = ('Auto clocked in to %s.'):format(cfg.label),
                duration    = 5000,
            })
            TriggerClientEvent('timeclock:client:updateStatus', src, newJob, true)
            sendWebhook(cfg.webhook, buildEmbed(
                '🔄 Job Swap — Shift Started — ' .. cfg.label,
                ('**%s** clocked in to %s (job swap)'):format(name, cfg.label),
                Config.Colors.clockIn,
                {
                    { name = 'CitizenID',    value = pd.citizenid,                   inline = true },
                    { name = 'Swapped from', value = oldJob or 'unknown',            inline = true },
                    { name = 'Time',         value = ('<t:%d:t>'):format(os.time()),  inline = true },
                }
            ))
        else
            debugPrint('JobChanged: player already clocked in to new job =', newJob, '— skipping auto clock in')
        end
    else
        debugPrint('JobChanged: newJob not configured or nil —', tostring(newJob))
    end
end)

-- ─────────────────────────────────────────────────────────
--  Clock In
-- ─────────────────────────────────────────────────────────

RegisterNetEvent('timeclock:server:clockIn', function(job, forcedBy)
    local src = source
    debugPrint('event: timeclock:server:clockIn | src =', src, '| job =', job, '| forcedBy =', tostring(forcedBy))
    local pd  = getPlayerData(src)
    if not pd then
        debugPrint('clockIn: no PlayerData for src', src, '— aborting')
        return
    end
    if isInMulticharacter(src) then
        debugPrint('clockIn: src', src, 'in multicharacter — aborting')
        return
    end

    local citizenid = pd.citizenid
    local name      = pd.charinfo and (pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname) or citizenid

    if not Config.Jobs[job] then
        debugPrint('clockIn: job not configured —', job)
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = Config.Locale.noJob })
        return
    end

    if isPlayerClockedIn(citizenid, job) then
        debugPrint('clockIn: player already clocked in — citizenid =', citizenid, 'job =', job)
        TriggerClientEvent('ox_lib:notify', src, { type = 'warning', description = Config.Locale.alreadyClockedIn })
        return
    end

    debugPrint('clockIn: inserting session for', citizenid, 'job =', job)
    exports.oxmysql:execute(
        'INSERT INTO timeclock_sessions (citizenid, job, clock_in, forced_by) VALUES (?, ?, NOW(), ?)',
        { citizenid, job, forcedBy or nil }
    )

    TriggerClientEvent('ox_lib:notify', src, { type = 'success', description = Config.Locale.clockedIn })
    TriggerClientEvent('timeclock:client:updateStatus', src, job, true)

    local cfg = Config.Jobs[job]
    sendWebhook(cfg.webhook, buildEmbed(
        '🟢 Shift Started',
        ('**%s** has clocked **in** for %s'):format(name, cfg.label),
        Config.Colors.clockIn,
        {
            { name = 'CitizenID', value = citizenid,                        inline = true },
            { name = 'Job',       value = cfg.label,                        inline = true },
            { name = 'Time',      value = ('<t:%d:t>'):format(os.time()),    inline = true },
        }
    ))
    print(('[timeclock] %s clocked IN for %s%s'):format(citizenid, job, forcedBy and (' (forced by '..forcedBy..')') or ''))
end)

-- ─────────────────────────────────────────────────────────
--  Clock Out
-- ─────────────────────────────────────────────────────────

RegisterNetEvent('timeclock:server:clockOut', function(job, forcedBy)
    local src = source
    debugPrint('event: timeclock:server:clockOut | src =', src, '| job =', job, '| forcedBy =', tostring(forcedBy))
    local pd  = getPlayerData(src)
    if not pd then
        debugPrint('clockOut: no PlayerData for src', src, '— aborting')
        return
    end
    if isInMulticharacter(src) then
        debugPrint('clockOut: src', src, 'in multicharacter — aborting')
        return
    end

    local citizenid = pd.citizenid
    local name      = pd.charinfo and (pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname) or citizenid

    if not Config.Jobs[job] then
        debugPrint('clockOut: job not configured —', job)
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = Config.Locale.noJob })
        return
    end

    local sessionId, _ = getClockInTime(citizenid, job)
    if not sessionId then
        debugPrint('clockOut: no open session — citizenid =', citizenid, 'job =', job)
        TriggerClientEvent('ox_lib:notify', src, { type = 'warning', description = Config.Locale.notClockedIn })
        return
    end

    debugPrint('clockOut: closing sessionId =', sessionId, 'for', citizenid, job)
    exports.oxmysql:execute(
        'UPDATE timeclock_sessions SET clock_out = NOW(), duration_secs = TIMESTAMPDIFF(SECOND, clock_in, NOW()), forced_by = COALESCE(forced_by, ?) WHERE id = ?',
        { forcedBy or nil, sessionId }
    )

    local totalSecs = getTotalSeconds(citizenid, job)
    local hms       = secondsToHMS(totalSecs)
    debugPrint('clockOut: session closed, total =', hms, 'for', citizenid, job)

    TriggerClientEvent('ox_lib:notify', src, {
        type        = 'inform',
        description = string.format(Config.Locale.clockedOut, hms),
        duration    = 6000,
    })
    TriggerClientEvent('timeclock:client:updateStatus', src, job, false)

    local cfg = Config.Jobs[job]
    sendWebhook(cfg.webhook, buildEmbed(
        '🔴 Shift Ended',
        ('**%s** has clocked **out** for %s'):format(name, cfg.label),
        Config.Colors.clockOut,
        {
            { name = 'CitizenID',                  value = citizenid,                        inline = true  },
            { name = 'Job',                        value = cfg.label,                        inline = true  },
            { name = 'Session End',                value = ('<t:%d:t>'):format(os.time()),    inline = true  },
            { name = 'Total Hours (All Sessions)', value = hms,                              inline = false },
        }
    ))
    sendMail(citizenid, Config.Mail.senders.clockOut,
        '🔴 Shift Ended — ' .. cfg.label,
        ('You have clocked out of **%s**.\n\nTotal hours on record: **%s**'):format(cfg.label, hms)
    )
    print(('[timeclock] %s clocked OUT for %s (total %s)%s'):format(citizenid, job, hms, forcedBy and (' (forced by '..forcedBy..')') or ''))
end)

-- ─────────────────────────────────────────────────────────
--  Callback: boss status per job
-- ─────────────────────────────────────────────────────────

lib.callback.register('timeclock:getBossStatus', function(source)
    debugPrint('callback: getBossStatus | src =', source)
    local pd = getPlayerData(source)
    if not pd then
        debugPrint('getBossStatus: no PlayerData — returning empty')
        return {}
    end

    local result  = {}
    local allJobs = {}

    if pd.job and pd.job.name then
        allJobs[pd.job.name] = pd.job.grade and pd.job.grade.level or 0
        debugPrint('getBossStatus: primary job =', pd.job.name, 'grade =', allJobs[pd.job.name])
    end

    if Config.Multijob.enabled then
        local mjData = getMultijobData(pd.citizenid)
        for jobName, grade in pairs(mjData) do
            if allJobs[jobName] == nil then
                allJobs[jobName] = grade
                debugPrint('getBossStatus: added from multijob —', jobName, 'grade =', grade)
            end
        end
    else
        debugPrint('getBossStatus: multijob disabled — only primary job checked')
    end

    for jobName, grade in pairs(allJobs) do
        if Config.Jobs[jobName] then
            local boss = gradeIsBoss(jobName, grade)
            result[jobName] = boss
            debugPrint('getBossStatus: result —', jobName, '=', tostring(boss))
        else
            debugPrint('getBossStatus: skipped (not in Config.Jobs) —', jobName)
        end
    end

    return result
end)

-- ─────────────────────────────────────────────────────────
--  Callback: clock status for all player's configured jobs
-- ─────────────────────────────────────────────────────────

lib.callback.register('timeclock:getMyStatus', function(source)
    debugPrint('callback: getMyStatus | src =', source)
    local pd = getPlayerData(source)
    if not pd then
        debugPrint('getMyStatus: no PlayerData — returning empty')
        return {}
    end

    local jobs   = getConfiguredJobNames(pd)
    local status = {}
    debugPrint('getMyStatus: building status for', #jobs, 'job(s)')
    for _, j in ipairs(jobs) do
        local sessionId, clockInTime = getClockInTime(pd.citizenid, j)
        local totalSecs = getTotalSeconds(pd.citizenid, j)
        status[j] = {
            clockedIn   = sessionId ~= nil,
            clockInTime = clockInTime,
            totalSecs   = totalSecs,
        }
        debugPrint('getMyStatus:', j, '| clockedIn =', tostring(sessionId ~= nil), '| totalSecs =', totalSecs)
    end
    return status
end)

-- ─────────────────────────────────────────────────────────
--  Shared: fetch employee list
-- ─────────────────────────────────────────────────────────

local function fetchEmployees(job)
    debugPrint('fetchEmployees: job =', job)
    local mjTbl  = Config.Multijob.table
    local mjCid  = Config.Multijob.citizenidColumn
    local mjData = Config.Multijob.dataColumn

    local empResult = exports.oxmysql:executeSync(([[
        SELECT DISTINCT p.citizenid, p.charinfo
        FROM players p
        WHERE JSON_UNQUOTE(JSON_EXTRACT(p.job, '$.name')) = ?
           OR EXISTS (
               SELECT 1 FROM `%s` mj
               WHERE mj.`%s` = p.citizenid
               AND JSON_CONTAINS_PATH(mj.`%s`, 'one', CONCAT('$.', ?))
           )
    ]]):format(mjTbl, mjCid, mjData), { job, job })

    if not empResult or #empResult == 0 then
        debugPrint('fetchEmployees: no employees found for job =', job)
        return {}
    end

    debugPrint('fetchEmployees: found', #empResult, 'employee row(s) for job =', job)

    local employees = {}
    for _, row in ipairs(empResult) do
        local cid = row.citizenid
        debugPrint('fetchEmployees: processing citizenid =', cid)

        local totalResult = exports.oxmysql:executeSync(
            'SELECT COALESCE(SUM(duration_secs), 0) AS total FROM timeclock_sessions WHERE citizenid = ? AND job = ? AND clock_out IS NOT NULL',
            { cid, job }
        )
        local totalSecs    = tonumber(totalResult and totalResult[1] and totalResult[1].total) or 0
        local weeklySecs   = getWeeklySeconds(cid, job)
        local playtimeMins = getPlaytimeMinutes(cid, job)

        local openResult = exports.oxmysql:executeSync(
            'SELECT id, clock_in FROM timeclock_sessions WHERE citizenid = ? AND job = ? AND clock_out IS NULL LIMIT 1',
            { cid, job }
        )
        local clockedIn      = openResult and openResult[1] ~= nil
        local currentClockIn = clockedIn and openResult[1].clock_in or nil
        local lastClockIn    = getLastClockIn(cid, job)

        local ok, charinfo = pcall(json.decode, row.charinfo or '{}')
        local name = (ok and charinfo and charinfo.firstname)
            and (charinfo.firstname .. ' ' .. charinfo.lastname)
            or cid

        debugPrint('fetchEmployees:', cid, '| name =', name, '| clockedIn =', tostring(clockedIn), '| totalSecs =', totalSecs, '| weeklySecs =', weeklySecs, '| playtimeMins =', playtimeMins)

        employees[#employees + 1] = {
            citizenid      = cid,
            name           = name,
            totalSecs      = totalSecs,
            totalHMS       = secondsToHMS(totalSecs),
            weeklySecs     = weeklySecs,
            weeklyHMS      = secondsToHMS(weeklySecs),
            playtimeMins   = playtimeMins,
            clockedIn      = clockedIn,
            currentClockIn = currentClockIn,
            lastClockIn    = lastClockIn,
        }
    end

    debugPrint('fetchEmployees: returning', #employees, 'employee(s) for job =', job)
    return employees
end

-- ─────────────────────────────────────────────────────────
--  Callback: employee list for boss menus
-- ─────────────────────────────────────────────────────────

lib.callback.register('timeclock:getEmployees', function(source, job)
    debugPrint('callback: getEmployees | src =', source, '| job =', job)
    local pd  = getPlayerData(source)
    local cfg = Config.Jobs[job]
    if not pd or not cfg then
        debugPrint('getEmployees: no PlayerData or job not configured — returning empty')
        return {}
    end
    if not checkIsBoss(pd, job) then
        debugPrint('getEmployees: src', source, 'is not boss of', job, '— returning empty')
        return {}
    end
    return fetchEmployees(job)
end)

-- ─────────────────────────────────────────────────────────
--  Management: Adjust employee time
-- ─────────────────────────────────────────────────────────

RegisterNetEvent('timeclock:server:adjustTime', function(job, targetCitizenid, action, seconds)
    local src = source
    debugPrint('event: adjustTime | src =', src, '| job =', job, '| target =', targetCitizenid, '| action =', action, '| seconds =', tostring(seconds))
    local pd  = getPlayerData(src)
    if not pd or not Config.Jobs[job] then
        debugPrint('adjustTime: no PlayerData or job not configured — aborting')
        return
    end
    if not checkIsBoss(pd, job) then
        debugPrint('adjustTime: src', src, 'is not boss of', job, '— aborting')
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = Config.Locale.noBossPerms })
        return
    end

    seconds = tonumber(seconds) or 0
    if seconds <= 0 or seconds > (99 * 3600 + 59 * 60) then
        debugPrint('adjustTime: invalid seconds value =', seconds)
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Invalid time value.' })
        return
    end

    local bossName = pd.charinfo and (pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname) or pd.citizenid
    local cfg      = Config.Jobs[job]

    if action == 'add' then
        debugPrint('adjustTime: adding', seconds, 'secs to', targetCitizenid, 'for job =', job)
        exports.oxmysql:execute(
            'INSERT INTO timeclock_sessions (citizenid, job, clock_in, clock_out, duration_secs, forced_by) VALUES (?, ?, NOW(), NOW(), ?, ?)',
            { targetCitizenid, job, seconds, pd.citizenid }
        )
    elseif action == 'deduct' then
        debugPrint('adjustTime: deducting', seconds, 'secs from', targetCitizenid, 'for job =', job)
        local sessions = exports.oxmysql:executeSync(
            'SELECT id, duration_secs FROM timeclock_sessions WHERE citizenid = ? AND job = ? AND clock_out IS NOT NULL AND duration_secs > 0 ORDER BY clock_in ASC',
            { targetCitizenid, job }
        )

        debugPrint('adjustTime: found', sessions and #sessions or 0, 'deductible session(s)')
        local remaining = seconds
        for _, session in ipairs(sessions or {}) do
            if remaining <= 0 then break end
            local dur = tonumber(session.duration_secs) or 0
            if dur <= remaining then
                debugPrint('adjustTime: deleting session id =', session.id, 'dur =', dur)
                exports.oxmysql:execute('DELETE FROM timeclock_sessions WHERE id = ?', { session.id })
                remaining = remaining - dur
            else
                debugPrint('adjustTime: partial deduct from session id =', session.id, 'dur =', dur, 'deducting =', remaining)
                exports.oxmysql:execute(
                    'UPDATE timeclock_sessions SET duration_secs = duration_secs - ? WHERE id = ?',
                    { remaining, session.id }
                )
                remaining = 0
            end
        end

        if remaining > 0 then
            debugPrint('adjustTime: could not deduct full amount — short by', remaining, 'secs')
            TriggerClientEvent('ox_lib:notify', src, {
                type        = 'warning',
                description = ('Deducted all available time. %s short by %s.'):format(targetCitizenid, secondsToHMS(remaining)),
            })
        end
    else
        debugPrint('adjustTime: unknown action =', tostring(action))
    end

    local newTotal = getTotalSeconds(targetCitizenid, job)
    local hms      = secondsToHMS(seconds)
    local newHMS   = secondsToHMS(newTotal)
    debugPrint('adjustTime: complete — new total for', targetCitizenid, '=', newHMS)

    TriggerClientEvent('ox_lib:notify', src, {
        type        = 'success',
        description = ('%s %s for %s. New total: %s'):format(
            action == 'add' and 'Added' or 'Deducted', hms, targetCitizenid, newHMS
        ),
        duration    = 6000,
    })

    local targetSrc = findOnlineSource(targetCitizenid)
    if targetSrc then
        debugPrint('adjustTime: notifying target src =', targetSrc)
        TriggerClientEvent('ox_lib:notify', targetSrc, {
            type        = 'inform',
            description = ('Your timesheet was adjusted: %s %s by management. New total: %s'):format(
                action == 'add' and '+' or '-', hms, newHMS
            ),
            duration    = 8000,
        })
    else
        debugPrint('adjustTime: target not online — skipping notify')
    end

    sendWebhook(cfg.webhook, buildEmbed(
        (action == 'add' and '➕ Time Added' or '➖ Time Deducted') .. ' — ' .. cfg.label,
        ('**%s** %s **%s** %s timesheet by **%s** | New total: **%s**'):format(
            targetCitizenid,
            action == 'add' and 'had' or 'had',
            hms,
            action == 'add' and 'added to' or 'deducted from',
            bossName,
            newHMS
        ),
        action == 'add' and Config.Colors.clockIn or Config.Colors.clockOut
    ))
    sendMail(targetCitizenid, Config.Mail.senders.timeAdjust,
        (action == 'add' and '➕ Time Added' or '➖ Time Deducted') .. ' — ' .. cfg.label,
        ('Your timesheet for **%s** has been adjusted by management.\n\n%s **%s**\nNew total: **%s**'):format(
            cfg.label,
            action == 'add' and 'Added:' or 'Deducted:',
            hms,
            newHMS
        )
    )
end)

-- ─────────────────────────────────────────────────────────
--  /timecheck [id]
-- ─────────────────────────────────────────────────────────

local function handleTimecheck(src, targetId)
    debugPrint('handleTimecheck: src =', src, '| targetId =', tostring(targetId))
    local pd = getPlayerData(src)
    if not pd then
        debugPrint('handleTimecheck: no PlayerData for src', src)
        return
    end

    local bossJobs = {}
    for _, j in ipairs(getConfiguredJobNames(pd)) do
        if checkIsBoss(pd, j) then
            bossJobs[#bossJobs + 1] = j
            debugPrint('handleTimecheck: src', src, 'is boss of', j)
        end
    end

    if #bossJobs == 0 then
        debugPrint('handleTimecheck: no boss jobs for src', src)
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = Config.Locale.noBossPerms })
        return
    end

    local targetPd = getPlayerData(targetId)
    if not targetPd then
        debugPrint('handleTimecheck: target src', targetId, 'not found or offline')
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Player not found or not online.' })
        return
    end

    local targetName = targetPd.charinfo
        and (targetPd.charinfo.firstname .. ' ' .. targetPd.charinfo.lastname)
        or targetPd.citizenid

    debugPrint('handleTimecheck: checking', targetName, '(', targetPd.citizenid, ') across', #bossJobs, 'boss job(s)')

    local lines = {}
    for _, j in ipairs(bossJobs) do
        local total              = getTotalSeconds(targetPd.citizenid, j)
        local sessionId, cinTime = getClockInTime(targetPd.citizenid, j)
        local statusStr          = sessionId and ('✅ Since ' .. (cinTime or '?')) or '❌ Not clocked in'
        lines[#lines + 1] = ('[%s] %s | Total: %s'):format(Config.Jobs[j].label, statusStr, secondsToHMS(total))
        debugPrint('handleTimecheck:', j, '| clockedIn =', tostring(sessionId ~= nil), '| total =', secondsToHMS(total))
    end

    TriggerClientEvent('ox_lib:notify', src, {
        type        = 'inform',
        title       = 'Time Check: ' .. targetName,
        description = table.concat(lines, '\n'),
        duration    = 10000,
    })
end

RegisterCommand('timecheck', function(src, args)
    debugPrint('command: timecheck | src =', src, '| args =', tostring(args[1]))
    local targetId = tonumber(args[1])
    if not targetId then
        debugPrint('timecheck: no valid targetId provided')
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Usage: /timecheck [player id]' })
        return
    end
    handleTimecheck(src, targetId)
end, false)

RegisterNetEvent('timeclock:server:timecheckTarget', function(targetId)
    debugPrint('event: timeclock:server:timecheckTarget | src =', source, '| targetId =', tostring(targetId))
    handleTimecheck(source, targetId)
end)

-- ─────────────────────────────────────────────────────────
--  Management: Send total hours webhook
-- ─────────────────────────────────────────────────────────

RegisterNetEvent('timeclock:server:sendTotalHours', function(job)
    local src = source
    debugPrint('event: sendTotalHours | src =', src, '| job =', job)
    local pd  = getPlayerData(src)
    if not pd or not Config.Jobs[job] then
        debugPrint('sendTotalHours: no PlayerData or job not configured — aborting')
        return
    end
    if not checkIsBoss(pd, job) then
        debugPrint('sendTotalHours: src', src, 'is not boss of', job, '— aborting')
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = Config.Locale.noBossPerms })
        return
    end

    local cfg       = Config.Jobs[job]
    local employees = fetchEmployees(job)

    if not employees or #employees == 0 then
        debugPrint('sendTotalHours: no employees found for job =', job)
        TriggerClientEvent('ox_lib:notify', src, { type = 'warning', description = 'No employee records found.' })
        return
    end

    debugPrint('sendTotalHours: building report for', #employees, 'employee(s) — job =', job)

    local bossName = pd.charinfo and (pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname) or pd.citizenid
    local now      = os.time()
    local embeds   = {}

    embeds[#embeds + 1] = {
        title       = '📋 ' .. cfg.label .. ' — Hours Report',
        description = ('Requested by **%s** | Generated <t:%d:F>'):format(bossName, now),
        color       = Config.Colors.totalHours,
        footer      = { text = 'Silver Cloud RP • Time Clock' },
        timestamp   = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    }

    for i, emp in ipairs(employees) do
        if i > 9 then
            debugPrint('sendTotalHours: truncating at 9 employees (Discord embed limit)')
            break
        end

        local statusStr
        if emp.clockedIn and emp.currentClockIn then
            statusStr = ('🟢 On Duty since <t:%d:t>'):format(toUnix(emp.currentClockIn))
        else
            statusStr = '⚫ Off Duty'
        end

        local lastInStr = '—'
        if emp.lastClockIn then
            local ts = toUnix(emp.lastClockIn)
            lastInStr = ('<t:%d:t> — <t:%d:d>'):format(ts, ts)
        end

        debugPrint('sendTotalHours: embed', i, '—', emp.name, '| status =', statusStr, '| weekly =', emp.weeklyHMS, '| total =', emp.totalHMS)

        embeds[#embeds + 1] = {
            color  = emp.clockedIn and Config.Colors.clockIn or 8421504,
            fields = {
                { name = '👤 Employee',                value = emp.name,          inline = true  },
                { name = '🪪 CitizenID',                value = emp.citizenid,     inline = true  },
                { name = '📡 Status',                   value = statusStr,         inline = false },
                { name = '⏱ This Week',                 value = emp.weeklyHMS,     inline = true  },
                { name = '📅 Sessions Total',           value = emp.totalHMS,      inline = true  },
                { name = '🌐 Online as Job (All Time)', value = ('%dh %02dm'):format(math.floor(emp.playtimeMins / 60), emp.playtimeMins % 60), inline = true },
                { name = '🕐 Last Clock In',            value = lastInStr,         inline = false },
            },
        }
    end

    PerformHttpRequest(cfg.webhook, function() end, 'POST',
        json.encode({ embeds = embeds }),
        { ['Content-Type'] = 'application/json' }
    )
    debugPrint('sendTotalHours: webhook fired for job =', job)
    TriggerClientEvent('ox_lib:notify', src, { type = 'success', description = 'Hours report sent to Discord.' })
end)

-- ─────────────────────────────────────────────────────────
--  Management: Reset all clocks
-- ─────────────────────────────────────────────────────────

RegisterNetEvent('timeclock:server:resetClocks', function(job)
    local src = source
    debugPrint('event: resetClocks | src =', src, '| job =', job)
    local pd  = getPlayerData(src)
    if not pd or not Config.Jobs[job] then
        debugPrint('resetClocks: no PlayerData or job not configured — aborting')
        return
    end
    if not checkIsBoss(pd, job) then
        debugPrint('resetClocks: src', src, 'is not boss of', job, '— aborting')
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = Config.Locale.noBossPerms })
        return
    end

    debugPrint('resetClocks: closing open sessions then deleting all for job =', job)
    exports.oxmysql:execute(
        'UPDATE timeclock_sessions SET clock_out = NOW(), duration_secs = TIMESTAMPDIFF(SECOND, clock_in, NOW()) WHERE job = ? AND clock_out IS NULL',
        { job }
    )
    exports.oxmysql:execute('DELETE FROM timeclock_sessions WHERE job = ?', { job })

    local cfg      = Config.Jobs[job]
    local bossName = pd.charinfo and (pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname) or pd.citizenid
    sendWebhook(cfg.webhook, buildEmbed(
        '🔄 Clock Reset — ' .. cfg.label,
        ('All time clocks for **%s** reset to zero by **%s**'):format(cfg.label, bossName),
        Config.Colors.reset
    ))
    TriggerClientEvent('ox_lib:notify', src, { type = 'success', description = Config.Locale.resetDone })
    print(('[timeclock] %s reset all clocks for job: %s'):format(pd.citizenid, job))
end)

-- ─────────────────────────────────────────────────────────
--  Management: Force clock in/out
-- ─────────────────────────────────────────────────────────

RegisterNetEvent('timeclock:server:forceClockIn', function(job, targetCitizenid)
    local src = source
    debugPrint('event: forceClockIn | src =', src, '| job =', job, '| target =', targetCitizenid)
    local pd  = getPlayerData(src)
    if not pd or not Config.Jobs[job] then
        debugPrint('forceClockIn: no PlayerData or job not configured — aborting')
        return
    end
    if not checkIsBoss(pd, job) then
        debugPrint('forceClockIn: src', src, 'is not boss of', job, '— aborting')
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = Config.Locale.noBossPerms })
        return
    end

    if isPlayerClockedIn(targetCitizenid, job) then
        debugPrint('forceClockIn: target already clocked in —', targetCitizenid, job)
        TriggerClientEvent('ox_lib:notify', src, { type = 'warning', description = 'That employee is already clocked in.' })
        return
    end

    debugPrint('forceClockIn: inserting session for', targetCitizenid, 'job =', job, 'forced_by =', pd.citizenid)
    exports.oxmysql:execute(
        'INSERT INTO timeclock_sessions (citizenid, job, clock_in, forced_by) VALUES (?, ?, NOW(), ?)',
        { targetCitizenid, job, pd.citizenid }
    )

    local targetSrc = findOnlineSource(targetCitizenid)
    if targetSrc then
        debugPrint('forceClockIn: notifying target src =', targetSrc)
        TriggerClientEvent('ox_lib:notify', targetSrc, { type = 'inform', description = Config.Locale.forceClockIn })
        TriggerClientEvent('timeclock:client:updateStatus', targetSrc, job, true)
    else
        debugPrint('forceClockIn: target not online — skipping notify')
    end

    TriggerClientEvent('ox_lib:notify', src, { type = 'success', description = 'Employee force clocked in.' })

    local cfg      = Config.Jobs[job]
    local bossName = pd.charinfo and (pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname) or pd.citizenid
    sendWebhook(cfg.webhook, buildEmbed(
        '🟣 Force Clock In — ' .. cfg.label,
        ('**%s** was force clocked in by **%s**'):format(targetCitizenid, bossName),
        Config.Colors.forceAction
    ))
end)

RegisterNetEvent('timeclock:server:forceClockOut', function(job, targetCitizenid)
    local src = source
    debugPrint('event: forceClockOut | src =', src, '| job =', job, '| target =', targetCitizenid)
    local pd  = getPlayerData(src)
    if not pd or not Config.Jobs[job] then
        debugPrint('forceClockOut: no PlayerData or job not configured — aborting')
        return
    end
    if not checkIsBoss(pd, job) then
        debugPrint('forceClockOut: src', src, 'is not boss of', job, '— aborting')
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = Config.Locale.noBossPerms })
        return
    end

    local sessionId, _ = getClockInTime(targetCitizenid, job)
    if not sessionId then
        debugPrint('forceClockOut: no open session for', targetCitizenid, job)
        TriggerClientEvent('ox_lib:notify', src, { type = 'warning', description = 'That employee is not clocked in.' })
        return
    end

    debugPrint('forceClockOut: closing sessionId =', sessionId, 'for', targetCitizenid, job)
    exports.oxmysql:execute(
        'UPDATE timeclock_sessions SET clock_out = NOW(), duration_secs = TIMESTAMPDIFF(SECOND, clock_in, NOW()), forced_by = ? WHERE id = ?',
        { pd.citizenid, sessionId }
    )

    local targetSrc = findOnlineSource(targetCitizenid)
    if targetSrc then
        debugPrint('forceClockOut: notifying target src =', targetSrc)
        TriggerClientEvent('ox_lib:notify', targetSrc, { type = 'inform', description = Config.Locale.forceClockOut })
        TriggerClientEvent('timeclock:client:updateStatus', targetSrc, job, false)
    else
        debugPrint('forceClockOut: target not online — skipping notify')
    end

    TriggerClientEvent('ox_lib:notify', src, { type = 'success', description = 'Employee force clocked out.' })

    local cfg      = Config.Jobs[job]
    local bossName = pd.charinfo and (pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname) or pd.citizenid
    local total    = getTotalSeconds(targetCitizenid, job)
    local totalHMS = secondsToHMS(total)
    debugPrint('forceClockOut: total after close =', totalHMS, 'for', targetCitizenid)

    sendWebhook(cfg.webhook, buildEmbed(
        '🟣 Force Clock Out — ' .. cfg.label,
        ('**%s** force clocked out by **%s** | Total: %s'):format(targetCitizenid, bossName, totalHMS),
        Config.Colors.forceAction
    ))
    sendMail(targetCitizenid, Config.Mail.senders.forceClockOut,
        '🟣 Force Clocked Out — ' .. cfg.label,
        ('You were force clocked out of **%s** by management.\n\nTotal hours on record: **%s**'):format(cfg.label, totalHMS)
    )
end)

-- ─────────────────────────────────────────────────────────
--  Console command: generatereports
-- ─────────────────────────────────────────────────────────

RegisterCommand('generatereports', function(source, args)
    if source ~= 0 then
        print('[timeclock] generatereports can only be run from the server console.')
        return
    end

    print('[timeclock] Generating reports for all configured jobs...')
    debugPrint('generatereports: starting run')

    local now = os.time()

    for jobName, cfg in pairs(Config.Jobs) do
        debugPrint('generatereports: processing job =', jobName)
        local employees = fetchEmployees(jobName)

        if not employees or #employees == 0 then
            print(('[timeclock] %s — no employees found, skipping.'):format(jobName))
            debugPrint('generatereports: no employees for', jobName, '— skipping')
        else
            print(('[timeclock] %s — sending report for %d employee(s)...'):format(jobName, #employees))
            debugPrint('generatereports: building embeds for', #employees, 'employee(s) —', jobName)

            local embeds = {}

            embeds[#embeds + 1] = {
                title       = '📋 ' .. cfg.label .. ' — Scheduled Hours Report',
                description = ('Auto-generated | <t:%d:F>'):format(now),
                color       = Config.Colors.totalHours,
                footer      = { text = 'Silver Cloud RP • Time Clock' },
                timestamp   = os.date('!%Y-%m-%dT%H:%M:%SZ'),
            }

            for i, emp in ipairs(employees) do
                if i > 9 then
                    print(('[timeclock] %s — more than 9 employees, truncated to first 9 in this batch.'):format(jobName))
                    debugPrint('generatereports: truncating at 9 for', jobName)
                    break
                end

                local statusStr
                if emp.clockedIn and emp.currentClockIn then
                    statusStr = ('🟢 On Duty since <t:%d:t>'):format(toUnix(emp.currentClockIn))
                else
                    statusStr = '⚫ Off Duty'
                end

                local lastInStr = '—'
                if emp.lastClockIn then
                    local ts = toUnix(emp.lastClockIn)
                    lastInStr = ('<t:%d:t> — <t:%d:d>'):format(ts, ts)
                end

                debugPrint('generatereports: embed', i, '—', emp.name, '| weekly =', emp.weeklyHMS, '| total =', emp.totalHMS)

                embeds[#embeds + 1] = {
                    color  = emp.clockedIn and Config.Colors.clockIn or 8421504,
                    fields = {
                        { name = '👤 Employee',                value = emp.name,      inline = true  },
                        { name = '🪪 CitizenID',                value = emp.citizenid, inline = true  },
                        { name = '📡 Status',                   value = statusStr,     inline = false },
                        { name = '⏱ This Week',                 value = emp.weeklyHMS, inline = true  },
                        { name = '📅 Sessions Total',           value = emp.totalHMS,  inline = true  },
                        { name = '🌐 Online as Job (All Time)', value = ('%dh %02dm'):format(math.floor(emp.playtimeMins / 60), emp.playtimeMins % 60), inline = true },
                        { name = '🕐 Last Clock In',            value = lastInStr,     inline = false },
                    },
                }
            end

            PerformHttpRequest(cfg.webhook, function(statusCode)
                if statusCode == 204 then
                    print(('[timeclock] %s — report sent successfully.'):format(jobName))
                    debugPrint('generatereports: webhook 204 OK for', jobName)
                else
                    print(('[timeclock] %s — webhook returned status %s, check the URL.'):format(jobName, tostring(statusCode)))
                    debugPrint('generatereports: webhook returned', statusCode, 'for', jobName)
                end
            end, 'POST',
                json.encode({ embeds = embeds }),
                { ['Content-Type'] = 'application/json' }
            )
        end

        Wait(1500)
    end

    print('[timeclock] All reports dispatched.')
    debugPrint('generatereports: complete')
end, true)

-- ─────────────────────────────────────────────────────────
--  Exports
-- ─────────────────────────────────────────────────────────

exports('ClockIn', function(citizenid, job, forcedBy)
    debugPrint('export: ClockIn | citizenid =', citizenid, '| job =', job, '| forcedBy =', tostring(forcedBy))
    if not Config.Jobs[job] then
        debugPrint('export ClockIn: job not configured —', job)
        return false, 'job not configured'
    end
    if isPlayerClockedIn(citizenid, job) then
        debugPrint('export ClockIn: already clocked in —', citizenid, job)
        return false, 'already clocked in'
    end

    exports.oxmysql:execute(
        'INSERT INTO timeclock_sessions (citizenid, job, clock_in, forced_by) VALUES (?, ?, NOW(), ?)',
        { citizenid, job, forcedBy or nil }
    )

    local cfg = Config.Jobs[job]
    local src = findOnlineSource(citizenid)
    if src then
        TriggerClientEvent('ox_lib:notify', src, { type = 'success', description = Config.Locale.clockedIn })
        TriggerClientEvent('timeclock:client:updateStatus', src, job, true)
    end

    sendWebhook(cfg.webhook, buildEmbed(
        '🟢 Shift Started',
        ('**%s** clocked in for %s'):format(citizenid, cfg.label),
        Config.Colors.clockIn,
        {
            { name = 'CitizenID', value = citizenid,                           inline = true },
            { name = 'Job',       value = cfg.label,                           inline = true },
            { name = 'Time',      value = ('<t:%d:t>'):format(os.time()),       inline = true },
            { name = 'Source',    value = forcedBy or 'external',              inline = true },
        }
    ))

    print(('[timeclock] [export] %s clocked IN for %s (by %s)'):format(citizenid, job, forcedBy or 'external'))
    return true
end)

exports('ClockOut', function(citizenid, job, forcedBy)
    debugPrint('export: ClockOut | citizenid =', citizenid, '| job =', job, '| forcedBy =', tostring(forcedBy))
    if not Config.Jobs[job] then
        debugPrint('export ClockOut: job not configured —', job)
        return false, 'job not configured'
    end

    local sessionId, _ = getClockInTime(citizenid, job)
    if not sessionId then
        debugPrint('export ClockOut: not clocked in —', citizenid, job)
        return false, 'not clocked in'
    end

    exports.oxmysql:execute(
        'UPDATE timeclock_sessions SET clock_out = NOW(), duration_secs = TIMESTAMPDIFF(SECOND, clock_in, NOW()), forced_by = COALESCE(forced_by, ?) WHERE id = ?',
        { forcedBy or nil, sessionId }
    )

    local totalSecs = getTotalSeconds(citizenid, job)
    local hms       = secondsToHMS(totalSecs)
    local cfg       = Config.Jobs[job]
    local src       = findOnlineSource(citizenid)
    debugPrint('export ClockOut: session closed, total =', hms)

    if src then
        TriggerClientEvent('ox_lib:notify', src, {
            type        = 'inform',
            description = string.format(Config.Locale.clockedOut, hms),
            duration    = 6000,
        })
        TriggerClientEvent('timeclock:client:updateStatus', src, job, false)
    end

    sendWebhook(cfg.webhook, buildEmbed(
        '🔴 Shift Ended',
        ('**%s** clocked out of %s | Total: **%s**'):format(citizenid, cfg.label, hms),
        Config.Colors.clockOut,
        {
            { name = 'CitizenID',   value = citizenid,                          inline = true  },
            { name = 'Job',         value = cfg.label,                          inline = true  },
            { name = 'Time',        value = ('<t:%d:t>'):format(os.time()),      inline = true  },
            { name = 'Source',      value = forcedBy or 'external',             inline = true  },
            { name = 'Total Hours', value = hms,                                inline = false },
        }
    ))

    print(('[timeclock] [export] %s clocked OUT for %s (by %s) total %s'):format(citizenid, job, forcedBy or 'external', hms))
    return true, hms
end)

exports('IsClockedIn', function(citizenid, job)
    debugPrint('export: IsClockedIn | citizenid =', citizenid, '| job =', job)
    return isPlayerClockedIn(citizenid, job) ~= nil
end)

exports('GetTotalSeconds', function(citizenid, job)
    debugPrint('export: GetTotalSeconds | citizenid =', citizenid, '| job =', job)
    return getTotalSeconds(citizenid, job)
end)

exports('GetWeeklySeconds', function(citizenid, job)
    debugPrint('export: GetWeeklySeconds | citizenid =', citizenid, '| job =', job)
    return getWeeklySeconds(citizenid, job)
end)

exports('GetPlayerStatus', function(citizenid)
    debugPrint('export: GetPlayerStatus | citizenid =', citizenid)
    local status = {}
    for jobName, _ in pairs(Config.Jobs) do
        local sessionId, clockInTime = getClockInTime(citizenid, jobName)
        status[jobName] = {
            clockedIn   = sessionId ~= nil,
            clockInTime = clockInTime,
            totalSecs   = getTotalSeconds(citizenid, jobName),
            weeklySecs  = getWeeklySeconds(citizenid, jobName),
        }
        debugPrint('export GetPlayerStatus:', jobName, '| clockedIn =', tostring(sessionId ~= nil))
    end
    return status
end)

exports('AddTime', function(citizenid, job, seconds, addedBy)
    debugPrint('export: AddTime | citizenid =', citizenid, '| job =', job, '| seconds =', tostring(seconds), '| addedBy =', tostring(addedBy))
    if not Config.Jobs[job] then return false, 'job not configured' end
    seconds = tonumber(seconds) or 0
    if seconds <= 0 then return false, 'invalid seconds' end

    exports.oxmysql:execute(
        'INSERT INTO timeclock_sessions (citizenid, job, clock_in, clock_out, duration_secs, forced_by) VALUES (?, ?, NOW(), NOW(), ?, ?)',
        { citizenid, job, seconds, addedBy or 'external' }
    )

    local newHMS = secondsToHMS(getTotalSeconds(citizenid, job))
    debugPrint('export AddTime: new total =', newHMS)
    print(('[timeclock] [export] Added %s to %s for %s. New total: %s'):format(secondsToHMS(seconds), job, citizenid, newHMS))
    return true, newHMS
end)

exports('DeductTime', function(citizenid, job, seconds, deductedBy)
    debugPrint('export: DeductTime | citizenid =', citizenid, '| job =', job, '| seconds =', tostring(seconds), '| deductedBy =', tostring(deductedBy))
    if not Config.Jobs[job] then return false, 'job not configured' end
    seconds = tonumber(seconds) or 0
    if seconds <= 0 then return false, 'invalid seconds' end

    local sessions = exports.oxmysql:executeSync(
        'SELECT id, duration_secs FROM timeclock_sessions WHERE citizenid = ? AND job = ? AND clock_out IS NOT NULL AND duration_secs > 0 ORDER BY clock_in ASC',
        { citizenid, job }
    )

    debugPrint('export DeductTime: found', sessions and #sessions or 0, 'deductible session(s)')
    local remaining = seconds
    for _, session in ipairs(sessions or {}) do
        if remaining <= 0 then break end
        local dur = tonumber(session.duration_secs) or 0
        if dur <= remaining then
            debugPrint('export DeductTime: deleting session id =', session.id)
            exports.oxmysql:execute('DELETE FROM timeclock_sessions WHERE id = ?', { session.id })
            remaining = remaining - dur
        else
            debugPrint('export DeductTime: partial deduct from session id =', session.id)
            exports.oxmysql:execute(
                'UPDATE timeclock_sessions SET duration_secs = duration_secs - ? WHERE id = ?',
                { remaining, session.id }
            )
            remaining = 0
        end
    end

    local newHMS = secondsToHMS(getTotalSeconds(citizenid, job))
    debugPrint('export DeductTime: done — remaining undeducted =', remaining, '| new total =', newHMS)
    print(('[timeclock] [export] Deducted from %s for %s. New total: %s'):format(job, citizenid, newHMS))
    return true, newHMS, remaining
end)

exports('ResetClocks', function(job, resetBy)
    debugPrint('export: ResetClocks | job =', job, '| resetBy =', tostring(resetBy))
    if not Config.Jobs[job] then return false, 'job not configured' end

    exports.oxmysql:execute(
        'UPDATE timeclock_sessions SET clock_out = NOW(), duration_secs = TIMESTAMPDIFF(SECOND, clock_in, NOW()) WHERE job = ? AND clock_out IS NULL',
        { job }
    )
    exports.oxmysql:execute('DELETE FROM timeclock_sessions WHERE job = ?', { job })

    local cfg = Config.Jobs[job]
    sendWebhook(cfg.webhook, buildEmbed(
        '🔄 Clock Reset — ' .. cfg.label,
        ('All time clocks for **%s** reset by **%s**'):format(cfg.label, resetBy or 'external'),
        Config.Colors.reset
    ))

    debugPrint('export ResetClocks: done for', job)
    print(('[timeclock] [export] Clocks reset for %s by %s'):format(job, resetBy or 'external'))
    return true
end)

exports('GetEmployees', function(job)
    debugPrint('export: GetEmployees | job =', job)
    if not Config.Jobs[job] then return {} end
    return fetchEmployees(job)
end)

exports('CloseOpenSessions', function(citizenid)
    debugPrint('export: CloseOpenSessions | citizenid =', citizenid)
    closeOpenSessions(citizenid)
    return true
end)

-- ─────────────────────────────────────────────────────────
--  Duty toggle: QBCore:ToggleDuty fires QBCore:Server:OnJobUpdate
--  with same job, flipped onduty — single authoritative handler
-- ─────────────────────────────────────────────────────────

AddEventHandler('QBCore:Server:OnJobUpdate', function(source, newJob)
    debugPrint('event: QBCore:Server:OnJobUpdate | src =', source, '| job =', tostring(newJob and newJob.name), '| onduty =', tostring(newJob and newJob.onduty))

    local src = source
    if not newJob or not newJob.name then return end
    if not Config.AutoClock then return end

    local pd = getPlayerData(src)
    if not pd then
        debugPrint('QBCore:Server:OnJobUpdate: no PlayerData — player likely disconnecting, closing open sessions')
        local ok, offlinePlayer = pcall(function()
            return exports.qbx_core:GetOfflinePlayer(src)
        end)
        if ok and offlinePlayer and offlinePlayer.PlayerData then
            closeOpenSessions(offlinePlayer.PlayerData.citizenid)
        else
            debugPrint('QBCore:Server:OnJobUpdate: could not retrieve offline player — sessions may already be closed')
        end
        return
    end

    if isInMulticharacter(src) then
        debugPrint('QBCore:Server:OnJobUpdate: in multicharacter — skipping')
        return
    end

    local jobName = newJob.name
    if not Config.Jobs[jobName] then
        debugPrint('QBCore:Server:OnJobUpdate: job not in Config.Jobs —', jobName)
        return
    end

    if newJob.onduty then
        -- Extra guard: don't clock in if player is no longer connected
        if not GetPlayerName(src) then
            debugPrint('QBCore:Server:OnJobUpdate: player no longer connected — skipping clock in')
            return
        end
        if not isPlayerClockedIn(pd.citizenid, jobName) then
            debugPrint('QBCore:Server:OnJobUpdate: going on duty — clocking in', pd.citizenid, jobName)
            exports.oxmysql:execute(
                'INSERT INTO timeclock_sessions (citizenid, job, clock_in, forced_by) VALUES (?, ?, NOW(), ?)',
                { pd.citizenid, jobName, 'duty_on' }
            )
            local cfg  = Config.Jobs[jobName]
            local name = pd.charinfo and (pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname) or pd.citizenid
            TriggerClientEvent('ox_lib:notify', src, { type = 'success', description = ('Clocked in to %s (on duty).'):format(cfg.label) })
            TriggerClientEvent('timeclock:client:updateStatus', src, jobName, true)
            sendWebhook(cfg.webhook, buildEmbed(
                '🟢 Shift Started (On Duty)',
                ('**%s** went on duty for %s'):format(name, cfg.label),
                Config.Colors.clockIn,
                {
                    { name = 'CitizenID', value = pd.citizenid,                   inline = true },
                    { name = 'Job',       value = cfg.label,                      inline = true },
                    { name = 'Time',      value = ('<t:%d:t>'):format(os.time()),  inline = true },
                }
            ))
            print(('[timeclock] %s clocked IN (duty on) for %s'):format(pd.citizenid, jobName))
        else
            debugPrint('QBCore:Server:OnJobUpdate: already clocked in — skipping')
        end
    else
        local sessionId, _ = getClockInTime(pd.citizenid, jobName)
        if sessionId then
            debugPrint('QBCore:Server:OnJobUpdate: going off duty — clocking out', pd.citizenid, jobName)
            exports.oxmysql:execute(
                'UPDATE timeclock_sessions SET clock_out = NOW(), duration_secs = TIMESTAMPDIFF(SECOND, clock_in, NOW()), forced_by = COALESCE(forced_by, ?) WHERE id = ?',
                { 'duty_off', sessionId }
            )
            local totalSecs = getTotalSeconds(pd.citizenid, jobName)
            local hms       = secondsToHMS(totalSecs)
            local cfg       = Config.Jobs[jobName]
            local name      = pd.charinfo and (pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname) or pd.citizenid
            TriggerClientEvent('ox_lib:notify', src, {
                type        = 'inform',
                description = ('Clocked out of %s (off duty). Total: %s'):format(cfg.label, hms),
                duration    = 6000,
            })
            TriggerClientEvent('timeclock:client:updateStatus', src, jobName, false)
            sendWebhook(cfg.webhook, buildEmbed(
                '🔴 Shift Ended (Off Duty)',
                ('**%s** went off duty for %s | Total: **%s**'):format(name, cfg.label, hms),
                Config.Colors.clockOut,
                {
                    { name = 'CitizenID',   value = pd.citizenid,                   inline = true  },
                    { name = 'Job',         value = cfg.label,                      inline = true  },
                    { name = 'Time',        value = ('<t:%d:t>'):format(os.time()),  inline = true  },
                    { name = 'Total Hours', value = hms,                            inline = false },
                }
            ))
            print(('[timeclock] %s clocked OUT (duty off) for %s total %s'):format(pd.citizenid, jobName, hms))
        else
            debugPrint('QBCore:Server:OnJobUpdate: not clocked in — skipping clock out')
        end
    end
end)

-- ─────────────────────────────────────────────────────────
--  QBCore:UpdatePlayer — close open sessions on disconnect
-- ─────────────────────────────────────────────────────────

AddEventHandler('QBCore:UpdatePlayer', function()
    local src = source
    debugPrint('event: QBCore:UpdatePlayer | src =', src)
    if not Config.AutoClock then return end

    local pd = getPlayerData(src)
    if not pd then
        debugPrint('QBCore:UpdatePlayer: no PlayerData — player likely disconnecting, closing open sessions')
        local ok, offlinePlayer = pcall(function()
            return exports.qbx_core:GetOfflinePlayer(src)
        end)
        if ok and offlinePlayer and offlinePlayer.PlayerData then
            closeOpenSessions(offlinePlayer.PlayerData.citizenid)
        else
            debugPrint('QBCore:UpdatePlayer: could not retrieve offline player — skipping')
        end
        return
    end

    debugPrint('QBCore:UpdatePlayer: player still active —', pd.citizenid, '— no action needed')
end)

-- ─────────────────────────────────────────────────────────
--  QBCore:Server:SetDuty — duty toggle authoritative event
--  Fired by qbx_core when a player's duty state changes
-- ─────────────────────────────────────────────────────────

AddEventHandler('QBCore:Server:SetDuty', function(source, onDuty)
    local src = source
    debugPrint('event: QBCore:Server:SetDuty | src =', src, '| onDuty =', tostring(onDuty))

    local pd = getPlayerData(src)
    if not pd then
        debugPrint('QBCore:Server:SetDuty: no PlayerData — closing open sessions')
        local ok, offlinePlayer = pcall(function()
            return exports.qbx_core:GetOfflinePlayer(src)
        end)
        if ok and offlinePlayer and offlinePlayer.PlayerData then
            closeOpenSessions(offlinePlayer.PlayerData.citizenid)
        else
            debugPrint('QBCore:Server:SetDuty: could not retrieve offline player — skipping')
        end
        return
    end
    if not Config.AutoClock then return end
    if isInMulticharacter(src) then
        debugPrint('QBCore:Server:SetDuty: in multicharacter — skipping')
        return
    end

    local jobName = pd.job and pd.job.name
    if not jobName or not Config.Jobs[jobName] then
        debugPrint('QBCore:Server:SetDuty: job not in Config.Jobs —', tostring(jobName))
        return
    end

    if onDuty then
        if not isPlayerClockedIn(pd.citizenid, jobName) then
            debugPrint('QBCore:Server:SetDuty: going on duty — clocking in', pd.citizenid, jobName)
            exports.oxmysql:execute(
                'INSERT INTO timeclock_sessions (citizenid, job, clock_in, forced_by) VALUES (?, ?, NOW(), ?)',
                { pd.citizenid, jobName, 'duty_on' }
            )
            local cfg  = Config.Jobs[jobName]
            local name = pd.charinfo and (pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname) or pd.citizenid
            TriggerClientEvent('ox_lib:notify', src, { type = 'success', description = ('Clocked in to %s (on duty).'):format(cfg.label) })
            TriggerClientEvent('timeclock:client:updateStatus', src, jobName, true)
            sendWebhook(cfg.webhook, buildEmbed(
                '🟢 Shift Started (On Duty)',
                ('**%s** went on duty for %s'):format(name, cfg.label),
                Config.Colors.clockIn,
                {
                    { name = 'CitizenID', value = pd.citizenid,                   inline = true },
                    { name = 'Job',       value = cfg.label,                      inline = true },
                    { name = 'Time',      value = ('<t:%d:t>'):format(os.time()),  inline = true },
                }
            ))
            print(('[timeclock] %s clocked IN (duty on) for %s'):format(pd.citizenid, jobName))
        else
            debugPrint('QBCore:Server:SetDuty: already clocked in — skipping')
        end
    else
        local sessionId, _ = getClockInTime(pd.citizenid, jobName)
        if sessionId then
            debugPrint('QBCore:Server:SetDuty: going off duty — clocking out', pd.citizenid, jobName)
            exports.oxmysql:execute(
                'UPDATE timeclock_sessions SET clock_out = NOW(), duration_secs = TIMESTAMPDIFF(SECOND, clock_in, NOW()), forced_by = COALESCE(forced_by, ?) WHERE id = ?',
                { 'duty_off', sessionId }
            )
            local totalSecs = getTotalSeconds(pd.citizenid, jobName)
            local hms       = secondsToHMS(totalSecs)
            local cfg       = Config.Jobs[jobName]
            local name      = pd.charinfo and (pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname) or pd.citizenid
            TriggerClientEvent('ox_lib:notify', src, {
                type        = 'inform',
                description = ('Clocked out of %s (off duty). Total: %s'):format(cfg.label, hms),
                duration    = 6000,
            })
            TriggerClientEvent('timeclock:client:updateStatus', src, jobName, false)
            sendWebhook(cfg.webhook, buildEmbed(
                '🔴 Shift Ended (Off Duty)',
                ('**%s** went off duty for %s | Total: **%s**'):format(name, cfg.label, hms),
                Config.Colors.clockOut,
                {
                    { name = 'CitizenID',   value = pd.citizenid,                   inline = true  },
                    { name = 'Job',         value = cfg.label,                      inline = true  },
                    { name = 'Time',        value = ('<t:%d:t>'):format(os.time()),  inline = true  },
                    { name = 'Total Hours', value = hms,                            inline = false },
                }
            ))
            print(('[timeclock] %s clocked OUT (duty off) for %s total %s'):format(pd.citizenid, jobName, hms))
        else
            debugPrint('QBCore:Server:SetDuty: not clocked in — skipping clock out')
        end
    end
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(source)
    if not Config.AutoClock then return end  -- ADD THIS
    local src = source
    debugPrint('event: QBCore:Server:OnPlayerUnload | src =', src)

    local citizenid = playerCitizenids[src]
    if citizenid then
        debugPrint('QBCore:Server:OnPlayerUnload: closing open sessions for cached citizenid', citizenid)
        closeOpenSessions(citizenid)
    else
        -- Fall back to live/offline player
        local pd = getPlayerData(src)
        if pd then
            debugPrint('QBCore:Server:OnPlayerUnload: got live PlayerData for', pd.citizenid)
            closeOpenSessions(pd.citizenid)
            return
        end
        local ok, offlinePlayer = pcall(function()
            return exports.qbx_core:GetOfflinePlayer(src)
        end)
        if ok and offlinePlayer and offlinePlayer.PlayerData then
            debugPrint('QBCore:Server:OnPlayerUnload: got offline PlayerData for', offlinePlayer.PlayerData.citizenid)
            closeOpenSessions(offlinePlayer.PlayerData.citizenid)
        else
            debugPrint('QBCore:Server:OnPlayerUnload: could not retrieve PlayerData — skipping')
        end
    end
end)


-- ─────────────────────────────────────────────────────────
--  Admin: open management menu for any configured job
--  Requires 'timeclock.admin' ace permission
-- ─────────────────────────────────────────────────────────

RegisterNetEvent('timeclock:server:adminOpenMenu', function(job)
    local src = source
    debugPrint('event: adminOpenMenu | src =', src, '| job =', job)

    if not Config.Jobs[job] then
        debugPrint('adminOpenMenu: job not configured —', job)
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Job not configured.' })
        return
    end

    if not IsPlayerAceAllowed(src, 'admin') then
        debugPrint('adminOpenMenu: src', src, 'does not have timeclock.admin ace — denying')
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'No permission.' })
        return
    end

    debugPrint('adminOpenMenu: ace check passed for src', src, '— opening menu for job =', job)
    TriggerClientEvent('timeclock:client:adminOpenMenu', src, job)
end)

-- ─────────────────────────────────────────────────────────
--  /managetimesheet — server validates boss status
-- ─────────────────────────────────────────────────────────

RegisterNetEvent('timeclock:server:requestManageMenu', function()
    local src = source
    debugPrint('event: requestManageMenu | src =', src)

    local pd = getPlayerData(src)
    if not pd then
        debugPrint('requestManageMenu: no PlayerData — skipping')
        return
    end

    local bossJobs = {}
    for _, jobName in ipairs(getConfiguredJobNames(pd)) do
        if checkIsBoss(pd, jobName) then
            bossJobs[#bossJobs + 1] = jobName
            debugPrint('requestManageMenu: player is boss of', jobName)
        end
    end

    if #bossJobs == 0 then
        debugPrint('requestManageMenu: no boss jobs found for', pd.citizenid)
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = Config.Locale.noBossPerms })
        return
    end

    debugPrint('requestManageMenu: sending', #bossJobs, 'boss job(s) to client')
    TriggerClientEvent('timeclock:client:openManageMenu', src, bossJobs)
end)

RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    local src = source
    debugPrint('event: QBCore:Server:OnPlayerLoaded | src =', src)

    local pd = getPlayerData(src)
    if not pd then
        debugPrint('QBCore:Server:OnPlayerLoaded: no PlayerData — skipping')
        return
    end

    -- Cache citizenid for use on disconnect
    playerCitizenids[src] = pd.citizenid
    debugPrint('QBCore:Server:OnPlayerLoaded: cached citizenid', pd.citizenid, 'for src', src)

    debugPrint('QBCore:Server:OnPlayerLoaded: closing any stale open sessions for', pd.citizenid)
    closeOpenSessions(pd.citizenid)

    local allGrades = getAllPlayerJobGrades(pd)
    for jobName, _ in pairs(allGrades) do
        if Config.Jobs[jobName] then
            local onDuty = false
            if pd.job and pd.job.name == jobName then
                onDuty = pd.job.onduty == true
            end
            debugPrint('QBCore:Server:OnPlayerLoaded: checking job =', jobName, '| onDuty =', tostring(onDuty))
            if onDuty and not isPlayerClockedIn(pd.citizenid, jobName) and Config.AutoClock then
                debugPrint('QBCore:Server:OnPlayerLoaded: clocking in to', jobName, 'for', pd.citizenid)
                exports.oxmysql:execute(
                    'INSERT INTO timeclock_sessions (citizenid, job, clock_in, forced_by) VALUES (?, ?, NOW(), ?)',
                    { pd.citizenid, jobName, 'auto_login' }
                )
                local cfg  = Config.Jobs[jobName]
                local name = pd.charinfo and (pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname) or pd.citizenid
                TriggerClientEvent('ox_lib:notify', src, {
                    type        = 'inform',
                    description = ('Auto clocked in to %s (on duty).'):format(cfg.label),
                    duration    = 5000,
                })
                TriggerClientEvent('timeclock:client:updateStatus', src, jobName, true)
                sendWebhook(cfg.webhook, buildEmbed(
                    '🟢 Shift Resumed (Login)',
                    ('**%s** logged in on duty for %s'):format(name, cfg.label),
                    Config.Colors.clockIn,
                    {
                        { name = 'CitizenID', value = pd.citizenid,                   inline = true },
                        { name = 'Job',       value = cfg.label,                      inline = true },
                        { name = 'Time',      value = ('<t:%d:t>'):format(os.time()),  inline = true },
                    }
                ))
                print(('[timeclock] %s auto clocked IN (login on duty) for %s'):format(pd.citizenid, jobName))
            end
        end
    end
end)
