Config = {}

-- ─────────────────────────────────────────────────────────
--  Multijob Table Settings
-- ─────────────────────────────────────────────────────────

Config.Multijob = {
    enabled         = true,
    table           = 'multijobs',
    citizenidColumn = 'citizenid',
    dataColumn      = 'jobdata',
}

Config.Debug = false

Config.AutoClock = true -- Enable for auto fly in/fly out clock, and multi job switch
Config.multiCharacter = 'op-multicharacter' -- uses this export: isPlayerInsideMulticharacter

-- ─────────────────────────────────────────────────────────
--  ef-phone Mail Settings
-- ─────────────────────────────────────────────────────────

-- THIS USES THIS EXPORT.
--[[
local function sendMail(citizenid, sender, subject, message)
    if not Config.Mail or not Config.Mail.enabled then return end
    exports[Config.Mail.resource]:sendNewMailToOffline(citizenid, {
        sender  = sender  or Config.Mail.defaultSender,
        subject = subject,
        message = message,
    })
end
]]--
Config.Mail = {
    enabled  = true,   -- Set false to disable all mail sending
    resource = 'ef-phone',

    -- Default sender shown when no override is passed
    defaultSender = '⏱ Time Clock',

    -- Per-event sender overrides (set nil to use defaultSender)
    senders = {
        clockIn       = '⏱ Time Clock',
        clockOut      = '⏱ Time Clock',
        forceClockIn  = '⏱ Time Clock',
        forceClockOut = '⏱ Time Clock',
        timeAdjust    = '⏱ Time Clock',
    },
}

--[[
    Each job entry:
        label       = Display name for webhooks / notifications
        webhook     = Discord webhook URL for this job
        bossGrade   = Minimum grade to access boss/management features
        clockIn     = ox_target zone for clocking IN  (vector3 + size + heading)
        clockOut    = ox_target zone for clocking OUT (vector3 + size + heading)
                      Set clockOut = nil to reuse the clockIn zone for both actions.
]]

-- REMEMBER TO RUN INSTALL.SQL

Config.Jobs = {

    police = {
        label     = 'Los Santos Police Department',
        webhook   = '',
        bossGrade = 4, -- Commander+
        clockIn = {
            coords  = vector3(-1068.62, -814.63, 10.95),
            size    = vector3(1.5, 1.5, 1.5),
            heading = 0.0,
        },
        clockOut = nil, -- uses clockIn zone
    },
    -- Add more jobs here following the same pattern
}

-- ─────────────────────────────────────────────────────────
--  General Settings
-- ─────────────────────────────────────────────────────────

-- Discord embed colours (decimal)
Config.Colors = {
    clockIn     = 3066993,  -- green
    clockOut    = 15158332, -- red
    totalHours  = 3447003,  -- blue
    reset       = 16776960, -- yellow
    forceAction = 10181046, -- purple
}

-- How often (ms) the client polls its clock-in time for the /timecheck HUD
Config.HudPollInterval = 5000

-- Locale strings (edit to change language)
Config.Locale = {
    clockedIn       = 'You have clocked in.',
    clockedOut      = 'You have clocked out. Total time: %s',
    alreadyClockedIn  = 'You are already clocked in.',
    notClockedIn      = 'You are not clocked in.',
    noJob           = 'You are not employed in a configured job.',
    noBossPerms     = 'You do not have management permissions.',
    resetDone       = 'All clocks have been reset.',
    forceClockIn    = 'You have been force clocked in by management.',
    forceClockOut   = 'You have been force clocked out by management.',
}
