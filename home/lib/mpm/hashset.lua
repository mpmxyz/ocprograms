-----------------------------------------------------
--name       : lib/mpm/hashset.lua
--description: a hashset implementation not relying on raw equality
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------

--a quick and dirty hashset implementation using a given equality function
--(Lua tables are very nice but only support raw equality.)

--library table
local hashset = {}
--primes used as a seed for hash calculation
local primes = {3, 5, 7, 11, 13, 17, 19, 23, 29}

--is used within the condition (bucket items^2 > resize_trigger * allocated size) to trigger resizing
local resize_trigger = 10
--a value of 2 doubles the size of the hashset when increasing size
local resize_factor  = 2

--creates a new hashset
--arguments:
--  name       format
--  hashFunc   object, seed, hashmap size -> hash
--  equals     a,b -> true if a == b
--  sizeHint   optional, initializes the hashset with the given number of buckets
function hashset.new(hashFunc, equals, sizeHint)
  --an object -> object table containing the contents of the hashset
  local content = {}
  --object counter (only for debugging)
  local counter = 1
  --hash % size + 1 or "bucket" -> list of objects
  local set = {}
  --equals #set
  local size
  --currently used seed
  local seed
  
  --returns the bucket for the given object
  local function getList(obj)
    return set[math.floor(hashFunc(obj, seed, size)) % size + 1]
  end
  --returns the bucket for the given object
  --additionally returns its index if it already is in there
  local function getListIndex(obj)
    local list = getList(obj)
    for i = 1, #list do
      if equals(list[i], obj) then
        return list, i
      end
    end
    return list
  end
  --gets the equal object already within the hashset
  --returns nil if it doesn't exist
  local function get(obj)
    local list, index = getListIndex(obj)
    if index then
      return list[index]
    end
  end
  --forward declaration
  local resize
  --inserts the given object to the hashset if it isn't already
  local function insert(obj)
    local list, index = getListIndex(obj)
    if index then
      --already exists
      return list[index]
    end
    content[obj] = obj
    counter = counter + 1
    --trigger resizing if the current bucket is full
    --TODO: what about bad hashing? (if all hash values are equal...)
    if (#list) ^ 2 > resize_trigger * size then
      resize(resize_factor * size)
    else
      list[#list + 1] = obj
    end
    return obj
  end
  --removes the given object from the hashset
  local function remove(obj)
    local list, index
    if index then
      counter = counter - 1
      content[list[index]] = nil
      table.remove(list, index)
    end
  end
  
  --resizes the given hashset
  --Previously stored objects are reinserted to their new buckets.
  resize = function(newSize)
    seed = primes[math.random(1, #primes)]
    size = newSize
    --add lists
    for i=1, size do
      set[i] = {}
    end
    --insert objects in new hashtable
    for obj in pairs(content) do
      local list = getList(obj)
      list[#list + 1] = obj
    end
  end
  --set default size
  resize(16 or sizeHint)
  --return the hashset object
  return {
    insert = insert,
    get    = get,
    remove = remove,
  }
end

--return library
return hashset
