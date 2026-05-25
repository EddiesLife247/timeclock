-- timeclock/client/main.lua

local playerJobs      = {}     -- { [job] = grade }
local clockStatus     = {}     -- { [job] = { clockedIn, clockInTime, totalSecs } }
local bossCache       = {}     -- { [job] = true/false }  server-confirmed
local zonesRegistered = false
local playerLoading   = false  -- prevent duplicate onPlayerLoaded calls

-- ─────────────────────────────────────────────────────────
--  Debug helper
-- ─────────────────────────────────────────────────────────

local function debugPrint(...)
    if Config.Debug then
        local args = { ... }
        for i, v in ipairs(args) do args[i] = tostring(v) end
        print('[timeclock][CLIENT] ' .. table.concat(args, ' '))
    end
end

-- ─────────────────────────────────────────────────────────
--  Helpers
-- ─────────────────────────────────────────────────────────

local function secondsToHMS(secs)
    secs = math.floor(secs or 0)
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    local s = secs % 60
    return string.format('%02dh %02dm %02ds', h, m, s)
end

local function currentTimeString()
    local t = GetGameTimer()
    local totalSecs = math.floor(t / 1000)
    local h = math.floor(totalSecs / 3600) % 24
    local m = math.floor(totalSecs / 60) % 60
    local s = totalSecs % 60
    return string.format('%02d:%02d:%02d', h, m, s)
end

local function getConfiguredPlayerJobs()
    local result = {}
    for job, grade in pairs(playerJobs) do
        if Config.Jobs[job] then
            result[#result + 1] = { name = job, grade = grade }
        end
    end
    debugPrint('getConfiguredPlayerJobs: found', #result, 'configured job(s)')
    return result
end

local function isBoss(job)
    local result = Config.Jobs[job] ~= nil and bossCache[job] == true
    debugPrint('isBoss check:', job, '=', tostring(result))
    return result
end

-- ─────────────────────────────────────────────────────────
--  ox_target zones — registered once, closures read live state
-- ─────────────────────────────────────────────────────────

local function registerZones()
    if zonesRegistered then
        debugPrint('registerZones: already registered — skipping')
        return
    end
    zonesRegistered = true
    debugPrint('registerZones: registering ox_target zones for all configured jobs')

    for jobName, cfg in pairs(Config.Jobs) do
        debugPrint('registerZones: registering zone for job =', jobName, 'coords =', tostring(cfg.clockIn.coords))

        exports.ox_target:addSphereZone({
            coords  = cfg.clockIn.coords,
            radius  = 1.0,
            debug   = false,
            options = {
                {
                    name        = 'timeclock_in_' .. jobName,
                    icon        = 'fas fa-clock',
                    label       = 'Clock In — ' .. cfg.label,
                    distance    = 2.5,
                    canInteract = function()
                        local hasJob = playerJobs[jobName] ~= nil
                        local st     = clockStatus[jobName]
                        local result = hasJob and not (st and st.clockedIn)
                        debugPrint('canInteract [clockIn]', jobName, '| hasJob:', tostring(hasJob), '| clockedIn:', tostring(st and st.clockedIn), '| result:', tostring(result))
                        return result
                    end,
                    onSelect = function()
                        debugPrint('onSelect: clockIn triggered for job =', jobName)
                        TriggerServerEvent('timeclock:server:clockIn', jobName)
                    end,
                },
                {
                    name        = 'timeclock_out_inzone_' .. jobName,
                    icon        = 'fas fa-sign-out-alt',
                    label       = 'Clock Out — ' .. cfg.label,
                    distance    = 2.5,
                    canInteract = function()
                        local hasJob = playerJobs[jobName] ~= nil
                        local st     = clockStatus[jobName]
                        local result = hasJob and st ~= nil and st.clockedIn == true
                        debugPrint('canInteract [clockOut inzone]', jobName, '| hasJob:', tostring(hasJob), '| clockedIn:', tostring(st and st.clockedIn), '| result:', tostring(result))
                        return result
                    end,
                    onSelect = function()
                        debugPrint('onSelect: clockOut (inzone) triggered for job =', jobName)
                        TriggerServerEvent('timeclock:server:clockOut', jobName)
                    end,
                },
                {
                    name        = 'timeclock_boss_' .. jobName,
                    icon        = 'fas fa-users-cog',
                    label       = 'Management — ' .. cfg.label,
                    distance    = 2.5,
                    canInteract = function()
                        local result = isBoss(jobName)
                        debugPrint('canInteract [boss]', jobName, '| result:', tostring(result))
                        return result
                    end,
                    onSelect = function()
                        debugPrint('onSelect: openBossMenu triggered for job =', jobName)
                        openBossMenu(jobName)
                    end,
                },
                {
                    name        = 'timeclock_info_' .. jobName,
                    icon        = 'fas fa-info-circle',
                    label       = cfg.label .. ' — Clock In/Out Point',
                    distance    = 2.5,
                    canInteract = function()
                        local hasJob = playerJobs[jobName] ~= nil
                        local boss   = isBoss(jobName)
                        return not hasJob and not boss
                    end,
                    onSelect = function()
                        lib.notify({ type = 'inform', description = 'You are not employed as ' .. cfg.label .. '.' })
                    end,
                },
            },
        })

        if cfg.clockOut then
            debugPrint('registerZones: registering separate clockOut zone for job =', jobName)
            exports.ox_target:addSphereZone({
                coords  = cfg.clockOut.coords,
                radius  = 1.0,
                debug   = false,
                options = {
                    {
                        name        = 'timeclock_out_' .. jobName,
                        icon        = 'fas fa-sign-out-alt',
                        label       = 'Clock Out — ' .. cfg.label,
                        distance    = 2.5,
                        canInteract = function()
                            local hasJob = playerJobs[jobName] ~= nil
                            local st     = clockStatus[jobName]
                            local result = hasJob and st ~= nil and st.clockedIn == true
                            debugPrint('canInteract [clockOut separate zone]', jobName, '| hasJob:', tostring(hasJob), '| clockedIn:', tostring(st and st.clockedIn), '| result:', tostring(result))
                            return result
                        end,
                        onSelect = function()
                            debugPrint('onSelect: clockOut (separate zone) triggered for job =', jobName)
                            TriggerServerEvent('timeclock:server:clockOut', jobName)
                        end,
                    },
                    {
                        name        = 'timeclock_out_info_' .. jobName,
                        icon        = 'fas fa-info-circle',
                        label       = cfg.label .. ' — Clock Out Point',
                        distance    = 2.5,
                        canInteract = function()
                            local hasJob = playerJobs[jobName] ~= nil
                            return not hasJob
                        end,
                        onSelect = function()
                            lib.notify({ type = 'inform', description = 'You are not employed as ' .. cfg.label .. '.' })
                        end,
                    },
                },
            })
        end
    end

    debugPrint('registerZones: all zones registered')
end

-- ─────────────────────────────────────────────────────────
--  Job refresh — updates playerJobs + bossCache, no zone re-registration
-- ─────────────────────────────────────────────────────────

local function refreshJobs()
    debugPrint('refreshJobs: starting job refresh')
    local pd = exports.qbx_core:GetPlayerData()
    if not pd then
        debugPrint('refreshJobs: GetPlayerData returned nil — aborting')
        return
    end

    playerJobs = {}

    if pd.job and pd.job.name then
        playerJobs[pd.job.name] = pd.job.grade and pd.job.grade.level or 0
        debugPrint('refreshJobs: primary job =', pd.job.name, 'grade =', playerJobs[pd.job.name])
    else
        debugPrint('refreshJobs: no primary job found in player data')
    end

    if pd.jobs and type(pd.jobs) == 'table' then
        debugPrint('refreshJobs: processing pd.jobs array, count =', #pd.jobs)
        for _, entry in ipairs(pd.jobs) do
            if entry.name then
                local grade = 0
                if type(entry.grade) == 'table' then
                    grade = entry.grade.level or 0
                elseif type(entry.grade) == 'number' then
                    grade = entry.grade
                end
                playerJobs[entry.name] = grade
                debugPrint('refreshJobs: ps-multijob added', entry.name, 'grade =', grade)
            end
        end
    else
        debugPrint('refreshJobs: pd.jobs not present or not a table')
    end

    if pd.jobdata and type(pd.jobdata) == 'table' then
        debugPrint('refreshJobs: processing pd.jobdata fallback')
        for jobName, grade in pairs(pd.jobdata) do
            if not playerJobs[jobName] then
                playerJobs[jobName] = tonumber(grade) or 0
                debugPrint('refreshJobs: qbx_multijob fallback added', jobName, 'grade =', playerJobs[jobName])
            else
                debugPrint('refreshJobs: qbx_multijob skipped', jobName, '(already in playerJobs)')
            end
        end
    else
        debugPrint('refreshJobs: pd.jobdata not present or not a table')
    end

    -- Update bossCache in background — canInteract closures will pick it up live
    CreateThread(function()
        debugPrint('refreshJobs: awaiting getBossStatus callback')
        bossCache = lib.callback.await('timeclock:getBossStatus', false) or {}
        for jobName, _ in pairs(bossCache) do
            if not playerJobs[jobName] then
                playerJobs[jobName] = 0
                debugPrint('refreshJobs: added', jobName, 'to playerJobs from bossCache')
            end
        end
        debugPrint('refreshJobs: complete, total playerJobs:')
        for k, v in pairs(playerJobs) do
            debugPrint('  ->', k, 'grade:', v)
        end
    end)
end

-- ─────────────────────────────────────────────────────────
--  Initialisation
-- ─────────────────────────────────────────────────────────

local function onPlayerLoaded()
    if playerLoading then
        debugPrint('onPlayerLoaded: already loading — skipping duplicate call')
        return
    end
    playerLoading = true
    debugPrint('onPlayerLoaded: fired')

    CreateThread(function()
        debugPrint('onPlayerLoaded: waiting for PlayerData')
        local pd = nil
        local attempts = 0
        while not pd and attempts < 10 do
            pd = exports.qbx_core:GetPlayerData()
            if not pd then
                Wait(500)
                attempts = attempts + 1
            end
        end

        if not pd then
            debugPrint('onPlayerLoaded: no PlayerData after retries — aborting')
            playerLoading = false
            return
        end

        -- Build playerJobs
        playerJobs = {}
        if pd.job and pd.job.name then
            playerJobs[pd.job.name] = pd.job.grade and pd.job.grade.level or 0
            debugPrint('onPlayerLoaded: primary job =', pd.job.name, 'grade =', playerJobs[pd.job.name])
        end
        if pd.jobs and type(pd.jobs) == 'table' then
            for _, entry in ipairs(pd.jobs) do
                if entry.name then
                    local grade = 0
                    if type(entry.grade) == 'table' then grade = entry.grade.level or 0
                    elseif type(entry.grade) == 'number' then grade = entry.grade end
                    playerJobs[entry.name] = grade
                end
            end
        end

        -- Await bossCache before registering zones so Management option is correct on first load
        debugPrint('onPlayerLoaded: awaiting getBossStatus')
        bossCache = lib.callback.await('timeclock:getBossStatus', false) or {}
        for jobName, _ in pairs(bossCache) do
            if not playerJobs[jobName] then
                playerJobs[jobName] = 0
            end
        end

        debugPrint('onPlayerLoaded: playerJobs ready — registering zones')
        for k, v in pairs(playerJobs) do debugPrint('  ->', k, 'grade:', v) end

        registerZones()

        -- Load clock status
        Wait(300)
        debugPrint('onPlayerLoaded: awaiting getMyStatus')
        local status = lib.callback.await('timeclock:getMyStatus', false)
        if status then
            clockStatus = status
            debugPrint('onPlayerLoaded: clockStatus loaded')
            for k, v in pairs(clockStatus) do
                debugPrint('  job:', k, '| clockedIn:', tostring(v.clockedIn), '| totalSecs:', tostring(v.totalSecs))
            end
        else
            debugPrint('onPlayerLoaded: getMyStatus returned nil')
        end

        playerLoading = false
    end)
end

local function onPlayerUnloaded()
    debugPrint('onPlayerUnloaded: clearing all client state')
    playerJobs    = {}
    clockStatus   = {}
    bossCache     = {}
    playerLoading = false
end

-- ─────────────────────────────────────────────────────────
--  Boss Menu
-- ─────────────────────────────────────────────────────────

function openBossMenu(job)
    debugPrint('openBossMenu: opening for job =', job)
    local cfg = Config.Jobs[job]

    lib.registerContext({
        id    = 'timeclock_boss_' .. job,
        title = '⏱ ' .. cfg.label .. ' Management',
        options = {
            {
                title       = '📋 Send Total Hours Report',
                description = 'Post all employee hours to Discord',
                icon        = 'paper-plane',
                onSelect    = function()
                    debugPrint('bossMenu: sendTotalHours for job =', job)
                    TriggerServerEvent('timeclock:server:sendTotalHours', job)
                end,
            },
            {
                title       = '🔄 Reset All Clocks',
                description = 'Wipe all recorded hours for this job',
                icon        = 'rotate-left',
                onSelect = function()
                    debugPrint('bossMenu: resetClocks dialog opened for job =', job)
                    local confirmed = lib.alertDialog({
                        header  = 'Confirm Reset',
                        content = 'This will permanently delete all clock records for **' .. cfg.label .. '**. Are you sure?',
                        cancel  = true,
                    })
                    if confirmed == 'confirm' then
                        debugPrint('bossMenu: resetClocks confirmed for job =', job)
                        TriggerServerEvent('timeclock:server:resetClocks', job)
                    else
                        debugPrint('bossMenu: resetClocks cancelled for job =', job)
                    end
                end,
            },
            {
                title       = '🟢 Force Clock In Employee',
                description = 'Manually clock in a specific employee',
                icon        = 'user-clock',
                onSelect    = function()
                    debugPrint('bossMenu: openForceMenu in for job =', job)
                    openForceMenu(job, 'in')
                end,
            },
            {
                title       = '🔴 Force Clock Out Employee',
                description = 'Manually clock out a specific employee',
                icon        = 'user-minus',
                onSelect    = function()
                    debugPrint('bossMenu: openForceMenu out for job =', job)
                    openForceMenu(job, 'out')
                end,
            },
            {
                title       = '➕ Add Time to Employee',
                description = 'Manually add hours/minutes to a timesheet',
                icon        = 'clock',
                onSelect    = function()
                    debugPrint('bossMenu: openAdjustMenu add for job =', job)
                    openAdjustMenu(job, 'add')
                end,
            },
            {
                title       = '➖ Deduct Time from Employee',
                description = 'Manually remove hours/minutes from a timesheet',
                icon        = 'clock-rotate-left',
                onSelect    = function()
                    debugPrint('bossMenu: openAdjustMenu deduct for job =', job)
                    openAdjustMenu(job, 'deduct')
                end,
            },
        },
    })
    lib.showContext('timeclock_boss_' .. job)
end

function openForceMenu(job, action)
    debugPrint('openForceMenu: job =', job, 'action =', action)
    local employees = lib.callback.await('timeclock:getEmployees', false, job)

    if not employees or #employees == 0 then
        debugPrint('openForceMenu: no employees returned for job =', job)
        lib.notify({ type = 'warning', description = 'No employees found for this job.' })
        return
    end

    debugPrint('openForceMenu: received', #employees, 'employee(s)')

    local options = {}
    for _, emp in ipairs(employees) do
        local eligible = (action == 'in' and not emp.clockedIn) or (action == 'out' and emp.clockedIn)
        debugPrint('openForceMenu: employee =', emp.name, '| clockedIn:', tostring(emp.clockedIn), '| eligible:', tostring(eligible))
        if eligible then
            options[#options + 1] = {
                title       = emp.name,
                description = 'Total: ' .. emp.totalHMS .. (emp.clockedIn and ' | 🟢 In' or ' | ⚫ Out'),
                onSelect    = function()
                    debugPrint('openForceMenu: selected', emp.name, 'action =', action, 'citizenid =', emp.citizenid)
                    if action == 'in' then
                        TriggerServerEvent('timeclock:server:forceClockIn', job, emp.citizenid)
                    else
                        TriggerServerEvent('timeclock:server:forceClockOut', job, emp.citizenid)
                    end
                end,
            }
        end
    end

    if #options == 0 then
        debugPrint('openForceMenu: no eligible employees for action =', action)
        lib.notify({ type = 'inform', description = 'No eligible employees for this action.' })
        return
    end

    debugPrint('openForceMenu: showing context with', #options, 'eligible option(s)')
    lib.registerContext({
        id      = 'timeclock_force_' .. job .. '_' .. action,
        title   = (action == 'in' and '🟢 Force Clock In' or '🔴 Force Clock Out') .. ' — ' .. Config.Jobs[job].label,
        options = options,
    })
    lib.showContext('timeclock_force_' .. job .. '_' .. action)
end

function openAdjustMenu(job, action)
    debugPrint('openAdjustMenu: job =', job, 'action =', action)
    local employees = lib.callback.await('timeclock:getEmployees', false, job)

    if not employees or #employees == 0 then
        debugPrint('openAdjustMenu: no employees returned for job =', job)
        lib.notify({ type = 'warning', description = 'No employees found for this job.' })
        return
    end

    debugPrint('openAdjustMenu: received', #employees, 'employee(s)')

    local options = {}
    for _, emp in ipairs(employees) do
        debugPrint('openAdjustMenu: adding option for', emp.name, 'totalHMS =', emp.totalHMS)
        options[#options + 1] = {
            title       = emp.name,
            description = 'Current Total: ' .. emp.totalHMS,
            onSelect    = function()
                debugPrint('openAdjustMenu: selected', emp.name, 'for', action)
                local hoursInput = lib.inputDialog(
                    (action == 'add' and '➕ Add Time — ' or '➖ Deduct Time — ') .. emp.name,
                    {
                        { type = 'number', label = 'Hours',   placeholder = '0', min = 0, max = 99 },
                        { type = 'number', label = 'Minutes', placeholder = '0', min = 0, max = 59 },
                    }
                )
                if not hoursInput then
                    debugPrint('openAdjustMenu: input cancelled for', emp.name)
                    return
                end

                local hours        = tonumber(hoursInput[1]) or 0
                local minutes      = tonumber(hoursInput[2]) or 0
                local totalSeconds = (hours * 3600) + (minutes * 60)

                debugPrint('openAdjustMenu: input received — hours:', hours, 'minutes:', minutes, 'totalSeconds:', totalSeconds)

                if totalSeconds == 0 then
                    debugPrint('openAdjustMenu: zero time entered — aborting')
                    lib.notify({ type = 'warning', description = 'No time entered.' })
                    return
                end

                debugPrint('openAdjustMenu: triggering adjustTime for', emp.citizenid, action, totalSeconds)
                TriggerServerEvent('timeclock:server:adjustTime', job, emp.citizenid, action, totalSeconds)
            end,
        }
    end

    debugPrint('openAdjustMenu: showing context with', #options, 'option(s)')
    lib.registerContext({
        id      = 'timeclock_adjust_' .. job .. '_' .. action,
        title   = (action == 'add' and '➕ Add Time' or '➖ Deduct Time') .. ' — ' .. Config.Jobs[job].label,
        options = options,
    })
    lib.showContext('timeclock_adjust_' .. job .. '_' .. action)
end

-- ─────────────────────────────────────────────────────────
--  /timecheck [id]
-- ─────────────────────────────────────────────────────────

RegisterCommand('timecheck', function(_, args)
    debugPrint('timecheck command fired | args[1] =', tostring(args[1]))
    if args[1] then
        debugPrint('timecheck: boss target check for server ID =', args[1])
        TriggerServerEvent('timeclock:server:timecheckTarget', tonumber(args[1]))
    else
        local myJobs = getConfiguredPlayerJobs()
        if #myJobs == 0 then
            debugPrint('timecheck: player has no configured jobs')
            lib.notify({ type = 'error', description = Config.Locale.noJob })
            return
        end

        local lines = {}
        for _, j in ipairs(myJobs) do
            local st = clockStatus[j.name]
            debugPrint('timecheck: job =', j.name, '| clockStatus =', st and 'present' or 'nil')
            if st then
                local statusStr = st.clockedIn
                    and ('✅ Clocked In since ' .. (st.clockInTime or '?'))
                    or  '❌ Not clocked in'
                lines[#lines + 1] = ('[%s] %s | Total: %s'):format(
                    Config.Jobs[j.name].label, statusStr, secondsToHMS(st.totalSecs or 0)
                )
            end
        end

        debugPrint('timecheck: displaying', #lines, 'line(s)')
        lib.notify({
            type        = #lines > 0 and 'inform' or 'warning',
            title       = '⏱ Your Time',
            description = #lines > 0 and table.concat(lines, '\n') or 'No clock data loaded yet.',
            duration    = 8000,
        })
    end
end, false)

-- ─────────────────────────────────────────────────────────
--  Net events from server
-- ─────────────────────────────────────────────────────────

RegisterNetEvent('timeclock:client:updateStatus', function(job, isIn)
    debugPrint('updateStatus received | job =', job, '| isIn =', tostring(isIn))
    if not clockStatus[job] then clockStatus[job] = {} end
    clockStatus[job].clockedIn = isIn
    if isIn then
        clockStatus[job].clockInTime = currentTimeString()
        debugPrint('updateStatus: clockInTime set to', clockStatus[job].clockInTime)
    end

    -- Safety net: if zones haven't registered and we're not already loading, init now
    if not zonesRegistered and not playerLoading then
        debugPrint('updateStatus: zones not registered — triggering onPlayerLoaded')
        onPlayerLoaded()
    end
end)

-- ─────────────────────────────────────────────────────────
--  Event handlers
-- ─────────────────────────────────────────────────────────

-- QBX player loaded
AddEventHandler('qbx_core:client:onPlayerLoaded', function()
    debugPrint('event: qbx_core:client:onPlayerLoaded')
    onPlayerLoaded()
end)

-- QBCore legacy — fallback for servers that fire this instead
AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    debugPrint('event: QBCore:Client:OnPlayerLoaded')
    if not zonesRegistered and not playerLoading then
        onPlayerLoaded()
    end
end)

-- QBX player unloaded
AddEventHandler('qbx_core:client:onPlayerUnloaded', function()
    debugPrint('event: qbx_core:client:onPlayerUnloaded')
    onPlayerUnloaded()
end)

-- QBX primary job update — refresh jobs only, zones already registered
AddEventHandler('qbx_core:client:onJobUpdate', function()
    debugPrint('event: qbx_core:client:onJobUpdate')
    refreshJobs()
end)

-- QBX gang update
AddEventHandler('qbx_core:client:onGangUpdate', function()
    debugPrint('event: qbx_core:client:onGangUpdate')
    refreshJobs()
end)

-- ps-multijob active job swap
AddEventHandler('ps-multijob:client:ActiveJobChanged', function()
    debugPrint('event: ps-multijob:client:ActiveJobChanged')
    refreshJobs()
end)

-- Resource restart while already in session
AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    debugPrint('onClientResourceStart: resource restarted — resetting all state')
    zonesRegistered = false
    playerLoading   = false
    playerJobs      = {}
    clockStatus     = {}
    bossCache       = {}
    local pd = exports.qbx_core:GetPlayerData()
    if pd and pd.citizenid then
        debugPrint('onClientResourceStart: player already in session — calling onPlayerLoaded')
        onPlayerLoaded()
    else
        debugPrint('onClientResourceStart: no active player session — skipping init')
    end
end)

-- ─────────────────────────────────────────────────────────
--  /managetimesheet — server validates boss status
-- ─────────────────────────────────────────────────────────

RegisterCommand('managetimesheet', function()
    debugPrint('managetimesheet: command fired')
    TriggerServerEvent('timeclock:server:requestManageMenu')
end, false)

RegisterNetEvent('timeclock:client:openManageMenu', function(bossJobs)
    debugPrint('timeclock:client:openManageMenu | jobs =', #bossJobs)

    if #bossJobs == 0 then
        lib.notify({ type = 'error', description = Config.Locale.noBossPerms })
        return
    end

    if #bossJobs == 1 then
        debugPrint('managetimesheet: one boss job — opening directly:', bossJobs[1])
        openBossMenu(bossJobs[1])
        return
    end

    local options = {}
    for _, jobName in ipairs(bossJobs) do
        local cfg = Config.Jobs[jobName]
        if cfg then
            options[#options + 1] = {
                title    = '⏱ ' .. cfg.label,
                icon     = 'users-cog',
                onSelect = function()
                    debugPrint('managetimesheet: picker selected job =', jobName)
                    openBossMenu(jobName)
                end,
            }
        end
    end

    lib.registerContext({
        id      = 'timeclock_manage_picker',
        title   = '⏱ Manage Timesheets',
        options = options,
    })
    lib.showContext('timeclock_manage_picker')
end)

-- ─────────────────────────────────────────────────────────
--  /timesheet [job] — admin override
-- ─────────────────────────────────────────────────────────

RegisterCommand('timesheet', function(_, args)
    debugPrint('timesheet: command fired | args[1] =', tostring(args[1]))

    local jobName = args[1]
    if not jobName then
        local options = {}
        for job, cfg in pairs(Config.Jobs) do
            options[#options + 1] = {
                title    = '⏱ ' .. cfg.label,
                icon     = 'users-cog',
                onSelect = function()
                    debugPrint('timesheet: picker selected job =', job)
                    TriggerServerEvent('timeclock:server:adminOpenMenu', job)
                end,
            }
        end
        lib.registerContext({
            id      = 'timeclock_admin_picker',
            title   = '⏱ Timesheet Admin',
            options = options,
        })
        lib.showContext('timeclock_admin_picker')
        return
    end

    if not Config.Jobs[jobName] then
        lib.notify({ type = 'error', description = 'Job "' .. jobName .. '" is not configured.' })
        return
    end

    TriggerServerEvent('timeclock:server:adminOpenMenu', jobName)
end, false)

RegisterNetEvent('timeclock:client:adminOpenMenu', function(job)
    debugPrint('timeclock:client:adminOpenMenu | job =', job)
    if not Config.Jobs[job] then return end
    openBossMenu(job)
end)