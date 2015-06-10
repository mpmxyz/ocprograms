-----------------------------------------------------
--name       : lib/mpm/component_filter.lua
--description: intercepts component access to enable modifications
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------

--[[
  "component_filter" allows you to apply filters to component methods.
  When you 'apply' a list of filters the component.invoke function is replaced. *TODO: UPDATE DESCRIPTION*
  When executed this function searches the given list of filters by address and type.
  If it finds a filter, it is executed. Else it executes the original component.invoke.
  A filter list is a table with keys representing a component address or type and values representing filter functions.
  (The address is prioritized when searching.)
  There also is the special key "default" to be used when there is no other filter.
  A filter is just a function receiving the original component.invoke and all other parameters.
  It should return values similar to those of an unfiltered call since they are returned to the calling code.
  Else it might be surprised to get colors from component.filesystem.list().
  The following example shows a filesystem filter adding a computer.beep on every filesystem access:
  
  local component_filter = require 'component_filter'
  local shell = require 'shell'
  local component = require 'component'
  
  local filters = {
    filesystem = function(invoke, address, method, ...)
      --make some noise
      component.computer.beep(2000,0.05)
      --but still do what it was supposed to do
      return invoke(address, method, ...)
    end,
  }
  
  local function monitoredShell()
    shell.execute("sh")
  end
  
  component_filter.call(filters,monitoredShell)
]]
local component_filter = {}
--a table only containing stack states
local stack = {}
--a table containing every state
local allStates = {}

local component = require("component")
local topInvoke = component.invoke
--this is the new component.invoke, TODO: how to order multiple component wrappers?
function component.invoke(address, method, ...)
  return topInvoke(address, method, ...)
end


--creates an invoke function for the given state
local function newInvoke(state)
  return function(address, method, ...)
    --get filter list
    local filters = state.filters
    --filters[address] -> filter, filters[type] -> filter, filters.default -> filter
    local filter = filters[address] or filters[component.type(address)] or filters.default
    if filter then
      --filter(originalInvoke, address, method, ...) -> return values
      return filter(state.oldInvoke, address, method, ...)
    end
    --default: just call original function
    return state.oldInvoke(address, method, ...)
  end
end
--creates a new state
local function newState(filters, onStack, oldInvoke)
  --create a table
  local state = {
    filters = filters,
    onStack = onStack,
    oldInvoke = oldInvoke,
  }
  --add a function
  state.invoke = newInvoke(state)
  --and there it is...
  return state
end

--removes an entry in the complete list,
--also takes care of topInvoke changes if they are necessary
local function removeIndex(i)
  local state = allStates[i]
  local nextState = allStates[i+1]
  if nextState then
    --connect next state with the previous state
    nextState.oldInvoke = state.oldInvoke
  else
    --removed the top most state: update topInvoke
    topInvoke = state.oldInvoke
  end
  table.remove(allStates, i)
end
--finds a matching state and removes it
local function remove(filters, onStack)
  --from top to bottom...
  for i = #allStates,1,-1 do
    --find a state...
    local state = allStates[i]
    --which is having the same filter...
    if state.filters == filters then
      --and belongs to the specified part... (stack / non-stack)
      if state.onStack == onStack then
        --and remove it.
        return removeIndex(i)
      end
    end
  end
end
local function pop()
  --removes the state from the top of the stack
  local state = table.remove(stack)
  assert(state ~= nil, "Error: 'restore' without matching 'apply'.")
  --search in complete list...
  for i = #allStates,1,-1 do
    if allStates[i] == state then
      --and eliminate.
      return removeIndex(i)
    end
  end
end

--adds a state on top of the stack
local function push(state)
  table.insert(stack, state)
end
--creates a new state and remembers it, also pushes it on the stack if necessary
--Since the new filters are put on top of the other filters
--there will be a topInvoke change.

local function add(filters, onStack)
  local state = newState(filters, onStack, topInvoke)
  --remember state
  table.insert(allStates,state)
  if onStack then
    push(state)
  end
  --modify topInvoke
  topInvoke = state.invoke
end

--component_filter.apply(filters, noStack)
--from now on applies the given list of filters to every component.invoke call
--It is also filtering every filter created before.
--(adding a layer to the stack unless 'noStack' is true)
function component_filter.apply(filters, noStack)
  assert(type(filters) == "table", "Invalid Filter Type! (Table required.)")
  add(filters, not noStack)
end
--component_filter.restore()
--removes the top layer of the stack
function component_filter.restore()
  pop()
end
--component_filter.remove()
--removes the given filter list
--(removing the topmost non-stack filter list equal to the given one)
function component_filter.remove(filters)
  remove(filters, false)
end


--This function is used to store the return values "..." while doing some cleanup / error logic.
local function removeAndReturn(filters, ok, ...)
  remove(filters, false)
  if ok then
    return ...
  else
    return error((...),0)
  end
end

--component_filter.call(filters,func,...)
--a useful convenience function:
--1st: applies the filter
--2nd: calls the function
--3rd: reverts the first step (Even if step two throws an error!)
--4th: returns anything the function returned (errors are forwarded without change)
function component_filter.call(filters, ...)
  assert(type(filters) == "table", "Invalid Filter Type! (Table required.)")
  add(filters, false)
  return removeAndReturn(filters, pcall(...))
end

return component_filter
