-- Store spawned vehicle network IDs mapped to their plate for potential management
local spawnedVehicles = {} -- [plate] = { netId = netId, owner = identifier }

-- Function to get player identifier based on config
local function GetPlayerIdentifier(playerSource)
    for i = 0, GetNumPlayerIdentifiers(playerSource) - 1 do
        local identifier = GetPlayerIdentifier(playerSource, i)
        if identifier and string.starts(identifier, Config.PlayerIdentifier .. ':') then
            return identifier
        end
    end
    return nil -- Return nil if the configured identifier type is not found
end

-- Function to spawn a single vehicle from saved data
local function SpawnSavedVehicle(data)
    local modelHash = tonumber(data.model) -- Ensure model is a number
    if not modelHash then
        print(('[persistent_vehicles] Error: Invalid model hash for plate %s'):format(data.plate))
        return
    end

    -- Request model only if needed
    if not HasModelLoaded(modelHash) then
        RequestModel(modelHash)
        while not HasModelLoaded(modelHash) do
            Wait(100) -- Wait for model to load
        end
    end

    -- Create the vehicle
    local vehicle = CreateVehicle(modelHash, data.pos_x, data.pos_y, data.pos_z, data.heading, true, false) -- Create networked, don't automatically network register yet
    if vehicle == 0 then
        print(('[persistent_vehicles] Error: Failed to create vehicle for plate %s'):format(data.plate))
        SetModelAsNoLongerNeeded(modelHash)
        return
    end

    -- Network registration and mission entity status
    NetworkRegisterEntityAsNetworked(vehicle)
    while not NetworkGetEntityIsNetworked(vehicle) do
        Wait(0)
    end
    SetEntityAsMissionEntity(vehicle, true, true) -- Make it persistent

    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    SetNetworkIdExistsOnAllMachines(netId, true) -- Ensure it exists everywhere

    -- Set basic properties
    SetVehicleNumberPlateText(vehicle, data.plate)
    SetVehicleFuelLevel(vehicle, data.fuel_level)
    SetVehicleEngineHealth(vehicle, data.health_engine)
    SetVehicleBodyHealth(vehicle, data.health_body)
    SetVehicleDoorLockStatus(vehicle, data.locked and 2 or 1) -- 1=Unlocked, 2=Locked

    -- Apply complex properties (mods, colors, etc.)
    local properties = json.decode(data.vehicle_properties)
    if properties then
        SetVehicleProperties(vehicle, properties)
    end

    -- Apply tyre status
    local tyreStatus = json.decode(data.health_tyres or '{}')
    for tyreIndex, isBurst in pairs(tyreStatus) do
        if isBurst then
            SetVehicleTyreBurst(vehicle, tonumber(tyreIndex), true, 1000.0)
        end
    end

    -- Apply window status
    local windowStatus = json.decode(data.health_windows or '{}')
    for windowIndex, isBroken in pairs(windowStatus) do
        if isBroken then
            SmashVehicleWindow(vehicle, tonumber(windowIndex))
        end
    end

    -- Apply door status (might need careful handling depending on damage model)
    -- Example: Assuming true means broken/off
    local doorStatus = json.decode(data.health_doors or '{}')
    for doorIndex, isBroken in pairs(doorStatus) do
        if isBroken then
           SetVehicleDoorBroken(vehicle, tonumber(doorIndex), true) -- true = broken off
        end
    end

    SetModelAsNoLongerNeeded(modelHash) -- Release model

    spawnedVehicles[data.plate] = { netId = netId, owner = data.owner_identifier }

    if Config.Debug then
        print(('[persistent_vehicles] Spawned vehicle: Plate %s, Owner %s, NetID %d'):format(data.plate, data.owner_identifier, netId))
    end
end

-- Function to load and spawn all vehicles for a player
local function LoadPlayerVehicles(playerSource)
    local identifier = GetPlayerIdentifier(playerSource)
    if not identifier then
        print(('[persistent_vehicles] Error: Could not get identifier for player %s'):format(playerSource))
        return
    end

    if Config.Debug then
        print(('[persistent_vehicles] Loading vehicles for player %s (%s)'):format(GetPlayerName(playerSource), identifier))
    end

    -- Use oxmysql for the query
    local result = MySQL.query.await('SELECT * FROM player_vehicles WHERE owner_identifier = ?', { identifier })

    if result and #result > 0 then
        for _, vehicleData in ipairs(result) do
            -- Check if vehicle might already be spawned (e.g., server didn't restart, player reconnected)
            if not spawnedVehicles[vehicleData.plate] then
                 SpawnSavedVehicle(vehicleData)
            elseif Config.Debug then
                 print(('[persistent_vehicles] Vehicle %s already spawned, skipping.'):format(vehicleData.plate))
            end
        end
    elseif Config.Debug then
        print(('[persistent_vehicles] No saved vehicles found for %s'):format(identifier))
    end
end

-- Event Handler: Player Connecting
AddEventHandler('playerJoining', function()
    local src = source
    -- Delay slightly to ensure player is fully loaded
    SetTimeout(5000, function()
        if GetPlayerName(src) then -- Check if player still connected
             LoadPlayerVehicles(src)
        end
    end)
end)

-- Event Handler: Player Disconnecting
AddEventHandler('playerDropped', function(reason)
    local src = source
    local identifier = GetPlayerIdentifier(src)
    if not identifier then return end

    if Config.Debug then
        print(('[persistent_vehicles] Player %s (%s) disconnected. Keeping their vehicles spawned.'):format(GetPlayerName(src), identifier))
    end

    -- Decide what to do with vehicles on disconnect. For full persistence, we leave them.
    -- You *could* despawn them here and rely on reload on next join, but the request
    -- implies they stay put like real parked cars.

    -- Example: If you wanted to despawn them:
    -- for plate, data in pairs(spawnedVehicles) do
    --     if data.owner == identifier and NetworkDoesNetworkIdExist(data.netId) then
    --         local entity = NetworkGetEntityFromNetworkId(data.netId)
    --         if DoesEntityExist(entity) then
    --             DeleteEntity(entity)
    --             if Config.Debug then
    --                 print(('[persistent_vehicles] Despawned vehicle %s for disconnected player %s'):format(plate, identifier))
    --             end
    --         end
    --         spawnedVehicles[plate] = nil -- Remove from tracked list
    --     end
    -- end
end)


-- Server Event: Client requests to save a vehicle
RegisterNetEvent('persistent_vehicles:saveVehicle', function(vehicleData)
    local src = source
    local identifier = GetPlayerIdentifier(src)
    if not identifier then
        print(('[persistent_vehicles] Error: Save request from player %s without valid identifier.'):format(src))
        return
    end

    -- Validate incoming data (basic checks)
    if not vehicleData or not vehicleData.plate or not vehicleData.model or not vehicleData.pos or not vehicleData.propertiesJson then
        print(('[persistent_vehicles] Error: Incomplete vehicle data received from player %s for plate %s.'):format(src, vehicleData and vehicleData.plate or 'N/A'))
        return
    end

    if Config.Debug then
        print(('[persistent_vehicles] Received save request for plate %s from %s'):format(vehicleData.plate, identifier))
    end

    -- Prepare data for database insertion/update
    local query = [[
        INSERT INTO player_vehicles (
            owner_identifier, plate, model, pos_x, pos_y, pos_z, heading,
            vehicle_properties, fuel_level, health_engine, health_body,
            health_tyres, health_windows, health_doors, locked
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            model = VALUES(model), pos_x = VALUES(pos_x), pos_y = VALUES(pos_y), pos_z = VALUES(pos_z), heading = VALUES(heading),
            vehicle_properties = VALUES(vehicle_properties), fuel_level = VALUES(fuel_level), health_engine = VALUES(health_engine),
            health_body = VALUES(health_body), health_tyres = VALUES(health_tyres), health_windows = VALUES(health_windows),
            health_doors = VALUES(health_doors), locked = VALUES(locked), last_update = NOW();
    ]]

    local params = {
        identifier,
        vehicleData.plate,
        tonumber(vehicleData.model),
        vehicleData.pos.x,
        vehicleData.pos.y,
        vehicleData.pos.z,
        vehicleData.heading,
        vehicleData.propertiesJson, -- Already JSON encoded by client
        vehicleData.fuel,
        vehicleData.engineHealth,
        vehicleData.bodyHealth,
        vehicleData.tyresJson,      -- Already JSON encoded by client
        vehicleData.windowsJson,    -- Already JSON encoded by client
        vehicleData.doorsJson,      -- Already JSON encoded by client
        vehicleData.locked
    }

    -- Execute the query using oxmysql
    local success, result = pcall(MySQL.execute.await, query, params)

    if success then
        if Config.Debug then
            print(('[persistent_vehicles] Successfully saved/updated vehicle %s for %s. Rows affected: %s'):format(vehicleData.plate, identifier, result))
        end
    else
        print(('[persistent_vehicles] Error saving vehicle %s for %s: %s'):format(vehicleData.plate, identifier, result)) -- 'result' contains the error message on pcall failure
    end
end)

-- Add a command to manually spawn vehicles if needed for testing
RegisterCommand('loadmycars', function(source, args, rawCommand)
    local src = source
    LoadPlayerVehicles(src)
    TriggerClientEvent('chat:addMessage', src, { args = { '^2[Vehicles]', 'Attempting to load your saved vehicles.' } })
end, false) -- false = not restricted

-- Clean up spawned vehicle table on resource stop (important!)
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        spawnedVehicles = {}
        print('[persistent_vehicles] Resource stopped, cleared spawned vehicle cache.')
    end
end)

-- Initial load for any vehicles already saved when the script starts (covers server restarts)
-- Note: This might spawn vehicles for players not currently online.
-- Consider if you want this behavior or only load on player connect.
-- For the "real life parking" feel, loading them all makes sense.
Citizen.CreateThread(function()
    Wait(2000) -- Wait a bit for DB connection to be ready
    print('[persistent_vehicles] Performing initial load of all saved vehicles...')
    local result = MySQL.query.await('SELECT * FROM player_vehicles', {})
    if result and #result > 0 then
        local count = 0
        for _, vehicleData in ipairs(result) do
            SpawnSavedVehicle(vehicleData)
            count = count + 1
        end
        print(('[persistent_vehicles] Initial load complete. Spawned %d vehicles.'):format(count))
    else
        print('[persistent_vehicles] No vehicles found in database for initial load.')
    end
end)
