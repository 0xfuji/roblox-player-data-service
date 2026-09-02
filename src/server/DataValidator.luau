local DataValidator = {}

local function isFiniteNumber(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

function DataValidator.deepCopy(value, seen)
    if type(value) ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] then
        error("Cannot copy a cyclic table", 2)
    end

    local copy = {}
    seen[value] = copy

    for key, child in pairs(value) do
        copy[DataValidator.deepCopy(key, seen)] = DataValidator.deepCopy(child, seen)
    end

    seen[value] = nil
    return copy
end

local function validateDataStoreValue(value, seen, path)
    local valueType = typeof(value)

    if valueType == "number" then
        if not isFiniteNumber(value) then
            return false, string.format("%s contains a non-finite number", path)
        end
        return true
    end

    if valueType == "string" or valueType == "boolean" then
        return true
    end

    if valueType ~= "table" then
        return false, string.format(
            "%s contains unsupported type '%s'",
            path,
            valueType
        )
    end

    seen = seen or {}
    if seen[value] then
        return false, string.format("%s contains a cyclic table", path)
    end

    seen[value] = true

    for key, child in pairs(value) do
        local keyType = typeof(key)
        if keyType ~= "string" and keyType ~= "number" then
            seen[value] = nil
            return false, string.format(
                "%s contains unsupported key type '%s'",
                path,
                keyType
            )
        end

        local childPath = string.format("%s.%s", path, tostring(key))
        local ok, err = validateDataStoreValue(child, seen, childPath)

        if not ok then
            seen[value] = nil
            return false, err
        end
    end

    seen[value] = nil
    return true
end

local function validateTemplateShape(template, data, path)
    if typeof(template) ~= typeof(data) then
        return false, string.format(
            "%s expected %s, got %s",
            path,
            typeof(template),
            typeof(data)
        )
    end

    if typeof(template) == "number" and not isFiniteNumber(data) then
        return false, string.format("%s must be a finite number", path)
    end

    if typeof(template) ~= "table" then
        return true
    end

    for key, templateValue in pairs(template) do
        local dataValue = data[key]

        if dataValue == nil then
            return false, string.format(
                "%s.%s is missing",
                path,
                tostring(key)
            )
        end

        local ok, err = validateTemplateShape(
            templateValue,
            dataValue,
            string.format("%s.%s", path, tostring(key))
        )

        if not ok then
            return false, err
        end
    end

    return true
end

function DataValidator.reconcile(template, data)
    local result

    if type(data) == "table" then
        result = DataValidator.deepCopy(data)
    else
        result = {}
    end

    for key, defaultValue in pairs(template) do
        local currentValue = result[key]

        if currentValue == nil then
            result[key] = DataValidator.deepCopy(defaultValue)
        elseif type(defaultValue) == "table" and type(currentValue) == "table" then
            result[key] = DataValidator.reconcile(defaultValue, currentValue)
        elseif typeof(defaultValue) ~= typeof(currentValue) then
            -- If an older/corrupted value has the wrong type, fall back to the
            -- current default instead of letting it poison the live profile.
            result[key] = DataValidator.deepCopy(defaultValue)
        end
    end

    return result
end

function DataValidator.validate(template, data)
    if type(data) ~= "table" then
        return false, "Profile root must be a table"
    end

    local ok, err = validateTemplateShape(template, data, "data")
    if not ok then
        return false, err
    end

    return validateDataStoreValue(data, nil, "data")
end

function DataValidator.validateValue(templateValue, value)
    local ok, err = validateTemplateShape(templateValue, value, "value")
    if not ok then
        return false, err
    end

    return validateDataStoreValue(value, nil, "value")
end

return DataValidator
