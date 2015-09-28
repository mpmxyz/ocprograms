-----------------------------------------------------
--name       : lib/mpm/hashset.lua
--description: allows using raw values or getters for the same property
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------

local values = {}
--type sets used to extract values
values.types_callable = {
  ["function"] = true,
  --due to component wrappers:
  ["table"]    = true,
}
values.types_indexable = {
  ["table"]    = true,
}
--values.get(value, forceCall, key, ...) -> value
--If the given value is a primitive value, it is simply returned.
--If it is a function it is called with the parameters (key, ...) and the first result is returned.
--If it is a table it is called as a function if forceCall is true.
--Else it will be indexed using key. The other parameters are applied recursively if they aren't nil.
function values.get(value, forceCall, key, ...)
  local typ = type(value)
  if values.types_indexable[typ] and key ~= nil and not forceCall then
    value = value[key]
    --if (...) ~= nil then
    --multidimensional keys: applied recursively
    return values.get(value, false, ...)
    --end
  elseif values.types_callable[typ] then
    return (value(key, ...))
  end
  return value
end


function values.set(target, value, forceCall, key, ...)
  local typ = type(target)
  if values.types_indexable[typ] and key ~= nil and not forceCall then
    if (...) ~= nil then
      --multidimensional keys: applied recursively
      return values.set(target[key], value, false, ...)
    else
      target[key] = value
      return true
    end
  elseif values.types_callable[typ] then
    if key == nil then
      target(value)
    else
      --TODO: better format?
      target(value, key, ...)
    end
    return true
  end
  return false
end

--type sets used to check value types
values.types_number = {
  --raw
  ["number"]   = true,
  --via callable or indexable object
  ["function"] = true,
  ["table"]    = true,
}
values.types_string = {
  --raw
  ["string"]   = true,
  --via callable or indexable object
  ["function"] = true,
  ["table"]    = true,
}
values.types_table = {
  --raw
  ["table"]    = true,
  --via callable object
  ["function"] = true,
}

values.types_raw_number = {
  --raw only
  ["number"]   = true,
}
values.types_raw_string = {
  --raw only
  ["string"]   = true,
}
values.types_raw_table = {
  --raw only
  ["table"]    = true,
}

--values.check(value, name, permitted_types, wrongTypeText, default) -> value or default
--This function checks if the given value has a valid type. It returns the value or the given default value if the value is nil.
--'value' is the value being checked.
--'name' is a name used for error descriptions.
--'permitted_types' is a table with type strings as keys. All 'true' values mark a valid type.
--'wrongTypeText' is a string appended to the name to get the error message if the value type isn't valid.
--'default' is used as the output value if the input value is nil. Throws an error if both the value and 'default' are nil.
function values.check(value, name, permittedTypes, wrongTypeText, default)
  if not permittedTypes[type(value)] then
    if value == nil then
      if default == nil then
        error("'" .. name .. "' is missing!")
      end
      return default
    else
      error("'" .. name .. "' " .. wrongTypeText)
    end
  end
  return value
end

local checkTables = {
  checkNumber    = values.types_number,
  checkString    = values.types_string,
  checkTable     = values.types_table,
  checkRawNumber = values.types_raw_number,
  checkRawString = values.types_raw_string,
  checkRawTable  = values.types_raw_table,
  checkCallable  = values.types_callable,
}
local checkMessages = {
  checkNumber    = "has to be a number or a callable object!",
  checkString    = "has to be a string or a callable object!",
  checkTable     = "has to be a table or a callable object!",
  checkRawNumber = "has to be a number!",
  checkRawString = "has to be a string!",
  checkRawTable  = "has to be a table!",
  checkCallable  = "has to be a callable object!",
}

for name, permittedTypes in pairs(checkTables) do
  local msg = checkMessages[name]
  --Asserts that the given value has the correct type or can be converted to one by using values.get().
  --(throws an error using the given name otherwise)
  values[name] = function(value, name, default)
    return values.check(value, name, permittedTypes, msg, default)
  end
end

return values
