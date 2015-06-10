-----------------------------------------------------
--name       : lib/cbrowse.lua
--description: allows executing cbrowse to debug programs
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : http://oc.cil.li/index.php?/topic/576-cbrowse-inspecting-lua-components-and-other-objects/
-----------------------------------------------------

--This just contains a wrapper for executing cbrowse with some values.
local shell = require("shell")

local cbrowse = {}

--executes cbrowse with the given values
--All values after the first nil value are ignored. (limitation by sh.lua)
function cbrowse.view(...)
  return shell.execute("cbrowse --raw --", nil, ...)
end

--executes cbrowse with a global environment and the given values
--All values after the first nil value are ignored. (limitation by sh.lua)
function cbrowse.viewEnv(env, ...)
  return shell.execute("cbrowse --raw --env --", nil, env, ...)
end

return cbrowse
