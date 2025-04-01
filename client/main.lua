local lastVehicle = nil -- Store the entity handle of the last vehicle the player was in
local currentVehicle = nil -- Store the entity handle of the current vehicle

Citizen.CreateThread(function()
    while true do
        Wait(Config.CheckInterval) -- Check periodically

        local playerPed = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(playerPed, false) -- Get vehicle player is currently in

        if vehicle ~= 0 and vehicle ~= currentVehicle then
            -- Player entered a new vehicle
            currentVehicle = vehicle
            if Config.Debug then
                 local plate = GetVehicleNumberPlateText(currentVehicle)
                 print(('[persistent_vehicles] Player entered vehicle: %s, Plate: %s'):format(GetEntityModel(currentVehicle), plate))
            end
        elseif vehicle == 0 and currentVehicle ~= nil then
            -- Player just exited the vehicle stored in 'currentVehicle'
            lastVehicle = currentVehicle
            currentVehicle = nil -- Reset current vehicle
            HandleVehicleExit(lastVehicle) -- Process the exit
        end
    end
end)

function HandleVehicleExit(vehicle)
    if not DoesEntityExist(vehicle) then return end -- Safety check

    local plate = GetVehicleNumberPlateText(vehicle)
    if not plate or string.gsub(plate, "%s+", "") == "" then -- Ignore vehicles without plates or only whitespace
        if Config.Debug then print(('[persistent_vehicles] Ignoring vehicle exit: No valid plate.')) end
        lastVehicle = nil -- Clear last vehicle since it wasn't saved
        return
    end

    -- ================================================================
    -- !! IMPORTANT !! Add Ownership Check Here
    -- ================================================================
    -- Before saving, you MUST check if the player actually owns this vehicle.
    -- This usually involves triggering a server event to check the plate/vehicle against
    -- the player's identifier in a separate ownership table (e.g., player_garages).
    --
    -- Example (Conceptual - requires server-side check):
    -- TriggerServerEvent('persistent_vehicles:checkOwnership', plate, function(isOwner)
    --     if isOwner then
    --         SaveVehicle(vehicle)
    --     else
    --         if Config.Debug then print(('[persistent_vehicles] Player does not own vehicle %s, not saving.'):format(plate)) end
    --         lastVehicle = nil -- Clear last vehicle
    --     end
    -- end)

    -- For this example, we'll skip the ownership check and save *any* vehicle exited.
    -- !! THIS IS NOT RECOMMENDED FOR A LIVE SERVER without an ownership check !!
    if Config.Debug then print(('[persistent_vehicles] Ownership check skipped (DEBUG/EXAMPLE). Proceeding to save vehicle %s'):format(plate)) end
    SaveVehicle(vehicle)
    -- ================================================================

end

function SaveVehicle(vehicle)
    if not DoesEntityExist(vehicle) then
        if Config.Debug then print(('[persistent_vehicles] Cannot save: Vehicle entity no longer exists.')) end
        lastVehicle = nil
        return
    end

    local plate = GetVehicleNumberPlateText(vehicle)
    local model = GetEntityModel(vehicle)
    local coords = GetEntityCoords(vehicle)
    local heading = GetEntityHeading(vehicle)
    local properties = GetVehicleProperties(vehicle) -- Gets mods, colors etc as a table
    local fuel = GetVehicleFuelLevel(vehicle)
    local engineHealth = GetVehicleEngineHealth(vehicle)
    local bodyHealth = GetVehicleBodyHealth(vehicle)
    local locked = GetVehicleDoorLockStatus(vehicle) > 1 -- Check if locked (Status > 1 usually means locked)

    -- Tyre Status
    local tyres = {}
    for i = 0, GetVehicleNumberOfWheels(vehicle) - 1 do
        -- Check tyre health/burst status based on index
        if IsVehicleTyreBurst(vehicle, i, false) then -- false checks visual burst, true checks completely burst
            tyres[tostring(i)] = true -- Store index as string key, value as true if burst
        end
    end

    -- Window Status
    local windows = {}
    -- Common window indices: 0=FrontLeft, 1=FrontRight, 2=RearLeft, 3=RearRight, etc. Check natives docs for specifics per vehicle.
    for i = 0, 7 do -- Check a common range of window indices
         if not IsVehicleWindowIntact(vehicle, i) then
             windows[tostring(i)] = true -- Store index as string key, value as true if broken
         end
    end

     -- Door Status
    local doors = {}
    -- Common door indices: 0=FrontLeft, 1=FrontRight, 2=RearLeft, 3=RearRight, 4=Hood, 5=Trunk
    for i = 0, 5 do
        if IsVehicleDoorDamaged(vehicle, i) then -- You might want `IsVehicleDoorBroken` specifically if you only care if it's *off*
             doors[tostring(i)] = true -- Store index as string key, value as true if damaged/broken
        end
    end

    -- Prepare data payload
    local vehicleData = {
        plate = plate,
        model = model,
        pos = coords,
        heading = heading,
        propertiesJson = json.encode(properties), -- Encode properties table to JSON string
        fuel = fuel,
        engineHealth = engineHealth,
        bodyHealth = bodyHealth,
        tyresJson = json.encode(tyres),           -- Encode tyres table to JSON string
        windowsJson = json.encode(windows),       -- Encode windows table to JSON string
        doorsJson = json.encode(doors),           -- Encode doors table to JSON string
        locked = locked
    }

    if Config.Debug then
        print(('[persistent_vehicles] Sending save request for plate %s'):format(plate))
        -- Be careful printing propertiesJson, it can be very long
        -- print(json.encode(vehicleData)) -- Uncomment for detailed debug
    end

    -- Send data to server for saving
    TriggerServerEvent('persistent_vehicles:saveVehicle', vehicleData)

    lastVehicle = nil -- Clear the last vehicle reference after attempting save
end

-- Helper function because Lua doesn't have string.starts built-in before Lua 5.3
if not string.starts then
    function string.starts(str, start)
        return str:sub(1, #start) == start
    end
end
