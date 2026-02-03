--- JSON Schema validation for tool inputs
local M = {}

---@param value any
---@param expected_type string
---@return boolean
local function check_type(value, expected_type)
  if expected_type == "string" then
    return type(value) == "string"
  elseif expected_type == "number" then
    return type(value) == "number"
  elseif expected_type == "integer" then
    return type(value) == "number" and value % 1 == 0
  elseif expected_type == "boolean" then
    return type(value) == "boolean"
  elseif expected_type == "array" then
    return type(value) == "table" and vim.islist(value)
  elseif expected_type == "object" then
    return type(value) == "table" and not vim.islist(value)
  elseif expected_type == "null" then
    return value == nil or value == vim.NIL
  end
  return true -- Unknown type, allow
end

---@param value any
---@param schema table
---@param path string
---@return boolean, string|nil
local function validate_value(value, schema, path)
  -- Handle nil/missing values (checked separately for required)
  if value == nil then
    return true, nil
  end

  -- Type check
  if schema.type then
    if not check_type(value, schema.type) then
      return false, string.format("%s: expected %s, got %s", path, schema.type, type(value))
    end
  end

  -- Enum check
  if schema.enum then
    local found = false
    for _, allowed in ipairs(schema.enum) do
      if value == allowed then
        found = true
        break
      end
    end
    if not found then
      return false, string.format("%s: must be one of [%s]", path, table.concat(schema.enum, ", "))
    end
  end

  -- Nested object validation
  if schema.type == "object" and type(value) == "table" then
    -- Check nested required fields
    if schema.required then
      for _, field in ipairs(schema.required) do
        if value[field] == nil then
          return false, string.format("%s: missing required field: %s", path, field)
        end
      end
    end
    -- Validate nested properties
    if schema.properties then
      for prop_name, prop_schema in pairs(schema.properties) do
        local ok, err = validate_value(value[prop_name], prop_schema, path .. "." .. prop_name)
        if not ok then
          return false, err
        end
      end
    end
  end

  -- Array item validation
  if schema.type == "array" and schema.items and type(value) == "table" then
    for i, item in ipairs(value) do
      local ok, err = validate_value(item, schema.items, path .. "[" .. i .. "]")
      if not ok then
        return false, err
      end
    end
  end

  return true, nil
end

--- Validate args against a JSON Schema
---@param args table The input arguments to validate
---@param schema table|nil The JSON Schema to validate against
---@return boolean success
---@return string|nil error_message
function M.validate(args, schema)
  -- No schema = no validation
  if not schema then
    return true, nil
  end

  -- Ensure args is a table
  if type(args) ~= "table" then
    return false, "args must be a table"
  end

  -- Check required fields
  if schema.required then
    for _, field in ipairs(schema.required) do
      if args[field] == nil then
        return false, string.format("missing required field: %s", field)
      end
    end
  end

  -- Validate each property
  if schema.properties then
    for prop_name, prop_schema in pairs(schema.properties) do
      local ok, err = validate_value(args[prop_name], prop_schema, prop_name)
      if not ok then
        return false, err
      end
    end
  end

  return true, nil
end

return M
