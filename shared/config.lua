Config = {}

-- Formula car model names (Case-sensitive!)
Config.FormulaCars = {
    'formula', -- Progen PR4
    'formula2', -- Ocelot R88
    -- Add other models here if needed
}

Config.RacingStewarts = {
    -- Add CIDs of allowed players
    'J8H2VZ1X',
	'OJ8XK2AV',
	'D9NFMU51',
    --'CID2',
    -- Add more as needed
}

-- KERS system settings
Config.KERS = {
    enabled = true,            -- Globally enable/disable KERS functionality
    displayUI = true,          -- Default display state for KERS UI (can be toggled)
    activeDuration = 5000,     -- Duration KERS stays active once triggered (ms)
    cooldownDuration = 30000,  -- Cooldown before KERS can be used again (ms)
    sounds = {
        enabled = true,
        activate = "CONFIRM_BEEP",
        deactivate = "CANCEL",
        ready = "WAYPOINT_SET"
    }
}

-- Boost fuel consumption settings (Requires ox_fuel)
Config.BoostFuelConsumption = {
    enabled = true,           -- Set to false if not using ox_fuel or don't want fuel drain
    consumptionRate = 0.5,     -- Percentage of fuel consumed per second of KERS usage (Lower values = less consumption)
}

-- Tire Wear Settings
Config.TireWear = {
    enabled = true,

    -- Wear rates
    baseWearRate = 1.3,        -- Base wear percentage per kilometer driven on standard surfaces (e.g., 5.0 means 5% wear per km)
    steeringWearMultiplier = 1.4, -- Extra wear multiplier for outside tires during turns (1.0 = none, 1.3 = 30% extra)
    steeringAngleThreshold = 0.1, -- Minimum steering angle (radians, ~6 deg) to trigger extra wear

    -- UI settings
    displayUI = true,          -- Default display state for Tire UI (can be toggled)

    -- Probabilistic Blowout
    blowoutChanceAtZero = 0.15,  -- 15% chance per check interval to blowout when tire is at 0% wear
    blowoutCheckInterval = 500 -- How often (in ms) to check for a blowout when a tire is at 0%

    -- NOTE: All handling modification settings have been removed in this refactor.
    -- NOTE: All dirt/off-road settings have been removed in this refactor.
}

-- Pit Stop Settings
Config.PitStop = {
    Enabled = true,
    JackItem = 'carjack',
    ImpactWrenchItem = 'impactwrench', -- Make sure this item exists in ox_inventory
	RepairItem = 'impactwrench', -- Item required to repair
    RepairTargetDistance = 1.5,  -- Distance to interact with repair target
	RepairAnimDict = "anim@amb@clubhouse@tutorial@bkr_tut_ig3@",
    RepairAnimName = "machinic_loop_mechandplayer",
    RepairAnimFlags = 49,
    RepairAnimDuration = 15000,

    -- Jacking Configuration
    JackProp = 'prop_carjack',
    JackAttachBone = 'chassis_dummy',
    JackAttachOffset = vector3(0.0, -0.5, -0.7),
    JackAttachRotation = vector3(0.0, 0.0, 90.0),
    JackAnimDict = 'mini@repair',
    JackAnimName = 'fixing_a_ped',
    JackAnimFlags = 49,
    JackDuration = 2000,
    JackLiftAmount = 0.25,

    -- Target Options (Jacking - on Car)
    JackTargetIcon = 'fa-solid fa-arrow-up-from-bracket',
    JackTargetLabel = 'Use Car Jack',
    JackTargetDistance = 1.5,

    -- Target Options (Unjacking - on Car) -- Changed from prop to car
    UnjackTargetIcon = 'fa-solid fa-arrow-down-to-bracket',
    UnjackTargetLabel = 'Remove Jack',
    UnjackTargetDistance = 1.5, -- Kept same distance for consistency

    -- *** NEW: Tire Changing Config ***
    TireTargetIcon = 'fa-solid fa-wrench',
    TireTargetLabel = 'Change Tire (%s)', -- %s will be replaced with FL, FR, etc.
    TireTargetDistance = 1.2, -- Slightly shorter distance for wheel interaction
    TireBones = { -- Map visual index (0-3) to bone names
        [0] = 'wheel_lf',  -- Front Left
        [1] = 'wheel_rf',  -- Front Right
        [2] = 'wheel_lr',  -- Rear Left
        [3] = 'wheel_rr',  -- Rear Right
    },
    TireChangeAnimDict = "anim@amb@clubhouse@tutorial@bkr_tut_ig3@", -- Example anim
    TireChangeAnimName = "machinic_loop_mechandplayer",           -- Example anim
    TireChangeAnimFlags = 49, -- Loop + Upper body? Adjust if needed (e.g., 1 for full body loop)
    TireChangeDuration = 3000, -- ms duration per tire change (placeholder)
}


-- Debug mode
Config.Debug = false -- Enable extensive debug printing in F8 console (Set to false for production)

-- Debug print function (Used internally by the script)
-- Ensure this function uses the 'source' parameter correctly
function Config.DebugPrint(source, message)
    if Config.Debug then
        print(string.format('^3[dude_formularacing | %s]^7: %s', source, message))
    end
end

-- Table to store precomputed hashes (Populated by client scripts)
Config.FormulaCarHashes = {} -- Keep this line here

Config.BoundarySettings = {
    Enabled = true,                 -- Master switch for the entire track boundary feature
    WarningPercent = 0.90,           -- Warn when player is past 80% of the radius (e.g., 0.8 for 80%)
    CheckIntervalClient = 1500,     -- Milliseconds between client-side distance checks
    ShowClientWarning = true,       -- Show ox_lib notification to the player as a warning
}


Config.Tracks = {
    ['track1'] = {
        name = "AM International Raceway",
		boundaryCenter = vec3(-2709.61, 8534.75, 44.46),  -- Center point of your track
        boundaryRadius = 700.0,  -- Adjust based on your track size
        pitZone = {
            points = {
                vec3(-2963.53, 8114.65, 42.8),
                vec3(-2769.16, 8086.24, 42.8),
                vec3(-2692.06, 8084.90, 42.8),
                vec3(-2691.29, 8098.55, 42.8),
                vec3(-2850.34, 8155.72, 42.8),
                vec3(-2965.52, 8159.50, 42.8),
            },
            thickness = 6.0,
        },
        spawnLocations = {
            vector4(-2863.21, 8112.12, 44.35, 260.73),
            vector4(-2870.74, 8113.36, 44.41, 261.39),
            vector4(-2878.37, 8114.70, 44.48, 258.01),
            vector4(-2885.95, 8115.86, 44.54, 263.23),
            vector4(-2892.23, 8116.72, 44.59, 260.13),
            vector4(-2900.19, 8118.07, 44.66, 266.72),
            vector4(-2906.13, 8118.95, 44.71, 259.25),
            vector4(-2912.79, 8120.01, 44.76, 259.28),
            vector4(-2919.15, 8120.94, 44.81, 261.60),
            vector4(-2926.79, 8122.10, 44.87, 262.21)
        },
		recoverySpots = {
            vector4(-2929.87, 8143.60, 44.82, 168.50),
            vector4(-2924.44, 8142.40, 44.82, 169.50),
            vector4(-2908.62, 8140.05, 44.82, 168.69),
            vector4(-2901.84, 8139.78, 44.60, 169.47),
            vector4(-2896.84, 8138.16, 44.60, 171.83),
            vector4(-2880.73, 8135.76, 44.60, 168.12),
            vector4(-2874.23, 8134.78, 44.37, 174.33),
            vector4(-2869.12, 8134.26, 44.37, 170.00),
            vector4(-2853.04, 8131.50, 44.37, 166.89),
            vector4(-2846.67, 8130.95, 44.14, 177.31)
        },
		extraSpawnLocations = {
            vector4(-2916.16, 8149.36, 44.86, 259.59),
            vector4(-2909.37, 8148.26, 44.85, 260.77),
            vector4(-2899.20, 8146.55, 44.59, 260.36),
            vector4(-2889.74, 8145.10, 44.60, 261.57),
            vector4(-2871.72, 8142.37, 44.36, 260.63),
            vector4(-2860.50, 8140.94, 44.39, 261.06)
        },
		
        maxSpeed = 50.0,  -- MPH
        speedCheckInterval = 250
    },
    ['track2'] = {
        name = "Seagull Raceway",
		boundaryCenter = vec3(1402.05, 6808.26, 14.76),  -- Center point of your track
        boundaryRadius = 325.0,  -- Adjust based on your track size
        pitZone = {
            points = {
                -- Add your second track's pit zone coordinates
                vec3(1237.05, 6675.61, 10.0),
				vec3(1242.58, 6655.89, 10.0),
				vec3(1263.65, 6645.51, 10.0),
				vec3(1422.54, 6645.47, 10.0),
				vec3(1438.89, 6637.37, 10.0),
				vec3(1437.82, 6620.81, 10.0),
				vec3(1254.05, 6621.16, 10.0),
				vec3(1231.31, 6650.01, 10.0),
				vec3(1229.12, 6675.54, 10.0),
                -- ... more points
            },
            thickness = 6.0,
        },
        spawnLocations = {
            -- Add spawn locations for track 2
           -- vector4(x, y, z, heading),
			vector4(1414.73, 6635.77, 10.40, 267.19),
			vector4(1402.35, 6635.65, 10.40, 269.83),
			vector4(1390.75, 6635.67, 10.40, 267.56),
			vector4(1378.29, 6635.68, 10.40, 267.70),
			vector4(1366.36, 6635.69, 10.40, 270.55),
			vector4(1326.70, 6635.61, 10.41, 266.48),
			vector4(1313.97, 6635.79, 10.41, 267.07),
			vector4(1302.00, 6635.70, 10.41, 272.44),
			vector4(1289.48, 6635.68, 10.41, 267.29),
			vector4(1277.23, 6635.59, 10.41, 268.03),
            -- ... more spawn locations
        },
        recoverySpots = {
            vector4(1415.39, 6627.82, 10.41, 0.32),
            vector4(1403.20, 6627.98, 10.41, 1.16),
            vector4(1391.29, 6627.33, 10.41, 0.43),
            vector4(1379.24, 6627.49, 10.41, 1.81),
            vector4(1367.18, 6627.24, 10.41, 4.06),
            vector4(1326.70, 6627.39, 10.41, 4.59),
            vector4(1314.77, 6627.35, 10.41, 359.55),
            vector4(1302.69, 6627.82, 10.41, 356.47),
            vector4(1290.63, 6627.54, 10.41, 13.53),
            vector4(1278.51, 6627.46, 10.41, 357.09)
        },
		extraSpawnLocations = {
            vector4(1266.07, 6622.58, 10.38, 2.09),
            vector4(1261.91, 6623.10, 10.38, 359.35),
            vector4(1257.38, 6623.02, 10.38, 2.80),
            vector4(1253.11, 6625.79, 10.38, 266.60),
            vector4(1253.36, 6629.74, 10.38, 274.96),
            vector4(1259.11, 6630.21, 10.38, 268.81)
        },

        maxSpeed = 50.0,
        speedCheckInterval = 250
		}
    -- Add more tracks as needed
	
	}

-- Active track (can be changed dynamically)
Config.ActiveTrack = 'track1'
