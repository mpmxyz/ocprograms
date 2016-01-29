-----------------------------------------------------
--name       : home/bin/split.lua
--description: creates a split screen (more a hack)
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : http://oc.cil.li/index.php?/topic/
-----------------------------------------------------

local computer = require("computer")
local shell = require("shell")
local component = require("component")

--remember original functions
local coroutine_yield = coroutine.yield
local coroutine_resume = coroutine.resume
local computer_pullSignal = computer.pullSignal

function computer.pullSignal(timeout)
  checkArg(1, timeout, "number", "nil")
  return coroutine_yield(timeout or math.huge)
end
function coroutine.yield(...)
  return coroutine_yield("", ...)
end
function coroutine.resume(co, ...)
  local returned = table.pack(coroutine_resume(co, ...))
  while returned[1] and returned[2] ~= "" and coroutine.status(co) == "suspended" do
    --waiting for event
    returned = table.pack(coroutine_resume(co, computer.pullSignal(returned[2])))
  end
  --else: normal operation
  if returned[1] then
    if coroutine.status(co) == "dead" then
      --return
      return table.unpack(returned, 1, returned.n)
    else
      --yield
      return true, table.unpack(returned, 3, returned.n)
    end
  else
    --error
    return false, returned[2]
  end
end

local function newThread(x, y, w, h, gpu)
  return coroutine.create(function()
    local ok, err = (shell.execute("newwin", nil, x, y, w, h, gpu))
    if ok then
      io.stderr:write(err)
    else
      io.stderr:write("stopped")
    end
    error("stopped", 0)
  end)
end


local threads = {}
local timeouts = {}

local screenAddress = component.list("screen", true)
for address in component.list("gpu", true) do
  local gpu = component.proxy(address)
  gpu.bind(assert(screenAddress(), "Not enough screens!"), true)
  local width, height = gpu.getResolution()
  table.insert(threads, newThread(1, 1, math.floor(width / 2), height, gpu))
  table.insert(threads, newThread(math.floor(width / 2) + 1, 1, math.ceil(width / 2), height, gpu))
end

local function runThreads(currentTime, ...)
  local survivingThreads = {}
  local survivingTimeouts = {}
  for i = 1, #threads do
    local thread = threads[i]
    local alive, timeout = true, timeouts[i]
    if (...) or timeout < currentTime then
      alive, timeout = coroutine_resume(thread, ...)
      if alive then
        if type(timeout) == "number" then
          timeout = currentTime + timeout
        else
          --unexpected yield
          alive = false
        end
      else
        
      end
    end
    if alive then
      survivingThreads[#survivingThreads + 1] = thread
      survivingTimeouts[#survivingTimeouts + 1] = timeout
    end
  end
  threads = survivingThreads
  timeouts = survivingTimeouts
end

local function getMinTimeout()
  local timeout = math.huge
  for i = 1, #timeouts do
    timeout = math.min(timeout, timeouts[i])
  end
  return timeout
end


while threads[1] do
  local currentTime = computer.uptime()
  local waitingTime = getMinTimeout() - currentTime
  runThreads(currentTime, computer_pullSignal(waitingTime))
end

--term.write = term_write
--coroutine.create = coroutine_create
--restore original functions
coroutine.yield = coroutine_yield
coroutine.resume = coroutine_resume
computer.pullSignal = computer_pullSignal
