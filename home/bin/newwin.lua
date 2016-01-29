-----------------------------------------------------
--name       : home/bin/newwin.lua
--description: runs shell within the given window
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : http://oc.cil.li/index.php?/topic/
-----------------------------------------------------

local component = require("component")
local term = require("term")
local shell = require("shell")

local x, y, w, h, gpu = ...
x = tonumber(x)
y = tonumber(y)
w = tonumber(w)
h = tonumber(h)


term.setWindow(term.newWindow(x, y, w, h, gpu))
term:focus()

shell.execute("sh")
