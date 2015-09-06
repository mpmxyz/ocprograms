-----------------------------------------------------
--name       : bin/gpid.lua
--description: starting, debugging and stopping PID controllers
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : http://oc.cil.li/index.php?/topic/558-pid-pid-controllers-for-your-reactor-library-included/
-----------------------------------------------------
--TODO: 
--
--<<< [reactor.pid] |  turbine.pid  >>>  [Add New]
----Settings--
--Status           ID
-- Enabled          reactor.pid
--Target           Current          Error
-- +12345678.12  -  +12345678.12  =  +12345678.12
--Proportional     Integral         Derivative
-- +12345678.12     +12345678.12     +12345678.12
--Minimum          Maxmimum         Default
-- +12345678.12     +12345678.12     +12345678.12
----Calculation--               |    |    |           <- "|" gibt den ursprünglichen Wertebereich an
--offset +12345678.12    -[ <<<<<<<<<<          ]+
--P      +12345678.12    -[ >>>                 ]+
--D      +12345678.12    -[   >>>>>>>>>>>       ]+
--sum    +12345678.12     /-----/         \-----\
--output +12345678.12     [                   X ]
--


local qui = require("mpm.qui")
local component = require("component")

local ui = [[
*l* *selection********************* *r*  [*new***]
--Settings--
Status           ID
 *toggle**        *changeid***********************
Target           Current          Error
 *target*****  -  *current****  =  *error******
Proportional     Integral         Derivative
 *p**********     *i**********     *d**********
Minimum          Maxmimum         Default
 *min********     *max********     *default****
--Calculation--         *imageRange**************
offset *valOffset**    -*imageOffset*************+
P      *valP*******    -*imageP******************+
D      *valD*******    -*imageD******************+
sum    *valSum*****     *imageTransition*********
output *valOutput**     *imageOutput*************
]]

local uiObject = qui.load(ui, {
  h = "%*+(%a*)%*+",
  v = "%#+(%a*)%#+",
}, {
  new = {
    text = "Add New",
  },
  test = {
    text = "123456\nabcdef\r654321\r\njklmno",
  },
  ve = {
    text = "^\n|\n|\nV",
  },
})
uiObject:update()
uiObject:draw(component.gpu)
