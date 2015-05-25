
--this just contains a wrapper for executing cbrowse with some values

local shell = require("shell")

local cbrowse = {}

function cbrowse.view(...)
  return shell.execute("cbrowse --raw --", nil, ...)
end

function cbrowse.viewEnv(env, ...)
  return shell.execute("cbrowse --raw --env --", nil, env, ...)
end

return cbrowse
