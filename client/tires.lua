-- client/tires.lua (v1.4.0 - Direct State Sync Fix)
--[[
    Tire Wear System - NUI Version with Per-Vehicle State (State Bags)
]]
-- Local variables
local visualToGameIndex = { [0]=0, [1]=1, [2]=4, [3]=5 }
local gameToVisualIndex = { [0]=0, [1]=1, [4]=2, [5]=3 }
local displayUI = Config.TireWear and Config.TireWear.displayUI or true
local displayKersUI = Config.KERS and Config.KERS.displayUI or true
local currentVehicleId = nil -- Store the NATIVE ID of the vehicle the player is currently driving
local isActivelyInFormulaCar = false
local isCurrentlyOffRoad = false
local lastStateCheckTime = {} -- Track last time state bag was checked per vehicle to avoid spamming init event
local stateBagChecks = {} -- Track state bag check attempts

-- Handling Modifiers State (Potentially remove if feature unused)
local baseHandling = {}
local currentHandlingModifiers = {}
local handlingCheckRunning = false
local handlingFieldHashes = { ["fTractionCurveMax"]=0x53B08B3D, ["fTractionCurveMin"]=0x58397533, ["fTractionLossMult"]=0xB76A335F }

-- NUI Update Timer
local lastNuiTireUpdate = 0
local nuiTireUpdateInterval = 250 -- ms between updates
local blowoutCheckTimer = GetGameTimer()

-- Debug function
local function TireDEBUG(message) if Config and Config.Debug then print("^5[dude_formularacing | Tires]^7: " .. message) end end

-- Helper to get state from state bag, requesting init if needed
local function GetVehicleTireState(vehicleId)
    if not DoesEntityExist(vehicleId) then return nil end
    
    -- IMPORTANT CHANGE: Always get a fresh state
    local state = nil
    if Entity(vehicleId).state then
        state = Entity(vehicleId).state.tireInfo
    end
    
    if state then return state end
    
    local now = GetGameTimer()
    local vehicleKey = tostring(vehicleId)
    local lastCheck = lastStateCheckTime[vehicleKey] or 0
    local checkCount = stateBagChecks[vehicleKey] or 0
    
    if now - lastCheck > 5000 then
        TireDEBUG("GetVehicleTireState: State bag 'tireInfo' not found for vehID " .. vehicleId .. ". Requesting initialization.")
        TriggerServerEvent('dude_formularacing:server:initializeTireState', VehToNet(vehicleId))
        lastStateCheckTime[vehicleKey] = now
        stateBagChecks[vehicleKey] = checkCount + 1
    end
    return nil
end

-- Safe Handling Functions
local function SafeSetVehicleHandlingFloat(vehicleId, fieldName, value) if not DoesEntityExist(vehicleId) then return end; local h=handlingFieldHashes[fieldName]; if h then SetVehicleHandlingFloat(vehicleId,h,value) else TireDEBUG("Unknown handling field hash for: "..fieldName) end end
local function SafeGetVehicleHandlingFloat(vehicleId, fieldName) if not DoesEntityExist(vehicleId) then return nil end; local h=handlingFieldHashes[fieldName]; if h then return GetVehicleHandlingFloat(vehicleId,h) else TireDEBUG("Unknown handling field hash for: "..fieldName); return nil end end

-- Initialize
CreateThread(function()
    TireDEBUG("Tire system initializing (State Bag Version)...")
    Config.FormulaCarHashes = {}
    Wait(1000)
    displayUI = Config.TireWear and Config.TireWear.displayUI or true
    displayKersUI = Config.KERS and Config.KERS.displayUI or true
    if Config.FormulaCars then for _, mN in ipairs(Config.FormulaCars) do local h=GetHashKey(mN); if h~=0 then table.insert(Config.FormulaCarHashes,h); TireDEBUG("Reg Hash: "..mN.." ("..h..")") else TireDEBUG("Failed hash: "..mN) end end else TireDEBUG("Config.FormulaCars not found!") end
    TireDEBUG("Tire system initialized.")
    SendNUIMessage({action='showTires', display=false}); SendNUIMessage({action='showUI', display=false})
end)

-- StoreBaseHandling
local function StoreBaseHandling(vehicleId)
     if not DoesEntityExist(vehicleId) then return end
     -- Check if handling modification is enabled in config (add this check if needed)
     -- local modifyHandling = Config.TireWear and Config.TireWear.modifyHandling or false
     -- if not modifyHandling then return end

     local netId = VehToNet(vehicleId)
     if baseHandling[netId] then return end -- Already stored
     baseHandling[netId] = {}
     for field, hash in pairs(handlingFieldHashes) do
         local value = SafeGetVehicleHandlingFloat(vehicleId, field)
         if value then baseHandling[netId][field] = value end
     end
     TireDEBUG("Stored base handling for vehNetID: " .. netId)
end

-- ResetHandlingToBase
local function ResetHandlingToBase(vehicleId)
     if not DoesEntityExist(vehicleId) then return end
     -- Check if handling modification is enabled in config (add this check if needed)
     -- local modifyHandling = Config.TireWear and Config.TireWear.modifyHandling or false
     -- if not modifyHandling then return end

     local netId = VehToNet(vehicleId)
     if not baseHandling[netId] then -- TireDEBUG("Cannot reset handling, base not stored for vehNetID: "..netId);
         return
     end
     if currentHandlingModifiers[netId] then -- Only reset if modifiers were applied
         for field, baseValue in pairs(baseHandling[netId]) do
             if baseValue then SafeSetVehicleHandlingFloat(vehicleId, field, baseValue) end
         end
         TireDEBUG("Reset handling to base for vehNetID: " .. netId)
         currentHandlingModifiers[netId] = nil -- Clear applied modifiers flag
     end
     -- Don't clear baseHandling[netId] here, might re-enter vehicle
end

-- UpdateTireUIFromState function (Reads current state and sends NUI)
-- This is called by the main loop based on the timer
local function UpdateTireUIFromState(vehicleId)
    if not displayUI or not DoesEntityExist(vehicleId) then return end
    
    -- IMPORTANT: Always get a fresh state directly from the state bag
    local currentState = nil
    if Entity(vehicleId).state then
        currentState = Entity(vehicleId).state.tireInfo
    end
    
    if not currentState or not currentState.wear or not currentState.burst then
        return
    end

   -- TireDEBUG("UpdateTireUIFromState: Reading state for NUI: "..json.encode(currentState))

    local nuiBurstStatus = {}
    -- gameToVisualIndex defined globally at top

    for gameIdx, isBurst in pairs(currentState.burst) do
        local visualIdx = gameToVisualIndex[gameIdx]
        if visualIdx ~= nil then
            nuiBurstStatus[visualIdx] = isBurst
        end
    end

    SendNUIMessage({action='updateTires', wear = currentState.wear, burstStatus = nuiBurstStatus})
    -- *** CRUCIAL: Reset the NUI update timer AFTER sending the message ***
    lastNuiTireUpdate = GetGameTimer()
   -- TireDEBUG("UpdateTireUIFromState: Sent NUI update. Reset lastNuiTireUpdate.")
end

-- Main tire wear thread
CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        local vehicleId = GetVehiclePedIsIn(ped, false)

        if vehicleId ~= 0 and DoesEntityExist(vehicleId) then
            local isFormula = false
            local checkFunc = _G.IsFormulaCar or function(v) if not v or v==0 or not DoesEntityExist(v) then return false end; local m=GetEntityModel(v); if Config.FormulaCarHashes then for _,h in ipairs(Config.FormulaCarHashes) do if m==h then return true end end end; return false end
            isFormula = checkFunc(vehicleId)

            if isFormula then
                -- Check if entering or switching formula cars
                if not isActivelyInFormulaCar or currentVehicleId ~= vehicleId then
                    TireDEBUG("Entered Formula Car (ID: " .. vehicleId .. ")")
                    currentVehicleId = vehicleId
                    isActivelyInFormulaCar = true
                    isCurrentlyOffRoad = false
                    local currentState = GetVehicleTireState(vehicleId)
                    if currentState then
                        TireDEBUG("Using state bag for vehicle ID " .. vehicleId .. ": Wear=" .. json.encode(currentState.wear))
                        Entity(vehicleId).state:set('distSinceWear', 0.0, true)
                        Entity(vehicleId).state:set('lastPosForWear', GetEntityCoords(vehicleId), true)
                    else
                         TireDEBUG("State bag not yet available for vehicle ID " .. vehicleId .. ", will retry.")
                    end
                    StoreBaseHandling(vehicleId)
                    Wait(100)
                    local shouldShowTires = displayUI
                    local shouldShowKers = displayKersUI
                    if shouldShowTires or shouldShowKers then SendNUIMessage({action='showUI',display=true}); TireDEBUG(">>> Sent showUI=true (Entering)")
                    else SendNUIMessage({action='showUI',display=false}); TireDEBUG(">>> Sent showUI=false (Entering, Both UI Disabled)") end
                    if shouldShowTires then SendNUIMessage({action='showTires',display=true}); TireDEBUG(">>> Sent showTires=true") end
                    lastNuiTireUpdate = GetGameTimer() - nuiTireUpdateInterval - 1 -- Force NUI update try on entry
                end

                -- *** ACTIONS WHILE ACTIVELY IN FORMULA CAR ***
                sleep = 250
                local currentState = GetVehicleTireState(vehicleId)
                if not currentState then -- TireDEBUG("State bag still not available for active vehicle ID " .. vehicleId);
                    goto ContinueLoop
                end

                -- Calculate Wear
                local currentPos = GetEntityCoords(vehicleId)
                local speed = GetEntitySpeed(vehicleId)
                local steeringAngle = GetVehicleSteeringAngle(vehicleId)
                local lastPos = Entity(vehicleId).state.lastPosForWear or currentPos
                local distAccumulated = Entity(vehicleId).state.distSinceWear or 0.0
                if lastPos ~= vector3(0,0,0) then
                   local distFrame=#(currentPos-lastPos)
                   if distFrame > 0.01 and distFrame < 100.0 and speed > 0.1 then
                       distAccumulated = distAccumulated + (distFrame / 1000.0)
                   end
                end
                Entity(vehicleId).state:set('lastPosForWear', currentPos, true)
                if speed > 1.0 and distAccumulated > 0.001 then
                    ApplyTireWear(vehicleId, distAccumulated, steeringAngle, isCurrentlyOffRoad)
                    Entity(vehicleId).state:set('distSinceWear', 0.0, true)
                else
                    Entity(vehicleId).state:set('distSinceWear', distAccumulated, true)
                end
                CheckForBlowout(vehicleId)

                -- Send NUI Update (Main Loop) - Check if timer elapsed
                local currentTime = GetGameTimer()
                if displayUI and (currentTime - lastNuiTireUpdate > nuiTireUpdateInterval) then
                    UpdateTireUIFromState(vehicleId) -- Call the function which reads state and resets timer
                end
            else
                 -- In a non-formula vehicle
                if isActivelyInFormulaCar then
                    TireDEBUG("Exited formula car (switched vehicle or non-formula).")
                    if currentVehicleId then ResetHandlingToBase(currentVehicleId) end
                    isActivelyInFormulaCar = false; currentVehicleId = nil; isCurrentlyOffRoad = false;
                    SendNUIMessage({action='showTires',display=false})
                    if not displayKersUI then SendNUIMessage({action='showUI', display=false}) end
                    TireDEBUG(">>> Sent showTires=false (Switched/Non-Formula)")
                end
                sleep = 1000
            end
        else
            -- Not in any vehicle or vehicleId became invalid
            if isActivelyInFormulaCar then
                TireDEBUG("Exited vehicle entirely or current vehicle became invalid.")
                 if currentVehicleId then ResetHandlingToBase(currentVehicleId) end
                isActivelyInFormulaCar = false; currentVehicleId = nil; isCurrentlyOffRoad = false;
                SendNUIMessage({action='showTires',display=false}); SendNUIMessage({action='showUI',display=false}); TireDEBUG(">>> Sent showTires=false & showUI=false (Exited/Invalid)")
            end
            sleep = 1500
        end
        ::ContinueLoop::
        Wait(sleep)
    end
end)

-- ApplyTireWear function (Updates state bag)
function ApplyTireWear(vehicleId, distanceKm, steeringAngle, offRoad)
    if not Config.TireWear or not Config.TireWear.enabled then return end
    if not DoesEntityExist(vehicleId) then return end
    local currentState = GetVehicleTireState(vehicleId)
    if not currentState or not currentState.wear or not currentState.burst then return end
    local baseWearAmount = (Config.TireWear.baseWearRate or 0) * distanceKm
    if baseWearAmount <= 0 then return end
    local steerThreshold = (Config.TireWear.steeringAngleThreshold or 0.1)
    local steerMultiplier = ((Config.TireWear.steeringWearMultiplier) or 1.0) - 1.0
    local leftTurn = steeringAngle < -steerThreshold
    local rightTurn = steeringAngle > steerThreshold
    local wearMultiplier = 1.0
    local changed = false
    local newWear = {}
    for k, v in pairs(currentState.wear) do newWear[k] = v end
    -- visualToGameIndex defined globally at top

    for visualIdx = 0, 3 do
        local gameWheelIndex = visualToGameIndex[visualIdx]
        if gameWheelIndex and newWear[visualIdx] and newWear[visualIdx] > 0 and currentState.burst[gameWheelIndex] == false then
            local steeringWearAddon = 0.0
            local isFrontLeft = visualIdx == 0; local isFrontRight = visualIdx == 1
            local isRearLeft = visualIdx == 2; local isRearRight = visualIdx == 3
            if steerMultiplier > 0 then
                if rightTurn and (isFrontLeft or isRearLeft) then steeringWearAddon = baseWearAmount * steerMultiplier
                elseif leftTurn and (isFrontRight or isRearRight) then steeringWearAddon = baseWearAmount * steerMultiplier end
            end
            local totalWearAmount = (baseWearAmount + steeringWearAddon) * wearMultiplier
            local previousWear = newWear[visualIdx]
            newWear[visualIdx] = math.max(0, newWear[visualIdx] - totalWearAmount)
            if math.abs(newWear[visualIdx] - previousWear) > 0.01 then changed = true end
        end
    end
    if changed then
         Entity(vehicleId).state:set('tireInfo', { wear = newWear, burst = currentState.burst }, true)
    end
end

-- CheckForBlowout function (Updates state bag)
function CheckForBlowout(vehicleId)
    if not Config.TireWear or not Config.TireWear.enabled then return end
    if not DoesEntityExist(vehicleId) then return end
    local currentState = GetVehicleTireState(vehicleId)
    if not currentState or not currentState.wear or not currentState.burst then return end
    local checkInterval = Config.TireWear.blowoutCheckInterval or 500
    local currentTime = GetGameTimer()
    if currentTime - blowoutCheckTimer < checkInterval then return end
    blowoutCheckTimer = currentTime
    local chance = Config.TireWear.blowoutChanceAtZero or 0.15
    local needsCheck = false
    local stateChanged = false
    local newBurst = {}
    for k, v in pairs(currentState.burst) do newBurst[k] = v end
    -- visualToGameIndex defined globally at top

    for visualIdx = 0, 3 do if currentState.wear[visualIdx] and currentState.wear[visualIdx] <= 0 then needsCheck = true; break end end

    if needsCheck then
        for visualIdx = 0, 3 do
            local gameWheelIndex = visualToGameIndex[visualIdx]
            if gameWheelIndex then
                local actualBurstState = IsVehicleTyreBurst(vehicleId, gameWheelIndex, false)
                if newBurst[gameWheelIndex] ~= actualBurstState then
                    newBurst[gameWheelIndex] = actualBurstState
                    stateChanged = true
                    TireDEBUG("Synced burst status for vehicle ID " .. vehicleId .. " gameIdx " .. gameWheelIndex .. " to " .. tostring(actualBurstState))
                end
                if not newBurst[gameWheelIndex] and currentState.wear[visualIdx] and currentState.wear[visualIdx] <= 0 then
                    if math.random() < chance then
                        SetVehicleTyreBurst(vehicleId, gameWheelIndex, true, 1000.0)
                        newBurst[gameWheelIndex] = true
                        stateChanged = true
                        TireDEBUG("Blowout! VehID: " .. vehicleId .. " VisIdx: " .. visualIdx)
                        exports['ox_lib']:notify({title='Tire Wear',description='Tire blowout! ('..({[0]="FL",[1]="FR",[2]="RL",[3]="RR"})[visualIdx]..')',type='error'})
                    end
                end
            end
        end
        if stateChanged then
            Entity(vehicleId).state:set('tireInfo', { wear = currentState.wear, burst = newBurst }, true)
            TireDEBUG("Updated tire burst state bag for vehID " .. vehicleId .. ": " .. json.encode(newBurst))
            lastNuiTireUpdate = GetGameTimer() - nuiTireUpdateInterval - 1 -- Force NUI update if burst state changes
        end
    end
end

-- SetTireWear function (Updates state bag)
function SetTireWear(vehicleId, visualWheelIndex, value)
    if not Config.TireWear or not Config.TireWear.enabled then return end
    if not vehicleId or vehicleId == 0 or not DoesEntityExist(vehicleId) then return end
    
    -- IMPORTANT: Always get a fresh state
    local currentState = nil
    if Entity(vehicleId).state then
        currentState = Entity(vehicleId).state.tireInfo
    end
    
    if not currentState or not currentState.wear or not currentState.burst then 
        TireDEBUG("SetTireWear: State bag not ready for vehID " .. vehicleId)
        return 
    end
    
    if visualWheelIndex == nil or value == nil or visualWheelIndex < 0 or visualWheelIndex > 3 then 
        TireDEBUG("SetTireWear: Invalid index/value.")
        return 
    end

    -- visualToGameIndex defined globally at top
    local gameWheelIndex = visualToGameIndex[visualWheelIndex]
    if not gameWheelIndex then 
        TireDEBUG("SetTireWear: Invalid visual index mapping.")
        return 
    end

    local clampedValue = math.max(0, math.min(100, value))
    local oldValue = currentState.wear[visualWheelIndex] or 100.0

    if math.abs(clampedValue - oldValue) < 0.1 then return end

    local newWear = {}
    for k, v in pairs(currentState.wear) do newWear[k] = v end
    local newBurst = {}
    for k, v in pairs(currentState.burst) do newBurst[k] = v end

    newWear[visualWheelIndex] = clampedValue
    local burstChanged = false

    if clampedValue > 0 then
        if IsVehicleTyreBurst(vehicleId, gameWheelIndex, false) then
            SetVehicleTyreFixed(vehicleId, gameWheelIndex)
            newBurst[gameWheelIndex] = false
            burstChanged = true
            TireDEBUG("Fixed burst tire visIdx " .. visualWheelIndex)
        elseif newBurst[gameWheelIndex] == true then
            newBurst[gameWheelIndex] = false
            burstChanged = true
        end
    elseif clampedValue <= 0 then
         if not IsVehicleTyreBurst(vehicleId, gameWheelIndex, false) then
             SetVehicleTyreBurst(vehicleId, gameWheelIndex, true, 1000.0)
             newBurst[gameWheelIndex] = true
             burstChanged = true
             TireDEBUG("Manually burst tire visIdx " .. visualWheelIndex)
        elseif newBurst[gameWheelIndex] == false then
            newBurst[gameWheelIndex] = true
            burstChanged = true
        end
    end

    TireDEBUG(string.format("Set veh ID %d tire visIdx %d wear from %.2f to %.2f", vehicleId, visualWheelIndex, oldValue, clampedValue))
    
    -- Set the state with the new values
    Entity(vehicleId).state:set('tireInfo', { wear = newWear, burst = newBurst }, true)
    TireDEBUG("Updated tireInfo state bag after SetTireWear for visIdx " .. visualWheelIndex .. ": Wear="..json.encode(newWear).." Burst="..json.encode(newBurst))

    -- Force a UI update check soon for the player currently in the car, if any
    local playerPed = PlayerPedId()
    if GetVehiclePedIsIn(playerPed, false) == vehicleId then
        lastNuiTireUpdate = GetGameTimer() - nuiTireUpdateInterval - 1
        TireDEBUG("SetTireWear forcing local UI refresh check soon.")
    end
    
    -- Notify server about the tire change to broadcast to other clients
    local vehicleNetId = VehToNet(vehicleId)
    if vehicleNetId and vehicleNetId > 0 then
        -- Use the new server-side force update to ensure all clients get the right value
        TireDEBUG("Requesting server to force-set tire " .. visualWheelIndex .. " to " .. clampedValue)
        TriggerServerEvent('dude_f1:forceTireValue', vehicleNetId, visualWheelIndex, clampedValue)
        
        -- Also trigger the regular notification event
        TriggerServerEvent('dude_f1:tireChanged', vehicleNetId, visualWheelIndex)
    end
end

-- ResetTireWear function (Updates state bag)
function ResetTireWear(vehicleId)
    if not Config.TireWear or not Config.TireWear.enabled then return end
    if not vehicleId or vehicleId == 0 or not DoesEntityExist(vehicleId) then return end
    TireDEBUG("Resetting ALL tires to 100% for vehicle ID " .. vehicleId)

    -- visualToGameIndex defined globally at top
    for visualIdx = 0, 3 do
        local gameIndex = visualToGameIndex[visualIdx]
        if gameIndex and IsVehicleTyreBurst(vehicleId, gameIndex, false) then
            SetVehicleTyreFixed(vehicleId, gameIndex)
        end
    end
    local defaultState = {
        wear = { [0]=100.0, [1]=100.0, [2]=100.0, [3]=100.0 },
        burst = { [0]=false, [1]=false, [4]=false, [5]=false }
    }
    Entity(vehicleId).state:set('tireInfo', defaultState, true)
    TireDEBUG("Reset tireInfo state bag for vehID " .. vehicleId)
    ResetHandlingToBase(vehicleId)

    -- Force a UI update check soon for the player currently in the car, if any
    local playerPed = PlayerPedId()
    if GetVehiclePedIsIn(playerPed, false) == vehicleId then
        lastNuiTireUpdate = GetGameTimer() - nuiTireUpdateInterval - 1
        TireDEBUG("ResetTireWear forcing local UI refresh check soon.")
    end
    
    -- Broadcast all tire changes
    local vehicleNetId = VehToNet(vehicleId)
    if vehicleNetId and vehicleNetId > 0 then
        for visualIdx = 0, 3 do
            TriggerServerEvent('dude_f1:tireChanged', vehicleNetId, visualIdx)
        end
    end
end

-- GetTireWear function (Reads from state bag)
function GetTireWear()
    if not isActivelyInFormulaCar or not currentVehicleId then return { [0]=100.0, [1]=100.0, [2]=100.0, [3]=100.0 } end
    
    -- IMPORTANT: Always get a fresh state
    local currentState = nil
    if Entity(currentVehicleId).state then
        currentState = Entity(currentVehicleId).state.tireInfo
    end
    
    if not currentState or not currentState.wear then return { [0]=100.0, [1]=100.0, [2]=100.0, [3]=100.0 } end
    local wearCopy = {}
    for i = 0, 3 do wearCopy[i] = currentState.wear[i] or 100.0 end
    return wearCopy
end

-- ToggleTireUI function
function ToggleTireUI(state)
    local newState = (state ~= nil) and state or not displayUI
    if newState ~= displayUI then
        displayUI = newState
        Config.TireWear.displayUI = newState
        TireDEBUG("Tire NUI display setting: "..(displayUI and "enabled" or "disabled"))
        TriggerEvent('dude_formularacing:tireUIDisplayState', newState)
        if isActivelyInFormulaCar then
            SendNUIMessage({action='showTires', display=displayUI})
            TireDEBUG(">>> Sent showTires="..tostring(displayUI).." (Toggle)")
            if displayUI then
                SendNUIMessage({action='showUI', display=true})
                TireDEBUG(">>> Sent showUI=true (Toggle Tires ON)")
                lastNuiTireUpdate = GetGameTimer() - nuiTireUpdateInterval - 1
            else
                if not displayKersUI then SendNUIMessage({action='showUI', display=false}); TireDEBUG(">>> Sent showUI=false (Toggle Tires OFF, KERS also off)")
                else TireDEBUG(">>> Skipped sending showUI=false (Toggle Tires OFF, KERS still on)") end
            end
        end
    end
    return displayUI
end

-- Event listener for KERS UI state
RegisterNetEvent('dude_formularacing:kersUIDisplayState', function(kersDisplayState)
    TireDEBUG("Received KERS UI display state: "..tostring(kersDisplayState))
    displayKersUI = kersDisplayState
end)

-- *** ENHANCED: Event handler to force UI refresh check ***
RegisterNetEvent('dude_formularacing:forceTireUIRefresh', function()
    -- Only force refresh if the player is currently in a formula car and the UI is enabled
    if isActivelyInFormulaCar and displayUI and currentVehicleId then
        TireDEBUG("Received forceTireUIRefresh event. Forcing immediate UI update.")
        -- Immediately update UI with current state
        UpdateTireUIFromState(currentVehicleId)
    end
end)

-- *** ENHANCED: Event handler to process tire changes from other players ***
RegisterNetEvent('dude_formularacing:client:tireChangedUpdate', function(sourcePlayerSrvId, vehicleNetId, changedVisualIndex)
    local localPlayer = PlayerId()
    local localPlayerSrvId = GetPlayerServerId(localPlayer)
    if sourcePlayerSrvId == localPlayerSrvId then return end -- Ignore if self

    TireDEBUG(string.format("Received tireChangedUpdate event: FromSrvId=%d vehNetId=%d, tireIdx=%d", sourcePlayerSrvId, vehicleNetId, changedVisualIndex))
    local playerPed = PlayerPedId()
    local currentVehId = GetVehiclePedIsIn(playerPed, false)

    if currentVehId and currentVehId ~= 0 then
        local currentVehNetId = NetworkGetNetworkIdFromEntity(currentVehId)
        if currentVehNetId == vehicleNetId then
            TireDEBUG(" > Event is for the vehicle I am currently in (NativeID: "..currentVehId..")")
            
            -- IMPORTANT: Force a direct refresh of the state from server
            if Entity(currentVehId).state then
                -- Clear any local cache that might exist
                TireDEBUG(" > Forcing state refresh and UI update")
                
                -- Immediately update UI with current state
                UpdateTireUIFromState(currentVehId)
                
                -- Also trigger the refresh event as a backup
                TriggerEvent('dude_formularacing:forceTireUIRefresh')
                
                -- Add additional delay and try again to ensure we get the latest state
                SetTimeout(200, function()
                    if DoesEntityExist(currentVehId) and GetVehiclePedIsIn(PlayerPedId(), false) == currentVehId then
                        TireDEBUG(" > Performing delayed UI update to ensure latest state")
                        UpdateTireUIFromState(currentVehId)
                    end
                end)
            else
                TireDEBUG(" > No state bag available for vehicle")
            end
        end
    end
end)

RegisterNetEvent('dude_formularacing:directTireUpdate', function(vehicleNetId, visualIndex, newValue)
    if type(vehicleNetId) ~= 'number' or vehicleNetId <= 0 then return end
    if type(visualIndex) ~= 'number' or visualIndex < 0 or visualIndex > 3 then return end
    if type(newValue) ~= 'number' then return end
    
    TireDEBUG("Received directTireUpdate for vehNetId " .. vehicleNetId .. ", tire " .. visualIndex .. " = " .. newValue)
    
    local vehicle = NetToVeh(vehicleNetId)
    if DoesEntityExist(vehicle) then
        -- Force update the state bag locally for this tire
        local currentState = nil
        if Entity(vehicle).state then
            currentState = Entity(vehicle).state.tireInfo
        end
        
        if currentState and currentState.wear and currentState.burst then
            local newWear = {}
            for k, v in pairs(currentState.wear) do newWear[k] = v end
            local newBurst = {}
            for k, v in pairs(currentState.burst) do newBurst[k] = v end
            
            -- Set the new value
            newWear[visualIndex] = newValue
            
            -- Fix the tire if value > 0
            if newValue > 0 then
                local gameWheelIndex = visualToGameIndex[visualIndex]
                if gameWheelIndex and IsVehicleTyreBurst(vehicle, gameWheelIndex, false) then
                    SetVehicleTyreFixed(vehicle, gameWheelIndex)
                    newBurst[gameWheelIndex] = false
                    TireDEBUG("Fixed burst tire visIdx " .. visualIndex)
                end
            end
            
            -- Update state bag
            Entity(vehicle).state:set('tireInfo', { wear = newWear, burst = newBurst }, true)
            TireDEBUG("Directly updated state bag for vehId " .. vehicle .. ", tire " .. visualIndex .. " = " .. newValue)
            
            -- Force UI update if player is in this vehicle
            local playerPed = PlayerPedId()
            if GetVehiclePedIsIn(playerPed, false) == vehicle then
                TireDEBUG("In this vehicle - forcing immediate UI update")
                lastNuiTireUpdate = GetGameTimer() - nuiTireUpdateInterval - 1
                UpdateTireUIFromState(vehicle)
            end
        end
    end
end)

-- Add a new export to force UI update
function ForceUpdateTireUI(vehicleId)
    if not DoesEntityExist(vehicleId) or not displayUI then return end
    
    local currentState = nil
    if Entity(vehicleId).state then
        currentState = Entity(vehicleId).state.tireInfo
    end
    
    if currentState and currentState.wear and currentState.burst then
        UpdateTireUIFromState(vehicleId)
        TireDEBUG("ForceUpdateTireUI: Forced UI update for vehicle " .. vehicleId)
        return true
    else
        TireDEBUG("ForceUpdateTireUI: No valid state for vehicle " .. vehicleId)
        return false
    end
end

-- Helper to get current formula car if player is in one (returns native ID)
local function GetCurrentFormulaCarId()
    local p = PlayerPedId()
    if not IsPedInAnyVehicle(p, false) then return nil end
    local v = GetVehiclePedIsIn(p, false)
    if not DoesEntityExist(v) then return nil end
    local checkFunc = _G.IsFormulaCar or function(veh) if not veh or veh==0 or not DoesEntityExist(veh) then return false end; local m=GetEntityModel(veh); if Config.FormulaCarHashes then for _,h in ipairs(Config.FormulaCarHashes) do if m==h then return true end end end; return false end
    if checkFunc(v) then return v else return nil end
end

-- Commands
local function IsRacingStewart()
    return lib.callback.await('dude_formularacing:CheckRacingStewart', false)
end

-- Repair Tires Command
RegisterCommand('repairtires', function() 
    -- Check Racing Stewart permission
    if not IsRacingStewart() then
        exports['ox_lib']:notify({
            title = 'Tire Wear',
            description = "You are not authorized!",
            type = 'error'
        })
        return 
    end

    local vId = GetCurrentFormulaCarId()
    if not vId then 
        exports['ox_lib']:notify({
            title = 'Tire Wear',
            description = "Not in a Formula car?",
            type = 'error'
        }) 
        return 
    end

    ResetTireWear(vId)
    exports['ox_lib']:notify({
        title = 'Tire Wear',
        description = "All tires repaired for current vehicle.",
        type = 'success'
    })
end, false)

-- Force Wear Command
-- RegisterCommand('forcewear', function(source, args)
    --Check Racing Stewart permission
    -- if not IsRacingStewart() then
        -- exports['ox_lib']:notify({
            -- title = 'Tire Wear',
            -- description = "You are not authorized!",
            -- type = 'error'
        -- })
        -- return 
    -- end

    -- local vId = GetCurrentFormulaCarId()
    -- if not vId then 
        -- exports['ox_lib']:notify({
            -- title = 'Tire Wear',
            -- description = "Not in a Formula car?",
            -- type = 'error'
        -- }) 
        -- return 
    -- end

    -- if not args[1] or not args[2] then 
        -- exports['ox_lib']:notify({
            -- title = 'Tire Wear',
            -- description = "Usage: /forcewear [0-3|all] [amount%]",
            -- type = 'inform'
        -- }) 
        -- return 
    -- end

    -- local wA = args[1]:lower()
    -- local a = tonumber(args[2])
    
    -- if not a then 
        -- exports['ox_lib']:notify({
            -- title = 'Tire Wear',
            -- description = "Amount must be a number.",
            -- type = 'error'
        -- }) 
        -- return 
    -- end

    -- a = math.max(0, math.min(100, a))

    -- if wA == "all" then 
        -- for i = 0, 3 do 
            -- SetTireWear(vId, i, a) 
        -- end 
        -- exports['ox_lib']:notify({
            -- title = 'Tire Wear',
            -- description = "Set all tires to "..a.."%",
            -- type = 'success'
        -- })
    -- else 
        -- local wI = tonumber(wA)
        -- if wI ~= nil and wI >= 0 and wI <= 3 then 
            -- SetTireWear(vId, wI, a)
            -- exports['ox_lib']:notify({
                -- title = 'Tire Wear',
                -- description = "Set tire "..wI.." to "..a.."%",
                -- type = 'success'
            -- })
        -- else 
            -- exports['ox_lib']:notify({
                -- title = 'Tire Wear',
                -- description = "Wheel index must be 0-3 or 'all'.",
                -- type = 'error'
            -- }) 
        -- end 
    -- end
-- end, false)


-- Exports
exports('GetTireWear', GetTireWear)
exports('SetTireWear', SetTireWear)
exports('ResetTireWear', ResetTireWear)
exports('ToggleTireUI', ToggleTireUI)
exports('ForceUpdateTireUI', ForceUpdateTireUI)
-- *** NEW: Export to allow external timer reset (Alternative to local event) ***
exports('ForceTireUIRefresh', function()
   if isActivelyInFormulaCar and displayUI and currentVehicleId then
       UpdateTireUIFromState(currentVehicleId)
   end
end)

-- Set _G.IsFormulaCar
if not _G.IsFormulaCar then local function CheckIfFormula(veh) if not veh or veh==0 or not DoesEntityExist(veh) then return false end; local m=GetEntityModel(veh); if Config.FormulaCarHashes then for _,h in ipairs(Config.FormulaCarHashes) do if m==h then return true end end end; return false end; _G.IsFormulaCar=CheckIfFormula; TireDEBUG("Set _G.IsFormulaCar") end
-- onResourceStop handler
AddEventHandler('onResourceStop', function(resourceName) if GetCurrentResourceName()~=resourceName then return end; SendNUIMessage({action='showTires', display=false}); SendNUIMessage({action='showUI',display=false}); TireDEBUG(">>> Sent showTires=false & showUI=false (Resource Stop)") end)
-- NUI Callback receiver
RegisterNUICallback('nuiReady', function(data, cb) TireDEBUG("NUI reported ready."); cb('ok') end)

TireDEBUG("Tire Client Script Loaded (v1.4.0 - Direct State Sync Fix)")