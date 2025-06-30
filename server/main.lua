-- server/main.lua
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    print('^2dude_formularacing^7: Resource started (NUI Final Version)')
end)

RegisterNetEvent('dude_formularacing:syncActiveTrack', function(trackKey)
    if Config.Tracks[trackKey] then
        Config.ActiveTrack = trackKey
        print(string.format("^2Active track synchronized to: %s^7", trackKey))
    else
        print(string.format("^1Invalid track key received: %s^7", tostring(trackKey)))
    end
end)