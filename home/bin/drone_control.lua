-----------------------------------------------------
--name       : bin/drone_control.lua
--description: a remote control for drones (controlling program)
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------

local keyboard = require("keyboard")
local component = require("component")
local computer = require("computer")
local shell = require("shell")
local event = require("event")
local sides = require("sides")

local INIT_PORT = 1

--TODO: goto
--TODO: feedback

--define helper functions
local function encrypt(msg, key)
  --appending checksum and encrypting
  key = key or ""
  
  local chars = {}
  local sum = 0
  for i = 1, #msg + 1 do
    local char = i <= #msg and msg:byte(i) or sum
    local keyChar = (key == "" and 0) or key:byte((i - 1) % #key + 1)
    sum = (sum - char) % 256
    chars[i] = string.char((char + keyChar) % 256)
  end
  return table.concat(chars)
end
local function decrypt(msg, key)
  --decrypting and checking checksum
  key = key or ""
  local chars = {}
  local sum = 0
  for i = 1, #msg do
    local keyChar = (key == "" and 0) or key:byte((i - 1) % #key + 1)
    local char = (msg:byte(i) - keyChar) % 256
    sum = (sum + char) % 256
    chars[i] = string.char(char)
  end
  if sum ~= 0 then
    --checksum failed
    return nil
  end
  return table.concat(chars, "", 1, #msg - 1)
end
--encoding and decoding of drone protocol
local function encode(drone_id, key, msg)
  return "drone" .. drone_id .. " " .. encrypt(msg, key)
end
local function decode(drone_id, key, msg)
  local id, msg = msg:match("^drone(%S+) (.-)$")
  if id == drone_id then
    return decrypt(msg, key)
  end
end

--extract id and key from parameters
local parameters, options = shell.parse(...)
local drone_id, drone_key = parameters[1], parameters[2]

--get modem
local modem = component.modem
modem.open(INIT_PORT)

--find drone
local drone_address, drone_port
modem.broadcast(INIT_PORT, encode(drone_id, drone_key, "id('"..modem.address.."',"..INIT_PORT..")"))

local timeout = computer.uptime() + 5
print("Connecting...")

while true do
  local timeLeft = timeout - computer.uptime()
  if timeLeft <= 0 then
    print("Timeout. Check connection!")
    return
  end
  local event, receiverAddress, senderAddress, port, dist, msg = event.pull(timeLeft, "modem_message", nil, nil, INIT_PORT)
  if msg then
    msg = decode(drone_id, drone_key, msg)
    if msg then
      drone_port = tonumber(msg:match("^port%((.-)%)$"))
      if drone_port then
        drone_address = senderAddress
        break
      end
    end
  end
end
modem.open(drone_port)

--resizing screen to allow seeing drone
local gpu = component.gpu
local oldResolutionX, oldResolutionY = gpu.getResolution()
gpu.setResolution(23, 5)
print("Connected.")

--run main loop
--  on key event -> send encrypted command
local function newAction(msg)
  return function()
    modem.send(drone_address, drone_port, encode(drone_id, drone_key, msg))
  end
end
local actions = {
  --movement
  [keyboard.keys.w] = newAction("move( 1, 0, 0)"),
  [keyboard.keys.s] = newAction("move(-1, 0, 0)"),
  [keyboard.keys.d] = newAction("move( 0, 0, 1)"),
  [keyboard.keys.a] = newAction("move( 0, 0,-1)"),
  [keyboard.keys.r] = newAction("move( 0, 1, 0)"),
  [keyboard.keys.f] = newAction("move( 0,-1, 0)"),
  --place / break
  [keyboard.keys.q] = newAction("return swing("..sides.down..")"),
  [keyboard.keys.e] = newAction("return place("..sides.down..")"),
  --leash
  [keyboard.keys.t] = newAction("return leash("..sides.down..")"),
  [keyboard.keys.g] = newAction("return unleash()"),
  --inventory
  [keyboard.keys.tab] = newAction("return count()"),
  [keyboard.keys.space] = newAction("return space()"),
}
--selecting slots
for i = 1, 8 do
  actions[keyboard.keys[tostring(i)]] = newAction("return select("..tostring(i)..")")
end

local actionEnv = {
  status = print,
}


local cooldown = computer.uptime()
while true do
  local event, source, char, key, dist, msg = event.pull()
  --event, receiverAddress, senderAddress, port, dist, msg
  if event == "interrupted" then
    break
  elseif event == "key_down" then
    local action = actions[key]
    if action then
      if computer.uptime() - cooldown > 0 then
        action()
        if not keyboard.isShiftDown() then
          cooldown = computer.uptime() + 0.2
        end
      end
    end
  elseif event == "key_up" then
    cooldown = computer.uptime()
  elseif event == "modem_message" then
    local receiverAddress, senderAddress, port = source, char, key
    --on message: decrypt and verify, execute
    if port == drone_port then
      msg = decode(drone_id, drone_key, msg)
      if msg then
        local func, err = load(msg, nil, nil, setmetatable({},{__index=actionEnv}))
        xpcall(func, debug.traceback)
      end
    end
  end
end

--resizing screen to original size
gpu.setResolution(oldResolutionX, oldResolutionY)
