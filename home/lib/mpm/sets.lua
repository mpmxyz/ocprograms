-----------------------------------------------------
--name       : lib/mpm/sets.lua
--description: helper functions to work with table sets
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------


--library table
local sets = {}

--takes all values from "source" and copies them to the target set
--If a key within "source" is also within "ignoredKeys", its value isn't added to the target set.
--If "ignoredKeys" isn't a table, it is used as a set only containing its value.
function sets.mergeInsert(target, source, ignoredKeys)
  if type(ignoredKeys) == "table" then
    for k,v in pairs(source) do
      if ignoredKeys[k] == nil then
        --add to set
        target[v] = v
      end
    end
  else
    for k,v in pairs(source) do
      --good news: k can never be nil; ignoredKeys == nil therefore disables filtering
      if k ~= ignoredKeys then
        --add to set
        target[v] = v
      end
    end
  end
  return target
end
--creates a new set with all values from the given list
--(equals a copying operation when the argument is a set already)
function sets.new(setOrList, ignoredKeys)
  return sets.mergeInsert({}, setOrList, ignoredKeys)
end
--merges two sets/lists and returns a new one
function sets.merge(a, b, ignoredKeys)
  return sets.mergeInsert(sets.new(a, ignoredKeys), b, ignoredKeys)
end

--returns true if the set "a" and the set/list "b" contain the same elements
function sets.equals(a, b)
  if rawequal(a, b) then
    --raw equality shortcut
    return true
  end
  --It's quite simple:
  --Both "a" and "b" have to have the same length to be equal.
  --That's why they are iterated in parallel.
  --Whenever one finishes earlier than the other, they can't be equal.
  --While iterating it is checked that every value within "b" is also within "a".
  --If that is the case there is no need to check it in the opposite direction because both sets have an equal number of elements and those elements can't be duplicated.
  --If "b" is a list it is required to have no duplicate values.
  local ka     = next(a)
  local kb, vb = next(b)
  while ka and kb do
    if a[vb] ~= nil then
      ka     = next(a, ka)
      kb, vb = next(b, kb)
    else
      --"a" is missing something that "b" has.
      return false
    end
  end
  if ka~=kb then
    --different number of elements
    return false
  end
  --equal contents
  return true
end

return sets
