-----------------------------------------------------
--name       : lib/stack.lua
--description: stack - simple and efficient stack manipulation
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : http://oc.cil.li/index.php?/topic/
-----------------------------------------------------

local stack = {}
local methods = {}
local meta = {
  __index = methods,
  __len = function(t)
    return t.n
  end,
}

--stack.new([s]) -> s
--creates a new stack object
--The argument can be used to convert an existing table to a stack object.
--returns a stack object
function stack.new(obj)
  --prepare optional argument obj
  checkArg(1, obj, "table", "nil")
  obj = obj or {}
  --allow size override for stacks containing nil
  obj.n = obj.n or #obj
  --add methods and support for # operator via metatable
  return setmetatable(obj, meta)
end

--s:push(value) -> value
--pushes the value to the stack
--returns the value
function methods:push(value)
  self.n = self.n + 1
  self[self.n] = value
  return value
end

--s:pop() -> value
--pops a value from the stack and returns it
function methods:pop()
  assert(self.n > 0, "Stack is already empty!")
  --remember old value
  local value = self[self.n]
  --remove value from stack and return
  self[self.n] = nil
  self.n = self.n - 1
  return value
end
--s:top() -> value
--returns top value from stack
function methods:top()
  return self[self.n]
end
--s:set(new) -> old
--replaces the top value from the stack
--returns the old value
function methods:set(new)
  assert(self.n > 0, "Stack is empty!")
  local old = self[self.n]
  self[self.n] = new
  return old
end

--s:isEmpty() -> boolean
--returns true if the stack is empty
function methods:isEmpty()
  return (self.n == 0)
end

return stack
