
local DebugPrint = function(msg) Config.DebugPrint("ServerPitStop", msg) end

if not Config.PitStop.Enabled then DebugPrint("Pit Stop disabled."); return end

-- Pit Spawn Locations (copy from client script)
-- local SPAWN_LOCATIONS = {
    -- vector4(-2851.26, 8111.57, 44.25, 261.04),
    -- vector4(-2856.28, 8112.26, 44.29, 262.06),
    -- vector4(-2861.49, 8113.06, 44.34, 258.68),
    -- vector4(-2866.61, 8114.00, 44.38, 258.93),
    -- vector4(-2871.03, 8114.53, 44.42, 258.18),
    -- vector4(-2876.82, 8115.41, 44.47, 259.38),
    -- vector4(-2881.61, 8116.13, 44.51, 258.41),
    -- vector4(-2885.97, 8116.63, 44.54, 261.82),
    -- vector4(-2890.73, 8117.41, 44.58, 259.72),
    -- vector4(-2896.04, 8118.13, 44.63, 258.50)
-- }

-- Helper function to get vehicles in an area
function GetVehiclesInArea(coords, radius)
    local vehicles = {}
    local vehiclePool = GetGamePool('CVehicle')
    
    for _, vehicle in ipairs(vehiclePool) do
        local vehicleCoords = GetEntityCoords(vehicle)
        local distance = #(vehicleCoords - coords)
        
        if distance <= radius then
            table.insert(vehicles, vehicle)
        end
    end
    
    return vehicles
end

local function trim(s)
    if type(s) ~= 'string' then return s end
    return s:match("^%s*(.-)%s*$")
end

function IsRacingStewart(source)
    local qbxPlayer = exports.qbx_core:GetPlayer(source)
    if not qbxPlayer then return false end
    
    -- Check if CID is in the whitelist
    for _, cid in ipairs(Config.RacingStewarts) do
        if qbxPlayer.PlayerData.citizenid == cid then
            return true
        end
    end
    
    -- Optional: Add admin check
    local permission = qbxPlayer.PlayerData.permission
    return permission == 'admin' or permission == 'god'
end

-- Callback to check Racing Stewart status (server-side)
lib.callback.register('dude_formularacing:CheckRacingStewart', function(source)
    local qbxPlayer = exports.qbx_core:GetPlayer(source)
    if not qbxPlayer then return false end
    
    -- Check if CID is in the whitelist
    for _, cid in ipairs(Config.RacingStewarts) do
        if qbxPlayer.PlayerData.citizenid == cid then
            return true
        end
    end
    
    -- Optional: Add admin check
    local permission = qbxPlayer.PlayerData.permission
    return permission == 'admin' or permission == 'god'
end)

local ServerSpawnedRaceCarNetIds = {}


RegisterCommand('raceday', function(source, args)
    if not IsRacingStewart(source) then
        TriggerClientEvent('ox_lib:notify', source, { title = 'Race Day', description = 'You are not authorized!', type = 'error' })
        return
    end

    local action = args[1] and string.lower(args[1]) or nil

    if action == 'begin' then
        DebugPrint("'/raceday begin' initiated by source: " .. source)
		DebugPrint("Current Active Track: " .. Config.ActiveTrack) 

        -- 1. PRE-EMPTIVE DESPAWN (by plate, as a fallback/cleanup)
        DebugPrint("Despawning any existing 'FORM' cars by plate (pre-emptive)...")
        local vehicles = GetGamePool('CVehicle')
        local preDespawnedCount = 0
        for i = 1, #vehicles do
            local vehHandle = vehicles[i]
            if DoesEntityExist(vehHandle) then
                local rawPlate = GetVehicleNumberPlateText(vehHandle)
                if type(rawPlate) == 'string' and rawPlate ~= "" then
                    local plate = trim(rawPlate)
                    local plateNumMatch = plate:match("^FORM(%d+)$")
                    if plateNumMatch then
                        DebugPrint("Pre-despawning car with plate: " .. plate .. " (Handle: " .. vehHandle .. ")")
                        DeleteEntity(vehHandle)
                        preDespawnedCount = preDespawnedCount + 1
                    end
                end
            end
        end
        DebugPrint("Pre-emptively despawned " .. preDespawnedCount .. " cars by plate.")
        Wait(500)

        ServerSpawnedRaceCarNetIds = {}
        DebugPrint("Cleared ServerSpawnedRaceCarNetIds list.")

        local activeTrackKey = Config.ActiveTrack
        local trackConfig = Config.Tracks[activeTrackKey]
        if not trackConfig then
            DebugPrint("ERROR: Active track cfg ('" .. activeTrackKey .. "') not found.")
            TriggerClientEvent('ox_lib:notify', source, { title = 'Race Day', description = "Error: Active track config not found.", type = 'error' })
            return
        end

        -- Use trackConfig for spawn locations
        local spawnLocations = trackConfig.spawnLocations
        local extraSpawnLocations = trackConfig.extraSpawnLocations or {}
        local CAR_SPAWN_OVERALL_DELAY_MS = 250 
        local CREATE_VEHICLE_ATTEMPTS = 3    
        local carsSuccessfullySpawned = 0

        -- Function to attempt vehicle creation with retries AND cleanup
       local function AttemptCreateVehicle(hash, x, y, z, h, identifier)
    local vehicle = nil
    local attempts = 0
    local maxAttempts = 5
    local delayBetweenAttempts = 250

    while attempts < maxAttempts do
        attempts = attempts + 1
        
        -- Attempt to create vehicle
        vehicle = CreateVehicle(hash, x, y, z, h, true, true)
        
        -- Wait a short moment to allow vehicle to be fully created
        Wait(100)
        
        -- Check if vehicle exists and is valid
        if DoesEntityExist(vehicle) then
            -- Additional validation
            local netId = NetworkGetNetworkIdFromEntity(vehicle)
            if netId and netId ~= 0 then
                DebugPrint(string.format("%s: Successfully created vehicle (Handle: %d, NetID: %d) on attempt %d", 
                    identifier, vehicle, netId, attempts))
                return vehicle
            else
                DebugPrint(string.format("%s: Created vehicle, but failed to get valid NetID. Deleting.", identifier))
                DeleteEntity(vehicle)
            end
        else
            DebugPrint(string.format("%s: Failed to create vehicle on attempt %d", identifier, attempts))
        end
        
        -- Wait before next attempt
        Wait(delayBetweenAttempts)
    end
    
    DebugPrint(string.format("%s: CRITICAL - Failed to create vehicle after %d attempts", identifier, maxAttempts))
    return nil
end

        -- Spawn primary cars loop (remains structurally the same, uses new AttemptCreateVehicle)
        for i = 1, #spawnLocations do
    local spawnLoc = spawnLocations[i]
    local vehicleHash = GetHashKey('formula')
    local carIdentifier = "FORM" .. i

    if vehicleHash ~= 0 then
        local vehicle = AttemptCreateVehicle(vehicleHash, spawnLoc.x, spawnLoc.y, spawnLoc.z, spawnLoc.w, carIdentifier)
        
        if vehicle then
            SetVehicleNumberPlateText(vehicle, carIdentifier)
            local vehicleNetId = NetworkGetNetworkIdFromEntity(vehicle)
            
            if vehicleNetId and vehicleNetId ~= 0 then
                table.insert(ServerSpawnedRaceCarNetIds, vehicleNetId)
                carsSuccessfullySpawned = carsSuccessfullySpawned + 1
                
                DebugPrint(string.format("Spawned %s (NetID: %d) - Tracking NetID.", carIdentifier, vehicleNetId))
                
                -- Add a small, random delay to distribute network load
                Wait(math.random(50, 200))
                
                TriggerClientEvent('dude_formularacing:client:SetupRaceCar', -1, vehicleNetId, carIdentifier, i - 1, false, source)
            else
                DebugPrint(string.format("ERROR: Could not get NetID for %s (Handle: %d). Deleting.", carIdentifier, vehicle))
                DeleteEntity(vehicle)
            end
        else
            DebugPrint(string.format("ERROR: Failed to create vehicle for %s", carIdentifier))
        end
    else
        DebugPrint(string.format("ERROR: Invalid hash for model 'formula' for %s", carIdentifier))
    end
    
    -- Increased delay between vehicle spawns
    Wait(CAR_SPAWN_OVERALL_DELAY_MS)
end

        -- Spawn extra cars loop (remains structurally the same, uses new AttemptCreateVehicle)
        local plateStartIndex = #spawnLocations + 1
        for i = 1, #extraSpawnLocations do
            local spawnLoc = extraSpawnLocations[i]
            local vehicleHash = GetHashKey('formula')
            local plateNumber = plateStartIndex + i - 1
            local carIdentifier = "FORM" .. plateNumber

            if vehicleHash ~= 0 then
                local vehicle = AttemptCreateVehicle(vehicleHash, spawnLoc.x, spawnLoc.y, spawnLoc.z, spawnLoc.w, carIdentifier .. " (Extra)")
                if vehicle then
                    SetVehicleNumberPlateText(vehicle, carIdentifier)
                    local vehicleNetId = NetworkGetNetworkIdFromEntity(vehicle)
                    if vehicleNetId and vehicleNetId ~= 0 then
                        table.insert(ServerSpawnedRaceCarNetIds, vehicleNetId)
                        carsSuccessfullySpawned = carsSuccessfullySpawned + 1
                        DebugPrint("Spawned " .. carIdentifier .. " (Extra) (NetID: " .. vehicleNetId .. ") - Tracking NetID.")
                        TriggerClientEvent('dude_formularacing:client:SetupRaceCar', -1, vehicleNetId, carIdentifier, nil, true, source)
                    else
                        DebugPrint("ERROR: Could not get NetID for " .. carIdentifier .. " (Extra) (Handle: " .. vehicle .. "). Deleting.")
                        DeleteEntity(vehicle)
                    end
                end
            else
                DebugPrint("ERROR: Invalid hash for model 'formula' for " .. carIdentifier .. " (Extra)")
            end
            Wait(CAR_SPAWN_OVERALL_DELAY_MS)
        end

        TriggerClientEvent('ox_lib:notify', source, { title = 'Race Day', description = 'Race cars spawned! (' .. carsSuccessfullySpawned .. '/' .. (#spawnLocations + #extraSpawnLocations) .. ')', type = 'success' })
        DebugPrint("'/raceday begin' completed. Tracked " .. #ServerSpawnedRaceCarNetIds .. " NetIDs. Successfully spawned: " .. carsSuccessfullySpawned)

    elseif action == 'end' then
        -- ... (The 'end' logic can remain the same as the previous version, as it relies on ServerSpawnedRaceCarNetIds and fallback plate check)
        DebugPrint("'/raceday end' initiated by source: " .. source)
        local despawnedByNetIdCount = 0
        if #ServerSpawnedRaceCarNetIds > 0 then
            DebugPrint("Despawning " .. #ServerSpawnedRaceCarNetIds .. " cars using tracked NetIDs...")
            for _, netId in ipairs(ServerSpawnedRaceCarNetIds) do
                local vehHandle = NetworkGetEntityFromNetworkId(netId)
                if DoesEntityExist(vehHandle) then
                    local plateForLog = trim(GetVehicleNumberPlateText(vehHandle) or "UNKNOWN_PLATE")
                    DebugPrint("Despawning car by NetID: " .. netId .. " (Plate: " .. plateForLog .. ", Handle: " .. vehHandle .. ")")
                    DeleteEntity(vehHandle)
                    despawnedByNetIdCount = despawnedByNetIdCount + 1
                else
                    DebugPrint("Warning: Tracked NetID " .. netId .. " no longer corresponds to an existing entity.")
                end
            end
            ServerSpawnedRaceCarNetIds = {} 
            DebugPrint("Finished despawning by NetID. Cleared tracked list.")
        else
            DebugPrint("No NetIDs were tracked from the last '/raceday begin'. Attempting plate-based despawn as a fallback.")
        end

        local fallbackDespawnCount = 0
        local vehicles = GetGamePool('CVehicle')
        DebugPrint("Performing fallback plate-based despawn for any remaining 'FORM' cars...")
        for i = 1, #vehicles do
            local vehHandle = vehicles[i]
            if DoesEntityExist(vehHandle) then
                local rawPlate = GetVehicleNumberPlateText(vehHandle)
                if type(rawPlate) == 'string' and rawPlate ~= "" then
                    local plate = trim(rawPlate)
                    local plateNumMatch = plate:match("^FORM(%d+)$")
                    if plateNumMatch then
                        DebugPrint("Fallback: Despawning car with plate: " .. plate .. " (Handle: " .. vehHandle .. ")")
                        DeleteEntity(vehHandle)
                        fallbackDespawnCount = fallbackDespawnCount + 1
                    end
                end
            end
        end
        
        local totalDespawned = despawnedByNetIdCount + fallbackDespawnCount
        TriggerClientEvent('ox_lib:notify', source, { title = 'Race Day', description = 'Race cars despawned. (NetID: '..despawnedByNetIdCount..', FallbackPlate: '..fallbackDespawnCount..')', type = 'success' })
        DebugPrint("'/raceday end' completed. Despawned by NetID: " .. despawnedByNetIdCount .. ". Fallback despawned by plate: " .. fallbackDespawnCount)

    else
        TriggerClientEvent('ox_lib:notify', source, { title = 'Race Day', description = 'Usage: /raceday [begin/end]', type = 'inform' })
    end
end, true)

-- Function to safely create prop server-side and return NetID
local function CreateServerProp(vehicleHandle, modelName) -- *** Takes SERVER HANDLE ***
    if type(vehicleHandle) ~= 'number' or vehicleHandle == 0 or not DoesEntityExist(vehicleHandle) then
         DebugPrint("CreateServerProp: ERROR - Received invalid vehicleHandle: " .. tostring(vehicleHandle))
         return nil
    end
    if not modelName then return nil end
    local modelHash = GetHashKey(modelName)
    local coords = GetEntityCoords(vehicleHandle) -- Use SERVER HANDLE
    if not coords or type(coords.x) ~= 'number' then DebugPrint("CreateServerProp: ERROR - Invalid vehicle coordinates for handle: "..vehicleHandle); return nil end

    DebugPrint("CreateServerProp: Attempting to create prop '"..modelName.."' for vehicle handle " .. vehicleHandle)
    local prop = CreateObjectNoOffset(modelHash, coords.x, coords.y, coords.z - 5.0, true, true, false)
    Wait(250)
    if not DoesEntityExist(prop) then DebugPrint("CreateServerProp: ERROR - Failed to create prop object."); return nil end
    DebugPrint("CreateServerProp: Created prop handle " .. prop)
    local propNetId = NetworkGetNetworkIdFromEntity(prop)
    if not propNetId or propNetId == 0 then DebugPrint("CreateServerProp: ERROR - Failed to get network ID for prop."); DeleteEntity(prop); return nil end
    DebugPrint("CreateServerProp: Prop created (Handle: "..prop..", NetID: "..propNetId..")")
    return propNetId
end

-- Event handler for jacking/unjacking request
RegisterNetEvent('dude_formularacing:reqJackState', function(vehicleNetId, isBeingJacked)
    local src = source
    DebugPrint("--> Received reqJackState from src " .. src .. " for vehNetId " .. vehicleNetId .. " - Jacking: " .. tostring(isBeingJacked))

    -- *** Assign vehicleHandle FIRST ***
    local vehicleHandle = NetworkGetEntityFromNetworkId(vehicleNetId)

    -- *** NOW use vehicleHandle for checks ***
    if not DoesEntityExist(vehicleHandle) or GetEntityType(vehicleHandle) ~= 2 then
        DebugPrint("   - DENIED: Vehicle invalid or doesn't exist server-side (Handle:"..tostring(vehicleHandle).."). NetID was: "..vehicleNetId);
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', title = 'Pit Stop', description = 'Target vehicle invalid.' });
        return
    end
    DebugPrint("   - Vehicle " .. vehicleNetId .. " exists (Handle: " .. vehicleHandle .. ").") -- Log the correct handle

    -- Use vehicleHandle for state bag access
    local currentJackState = nil;
    local successState, stateValue = pcall(function() return Entity(vehicleHandle).state.jackState end)
    if successState then
        currentJackState = stateValue
    else
         DebugPrint("   - ERROR accessing jackState state bag for handle "..vehicleHandle..": "..tostring(stateValue))
    end

    if isBeingJacked then
        DebugPrint("   - Processing Jack Request...")
        if currentJackState and currentJackState.jacked then DebugPrint("   - DENIED: Already jacked via state."); return end
        local hasJack = exports.ox_inventory:Search(src, 'count', Config.PitStop.JackItem); if not hasJack or hasJack < 1 then DebugPrint("   - DENIED: Player lacks item."); TriggerClientEvent('ox_lib:notify', src, { type = 'error', title = 'Pit Stop', description = 'Need ' .. Config.PitStop.JackItem .. '.' }); return end
        DebugPrint("   - VALIDATION PASSED for player " .. src)

        -- *** Pass vehicleHandle to CreateServerProp ***
        local propNetId = CreateServerProp(vehicleHandle, Config.PitStop.JackProp)
        if not propNetId then DebugPrint("   - ERROR: Failed to create prop server-side."); TriggerClientEvent('ox_lib:notify', src, { type = 'error', title = 'Pit Stop', description = 'Failed to create jack prop.' }); return end

        local stateToSet = { jacked = true, jacker = src, propNetId = propNetId }
        -- *** Use vehicleHandle for state setting ***
        local successSet = pcall(function() Entity(vehicleHandle).state:set('jackState', stateToSet, true) end)
        if not successSet then DebugPrint("   - ERROR setting state bag!"); if DoesEntityExist(NetToEnt(propNetId)) then DeleteEntity(NetToEnt(propNetId)) end; return end
        DebugPrint("   - Set jackState state bag: " .. json.encode(stateToSet))
        Wait(50)

        DebugPrint("   - Broadcasting syncJackState (true) with propNetId: ".. propNetId)
        TriggerClientEvent('dude_formularacing:client:syncJackState', -1, vehicleNetId, true, src, propNetId)

    else -- Unjacking Logic
        DebugPrint("   - Processing Un-Jack Request...")
        if not currentJackState or not currentJackState.jacked then DebugPrint("   - DENIED: Not jacked via state."); return end
        DebugPrint("   - Vehicle state shows jacked.")

        local propNetIdToDelete = currentJackState.propNetId

        -- *** Use vehicleHandle for state setting ***
        local successClear = pcall(function() Entity(vehicleHandle).state:set('jackState', nil, true) end)
        if not successClear then DebugPrint("   - ERROR clearing state bag!"); return end
        DebugPrint("   - Cleared jackState state bag.")
        Wait(50)

        DebugPrint("   - Broadcasting syncJackState (false) with propNetId: ".. (propNetIdToDelete or 'nil'))
        TriggerClientEvent('dude_formularacing:client:syncJackState', -1, vehicleNetId, false, src, propNetIdToDelete)

        Wait(300)
        if propNetIdToDelete and propNetIdToDelete ~= 0 then
            local propToDelete = NetworkGetEntityFromNetworkId(propNetIdToDelete) -- Use correct native here too
            if DoesEntityExist(propToDelete) then DebugPrint("   - Deleting authoritative prop (NetID: " .. propNetIdToDelete .. ")"); DeleteEntity(propToDelete)
            else DebugPrint("   - Authoritative prop (NetID: " .. propNetIdToDelete .. ") not found for deletion.") end
        else DebugPrint("   - No propNetId found in state bag to delete.") end
    end
    DebugPrint("<-- Finished processing reqJackState for NetID: " .. vehicleNetId)
end)

-- Event to relay tire change notification
RegisterNetEvent('dude_formularacing:tireChanged', function(vehicleNetId, visualIndex)
    local src = source
    if type(vehicleNetId) ~= 'number' or vehicleNetId <= 0 then return end; if type(visualIndex) ~= 'number' or visualIndex < 0 or visualIndex > 3 then return end
    TriggerClientEvent('dude_formularacing:client:tireChangedUpdate', -1, src, vehicleNetId, visualIndex)
end)

-- Handle player disconnects
local function handlePlayerDrop(playerId, reason) DebugPrint("Player "..playerId.." dropped.") end
-- AddEventHandler('QBCore:Server:PlayerDropped', handlePlayerDrop)

-- Clean up on resource stop
AddEventHandler('onResourceStop', function(resourceName) if GetCurrentResourceName() ~= resourceName then return end; DebugPrint("Resource stopping.") end)

-- Test event pong
RegisterNetEvent('dude_formularacing:testf1sv_pong', function(clientMessage) local src = source; print("[TEST PONG] Received from src " .. src .. ": " .. clientMessage) end)

DebugPrint("Pit Stop Server Script Loaded. (v2.1.2 - Correct Handle Assignment)")

-- Track recovery spot states
local RecoverySpotStates = {}

-- Initialize recovery spot states on resource start
CreateThread(function()
    for trackKey, trackConfig in pairs(Config.Tracks) do
        RecoverySpotStates[trackKey] = {}
        for i = 1, #trackConfig.recoverySpots do
            RecoverySpotStates[trackKey][i] = {
                occupied = false,
                playerSource = nil,
                occupiedTime = 0
            }
        end
    end
end)

-- Clean up abandoned recovery spots periodically
CreateThread(function()
    while true do
        Wait(60000)  -- Check every minute
        local currentTime = os.time()
        
        for trackKey, trackSpots in pairs(RecoverySpotStates) do
            for spotIndex, spotState in pairs(trackSpots) do
                -- Release spot if it's been occupied for more than 5 minutes
                if spotState.occupied and currentTime - spotState.occupiedTime > 300 then
                    spotState.occupied = false
                    spotState.playerSource = nil
                    spotState.occupiedTime = 0
                    print(string.format("Released abandoned recovery spot %d on track %s", spotIndex, trackKey))
                end
            end
        end
    end
end)

RegisterNetEvent('dude_formularacing:RequestPitRecovery', function()
    local src = source
    local activeTrack = Config.ActiveTrack
    local recoverySpots = Config.Tracks[activeTrack].recoverySpots
    
    -- Get the player's current vehicle
    local playerPed = GetPlayerPed(src)
    local vehicle = GetVehiclePedIsIn(playerPed, false)
    local plate = GetVehicleNumberPlateText(vehicle)
    
    -- Extract the number from the plate (now supports FORM1-FORM16)
    local plateNumber = tonumber(plate:match("FORM(%d+)"))
    
    if not plateNumber or plateNumber < 1 or plateNumber > 16 then
        -- Fallback to random spot if plate doesn't match expected format
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Pit Recovery',
            description = 'Invalid vehicle identification',
            type = 'error'
        })
        return
    end
    
    -- Determine recovery logic based on plate number
    local selectedSpotIndex
    if plateNumber <= 10 then
        -- Main race cars use their corresponding spot
        selectedSpotIndex = plateNumber
    else
        -- Extra cars use alternative recovery method
        local availableSpots = {}
        for i, spotState in ipairs(RecoverySpotStates[activeTrack]) do
            if not spotState.occupied then
                table.insert(availableSpots, i)
            end
        end
        
        if #availableSpots > 0 then
            selectedSpotIndex = availableSpots[math.random(#availableSpots)]
        else
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Pit Recovery',
                description = 'No recovery spots currently available',
                type = 'error'
            })
            return
        end
    end
    
    -- Mark the spot as occupied
    RecoverySpotStates[activeTrack][selectedSpotIndex].occupied = true
    RecoverySpotStates[activeTrack][selectedSpotIndex].playerSource = src
    RecoverySpotStates[activeTrack][selectedSpotIndex].occupiedTime = os.time()
    
    print(string.format("Selected recovery spot %d for player %d (Plate: %s)", selectedSpotIndex, src, plate))
    
    TriggerClientEvent('dude_formularacing:PitRecoveryConfirmed', src, selectedSpotIndex)
end)

-- Event to release a recovery spot when player is done
RegisterNetEvent('dude_formularacing:ReleasePitRecoverySpot', function(spotIndex)
    local src = source
    local activeTrack = Config.ActiveTrack
    
    if RecoverySpotStates[activeTrack][spotIndex] and 
       RecoverySpotStates[activeTrack][spotIndex].playerSource == src then
        RecoverySpotStates[activeTrack][spotIndex].occupied = false
        RecoverySpotStates[activeTrack][spotIndex].playerSource = nil
        RecoverySpotStates[activeTrack][spotIndex].occupiedTime = 0
        
        print(string.format("Released recovery spot %d by player %d", spotIndex, src))
    end
end)

RegisterNetEvent('dude_formularacing:vehicleRepaired', function(vehicleNetId)
    local src = source
    DebugPrint(string.format("Vehicle Repair Request from Source %d for NetID %d", src, vehicleNetId))

    -- Validate vehicle
    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    if not DoesEntityExist(vehicle) then
        DebugPrint(string.format("ERROR: Vehicle NetID %d does not exist on server", vehicleNetId))
        return
    end

    -- Broadcast repair event to all clients
    TriggerClientEvent('dude_formularacing:client:vehicleRepaired', -1, src, vehicleNetId)
end)

RegisterNetEvent('dude_formularacing:server:handleOutOfBoundsVehicle', function(vehicleNetId)
    local src = source
    local qbxPlayer = exports.qbx_core:GetPlayer(src) -- Get QBox player object

    if not qbxPlayer then
        Config.DebugPrint("ServerPitStop", string.format("[Boundary] ERROR: Could not get player object for source %s when handling out of bounds vehicle (NetID: %s).", src, vehicleNetId))
        return
    end

    local playerName = qbxPlayer.PlayerData.name or ("Player_" .. src)
    local playerCid = qbxPlayer.PlayerData.citizenid or "UNKNOWN_CID"

    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    if not DoesEntityExist(vehicle) then
        Config.DebugPrint("ServerPitStop", string.format("[Boundary] Player %s (CID: %s, Src: %s) - Vehicle (NetID: %s) reported out of bounds but does not exist on server. Already deleted?", playerName, playerCid, src, vehicleNetId))
        return
    end

    -- Server-side validation
    local currentTrackKey = Config.ActiveTrack -- Server has its own Config.ActiveTrack synced
    local trackConfig = Config.Tracks[currentTrackKey]

    if not (trackConfig and trackConfig.boundaryCenter and trackConfig.boundaryRadius) then
        Config.DebugPrint("ServerPitStop", string.format("[Boundary] Player %s (CID: %s, Src: %s) - No boundary config for track '%s'. Cannot validate vehicle (NetID: %s). Aborting deletion.", playerName, playerCid, src, currentTrackKey, vehicleNetId))
        return
    end

    -- 1. Check model (using Config.FormulaCars which is shared)
    local vehicleModelHash = GetEntityModel(vehicle)
    local isFormulaModel = false
    local vehicleModelName = "UnknownModel"
    for _, modelNameEntry in ipairs(Config.FormulaCars) do
        if GetHashKey(modelNameEntry) == vehicleModelHash then
            isFormulaModel = true
            vehicleModelName = modelNameEntry
            break
        end
    end

    if not isFormulaModel then
        Config.DebugPrint("ServerPitStop", string.format("[Boundary] Player %s (CID: %s, Src: %s) - Vehicle (NetID: %s, ModelHash: %s, Name: %s) is NOT a formula model. Aborting deletion.", playerName, playerCid, src, vehicleNetId, vehicleModelHash, vehicleModelName))
        return
    end

    -- 2. Check plate
    local plate = GetVehicleNumberPlateText(vehicle)
    plate = plate and trim(plate) or "" -- Use the trim function defined in this file
    if not string.match(plate, "^FORM%d+$") then
        Config.DebugPrint("ServerPitStop", string.format("[Boundary] Player %s (CID: %s, Src: %s) - Vehicle (NetID: %s, Plate: '%s') does not have a 'FORM' plate. Aborting deletion.", playerName, playerCid, src, vehicleNetId, plate))
        return
    end

    -- 3. Re-check distance (server-authoritative)
    local vehCoords = GetEntityCoords(vehicle)
    local dist = #(vehCoords - trackConfig.boundaryCenter)
    local radius = trackConfig.boundaryRadius

    if dist <= radius then -- If server says it's within bounds, don't delete
        Config.DebugPrint("ServerPitStop", string.format("[Boundary] Player %s (CID: %s, Src: %s) - Vehicle (NetID: %s, Plate: %s) reported OOB by client, but server says IN BOUNDS (Dist: %.2f, Radius: %.2f) on track '%s'. Aborting deletion.", playerName, playerCid, src, vehicleNetId, plate, dist, radius, currentTrackKey))
        return
    end

    -- All checks passed, log and delete
    local logMessage = string.format(
        "[BoundaryViolation] Player: %s (CID: %s, Src: %s) | Vehicle: %s (Plate: %s, NetID: %s) | Track: %s | Details: Exceeded boundary (Dist: %.2f / Radius: %.2f). DELETING VEHICLE.",
        playerName,
        playerCid,
        src,
        vehicleModelName,
        plate,
        vehicleNetId,
        currentTrackKey,
        dist,
        radius
    )
    print(logMessage) -- Print to server console
    -- If you have a Discord logging system, you could send logMessage there too.

    -- Attempt to remove from ServerSpawnedRaceCarNetIds if it's a race day car
    local removedFromList = false
    for i, netId_iter in ipairs(ServerSpawnedRaceCarNetIds) do
        if netId_iter == vehicleNetId then
            table.remove(ServerSpawnedRaceCarNetIds, i)
            Config.DebugPrint("ServerPitStop", "[Boundary] Removed NetID " .. vehicleNetId .. " from ServerSpawnedRaceCarNetIds (out-of-bounds deletion).")
            removedFromList = true
            break
        end
    end
    if not removedFromList then
        Config.DebugPrint("ServerPitStop", "[Boundary] NetID " .. vehicleNetId .. " was not in ServerSpawnedRaceCarNetIds (likely stolen or manually spawned).")
    end

    DeleteEntity(vehicle)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Vehicle Impounded', description = 'Your vehicle was too far off track and has been impounded.', type = 'error', duration = 10000})

end)