-----------------------------------------------------
--name       : bin/purgelib.lua
--description: removes entries from the package.loaded table; use with caution
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : http://oc.cil.li/index.php?/topic/558-pid-pid-controllers-for-your-reactor-library-included/
-----------------------------------------------------

local libs = table.pack(...)
if libs.n == 0 then
  print("Usage: purgelib libnames...")
else
  for _, lib in ipairs(libs) do
    package.loaded[lib] = nil
  end
end
