-- client/pitstop.lua (at the top after the existing debug function)
local DebugPrint = function(msg) Config.DebugPrint("ClientPitStop", msg) end

-- Add TireDEBUG function to avoid errors
local function TireDEBUG(msg)
    if Config and Config.Debug then
        print("^3[dude_formularacing | ClientPitStop:Tires]^7: " .. msg)
    end
end

-- Simplified update function that doesn't rely on exports
local function UpdateTireUI(vehicleId)
    if not vehicleId or not DoesEntityExist(vehicleId) then return end
    -- Just trigger the event to force a refresh
    TriggerEvent('dude_formularacing:forceTireUIRefresh')
    TireDEBUG("Triggered tire UI refresh event")
end


local JackedVehiclesLocalData = {} -- Key: vehicleNetId, Value: { originalZ = number }
local isJackingOrUnjacking = false
local isChangingTire = {} -- Key: vehicleNetId .. "_" .. visualIndex .. "_" .. PlayerId(), Value: boolean


local function GetLiftAmount()
    return (Config.PitStop and Config.PitStop.JackLiftAmount) or 0.25
end

if not Config.PitStop or not Config.PitStop.Enabled then DebugPrint("Pit Stop disabled."); return end

-- LoadAsset function
local function LoadAsset(type, name, timeout)
    if not name then return false end
    timeout = timeout or 1000
    local isLoadedFunc, requestFunc
    if type == 'anim' then isLoadedFunc = HasAnimDictLoaded; requestFunc = RequestAnimDict
    elseif type == 'model' then isLoadedFunc = HasModelLoaded; requestFunc = RequestModel
    else DebugPrint("ERROR: Unknown asset type '"..type.."'"); return false end

    if isLoadedFunc(name) then return true end
    requestFunc(name)
    local waited = 0
    while not isLoadedFunc(name) and waited < timeout do Wait(50); waited = waited + 50 end
    if not isLoadedFunc(name) then DebugPrint("ERROR: Failed to load asset '"..name.."'"); return false end
    return true
end

-- Load initial pitstop assets
local function LoadPitstopAssets()
    local success = true
    success = LoadAsset('anim', Config.PitStop.JackAnimDict) and success
    success = LoadAsset('model', Config.PitStop.JackProp) and success
    success = LoadAsset('anim', Config.PitStop.TireChangeAnimDict, 500) and success
    if not success then DebugPrint("LoadPitstopAssets: Failed to load one or more assets!") end
    return success
end
CreateThread(function() Wait(500); LoadPitstopAssets() end)

-- SetVehicleZSmooth function
local function SetVehicleZSmooth(vehicle, targetZ, duration)
    if not DoesEntityExist(vehicle) then return end
    local startZ = GetEntityCoords(vehicle).z
    local change = targetZ - startZ
    if math.abs(change) < 0.01 then SetEntityCoordsNoOffset(vehicle, GetEntityCoords(vehicle).x, GetEntityCoords(vehicle).y, targetZ, false, false, false); return end -- Snap if close enough

    local startTime = GetGameTimer()
    local endTime = startTime + duration

    CreateThread(function()
        while GetGameTimer() < endTime do
            if not DoesEntityExist(vehicle) then return end
            local elapsed = GetGameTimer() - startTime
            local progress = math.min(elapsed / duration, 1.0)
            local currentZ = startZ + (change * progress)
            local currentCoords = GetEntityCoords(vehicle)
            SetEntityCoordsNoOffset(vehicle, currentCoords.x, currentCoords.y, currentZ, false, false, false)
            Wait(0)
        end
        if DoesEntityExist(vehicle) then
            local finalCoords = GetEntityCoords(vehicle)
            SetEntityCoordsNoOffset(vehicle, finalCoords.x, finalCoords.y, targetZ, false, false, false) -- Ensure final position
        end
    end)
end

-- Pit Zone Setup
local pitZone = nil
local isInPitZone = false

local function CreatePitZone()
    local activeTrackConfig = Config.Tracks[Config.ActiveTrack]
    if not activeTrackConfig or not activeTrackConfig.pitZone then
        DebugPrint("No pit zone configuration found for active track")
        return
    end

    pitZone = lib.zones.poly({
        points = activeTrackConfig.pitZone.points,
        thickness = activeTrackConfig.pitZone.thickness or 6.0,
        debug = Config.Debug
    })
end

-- Speed Limit Function
local function LimitVehicleSpeed(vehicle)
    if DoesEntityExist(vehicle) then
        local activeTrackConfig = Config.Tracks[Config.ActiveTrack]
        local speedMph = activeTrackConfig.maxSpeed or 50.0
        SetVehicleMaxSpeed(vehicle, speedMph * 0.44704) -- Convert MPH to m/s
    end
end

-- Reset Vehicle Speed Function
local function ResetVehicleSpeed(vehicle)
    if DoesEntityExist(vehicle) then
        SetVehicleMaxSpeed(vehicle, 0.0) -- Reset to default
    end
end

-- Speed Limit Thread
CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        
        if IsPedInAnyVehicle(ped, false) then
            local vehicle = GetVehiclePedIsIn(ped, false)
            local activeTrackConfig = Config.Tracks[Config.ActiveTrack]
            
            if pitZone and DoesEntityExist(vehicle) then
                local coords = GetEntityCoords(vehicle)
                local inZone = pitZone:contains(coords)
                local checkInterval = activeTrackConfig.speedCheckInterval or 250
                
                if inZone and not isInPitZone then
                    isInPitZone = true
                    LimitVehicleSpeed(vehicle)
                    DebugPrint("Entered Pit Zone - Speed Limited")
                elseif not inZone and isInPitZone then
                    isInPitZone = false
                    ResetVehicleSpeed(vehicle)
                    DebugPrint("Left Pit Zone - Speed Restored")
                end
                
                sleep = checkInterval
            end
        end
        
        Wait(sleep)
    end
end)

-- Create the pit zone when the resource starts
CreateThread(function()
    Wait(2000) -- Wait for other resources to load
    CreatePitZone()
end)

-- Add ox_target options to Formula Cars
CreateThread(function()
    DebugPrint("Attempting to add ox_target for Formula Cars (v3.0.5)...")
    Wait(2000) -- Wait for other resources like ox_inventory
    if not exports.ox_target then DebugPrint("ERROR: ox_target export not found!"); return end
    if not Config.FormulaCarHashes or #Config.FormulaCarHashes == 0 then DebugPrint("ERROR: Config.FormulaCarHashes empty."); return end

    local targetOptions = {
        -- Option 1: Jack the Car
        {
            name = 'formulacar_jack_action',
            icon = Config.PitStop.JackTargetIcon or 'fa-solid fa-arrow-up-from-bracket',
            label = Config.PitStop.JackTargetLabel or 'Use Car Jack',
            distance = Config.PitStop.JackTargetDistance or 1.5,
            canInteract = function(entity, distance, coords, name, bone)
			 if not pitZone or not pitZone:contains(coords) then
        return false
    end
                if isJackingOrUnjacking then return false end -- Don't show if any action is in progress
                if not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then return false end
                local vehicleNetId = NetworkGetNetworkIdFromEntity(entity)
                if vehicleNetId == 0 then return false end -- Need network ID

                -- Check if ALREADY jacked (using both state bag and local cache)
                local jackState = Entity(entity).state.jackState
                if (jackState and jackState.jacked) or JackedVehiclesLocalData[vehicleNetId] then
                    return false -- Do not show JACK option if it's already jacked
                end

                -- Check if player has the jack item
                local hasJackItem = exports.ox_inventory:Search('count', Config.PitStop.JackItem) >= 1
                return hasJackItem
            end,
            onSelect = function(data)
                if isJackingOrUnjacking then return end -- Double check flag
                local vehicle = data.entity
                if not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then return end
                local vehicleNetId = NetworkGetNetworkIdFromEntity(vehicle)
                if vehicleNetId == 0 then return end

                -- Re-verify conditions before proceeding
                local jackState = Entity(vehicle).state.jackState
                if (jackState and jackState.jacked) or JackedVehiclesLocalData[vehicleNetId] then DebugPrint("Jack onSelect: Vehicle already jacked."); return end
                if exports.ox_inventory:Search('count', Config.PitStop.JackItem) < 1 then DebugPrint("Jack onSelect: Player lost jack item?"); exports['ox_lib']:notify({ type = 'error', title = 'Pit Stop', description = 'Missing '..(Config.PitStop.JackItem or 'jack') }); return end
                if not LoadPitstopAssets() then exports['ox_lib']:notify({ type = 'error', title = 'Pit Stop', description = 'Required assets not loaded.' }); return end

                isJackingOrUnjacking = true -- Set flag: Action starting
                DebugPrint("onSelect (Jack) - Attempting to jack vehicle NetID: " .. vehicleNetId)

                local playerPed = PlayerPedId()
                FreezeEntityPosition(playerPed, true)
                local animDict = Config.PitStop.JackAnimDict
                local animName = Config.PitStop.JackAnimName
                local animDuration = Config.PitStop.JackDuration or 2000
                local animFlags = Config.PitStop.JackAnimFlags or 49
                TaskPlayAnim(playerPed, animDict, animName, 8.0, -8.0, animDuration, animFlags, 0, false, false, false)
                DebugPrint("Playing jacking animation...")

                SetTimeout(animDuration, function()
                    FreezeEntityPosition(playerPed, false)
                    -- Check if the vehicle is still valid and NOT jacked before sending server request
                    local currentVehicle = data.entity -- Re-get entity in case handle changed? (Shouldn't but safe)
                    if DoesEntityExist(currentVehicle) and GetEntityType(currentVehicle) == 2 then
                        local currentNetId = NetworkGetNetworkIdFromEntity(currentVehicle)
                        local currentJackState = Entity(currentVehicle).state.jackState
                        if currentNetId == vehicleNetId and currentNetId ~= 0 and (not currentJackState or not currentJackState.jacked) and not JackedVehiclesLocalData[currentNetId] then
                            DebugPrint("Animation finished, triggering server event 'dude_formularacing:reqJackState' (TRUE) for NetID: " .. currentNetId)
                            TriggerServerEvent('dude_formularacing:reqJackState', currentNetId, true)
                        else
                            DebugPrint("Vehicle state changed/invalid during jacking animation. Aborting server request.");
                            isJackingOrUnjacking = false -- Reset flag as the action failed before server confirmation
                        end
                    else
                        DebugPrint("Vehicle disappeared during jacking animation. Aborting server request.");
                        isJackingOrUnjacking = false -- Reset flag as the action failed
                    end
                    -- Reset happens in sync event handler.
                end)
            end,
        },
        -- Option 2: Unjack the Car
        {
            name = 'formulacar_unjack_action',
            icon = Config.PitStop.UnjackTargetIcon or 'fa-solid fa-arrow-down-to-bracket',
            label = Config.PitStop.UnjackTargetLabel or 'Remove Jack',
            distance = Config.PitStop.UnjackTargetDistance or 1.5,
            canInteract = function(entity, distance, coords, name, bone)
			 if not pitZone or not pitZone:contains(coords) then
        return false
    end
                if isJackingOrUnjacking then return false end -- Don't show if any action is in progress
                if not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then return false end
                local vehicleNetId = NetworkGetNetworkIdFromEntity(entity)
                if vehicleNetId == 0 then return false end

                -- Check if vehicle IS jacked (using both state bag and local cache)
                local jackState = Entity(entity).state.jackState
                if (jackState and jackState.jacked) or JackedVehiclesLocalData[vehicleNetId] then
                    return true -- Show UNJACK option only if it IS jacked
                end
                return false
            end,
            onSelect = function(data)
                 if isJackingOrUnjacking then return end -- Double check flag
                 local vehicle = data.entity
                 if not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then return end
                 local vehicleNetId = NetworkGetNetworkIdFromEntity(vehicle)
                 if vehicleNetId == 0 then return end

                 -- Re-verify state before proceeding
                 local jackState = Entity(vehicle).state.jackState
                 if not ((jackState and jackState.jacked) or JackedVehiclesLocalData[vehicleNetId]) then DebugPrint("Unjack onSelect: Vehicle no longer jacked."); return end
                 if not LoadAsset('anim', Config.PitStop.JackAnimDict) then exports['ox_lib']:notify({ type = 'error', title = 'Pit Stop', description = 'Animation asset not loaded.' }); return end

                isJackingOrUnjacking = true -- Set flag: Action starting
                DebugPrint("onSelect (Unjack) - Triggering server unjack for vehicle NetID: " .. vehicleNetId)

                local playerPed = PlayerPedId()
                FreezeEntityPosition(playerPed, true)
                local animDict = Config.PitStop.JackAnimDict
                local animName = Config.PitStop.JackAnimName
                local animDuration = Config.PitStop.JackDuration or 2000
                local animFlags = Config.PitStop.JackAnimFlags or 49
                TaskPlayAnim(playerPed, animDict, animName, 8.0, -8.0, animDuration, animFlags, 0, false, false, false)
                DebugPrint("Playing unjacking animation...")

                SetTimeout(animDuration, function()
                    FreezeEntityPosition(playerPed, false)
                    local currentVehicle = data.entity
                    -- Check if still jacked before sending server request
                    local currentJackState = DoesEntityExist(currentVehicle) and Entity(currentVehicle).state.jackState or nil
                    if DoesEntityExist(currentVehicle) and NetworkGetNetworkIdFromEntity(currentVehicle) == vehicleNetId and ((currentJackState and currentJackState.jacked) or JackedVehiclesLocalData[vehicleNetId]) then
                        DebugPrint("Animation finished, triggering server event 'dude_formularacing:reqJackState' (FALSE) for NetID: " .. vehicleNetId)
                        TriggerServerEvent('dude_formularacing:reqJackState', vehicleNetId, false)
                    else
                        DebugPrint("Vehicle state changed during unjacking animation. Aborting server request.");
                        isJackingOrUnjacking = false -- Reset flag as the action failed before server confirmation
                    end
                    -- Reset happens in sync event handler.
                end)
            end,
        },
        -- Option 3: Repair Vehicle
    {
        name = 'formulacar_repair_action',
        icon = 'fa-solid fa-tools',
        label = 'Repair Vehicle',
        distance = Config.PitStop.RepairTargetDistance or 1.5,
        canInteract = function(entity, distance, coords, name, bone)
            -- Pit zone check
            if not pitZone or not pitZone:contains(coords) then
                return false
            end

            -- Check if vehicle exists and is of correct type
            if not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then 
                return false 
            end

            local vehicleNetId = NetworkGetNetworkIdFromEntity(entity)
            if vehicleNetId == 0 then return false end

            -- Check if vehicle is jacked
            local jackState = Entity(entity).state.jackState
            if not ((jackState and jackState.jacked) or JackedVehiclesLocalData[vehicleNetId]) then
                return false
            end

            -- Check if player has repair item
            local hasRepairItem = exports.ox_inventory:Search('count', Config.PitStop.RepairItem) >= 1
            return hasRepairItem
        end,
        onSelect = function(data)
    local vehicle = data.entity
    local vehicleNetId = NetworkGetNetworkIdFromEntity(vehicle)
    if vehicleNetId == 0 then return end

    -- Re-verify conditions
    local jackState = Entity(vehicle).state.jackState
    if not ((jackState and jackState.jacked) or JackedVehiclesLocalData[vehicleNetId]) then
        exports['ox_lib']:notify({ 
            type = 'error', 
            title = 'Pit Stop', 
            description = 'Vehicle must be jacked to repair' 
        })
        return
    end

    if exports.ox_inventory:Search('count', Config.PitStop.RepairItem) < 1 then 
        exports['ox_lib']:notify({ 
            type = 'error', 
            title = 'Pit Stop', 
            description = 'Missing '..(Config.PitStop.RepairItem or 'repair tool') 
        })
        return 
    end

    -- Load repair animation assets
    if not LoadAsset('anim', Config.PitStop.RepairAnimDict) then 
        exports['ox_lib']:notify({ 
            type = 'error', 
            title = 'Pit Stop', 
            description = 'Animation assets not loaded' 
        })
        return
    end

    local playerPed = PlayerPedId()
    FreezeEntityPosition(playerPed, true)
    TaskPlayAnim(playerPed, 
        Config.PitStop.RepairAnimDict, 
        Config.PitStop.RepairAnimName, 
        8.0, -8.0, 
        Config.PitStop.RepairAnimDuration, 
        Config.PitStop.RepairAnimFlags or 49, 
        0, false, false, false
    )

    -- Start repair progress
    if lib.progressCircle({
        duration = Config.PitStop.RepairAnimDuration,
        label = 'Repairing Vehicle',
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = {
            car = true
        }
    }) then
        FreezeEntityPosition(playerPed, false)
        
        -- Repair complete
        SetVehicleFixed(vehicle)
		SetVehicleEngineOn(vehicle, true, true, false)
        --SetVehicleFuelLevel(vehicle, 100.0)
        
        -- Reset tire wear
        -- if exports.dude_formularacing and exports.dude_formularacing.ResetTireWear then
            -- exports.dude_formularacing:ResetTireWear(vehicle)
        -- end

        exports['ox_lib']:notify({
            title = 'Pit Stop',
            description = 'Vehicle fully repaired and refueled',
            type = 'success'
        })

        -- Notify server about repair
        TriggerServerEvent('dude_formularacing:vehicleRepaired', vehicleNetId)

        -- Optional: Consume repair item
        TriggerServerEvent('dude_formularacing:ConsumeRepairItem')
    else
        FreezeEntityPosition(playerPed, false)
        exports['ox_lib']:notify({
            title = 'Pit Stop',
            description = 'Repair cancelled',
            type = 'error'
        })
    end
end,
    }
    }

    -- Option 3-6: Tire Changing Targets
    local tireLabels = { [0]="FL", [1]="FR", [2]="RL", [3]="RR" }
    for visualIndex = 0, 3 do
        local boneName = Config.PitStop.TireBones and Config.PitStop.TireBones[visualIndex]
        if boneName then
            local tireLabel = tireLabels[visualIndex] or tostring(visualIndex)
            local formattedLabel = string.format(Config.PitStop.TireTargetLabel or 'Change Tire (%s)', tireLabel)

            table.insert(targetOptions, {
                name = 'formulacar_tire_'..visualIndex,
                icon = Config.PitStop.TireTargetIcon or 'fa-solid fa-wrench',
                label = formattedLabel,
                distance = Config.PitStop.TireTargetDistance or 1.2,
                bones = { boneName }, -- Target specific bones for tires
                canInteract = function(entity, distance, coords, name, bone)
				 if not pitZone or not pitZone:contains(coords) then
        return false
    end
                    local vNetId = NetworkGetNetworkIdFromEntity(entity)
                    if vNetId == 0 then return false end
                    -- Create a unique key for this specific player changing this specific tire on this vehicle
                    local tireChangeKey = vNetId .. "_" .. visualIndex .. "_" .. PlayerId()
                    if isJackingOrUnjacking or isChangingTire[tireChangeKey] then return false end -- Check global and tire-specific flags

                    -- Vehicle must be jacked to change tires
                    local jState = Entity(entity).state.jackState
                    if not ((jState and jState.jacked) or JackedVehiclesLocalData[vNetId]) then return false end

                    -- Check tire wear state
                    local tState = Entity(entity).state.tireInfo
                    -- Show option if tire is not already full (or near full)
                    if not tState or not tState.wear or (tState.wear[visualIndex] and tState.wear[visualIndex] >= 99.9) then return false end

                    -- Check if player has wrench
                    local hasWrench = exports.ox_inventory:Search('count', Config.PitStop.ImpactWrenchItem) >= 1
                    return hasWrench
                end,
                onSelect = function(data)
                    -- Capture the correct visualIndex for this specific tire option
                    local currentVisualIndex = visualIndex -- Use the visualIndex captured when the table entry was created
                    local vehicle = data.entity
                    local vehicleNetId = NetworkGetNetworkIdFromEntity(vehicle)
                    if vehicleNetId == 0 then return end
                    local tireChangeKey = vehicleNetId .. "_" .. currentVisualIndex .. "_" .. PlayerId()

                    if isJackingOrUnjacking or isChangingTire[tireChangeKey] then return end -- Re-check flags

                    -- Re-verify conditions
                    local jackState = Entity(vehicle).state.jackState
                    if not ((jackState and jackState.jacked) or JackedVehiclesLocalData[vehicleNetId]) then DebugPrint("Tire onSelect: Vehicle not jacked."); return end
                    if exports.ox_inventory:Search('count', Config.PitStop.ImpactWrenchItem) < 1 then DebugPrint("Tire onSelect: Missing wrench."); exports['ox_lib']:notify({ type = 'error', title = 'Pit Stop', description = 'Missing '..(Config.PitStop.ImpactWrenchItem or 'wrench') }); return end
                    local tireStateInfo = Entity(vehicle).state.tireInfo
                    if not tireStateInfo or not tireStateInfo.wear or (tireStateInfo.wear[currentVisualIndex] and tireStateInfo.wear[currentVisualIndex] >= 99.9) then DebugPrint("Tire already changed/state invalid."); return end
                    if not LoadAsset('anim', Config.PitStop.TireChangeAnimDict) then exports['ox_lib']:notify({ type = 'error', title = 'Pit Stop', description = 'Animation asset not loaded.' }); return end

                    DebugPrint(string.format("onSelect (Tire %d - %s) - Starting change for vehNetId %d", currentVisualIndex, tireLabels[currentVisualIndex] or '?', vehicleNetId))
                    isChangingTire[tireChangeKey] = true -- Set tire-specific flag
                    local playerPed = PlayerPedId()
                    FreezeEntityPosition(playerPed, true)
                    TaskPlayAnim(playerPed, Config.PitStop.TireChangeAnimDict, Config.PitStop.TireChangeAnimName, 8.0, -8.0, Config.PitStop.TireChangeDuration, Config.PitStop.TireChangeAnimFlags or 49, 0, false, false, false)

                    SetTimeout(Config.PitStop.TireChangeDuration or 3000, function()
                        FreezeEntityPosition(playerPed, false)
                        -- Check if still jacked after animation
                        local currentVehicle = data.entity -- Re-get entity handle
                        local currentJackStateCheck = DoesEntityExist(currentVehicle) and Entity(currentVehicle).state.jackState or nil
                        if DoesEntityExist(currentVehicle) and NetworkGetNetworkIdFromEntity(currentVehicle) == vehicleNetId and ((currentJackStateCheck and currentJackStateCheck.jacked) or JackedVehiclesLocalData[vehicleNetId]) then
                            DebugPrint(string.format("Finished changing Tire %d for vehNetId %d.", currentVisualIndex, vehicleNetId))
                            -- IMPORTANT: Use the EXPORTED function to set wear
                            if exports.dude_formularacing and exports.dude_formularacing.SetTireWear then
                                exports.dude_formularacing:SetTireWear(vehicle, currentVisualIndex, 100.0) -- Pass vehicle handle, visual index, and new value
                                DebugPrint("Called exported SetTireWear function.")
                            else
                                DebugPrint("ERROR: Cannot find exports.dude_formularacing.SetTireWear function! Cannot set tire wear.")
                            end

                            exports['ox_lib']:notify({ title = 'Pit Stop', description = ('Tire %s Changed'):format(tireLabels[currentVisualIndex] or '?'), type = 'success' })
                            TriggerServerEvent('dude_formularacing:tireChanged', vehicleNetId, currentVisualIndex) -- Notify server (and thus others)
                        else
                            DebugPrint(string.format("Vehicle %d unjacked or invalid before tire %d change finished.", vehicleNetId, currentVisualIndex))
                        end
                        isChangingTire[tireChangeKey] = false -- Reset tire-specific flag
                    end)
                end,
            })
        else DebugPrint("Warning: No bone name for tire index " .. visualIndex .. " in Config.PitStop.TireBones") end
    end
	

    -- Register the target options with ox_target for the specified vehicle models
    exports.ox_target:addModel(Config.FormulaCarHashes, targetOptions)
    DebugPrint("Added ox_target options for models: " .. table.concat(Config.FormulaCarHashes, ", "))

end)

-- Function to wait for and return the authoritative prop handle from state bag
local function GetAuthoritativePropFromState(vehicleNetId, timeout)
    timeout = timeout or 1500
    local waitEndTime = GetGameTimer() + timeout
    local vehicle = NetToVeh(vehicleNetId)
    if not DoesEntityExist(vehicle) then
        DebugPrint("GetAuthoritativePropFromState: Vehicle NetID "..vehicleNetId.." not found locally.")
        return nil
    end
    local propToReturn = nil
    local propNetIdFound = nil

    while GetGameTimer() < waitEndTime do
        local jackState = Entity(vehicle).state.jackState
        local propNetId = jackState and jackState.propNetId or nil
        if propNetId and propNetId ~= 0 then
            propNetIdFound = propNetId -- Store the NetID found in the state bag
            local prop = NetToEnt(propNetId)
            if DoesEntityExist(prop) then
                propToReturn = prop -- Store the entity handle if it exists locally
                break
            end
        end
        Wait(100)
    end

    if propToReturn then
        DebugPrint("GetAuthoritativePropFromState: Found prop entity (Handle: "..propToReturn..", NetID: "..propNetIdFound..") for vehNetID "..vehicleNetId)
    elseif propNetIdFound then
         DebugPrint("GetAuthoritativePropFromState: Found propNetId "..propNetIdFound.." in state, but entity (Handle: "..tostring(NetToEnt(propNetIdFound))..") doesn't exist locally for vehNetID "..vehicleNetId)
    else
        DebugPrint("GetAuthoritativePropFromState: Timed out waiting for propNetId in state bag for vehNetID "..vehicleNetId)
    end
    return propToReturn, propNetIdFound -- Return both entity handle (if found) and the netID from state
end

-- Event handler for sync broadcast from server
RegisterNetEvent('dude_formularacing:client:syncJackState', function(vehicleNetId, isBeingJacked, playerServerId, authoritativePropNetId)
    DebugPrint("--> Received syncJackState: vehNetId="..vehicleNetId.." Jacking="..tostring(isBeingJacked).." Initiator="..playerServerId.." PropNetID="..(authoritativePropNetId or 'nil'))
    isJackingOrUnjacking = true
    local vehicle = NetToVeh(vehicleNetId)
    if not DoesEntityExist(vehicle) then
        DebugPrint("   - ERROR: Vehicle NetID "..vehicleNetId.." not found locally. Aborting sync.");
        isJackingOrUnjacking = false; return
    end
    DebugPrint("   - Vehicle entity exists locally (Handle: " .. vehicle .. ")")
    local playerPed = PlayerPedId()
    local isDriver = GetPedInVehicleSeat(vehicle, -1) == playerPed

    if isBeingJacked then
        local propToUse, propNetIdFromState = GetAuthoritativePropFromState(vehicleNetId, 2500)
        if not propNetIdFromState and authoritativePropNetId and authoritativePropNetId ~= 0 then
            DebugPrint("   - Using fallback propNetId from event: " .. authoritativePropNetId)
            propNetIdFromState = authoritativePropNetId
            propToUse = NetToEnt(authoritativePropNetId)
        end
        if not propNetIdFromState then
            DebugPrint("   - ERROR: Could not get authoritative propNetId from state or event! Aborting visual sync.");
            isJackingOrUnjacking = false; return
        end
        if not propToUse or not DoesEntityExist(propToUse) then
             DebugPrint("   - WARNING: Prop entity (NetID: "..propNetIdFromState..") not found locally, visuals might be incomplete, but proceeding with lift/freeze.")
        end

        local originalZ = GetEntityCoords(vehicle).z
        if not isDriver then
            local LIFT_AMOUNT = GetLiftAmount()
            local targetZ = originalZ + LIFT_AMOUNT
            DebugPrint(string.format("   - Non-Driver: OrigZ: %.4f | TargetZ: %.4f", originalZ, targetZ))
            if propToUse and DoesEntityExist(propToUse) then
                DebugPrint("   - Placing prop (Handle: "..propToUse..")"); PlaceObjectOnGroundProperly(propToUse); Wait(50)
                DebugPrint("   - Attaching prop"); local boneName = Config.PitStop.JackAttachBone or 'chassis_dummy'; local boneIndex = GetEntityBoneIndexByName(vehicle, boneName); if boneIndex == -1 then DebugPrint(" WARN: Invalid bone '"..boneName.."', using root."); boneIndex = 0 end
                local offset = Config.PitStop.JackAttachOffset or vector3(0.0,0.0,-0.8); local rotation = Config.PitStop.JackAttachRotation or vector3(0.0,0.0,0.0)
                if GetEntityAttachedTo(propToUse) then DetachEntity(propToUse, false, false); Wait(0) end
                AttachEntityToEntity(propToUse, vehicle, boneIndex, offset.x, offset.y, offset.z, rotation.x, rotation.y, rotation.z, false, false, true, false, 2, true); Wait(100)
                if GetEntityAttachedTo(propToUse) ~= vehicle then DebugPrint("   - ERROR: Prop attach failed!") else DebugPrint("   - Prop attached.") end
                DebugPrint("   - NoCollision"); SetEntityNoCollisionEntity(vehicle, propToUse, true); SetEntityNoCollisionEntity(propToUse, vehicle, true); Wait(50)
            else
                DebugPrint("   - Skipping prop placement/attach visuals as prop entity not found locally.")
            end
            DebugPrint("   - Freezing vehicle"); FreezeEntityPosition(vehicle, true); Wait(50)
            DebugPrint("   - Lifting vehicle"); SetVehicleZSmooth(vehicle, targetZ, 500); Wait(600)
        else
            DebugPrint("   - Driver: Freezing vehicle"); FreezeEntityPosition(vehicle, true); Wait(50)
            DebugPrint("   - Driver: Skipping prop attach/lift visuals"); Wait(100)
        end

        JackedVehiclesLocalData[vehicleNetId] = { originalZ = originalZ }
        DebugPrint("   - Stored local data (OrigZ: " .. string.format("%.4f", originalZ) .. ") for NetID: " .. vehicleNetId)

        local localPlayerServerId = GetPlayerServerId(PlayerId())
        if playerServerId == localPlayerServerId then
             DebugPrint("   - Initiator is local, clearing tasks"); ClearPedTasks(PlayerPedId())
        end
    else -- Unjacking Logic
        DebugPrint("   - Processing Unjack request.")
        local localData = JackedVehiclesLocalData[vehicleNetId]
        local originalZ = localData and localData.originalZ or nil
        local propToDetach = nil
        local propNetIdToUse = authoritativePropNetId

        if propNetIdToUse and propNetIdToUse ~= 0 then
            propToDetach = NetToEnt(propNetIdToUse)
            if propToDetach and DoesEntityExist(propToDetach) then
                if GetEntityAttachedTo(propToDetach) == vehicle then
                    DebugPrint("   - Detaching prop visually (Handle: "..propToDetach..", NetID: "..propNetIdToUse..")"); DetachEntity(propToDetach, true, true); Wait(100)
                else
                    DebugPrint("   - Prop (Handle: "..propToDetach..", NetID: "..propNetIdToUse..") exists locally but is not attached to vehicle (Handle: "..vehicle..").")
                end
            else
                 DebugPrint("   - Prop entity (NetID: "..propNetIdToUse..") not found locally to detach visually.")
            end
        else
            DebugPrint("   - No authoritativePropNetId received in event to detach visually.")
        end

        if not isDriver then
            if DoesEntityExist(vehicle) and originalZ then
                DebugPrint("   - Non-Driver: Lowering vehicle to Z: " .. string.format("%.4f", originalZ)); SetVehicleZSmooth(vehicle, originalZ, 500); Wait(600)
            elseif DoesEntityExist(vehicle) then
                 DebugPrint("   - WARN: Non-Driver: Cannot lower vehicle, originalZ missing from local data for NetID: " .. vehicleNetId)
            end
        else
            DebugPrint("   - Driver: Skipping lower visual"); Wait(100)
        end

        if DoesEntityExist(vehicle) then
            DebugPrint("   - Setting velocity zero"); SetVehicleForwardSpeed(vehicle, 0.0); SetEntityVelocity(vehicle, 0.0, 0.0, 0.0); Wait(50)
            DebugPrint("   - Unfreezing vehicle"); FreezeEntityPosition(vehicle, false); Wait(100)
        else
            DebugPrint("   - Vehicle NetID "..vehicleNetId.." not found to unfreeze.")
        end

        if JackedVehiclesLocalData[vehicleNetId] then
            JackedVehiclesLocalData[vehicleNetId] = nil
            DebugPrint("   - Cleared local jack data for NetID: " .. vehicleNetId)
            local myPlayerIdStr = "_" .. PlayerId()
            local prefix = vehicleNetId .. "_"
            for key, changing in pairs(isChangingTire) do
                 if changing and string.sub(key, 1, #prefix) == prefix and string.sub(key, -#myPlayerIdStr) == myPlayerIdStr then
                     DebugPrint("   - Clearing active tire change flag: " .. key)
                     isChangingTire[key] = false
                 end
            end
        end
    end

    DebugPrint("<-- Finished processing syncJackState for NetID: " .. vehicleNetId)
    isJackingOrUnjacking = false
    DebugPrint("isJackingOrUnjacking flag reset (end of sync handler).")
end)

-- Enhance the event handler to immediately update UI when a tire is changed by another player
RegisterNetEvent('dude_formularacing:client:tireChangedUpdate', function(sourcePlayerSrvId, vehicleNetId, changedVisualIndex)
    local localPlayer = PlayerId()
    local localPlayerSrvId = GetPlayerServerId(localPlayer)
    if sourcePlayerSrvId == localPlayerSrvId then return end -- Ignore if self

    TireDEBUG("Received tireChangedUpdate event: FromSrvId=" .. sourcePlayerSrvId .. " vehNetId=" .. vehicleNetId .. ", tireIdx=" .. changedVisualIndex)
    local playerPed = PlayerPedId()
    local currentVehId = GetVehiclePedIsIn(playerPed, false)

    if currentVehId and currentVehId ~= 0 then
        local currentVehNetId = NetworkGetNetworkIdFromEntity(currentVehId)
        if currentVehNetId == vehicleNetId then
            TireDEBUG(" > Event is for the vehicle I am currently in (NativeID: " .. currentVehId .. ")")
            -- Just trigger the refresh event
            TriggerEvent('dude_formularacing:forceTireUIRefresh')
        end
    end
end)

-- Event handler for vehicle repair updates
RegisterNetEvent('dude_formularacing:client:vehicleRepaired', function(sourcePlayerSrvId, vehicleNetId)
    local localPlayer = PlayerId()
    local localPlayerSrvId = GetPlayerServerId(localPlayer)
    if sourcePlayerSrvId == localPlayerSrvId then return end -- Ignore if self

    local playerPed = PlayerPedId()
    local currentVehId = GetVehiclePedIsIn(playerPed, false)

    if currentVehId and currentVehId ~= 0 then
        local currentVehNetId = NetworkGetNetworkIdFromEntity(currentVehId)
        if currentVehNetId == vehicleNetId then
            DebugPrint(string.format("Received vehicle repair for vehicle I'm in. NetID: %d", vehicleNetId))
            
            -- Comprehensive repair for the vehicle the player is in
            SetVehicleFixed(currentVehId)
            SetVehicleDeformationFixed(currentVehId)
            SetVehicleDirtLevel(currentVehId, 0.0)
            SetVehicleEngineHealth(currentVehId, 1000.0)
            SetVehicleBodyHealth(currentVehId, 1000.0)
            SetEntityHealth(currentVehId, GetEntityMaxHealth(currentVehId))

            -- Optional: Reset tire wear if needed
            -- if exports.dude_formularacing and exports.dude_formularacing.ResetTireWear then
                -- exports.dude_formularacing:ResetTireWear(currentVehId)
            -- end

            exports['ox_lib']:notify({
                title = 'Pit Stop',
                description = 'Vehicle repaired by pit crew',
                type = 'success'
            })
        end
    end
end)

-- Clean up on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    DebugPrint("Resource stopping. Cleaning up pitstop state.")
    isJackingOrUnjacking = false
    isChangingTire = {}
    JackedVehiclesLocalData = {}
	
	-- Add pit zone cleanup
    if pitZone then
        pitZone:remove()
        pitZone = nil
    end
	
	
    if exports.ox_target and Config.FormulaCarHashes and #Config.FormulaCarHashes > 0 then
        DebugPrint("Removing ox_target models...")
        pcall(function() exports.ox_target:removeModel(Config.FormulaCarHashes) end)
        DebugPrint("Removed ox_target models.")
    end
end)

local vehicleColors = {
    {primary = {31, 31, 31}, secondary = {31, 31, 31}},     -- Dark Gray
    {primary = {120, 0, 0}, secondary = {120, 0, 0}},       -- Dark Red
    {primary = {0, 51, 102}, secondary = {0, 51, 102}},     -- Navy Blue
    {primary = {102, 51, 0}, secondary = {102, 51, 0}},     -- Brown
    {primary = {0, 102, 51}, secondary = {0, 102, 51}},     -- Dark Green
    {primary = {51, 0, 102}, secondary = {51, 0, 102}},     -- Dark Purple
    {primary = {204, 102, 0}, secondary = {204, 102, 0}},   -- Dark Orange
    {primary = {0, 102, 102}, secondary = {0, 102, 102}}    -- Teal
}

-- Performance Upgrade Function
local function UpgradePerformance(vehicle)
    SetVehicleModKit(vehicle, 0)
    ToggleVehicleMod(vehicle, 18, true) -- Assuming this is for 'turbo'
    SetVehicleFixed(vehicle) -- Good to ensure it's repaired on spawn

    -- Apply other performance mods if configured (example from your old code)
    local PERFORMANCE_MOD_INDICES = { 11, 12, 13, 15, 16 } -- SPOILER, FRONT_BUMPER, SKIRT, EXHAUST, CHASSIS/FRAME
    for _, modType in ipairs(PERFORMANCE_MOD_INDICES) do
        local maxMod = GetNumVehicleMods(vehicle, modType) - 1
        if maxMod >= 0 then -- Check if any mods of this type exist
            SetVehicleMod(vehicle, modType, maxMod, false)
        end
    end
    -- You might want to add engine, brakes, transmission explicitly if they are not covered by ToggleVehicleMod
    -- SetVehicleMod(vehicle, 11, GetNumVehicleMods(vehicle, 11) - 1, false) -- Engine
    -- SetVehicleMod(vehicle, 12, GetNumVehicleMods(vehicle, 12) - 1, false) -- Brakes
    -- SetVehicleMod(vehicle, 13, GetNumVehicleMods(vehicle, 13) - 1, false) -- Transmission
    -- SetVehicleMod(vehicle, 15, GetNumVehicleMods(vehicle, 15) - 1, false) -- Suspension
    -- SetVehicleMod(vehicle, 16, GetNumVehicleMods(vehicle, 16) - 1, false) -- Armor (usually not for race cars)
end

RegisterNetEvent('dude_formularacing:client:SetupRaceCar', function(vehicleNetId, plateText, liveryIndex, isExtraCar, adminServerId)
    DebugPrint("Received SetupRaceCar event: NetID=" .. vehicleNetId .. " Plate=" .. plateText .. " LiveryIdx=" .. tostring(liveryIndex) .. " IsExtra=" .. tostring(isExtraCar))
    local vehicle = NetToVeh(vehicleNetId)

    local attempts = 0
    -- Wait up to 2.5 seconds (50 * 50ms) instead of 1 second
    while not DoesEntityExist(vehicle) and attempts < 100 do
        Wait(50)
        vehicle = NetToVeh(vehicleNetId)
        attempts = attempts + 1
    end

    if DoesEntityExist(vehicle) then
        DebugPrint("Setting up vehicle: " .. plateText .. " (Local Handle: " .. vehicle .. ")")
       SetVehicleHasBeenOwnedByPlayer(vehicle, true)
        SetEntityAsMissionEntity(vehicle, true, false)

        UpgradePerformance(vehicle)

        if isExtraCar then
            if #vehicleColors > 0 then
                local colorSet = vehicleColors[math.random(#vehicleColors)]
                SetVehicleCustomPrimaryColour(vehicle, colorSet.primary[1], colorSet.primary[2], colorSet.primary[3])
                SetVehicleCustomSecondaryColour(vehicle, colorSet.secondary[1], colorSet.secondary[2], colorSet.secondary[3])
            end
        else
            if liveryIndex ~= nil and liveryIndex >= 0 then
                SetVehicleModKit(vehicle, 0)
                SetVehicleMod(vehicle, 48, liveryIndex, false)
            end
        end

        SetVehicleDoorsLocked(vehicle, 2)
        SetVehicleFuelLevel(vehicle, 100.0)
        SetVehicleDirtLevel(vehicle, 0.0)
        SetVehicleOnGroundProperly(vehicle)
        SetVehicleEngineOn(vehicle, true, true, false) -- Start the car

        -- Conditional key giving: Only if this client is the admin who ran the command
        if adminServerId and GetPlayerServerId(PlayerId()) == adminServerId then
            DebugPrint("This client is the admin (ServerID: " .. adminServerId .. "). Triggering SetOwner for plate: " .. plateText)
            TriggerEvent("vehiclekeys:client:SetOwner", plateText)
        else
            -- Optional: Log if not the admin, for debugging purposes if needed
            -- DebugPrint("This client (ServerID: " .. GetPlayerServerId(PlayerId()) .. ") is NOT the admin (Admin ServerID: " .. tostring(adminServerId) .. "). Skipping SetOwner for " .. plateText)
        end
        DebugPrint("Applied setup for vehicle: " .. plateText)
    else
        DebugPrint("ERROR: Vehicle with NetID " .. vehicleNetId .. " (Plate: " .. plateText .. ") could not be found locally for setup after " .. attempts .. " attempts.")
    end
end)


-- Pit Recovery System
local isStuck = false
local stuckTimer = 0
local STUCK_THRESHOLD_TIME = 30000 -- 30 seconds stationary
local RECOVERY_COOLDOWN = 300000 -- 5 minute cooldown between recoveries
local isRecovering = false

-- Thread to monitor vehicle stuckness
CreateThread(function()
    local lastRecoveryTime = 0
    
    while true do
        local sleep = 1000
        local playerPed = PlayerPedId()
        
        if IsPedInAnyVehicle(playerPed, false) and not isRecovering then
            local vehicle = GetVehiclePedIsIn(playerPed, false)
            
            -- Check if it's a Formula car
            local isFormulaCar = false
            local checkFunc = _G.IsFormulaCar or function(v) 
                if not v or v==0 or not DoesEntityExist(v) then return false end
                local m = GetEntityModel(v)
                if Config.FormulaCarHashes then 
                    for _, h in ipairs(Config.FormulaCarHashes) do 
                        if m == h then return true end 
                    end 
                end
                return false 
            end
            isFormulaCar = checkFunc(vehicle)

            if isFormulaCar then
                local velocity = GetEntityVelocity(vehicle)
                local speed = math.sqrt(velocity.x^2 + velocity.y^2 + velocity.z^2)
                
                if speed < 0.5 then -- Very low speed threshold
                    stuckTimer = stuckTimer + sleep
                    
                    -- Check if truly stuck and not in pit zone
                    if stuckTimer >= STUCK_THRESHOLD_TIME and not isInPitZone then
                        local currentTime = GetGameTimer()
                        
                        -- Check recovery cooldown
                        if currentTime - lastRecoveryTime >= RECOVERY_COOLDOWN then
                            -- Show persistent notification at bottom
                            lib.showTextUI('Hold [CAPS LOCK] to return to Pits\n(3 seconds)', {
                                position = "bottom-center",
                                icon = 'car-burst',
                                style = {
                                    backgroundColor = 'rgba(255, 0, 0, 0.7)',
                                    color = 'white'
                                }
                            })
                            
                            local holdStartTime = GetGameTimer()
                            local holdDuration = 0
                            
                            -- Listen for CAPS LOCK
                            CreateThread(function()
                                while stuckTimer >= STUCK_THRESHOLD_TIME and not isRecovering do
                                    if IsControlPressed(0, 137) then  -- CAPS LOCK
                                        holdDuration = GetGameTimer() - holdStartTime
                                        
                                        -- Update UI with countdown
                                        lib.showTextUI(string.format('Recovering: %d seconds\nDO NOT RELEASE', math.ceil((3000 - holdDuration) / 1000)), {
                                            position = "bottom-center",
                                            icon = 'car-burst',
                                            style = {
                                                backgroundColor = 'rgba(255, 0, 0, 0.7)',
                                                color = 'white'
                                            }
                                        })
                                        
                                        if holdDuration >= 3000 then
                                            isRecovering = true
                                            lib.hideTextUI()
                                            TriggerServerEvent('dude_formularacing:RequestPitRecovery')
                                            break
                                        end
                                    else
                                        -- Reset if not holding
                                        holdStartTime = GetGameTimer()
                                        lib.showTextUI('Hold [CAPS LOCK] to return to Pits\n(3 seconds)', {
                                            position = "bottom-center",
                                            icon = 'car-burst',
                                            style = {
                                                backgroundColor = 'rgba(255, 0, 0, 0.7)',
                                                color = 'white'
                                            }
                                        })
                                    end
                                    
                                    Wait(100)
                                end
                            end)
                        end
                    end
                else
                    stuckTimer = 0
                    lib.hideTextUI()
                end
                
                sleep = 500
            end
        end
        
        Wait(sleep)
    end
end)

-- Server Event Handler for Pit Recovery
RegisterNetEvent('dude_formularacing:PitRecoveryConfirmed', function(spotIndex)
    local playerPed = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(playerPed, false)
    
    if not DoesEntityExist(vehicle) then
        DebugPrint("PitRecoveryConfirmed: Player not in a vehicle or vehicle invalid.")
        isRecovering = false -- Reset flag
        return
    end

    local activeTrackConfig = Config.Tracks[Config.ActiveTrack]
    if not activeTrackConfig or not activeTrackConfig.recoverySpots or not activeTrackConfig.recoverySpots[spotIndex] then
        DebugPrint("PitRecoveryConfirmed: Invalid track or recovery spot config. SpotIndex: " .. tostring(spotIndex))
        isRecovering = false -- Reset flag
        TriggerServerEvent('dude_formularacing:ReleasePitRecoverySpot', spotIndex) -- Still release spot if possible
        return
    end
    
    local recoverySpot = activeTrackConfig.recoverySpots[spotIndex]
    
    -- Teleport vehicle to recovery spot
    SetEntityCoords(vehicle, recoverySpot.x, recoverySpot.y, recoverySpot.z, false, false, false, true)
    PlaceObjectOnGroundProperly(vehicle)
    SetEntityHeading(vehicle, recoverySpot.w)
    SetVehicleOnGroundProperly(vehicle)
    
    -- Start repair timer
    local repairSuccess = lib.progressCircle({ -- Store result
        duration = 60000, -- Reduced for testing, original 60000
        label = 'Performing Emergency Repairs',
        position = 'bottom',
        useWhileDead = false,
        canCancel = false, -- Should not be cancellable for emergency repair
        disable = {
            car = true,
            move = true,
            combat = true
        }
    })

    if repairSuccess then -- Only proceed if progress circle completed
        -- Fully repair vehicle
        SetVehicleFixed(vehicle)
        SetVehicleEngineHealth(vehicle, 1000.0)
        SetVehiclePetrolTankHealth(vehicle, 1000.0) -- For ox_fuel if it uses this
        SetVehicleBodyHealth(vehicle, 1000.0)
        SetVehicleDeformationFixed(vehicle)
        SetVehicleDirtLevel(vehicle, 0.0)
        SetVehicleFuelLevel(vehicle, 100.0)
        SetVehicleEngineOn(vehicle, true, true, false) -- <<<< TURN CAR ON

        -- Reset tire wear
        if exports.dude_formularacing and exports.dude_formularacing.ResetTireWear then
            exports.dude_formularacing:ResetTireWear(vehicle)
        end
        
        lib.notify({
            title = 'Pit Recovery',
            description = 'Vehicle fully repaired, refueled, and started!',
            type = 'success'
        })
    else
        lib.notify({
            title = 'Pit Recovery',
            description = 'Emergency repairs interrupted or failed.', -- Should not happen if canCancel is false
            type = 'error'
        })
    end
    
    -- Release the recovery spot
    TriggerServerEvent('dude_formularacing:ReleasePitRecoverySpot', spotIndex)
    
    -- Reset recovering state
    isRecovering = false
    stuckTimer = 0 -- Reset stuck timer as well
end)

function SetActiveTrack(trackKey)
    if Config.Tracks[trackKey] then
        Config.ActiveTrack = trackKey
        
        -- Trigger server-side track change
        TriggerServerEvent('dude_formularacing:syncActiveTrack', trackKey)
        
        -- Recreate pit zone
        if pitZone then
            pitZone:remove()
        end
        CreatePitZone()
        
        DebugPrint("Active track changed to: " .. Config.Tracks[trackKey].name)
    else
        DebugPrint("Invalid track key: " .. tostring(trackKey))
    end
end

-- Example usage
RegisterCommand('changetrack', function(source, args)
    if args[1] and Config.Tracks[args[1]] then
        SetActiveTrack(args[1])
    end
end)