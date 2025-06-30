-- client/boost.lua
-- NUI Version with Cooldown Fix
-- Variables
local isInFormulaCar = false
local lastBoostState = false
local kersState = "READY"
local kersCooldownTimer = 0
local kersActiveTimer = 0
local hornBlocked = false

-- NUI Update Timer / State Tracking
local lastNuiKersUpdate = 0
local nuiKersUpdateInterval = 150 -- ms between KERS NUI data updates
local lastSentKersState = ""
local displayUI = Config.KERS.displayUI -- Local state for this UI part
local displayTiresUI = Config.TireWear.displayUI -- Track Tire state for parent logic

-- Boundary Check Variables
local currentVehicleBoundaryWarned = false
local currentBoundaryCheckVeh = nil -- Store the vehicle entity ID for which the warning/check is active
local lastBoundaryCheckTime = 0

-- Function to check if the current vehicle is a formula car
local function IsFormulaCar(vehicle) if _G.IsFormulaCar then return _G.IsFormulaCar(vehicle) else Config.DebugPrint("Warning: _G.IsFormulaCar not found in boost.lua"); if not vehicle or vehicle==0 or not DoesEntityExist(vehicle) then return false end; local m=GetEntityModel(vehicle); if Config.FormulaCarHashes then for _,h in ipairs(Config.FormulaCarHashes) do if m==h then return true end end end; return false end end

-- Input blocking thread
CreateThread(function() while true do if hornBlocked then DisableControlAction(0,86,true); Wait(0) else Wait(250) end end end)

-- Function to play sound
local function PlayKersSound(soundName) if Config.KERS.sounds.enabled and soundName then PlaySoundFrontend(-1,soundName,"HUD_FRONTEND_DEFAULT_SOUNDSET",false) end end

-- Function to send KERS update to NUI
local function SendKersNuiUpdate()
     if not isInFormulaCar or not displayUI then return end
     local dataToSend={action='updateKers', state=kersState, config={activeDuration=Config.KERS.activeDuration, cooldownDuration=Config.KERS.cooldownDuration}}
     if kersState=="ACTIVE" then dataToSend.activeTimer=kersActiveTimer elseif kersState=="COOLDOWN" then dataToSend.cooldownTimer=kersCooldownTimer end
     SendNUIMessage(dataToSend)
     lastSentKersState = kersState; lastNuiKersUpdate = GetGameTimer()
end

-- Main KERS and boost monitoring thread
CreateThread(function()
    Config.DebugPrint("KERS monitoring thread started (NUI Cooldown Fix Version)")
    while true do
        local sleep = 150
        local ped = PlayerPedId()

        if IsPedInAnyVehicle(ped, false) then
            local vehicle = GetVehiclePedIsIn(ped, false)
            local wasInFormulaCar = isInFormulaCar
            local currentlyIsFormula = IsFormulaCar(vehicle)

            -- Entering Formula Car
            if currentlyIsFormula and not wasInFormulaCar then
                isInFormulaCar = true
                kersState = "READY"; kersCooldownTimer = 0; kersActiveTimer = 0; hornBlocked = false; lastBoostState = false
				currentVehicleBoundaryWarned = false -- Reset boundary warning flag
                currentBoundaryCheckVeh = vehicle      -- Set current vehicle for boundary checks
                lastBoundaryCheckTime = 0             -- Reset boundary check timer to check immediately
                Config.DebugPrint("Entered formula car - KERS State RESET to READY")
                Wait(100)
                if displayUI then SendNUIMessage({ action='showUI', display=true }); SendNUIMessage({ action='showKers', display=true }); Config.DebugPrint(">>> Sent showUI=true & showKers=true")
                else if displayTiresUI then SendNUIMessage({action='showUI', display=true}); Config.DebugPrint(">>> Sent showUI=true (KERS Disabled, Tires Enabled)") else SendNUIMessage({action='showUI', display=false}); Config.DebugPrint(">>> Sent showUI=false (Both Disabled)") end; SendNUIMessage({action='showKers', display=false}) end
                SendKersNuiUpdate() -- Send initial READY state immediately
                Config.DebugPrint(">>> Sent initial KERS NUI update")
                lastNuiKersUpdate = GetGameTimer()

            -- Exiting Formula Car (but still in a vehicle)
            elseif not currentlyIsFormula and wasInFormulaCar then
                 isInFormulaCar = false
				 currentVehicleBoundaryWarned = false -- Reset boundary warning flag
                 currentBoundaryCheckVeh = nil
				 Config.DebugPrint("Switched from Formula car - KERS inactive")
                 SendNUIMessage({action='showKers', display=false}); if not displayTiresUI then SendNUIMessage({action='showUI', display=false}) end; Config.DebugPrint(">>> Sent showKers=false (Switched vehicle)")
            end

            -- If currently in a formula car, process KERS logic
            if isInFormulaCar then
                local previousState = kersState
                local isBoostPressed=IsControlPressed(0,86); hornBlocked=(kersState=="COOLDOWN")

                if kersState=="READY" then
                    if isBoostPressed and not lastBoostState then
                        Config.DebugPrint("KERS activated"); kersState="ACTIVE"; kersActiveTimer=0; kersCooldownTimer=0; PlayKersSound(Config.KERS.sounds.activate)
                        -- Send update immediately on activation
                         if displayUI then SendKersNuiUpdate() end
                    end
                elseif kersState=="ACTIVE" then
                    kersActiveTimer=kersActiveTimer+sleep
                    if Config.BoostFuelConsumption.enabled then local cF=GetVehicleFuelLevel(vehicle); local fC=Config.BoostFuelConsumption.consumptionRate*(sleep/1000); local nF=math.max(0,cF-fC); SetVehicleFuelLevel(vehicle,nF) end
                    if kersActiveTimer>=Config.KERS.activeDuration then
                        Config.DebugPrint("KERS depleted - cooldown"); kersState="COOLDOWN"; kersCooldownTimer=0; kersActiveTimer=0; PlayKersSound(Config.KERS.sounds.deactivate)
                         -- Send update immediately on state change
                         if displayUI then SendKersNuiUpdate() end
                    end
                elseif kersState=="COOLDOWN" then
                    kersCooldownTimer=kersCooldownTimer+sleep
                    if kersCooldownTimer>=Config.KERS.cooldownDuration then
                        Config.DebugPrint("KERS ready")
                        kersState="READY"; hornBlocked=false; kersCooldownTimer=0 -- Reset timer
                        PlayKersSound(Config.KERS.sounds.ready)
                        -- *** FIX: Send update immediately after state changes to READY ***
                        if displayUI then SendKersNuiUpdate() end
                    end
                end
                lastBoostState=isBoostPressed

                -- Send periodic NUI data updates only if timers are active (or state just changed, handled above)
                local timerActive = (kersState == "ACTIVE" or kersState == "COOLDOWN")
                local currentTime = GetGameTimer()
                if timerActive and displayUI and (currentTime - lastNuiKersUpdate > nuiKersUpdateInterval) then
                     SendKersNuiUpdate()
                end
				-- End KERS Logic

                -- Boundary Check Logic
                if Config.BoundarySettings and Config.BoundarySettings.Enabled then
                    local currentTimeForBoundary = GetGameTimer()
                    if currentTimeForBoundary - lastBoundaryCheckTime > Config.BoundarySettings.CheckIntervalClient then
                        lastBoundaryCheckTime = currentTimeForBoundary

                        local activeTrackKey_Boundary = Config.ActiveTrack
                        local activeTrackConfig_Boundary = Config.Tracks[activeTrackKey_Boundary]

                        -- Ensure vehicle is still the one we are checking and track config is valid
                        if vehicle == currentBoundaryCheckVeh and activeTrackConfig_Boundary and activeTrackConfig_Boundary.boundaryCenter and activeTrackConfig_Boundary.boundaryRadius then
                            local plate = GetVehicleNumberPlateText(vehicle)
                            plate = plate and string.gsub(plate, "%s+", "") or "" -- Trim all whitespace for consistency

                            if plate and string.sub(plate, 1, 4) == "FORM" then -- Only for "FORM" plated cars
                                local vehCoords = GetEntityCoords(vehicle)
                                if vehCoords and (vehCoords.x ~= 0 or vehCoords.y ~= 0 or vehCoords.z ~= 0) then -- Check for valid coords
                                    local dist = #(vehCoords - activeTrackConfig_Boundary.boundaryCenter)
                                    local radius = activeTrackConfig_Boundary.boundaryRadius
                                    local warningRadiusLimit = radius * Config.BoundarySettings.WarningPercent

                                    if dist > radius then
                                        Config.DebugPrint("Boundary", string.format("Vehicle NetID %s (Plate: %s) exceeded radius (%.2f/%.2f) on track %s. Requesting deletion.", VehToNet(vehicle), plate, dist, radius, activeTrackKey_Boundary))
                                        TriggerServerEvent('dude_formularacing:server:handleOutOfBoundsVehicle', VehToNet(vehicle))
                                        currentVehicleBoundaryWarned = false -- Reset, car should be deleted by server
                                    elseif dist > warningRadiusLimit then
                                        if not currentVehicleBoundaryWarned then
                                            if Config.BoundarySettings.ShowClientWarning then
                                                exports['ox_lib']:notify({
                                                    id = 'formulaboundary_warning',
                                                    title = 'Track Limits',
                                                    description = 'You are far off track! Return immediately or the vehicle will be impounded.',
                                                    type = 'warning',
                                                    duration = 8000
                                                })
                                            end
                                            Config.DebugPrint("Boundary", string.format("Vehicle NetID %s (Plate: %s) in warning zone (%.2f/%.2f) on track %s.", VehToNet(vehicle), plate, dist, radius, activeTrackKey_Boundary))
                                            currentVehicleBoundaryWarned = true
                                        end
                                    else
                                        if currentVehicleBoundaryWarned then
                                            currentVehicleBoundaryWarned = false -- Back in safe zone
                                            Config.DebugPrint("Boundary", string.format("Vehicle NetID %s (Plate: %s) back in safe zone on track %s.", VehToNet(vehicle), plate, activeTrackKey_Boundary))
                                        end
                                    end
                                end
                            else
                                -- Not a "FORM" plate car, reset warning if it was somehow set
                                if currentVehicleBoundaryWarned then currentVehicleBoundaryWarned = false end
                            end
                        else
                             -- No boundary config for current track or vehicle mismatch, reset warning
                            if currentVehicleBoundaryWarned then currentVehicleBoundaryWarned = false end
                        end
                    end
                end
                -- End Boundary Check Logic
            end
        -- Player is not in any vehicle
        else
            if isInFormulaCar then
                Config.DebugPrint("Exited vehicle entirely - reset KERS & hide UI")
                isInFormulaCar=false; kersState="READY"; kersCooldownTimer=0; kersActiveTimer=0; hornBlocked=false
				currentVehicleBoundaryWarned = false -- Reset boundary warning
                currentBoundaryCheckVeh = nil
                SendNUIMessage({action='showKers', display=false}); SendNUIMessage({action='showUI', display=false})
                Config.DebugPrint(">>> Sent showKers=false & showUI=false (Exited Veh)")
            elseif currentBoundaryCheckVeh ~= nil then -- Was in a vehicle that we were tracking for boundary, but maybe not a formula car
                currentVehicleBoundaryWarned = false
                currentBoundaryCheckVeh = nil
                Config.DebugPrint("Boost", "Exited non-formula or untracked vehicle. Boundary warning reset if active.")
            end
            sleep = 500
        end
        Wait(sleep)
    end
end)

-- Need to know when Tire UI state changes
RegisterNetEvent('dude_formularacing:tireUIDisplayState', function(tireDisplayState) Config.DebugPrint("Received Tire UI display state: "..tostring(tireDisplayState)); displayTiresUI = tireDisplayState end)

-- onResourceStop handler
AddEventHandler('onResourceStop', function(resourceName) if GetCurrentResourceName()~=resourceName then return end; SendNUIMessage({action='showKers', display=false}); SendNUIMessage({action='showUI', display=false}); Config.DebugPrint(">>> Sent showKers=false & showUI=false (Resource Stop)") end)

-- NUI Callback receiver
RegisterNUICallback('nuiReady', function(data, cb) Config.DebugPrint("NUI reported ready. Message Data: "..json.encode(data or {})); cb('ok') end)


-- CreateThread(function()
    -- while true do
        -- Wait(0) -- Run every frame for smooth drawing

        -- if Config.Debug then
            -- local activeTrackKey = Config.ActiveTrack
            -- if activeTrackKey and Config.Tracks[activeTrackKey] then
                -- local trackCfg = Config.Tracks[activeTrackKey]
                -- if trackCfg.boundaryCenter and trackCfg.boundaryRadius and trackCfg.boundaryRadius > 0 then
                    -- local center = trackCfg.boundaryCenter
                    -- local radius = trackCfg.boundaryRadius

                   -- --Draw a marker at the center point
                    -- DrawMarker(
                        -- 1, -- MarkerTypeCylinder (can also use 0 for sphere)
                        -- center.x, center.y, center.z,
                        -- 0.0, 0.0, 0.0,           -- Direction (not super relevant for static cylinder)
                        -- 0.0, 0.0, 0.0,           -- Rotation
                        -- 2.0, 2.0, 5.0,         -- Scale (small cylinder for center)
                        -- 0, 255, 0, 150,          -- Color (Green, semi-transparent)
                        -- false,                   -- Bob up and down
                        -- false,                   -- Face camera
                        -- 2,                       -- p19 (rotation order / draw on ground - check GTAV N Natives for details)
                        -- false,                   -- Rotate
                        -- nil, nil,                -- Texture dict and name
                        -- false                    -- Draw on entities
                    -- )

                    -- --Draw a larger cylinder representing the boundary radius
                    -- DrawMarker(
                        -- 1, -- MarkerTypeCylinder
                        -- center.x, center.y, center.z,
                        -- 0.0, 0.0, 0.0,
                        -- 0.0, 0.0, 0.0,
                        -- radius * 2.0, radius * 2.0, 100.0, -- Scale (Diameter for X/Y, 100m height for Z for visibility)
                        -- 255, 0, 0, 75,          -- Color (Red, more transparent)
                        -- false,
                        -- false,
                        -- 2,
                        -- false,
                        -- nil, nil,
                        -- false
                    -- )

                    -- --Draw a smaller cylinder for the warning radius if different from main radius
                    -- if Config.BoundarySettings and Config.BoundarySettings.WarningPercent and Config.BoundarySettings.WarningPercent < 1.0 then
                        -- local warningRadius = radius * Config.BoundarySettings.WarningPercent
                        -- if warningRadius > 0 and warningRadius < radius then
                             -- DrawMarker(
                                -- 1, -- MarkerTypeCylinder
                                -- center.x, center.y, center.z,
                                -- 0.0, 0.0, 0.0,
                                -- 0.0, 0.0, 0.0,
                                -- warningRadius * 2.0, warningRadius * 2.0, 98.0, -- Slightly shorter height to distinguish
                                -- 255, 165, 0, 60,          -- Color (Orange, also transparent)
                                -- false,
                                -- false,
                                -- 2,
                                -- false,
                                -- nil, nil,
                                -- false
                            -- )
                        -- end
                    -- end
                -- end
            -- end
        -- end
    -- end
-- end)