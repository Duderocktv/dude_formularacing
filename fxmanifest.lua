-- fxmanifest.lua (Corrected ox_lib Load & Client Scripts)

fx_version 'cerulean'
lua54 'yes'
game 'gta5'

author 'DudeRockTV & Gemini'
description 'Formula Racing script for FiveM - Refactored NUI Version with Pit Stops'
version '1.3.1' -- Increment version

ui_page 'html/ui.html'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua'
}

client_scripts {
    -- List all client scripts explicitly
    'client/tires.lua',
    'client/boost.lua',
    'client/pitstop.lua'
    -- Add any other client/*.lua files here by name if you have them
}

server_scripts {
    'server/main.lua',
    'server/pitstop.lua',
	'server/tires.lua'
    -- Add any other server/*.lua files here by name if you have them
}

files {
    'html/ui.html',
    'html/style.css',
    'html/script.js'
}

dependencies {
    'ox_lib',
    'ox_inventory',
    'ox_target',
    'ox_fuel'
}