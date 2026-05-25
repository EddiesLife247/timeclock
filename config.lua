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

Config.Jobs = {

    police = {
        label     = 'Los Santos Police Department',
        webhook   = 'https://discord.com/api/webhooks/1507852864624660631/XL_p46tM3GC0Z5ZZK-yevGRyNJEiCt5YzGv611e0ugbQjR-xXTqoDuqeKZIdyY-Z0ZU8',
        bossGrade = 4, -- Commander+
        clockIn = {
            coords  = vector3(-1068.62, -814.63, 10.95),
            size    = vector3(1.5, 1.5, 1.5),
            heading = 0.0,
        },
        clockOut = nil, -- uses clockIn zone
    },
    bcso = {
        label     = 'Blaine County Sheriff Department',
        webhook   = 'https://discord.com/api/webhooks/1507852928935792753/AA5WI8y7WKFI6zNXUunkwz17EyeEkV2W0v_pvMMH2jErXE9rOQSZgK7wAwqL0H-2FZFS',
        bossGrade = 4, -- Commander+
        clockIn = {
            coords  = vector3(1816.73, 3672.7, 34.71),
            size    = vector3(1.5, 1.5, 1.5),
            heading = 0.0,
        },
        clockOut = nil, -- uses clockIn zone
    },

    ambulance = {
        label     = 'Emergency Medical Services',
        webhook   = 'https://discord.com/api/webhooks/1507852982266495036/7Cqutfqi0tmPBz3Tr1K9ok-wxjJJlQlzBJ8yoboeEKw65nah2CugRZlNYv-dz06C4X08',
        bossGrade = 3,
        clockIn = {
            coords  = vector3(-432.4, -318.23, 34.91),
            size    = vector3(1.5, 1.5, 1.5),
            heading = 0.0,
        },
        clockOut = nil,
    },

    mechanic = {
        label     = 'LS Customs\'s Mechanics',
        webhook   = 'https://discord.com/api/webhooks/1507853045046706307/EWN8fRBZL9fzArnyhvhWGnhajSFwC5jE0wXLSQ73TZ3m9lVqBTKncnC9rIV67UUxSjGI',
        bossGrade = 2,
        clockIn = {
            coords  = vector3(-322.92, -146.48, 39.02),
            size    = vector3(1.5, 1.5, 1.5),
            heading = 0.0,
        },
        clockOut = nil,
    },
    burgershot = {
        label     = 'City Burgershot',
        webhook   = 'https://discord.com/api/webhooks/1507853101028085945/WirD0OwE7fAGULKYbYVsfpzf92uo5avuOywCn-ETmtRPsE3nQDeVyQpHE46NBSfjBHnz',
        bossGrade = 2,
        clockIn = {
            coords  = vector3(-1199.91, -902.83, 13.89),
            size    = vector3(1.5, 1.5, 1.5),
            heading = 0.0,
        },
        clockOut = nil,
    },
    realestate = {
        label     = 'Real Estate',
        webhook   = '',
        bossGrade = 2,
        clockIn = {
            coords  = vector3(-1199.91, -902.83, 13.89),
            size    = vector3(1.5, 1.5, 1.5),
            heading = 0.0,
        },
        clockOut = nil,
    },
    mosleys = {
        label     = 'Mosleys Mechanics',
        webhook   = 'https://discord.com/api/webhooks/1508034497164218508/F9oeuIZ2wfwU29YP6Kd8a-k1H8mviYz-FrahTi90AYKcBYQE-O4eOOdnxiI7Ze7PmwmR',
        bossGrade = 2,
        clockIn = {
            coords  = vector3(1726.76, 3702.16, 34.44),
            size    = vector3(1.5, 1.5, 1.5),
            heading = 0.0,
        },
        clockOut = nil,
    },
    bennys = {
        label     = 'Bennys Mechanic',
        webhook   = 'https://discord.com/api/webhooks/1508223110271205386/rgvp25BNxByPuXufZdYoCF3vERkzHzT_YSt2ka8rk1vnrjka47UxTnZb2fwBRaGoys6S',
        bossGrade = 2,
        clockIn = {
            coords  = vector3(-200.74, -1318.3, 31.09),
            size    = vector3(1.5, 1.5, 1.5),
            heading = 0.0,
        },
        clockOut = nil,
    },
    uwu = {
        label     = 'UWU Cafe',
        webhook   = 'https://discord.com/api/webhooks/1508514778321125406/1fYhWmOX--MxtSWarLfmw1HjFDuTatuoKutKIi52LqaVXkHMGN_hMceyB2B9eY6v9zFn',
        bossGrade = 2,
        clockIn = {
            coords  = vector3(-593.9, -1053.32, 22.34),
            size    = vector3(1.5, 1.5, 1.5),
            heading = 0.0,
        },
        clockOut = nil,
    },
    upnattom = {
        label     = 'Up n Attom',
        webhook   = 'https://discord.com/api/webhooks/1508514875410743446/anxT9CqEB8VN16rWcrvAJJU-dW23_tzU0_OGrzVtip3oNuSPitO1m085-4pZFt4SmdTV',
        bossGrade = 2,
        clockIn = {
            coords  = vector3(87.48, 298.0, 110.22),
            size    = vector3(1.5, 1.5, 1.5),
            heading = 0.0,
        },
        clockOut = nil,
    },
    papagarcia = {
        label     = 'Papa Garcia',
        webhook   = 'https://discord.com/api/webhooks/1508514973696135309/MJr849QpLR191CakDuM2l086EkhGmO72TunPlPk5RdWkT9nK9nqLZPY2_ky7GX4RhJMF',
        bossGrade = 2,
        clockIn = {
            coords  = vector3(-1201.24, -1321.27, 4.92),
            size    = vector3(1.5, 1.5, 1.5),
            heading = 0.0,
        },
        clockOut = nil,
    },
    rustytap = {
        label     = 'Rusty Tap',
        webhook   = 'https://discord.com/api/webhooks/1508515060316635196/cMAyFMW9zRnz1yyKJFZsZVoKJQPSKE-XqCctU3gtP423WXohhSCAK5MfNbo9WJXMT5XS',
        bossGrade = 2,
        clockIn = {
            coords  = vector3(-1199.91, -902.83, 13.89),
            size    = vector3(1.5, 1.5, 1.5),
            heading = 0.0,
        },
        clockOut = nil,
    },
    sandymotel = {
        label     = 'Sandy Motel',
        webhook   = 'https://discord.com/api/webhooks/1508515218999742556/JET8_WYUMjXuZKE_ll1-ryemiQ9_s1JOgcpoOF5LLnV5ylKLlCe8fQYrIJ1h-aH_RKr4',
        bossGrade = 2,
        clockIn = {
            coords  = vector3(-1199.91, -902.83, 13.89),
            size    = vector3(1.5, 1.5, 1.5),
            heading = 0.0,
        },
        clockOut = nil,
    },
    comicstore = {
        label     = 'Comic Store',
        webhook   = 'https://discord.com/api/webhooks/1508515317393916117/UXldS00bfHDYeuBpUiHkqT_l0Lx7m-r5dqcS4FnDwMYsrnAayXopPQEymISx-geCFOWq',
        bossGrade = 2,
        clockIn = {
            coords  = vector3(-1199.91, -902.83, 13.89),
            size    = vector3(1.5, 1.5, 1.5),
            heading = 0.0,
        },
        clockOut = nil,
    },
    fishnchips = {
        label     = 'Fish n Chips',
        webhook   = 'https://discord.com/api/webhooks/1508515686622822521/8U_VwwQyBZcG31JaFXZNdmEsiGT69T44N18ZML_UUcESEZI4WjjVl_yAU7Pn5MUDn1fO',
        bossGrade = 2,
        clockIn = {
            coords  = vector3(-1199.91, -902.83, 13.89),
            size    = vector3(1.5, 1.5, 1.5),
            heading = 0.0,
        },
        clockOut = nil,
    },
    peyote = {
        label     = 'Peyote Casino',
        webhook   = 'https://discord.com/api/webhooks/1508515881636991167/kl1O6eFAKUV617yJmkzY9P2G03M7nkPX1eSH9s4jtddgHo6Nj_-iBFtPYEcXMHI7OWqk',
        bossGrade = 2,
        clockIn = {
            coords  = vector3(313.93, 123.3, 104.12),
            size    = vector3(1.5, 1.5, 1.5),
            heading = 0.0,
        },
        clockOut = nil,
    },
    cluckinbell = {
        label     = 'Cluckin Bell',
        webhook   = 'https://discord.com/api/webhooks/1508515974582636689/gWvtrLUUBkyC-1VA7uWNwcXFOi8CPAmtPW6w-ySlrwAoGAHnyYW3IqX65JJEksRXT7Xu',
        bossGrade = 2,
        clockIn = {
            coords  = vector3(-158.36, -266.58, 43.6),
            size    = vector3(1.5, 1.5, 1.5),
            heading = 0.0,
        },
        clockOut = nil,
    },
    sandyburgershot = {
        label     = 'Sandy Burgershot',
        webhook   = 'https://discord.com/api/webhooks/1508516082955194589/yFIk1PDdx9IC6ow2bP2oAin2VVDA9F3qJWzcHe9a81tlGy-fbQarZTug-Hc-T-g9KfKv',
        bossGrade = 2,
        clockIn = {
            coords  = vector3(1593.01, 3765.01, 34.44),
            size    = vector3(1.5, 1.5, 1.5),
            heading = 0.0,
        },
        clockOut = nil,
    },
    reporter = {
        label     = 'Weazle News',
        webhook   = 'https://discord.com/api/webhooks/1508516190597677210/8MgRi2llWHS63S-jZaeCderGrUQMEBUX-D3Nv0uWrMqrUG1Fky2xplqpeMrLViwh-oHo',
        bossGrade = 2,
        clockIn = {
            coords  = vector3(-1199.91, -902.83, 13.89),
            size    = vector3(1.5, 1.5, 1.5),
            heading = 0.0,
        },
        clockOut = nil,
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
