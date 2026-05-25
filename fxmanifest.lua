fx_version 'cerulean'
game 'gta5'

name        'timeclock'
description 'Job Time Clock with Discord Webhooks'
author      'EddiesLife247'
version     '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/updater.lua',
}

client_scripts {
    'client/main.lua',
}
escrow_ignore {
    'config.lua',
    'install.sql',        -- was incorrectly 'closedroads.lua'
    'README.md',        -- was incorrectly 'closedroads.lua'

}
dependencies {
    'oxmysql',
    'ox_lib',
    'ox_target',
    'qbx_core',
}
