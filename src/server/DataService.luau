local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local DataValidator = require(script.Parent.DataValidator)
local DataTemplate = require(
    ServerScriptService:WaitForChild("PlayerData")
        :WaitForChild("Shared")
        :WaitForChild("DataTemplate")
)

local DATASTORE_NAME = "PlayerData_v1"
local AUTOSAVE_INTERVAL = 60
local MAX_RETRIES = 3
local RETRY_DELAY_SECONDS = 1.5
local SHUTDOWN_TIMEOUT_SECONDS = 25

local store = DataStoreService:GetDataStore(DATASTORE_NAME)

local DataService = {}

local profiles = {}
local initialized = false
local shuttingDown = false

local function getKey(userId)
    return string.format("player_%d", userId)
end

local function retryDataStore(operationName, callback)
    local lastError

    for attempt = 1, MAX_RETRIES do
        local success, result = pcall(callback)

        if success then
            return true, result
        end

        lastError = result

        warn(string.format(
            "[DataService] %s failed (attempt %d/%d): %s",
            operationName,
            attempt,
            MAX_RETRIES,
            tostring(result)
        ))

        if attempt < MAX_RETRIES then
            task.wait(RETRY_DELAY_SECONDS * attempt)
        end
    end

    return false, lastError
end

local function normalizePath(path)
    if type(path) == "table" then
        if #path == 0 then
            return nil, "Path cannot be empty"
        end

        local parts = table.create(#path)

        for index, part in ipairs(path) do
            if type(part) ~= "string" and type(part) ~= "number" then
                return nil, "Path parts must be strings or numbers"
            end

            parts[index] = part
        end

        return parts
    end

    if type(path) ~= "string" or path == "" then
        return nil, "Path must be a non-empty string or array"
    end

    local parts = {}

    for part in string.gmatch(path, "[^.]+") do
        table.insert(parts, part)
    end

    if #parts == 0 then
        return nil, "Path cannot be empty"
    end

    return parts
end

local function getPathValue(root, parts)
    local current = root

    for _, part in ipairs(parts) do
        if type(current) ~= "table" then
            return nil, false
        end

        current = current[part]

        if current == nil then
            return nil, false
        end
    end

    return current, true
end

local function setPathValue(root, parts, value)
    local current = root

    for index = 1, #parts - 1 do
        local part = parts[index]
        local nextValue = current[part]

        if type(nextValue) ~= "table" then
            return false, string.format(
                "Cannot write through non-table path segment '%s'",
                tostring(part)
            )
        end

        current = nextValue
    end

    current[parts[#parts]] = value
    return true
end

local function getProfile(player)
    if typeof(player) ~= "Instance" or not player:IsA("Player") then
        return nil, "Expected a Player"
    end

    local profile = profiles[player.UserId]

    if not profile then
        return nil, "Player data is not loaded"
    end

    return profile
end

local function saveProfile(player)
    local profile, profileError = getProfile(player)

    if not profile then
        return false, profileError
    end

    while profile.saving do
        task.wait()
    end

    if not profile.dirty then
        return true
    end

    profile.saving = true

    local revisionAtStart = profile.revision
    local snapshot = DataValidator.deepCopy(profile.data)

    local valid, validationError = DataValidator.validate(DataTemplate, snapshot)

    if not valid then
        profile.saving = false
        warn(string.format(
            "[DataService] Refusing to save invalid data for %s: %s",
            player.Name,
            validationError
        ))
        return false, validationError
    end

    local success, result = retryDataStore(
        string.format("Save %s", player.Name),
        function()
            return store:UpdateAsync(getKey(player.UserId), function()
                return snapshot
            end)
        end
    )

    profile.saving = false

    if not success then
        return false, tostring(result)
    end

    if profile.revision == revisionAtStart then
        profile.dirty = false
    end

    return true
end

local function loadProfile(player)
    if profiles[player.UserId] then
        return true
    end

    local success, storedData = retryDataStore(
        string.format("Load %s", player.Name),
        function()
            return store:GetAsync(getKey(player.UserId))
        end
    )

    if not success then
        warn(string.format(
            "[DataService] Could not load data for %s. The player will not receive a fresh profile because doing so could overwrite existing data.",
            player.Name
        ))

        if player.Parent then
            player:Kick("Your data could not be loaded. Please rejoin in a moment.")
        end

        return false
    end

    if storedData ~= nil and type(storedData) ~= "table" then
        warn(string.format(
            "[DataService] Invalid stored profile root for %s",
            player.Name
        ))

        if player.Parent then
            player:Kick("Your saved data could not be read safely. Please try again later.")
        end

        return false
    end

    local data
    local isNewProfile = storedData == nil

    if isNewProfile then
        data = DataValidator.deepCopy(DataTemplate)
    else
        data = DataValidator.reconcile(DataTemplate, storedData)
    end

    local valid, validationError = DataValidator.validate(DataTemplate, data)

    if not valid then
        warn(string.format(
            "[DataService] Validation failed for %s: %s",
            player.Name,
            validationError
        ))

        if player.Parent then
            player:Kick("Your saved data could not be loaded safely. Please try again later.")
        end

        return false
    end

    if not player.Parent then
        return false
    end

    profiles[player.UserId] = {
        data = data,
        dirty = isNewProfile,
        revision = 0,
        saving = false,
    }

    return true
end

function DataService.IsLoaded(player)
    return player ~= nil and profiles[player.UserId] ~= nil
end

function DataService.WaitForData(player, timeoutSeconds)
    timeoutSeconds = timeoutSeconds or 10
    local startedAt = os.clock()

    while player.Parent and not DataService.IsLoaded(player) do
        if os.clock() - startedAt >= timeoutSeconds then
            return false
        end

        task.wait(0.05)
    end

    return DataService.IsLoaded(player)
end

function DataService.GetSnapshot(player)
    local profile, err = getProfile(player)

    if not profile then
        return nil, err
    end

    return DataValidator.deepCopy(profile.data)
end

function DataService.GetValue(player, path)
    local profile, err = getProfile(player)

    if not profile then
        return nil, err
    end

    local parts, pathError = normalizePath(path)

    if not parts then
        return nil, pathError
    end

    local value, found = getPathValue(profile.data, parts)

    if not found then
        return nil, "Unknown data path"
    end

    return DataValidator.deepCopy(value)
end

function DataService.SetValue(player, path, value)
    local profile, err = getProfile(player)

    if not profile then
        return false, err
    end

    local parts, pathError = normalizePath(path)

    if not parts then
        return false, pathError
    end

    local templateValue, found = getPathValue(DataTemplate, parts)

    if not found then
        return false, "Path is not defined in DataTemplate"
    end

    local valid, validationError = DataValidator.validateValue(templateValue, value)

    if not valid then
        return false, validationError
    end

    local nextData = DataValidator.deepCopy(profile.data)
    local wrote, writeError = setPathValue(
        nextData,
        parts,
        DataValidator.deepCopy(value)
    )

    if not wrote then
        return false, writeError
    end

    profile.data = nextData
    profile.revision += 1
    profile.dirty = true

    return true
end

function DataService.Increment(player, path, amount)
    if type(amount) ~= "number"
        or amount ~= amount
        or amount == math.huge
        or amount == -math.huge
    then
        return false, "Amount must be a finite number"
    end

    local currentValue, err = DataService.GetValue(player, path)

    if currentValue == nil then
        return false, err
    end

    if type(currentValue) ~= "number" then
        return false, "Increment can only be used on number values"
    end

    local nextValue = currentValue + amount

    local success, setError = DataService.SetValue(player, path, nextValue)

    if not success then
        return false, setError
    end

    return true, nextValue
end

function DataService.Update(player, callback)
    if type(callback) ~= "function" then
        return false, "Update expects a callback function"
    end

    local profile, err = getProfile(player)

    if not profile then
        return false, err
    end

    local draft = DataValidator.deepCopy(profile.data)

    local success, callbackError = xpcall(function()
        callback(draft)
    end, debug.traceback)

    if not success then
        return false, callbackError
    end

    local valid, validationError = DataValidator.validate(DataTemplate, draft)

    if not valid then
        return false, validationError
    end

    profile.data = DataValidator.deepCopy(draft)
    profile.revision += 1
    profile.dirty = true

    return true
end

function DataService.SavePlayer(player)
    return saveProfile(player)
end

function DataService.Init()
    if initialized then
        return
    end

    initialized = true

    Players.PlayerAdded:Connect(function(player)
        task.spawn(loadProfile, player)
    end)

    Players.PlayerRemoving:Connect(function(player)
        if profiles[player.UserId] then
            local success, err = saveProfile(player)

            if not success then
                warn(string.format(
                    "[DataService] Final save failed for %s: %s",
                    player.Name,
                    tostring(err)
                ))
            end

            profiles[player.UserId] = nil
        end
    end)

    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(loadProfile, player)
    end

    task.spawn(function()
        while not shuttingDown do
            task.wait(AUTOSAVE_INTERVAL)

            if shuttingDown then
                break
            end

            for _, player in ipairs(Players:GetPlayers()) do
                if profiles[player.UserId] then
                    task.spawn(function()
                        local success, err = saveProfile(player)

                        if not success then
                            warn(string.format(
                                "[DataService] Autosave failed for %s: %s",
                                player.Name,
                                tostring(err)
                            ))
                        end
                    end)
                end
            end
        end
    end)

    game:BindToClose(function()
        shuttingDown = true

        local pending = 0

        for _, player in ipairs(Players:GetPlayers()) do
            if profiles[player.UserId] then
                pending += 1

                task.spawn(function()
                    local success, err = saveProfile(player)

                    if not success then
                        warn(string.format(
                            "[DataService] Shutdown save failed for %s: %s",
                            player.Name,
                            tostring(err)
                        ))
                    end

                    pending -= 1
                end)
            end
        end

        local startedAt = os.clock()

        while pending > 0
            and os.clock() - startedAt < SHUTDOWN_TIMEOUT_SECONDS
        do
            task.wait(0.05)
        end
    end)
end

return DataService
