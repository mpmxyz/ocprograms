-----------------------------------------------------
--name       : lib/parser/automaton.lua
--description: automaton.merge allows converting a non deterministic finite automaton to a deterministic one
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------

local cache = require("mpm.cache").wrap

local automaton = {}

--registry for children
local children = setmetatable({},{__mode="k"})

--getter for list of children
function automaton.children(stateSet)
  return children[stateSet]
end

--cache: this, next -> merged
--merges two automaton states to run them in parallel
--This function does NOT actively enforce the 'equal set' == 'same object'
--policy of sets.manager to avoid time and memory overhead.
--(It also makes it possible to collect unused sets.)
--Here is a reason why it still works without exploding memory usage:
--Tables that were filled with the same keys in the same order have the same order of iteration.
--(most of the time even independent from assignment order;
--but that has problems with number keys and nil assignments)
--This order helps reusing (first, second) pairs even if there is no explicit 'equal set' == 'equal object' code.
--If the order changed between set creations or even 'pairs' calls
--you'd have n! (first, second) pairs for every set of states with size n.
--Their 'next state' would also be created randomly.
--That would cause an exponential growth with a factorial base! -> (parallelStates!) ^ nSteps
automaton.merge = cache(function(first)
  return cache(function(second)
    --only merge if both states exist and are not equal
    if first == second then
      return first
    elseif type(first) == "table" and type(second) == "table" then
      --don't create recursions if first already is a merged state
      local oldChildren1 = children[first]
      local oldChildren2 = children[second]
      
      local newChildren = {}
      --added some redundant code to avoid throwing around table sets with a single value only
      if oldChildren1 then
        if oldChildren2 then
          local somethingMissingIn1 = false
          local somethingMissingIn2 = false
          --no primitive
          for k, v in pairs(oldChildren1) do
            newChildren[k] = true
            if not oldChildren2[k] then
              somethingMissingIn2 = true
            end
          end
          for k in pairs(oldChildren2) do
            if not newChildren[k] then
              newChildren[k] = true
              somethingMissingIn1 = true
            end
          end
          if not somethingMissingIn1 then
            return first
          elseif not somethingMissingIn2 then
            return second
          end
        else
          --second is primitive
          if oldChildren1[second] then
            --return early if second is already within first
            return first
          else
            newChildren[second] = true
          end
          for k, v in pairs(oldChildren1) do
            newChildren[k] = true
          end
        end
      else
        if oldChildren2 then
          --first is primitive
          if oldChildren2[first] then
            --return early if first is already within second
            return second
          else
            newChildren[first] = true
          end
          for k, v in pairs(oldChildren2) do
            newChildren[k] = true
          end
        else
          --2 non equal primitives
          newChildren[first]  = true
          newChildren[second] = true
        end
      end
      
      local mergedTable = cache(function(key)
        local output = false
        --calculate merged output, no recursion possible because there is no merged state in 'newChildren'
        for k in pairs(newChildren) do
          output = automaton.merge(output, k[key])
        end
        return output
      end, "k", "automaton.merged state")
      children[mergedTable] = newChildren
      
--[[
      getmetatable(mergedTable).__tostring = function()
        return tostring(first) .. "|" .. tostring(second)
      end
  ]]
      return mergedTable
    else
      --either false + table or false + true
      return first or second
    end
  end, "k", "automaton.merge.second")
end, "k", "automaton.merge.first")

return automaton
