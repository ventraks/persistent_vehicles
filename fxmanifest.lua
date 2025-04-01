fx_version 'cerulean'
game 'gta5'

author 'Ventraks'
description 'Persistent Vehicles'
version '1.0.0'

shared_scripts {
    'config.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua', -- Make sure oxmysql is started before this resource
    'server/main.lua'
}

client_scripts {
    'client/main.lua'
}

-- Dependencies
dependencies {
    'oxmysql'
}
