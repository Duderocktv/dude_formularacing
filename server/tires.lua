-- server/tires.lua (v1.3.1 - Enhanced Tire Relay)
local DebugPrint = function(msg) Config.DebugPrint("ServerTires", msg) end

-- Event to initialize tire state bag if it doesn't exist
RegisterNetEvent('dude_formularacing:server:initializeTireState', function(vehicleNetId)
    local src = source
    -- DebugPrint("Received initializeTireState request from src " .. src .. " for NetID: " .. vehicleNetId) -- Less verbose

    if type(vehicleNetId) ~= 'number' or vehicleNetId <= 0 then DebugPrint("InitializeTireState: INVALID NetID: " .. tostring(vehicleNetId)); return end
    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    if not DoesEntityExist(vehicle) then DebugPrint("InitializeTireState: DENIED - Vehicle NetID "..vehicleNetId.." does not exist."); return end

    local success, state = pcall(function() return Entity(vehicle).state.tireInfo end)
    if not success then DebugPrint("InitializeTireState: pcall FAILED accessing state bag."); return end
    if state then return end -- Already initialized

    DebugPrint("InitializeTireState: Initializing state bag 'tireInfo' for vehNetID: " .. vehicleNetId)
    local defaultStateData = { wear = { [0]=100.0, [1]=100.0, [2]=100.0, [3]=100.0 }, burst = { [0]=false, [1]=false, [4]=false, [5]=false } }
    local setStateSuccess, setStateError = pcall(function() Entity(vehicle).state:set('tireInfo', defaultStateData, true) end)
    if setStateSuccess then DebugPrint("InitializeTireState: State bag 'tireInfo' set successfully.") else DebugPrint("InitializeTireState: ERROR setting state bag: " .. tostring(setStateError)) end
end)

-- Event from client indicating a tire was changed
RegisterNetEvent('dude_f1:tireChanged', function(vehicleNetId, visualIndex)
    local src = source -- Server ID of the player who changed the tire
    DebugPrint("Received dude_f1:tireChanged from src " .. src .. " for vehNetID " .. vehicleNetId .. ", tire " .. visualIndex)

    if type(vehicleNetId) ~= 'number' or vehicleNetId <= 0 then return end
    if type(visualIndex) ~= 'number' or visualIndex < 0 or visualIndex > 3 then return end

    -- Get the vehicle entity
    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    if DoesEntityExist(vehicle) then
        -- Get the current state
        local success, state = pcall(function() return Entity(vehicle).state.tireInfo end)
        if success and state and state.wear and state.burst then
            -- Create a copy of the current state
            local newWear = {}
            for k, v in pairs(state.wear) do newWear[k] = v end
            local newBurst = {}
            for k, v in pairs(state.burst) do newBurst[k] = v end
            
            -- IMPORTANT: Set the tire to 100% (fully repaired)
            newWear[visualIndex] = 100.0
            
            -- Update the state bag on the server
            DebugPrint("Setting tire " .. visualIndex .. " to 100% for vehNetID " .. vehicleNetId)
            Entity(vehicle).state:set('tireInfo', { wear = newWear, burst = newBurst }, true)
            
            -- Send the direct update to all clients
            TriggerClientEvent('dude_formularacing:directTireUpdate', -1, vehicleNetId, visualIndex, 100.0)
            DebugPrint("Sent directTireUpdate to all clients for tire " .. visualIndex)
            
            -- Also trigger the regular update event for backward compatibility
            TriggerClientEvent('dude_formularacing:client:tireChangedUpdate', -1, src, vehicleNetId, visualIndex)
            DebugPrint("Relayed tireChangedUpdate to other clients.")
        else
            DebugPrint("WARNING: Could not access tire state for vehNetID " .. vehicleNetId)
        end
    else
        DebugPrint("WARNING: Vehicle NetID " .. vehicleNetId .. " not found on server")
    end
end)

RegisterNetEvent('dude_f1:forceTireValue', function(vehicleNetId, visualIndex, value)
    local src = source
    if type(vehicleNetId) ~= 'number' or vehicleNetId <= 0 then return end
    if type(visualIndex) ~= 'number' or visualIndex < 0 or visualIndex > 3 then return end
    if type(value) ~= 'number' then return end
    
    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    if DoesEntityExist(vehicle) then
        local success, state = pcall(function() return Entity(vehicle).state.tireInfo end)
        if success and state and state.wear then
            local newWear = {}
            for k, v in pairs(state.wear) do newWear[k] = v end
            local newBurst = {}
            for k, v in pairs(state.burst) do newBurst[k] = v end
            
            newWear[visualIndex] = value
            DebugPrint("Admin force-set tire " .. visualIndex .. " to " .. value .. "% for vehNetID " .. vehicleNetId)
            Entity(vehicle).state:set('tireInfo', { wear = newWear, burst = newBurst }, true)
            
            TriggerClientEvent('dude_formularacing:client:directTireUpdate', -1, vehicleNetId, visualIndex, value)
        end
    end
end)