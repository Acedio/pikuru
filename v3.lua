V3 = {}

function V3:new(o)
  local o = o or {}
  setmetatable(o, self)
  self.__index = self
  return o
end

function V3.__eq(a,b)
  return a.x == b.x and a.y == b.y and a.z == b.z
end

function V3.__add(a,b)
  return V3.v3(a.x+b.x, a.y+b.y, a.z+b.z)
end

function V3.__sub(a,b)
  return V3.v3(a.x-b.x, a.y-b.y, a.z-b.z)
end

function V3.__mul(a,b)
  if type(b) == "number" then
    return V3.v3(a.x * b, a.y * b, a.z * b)
  end
  if type(a) == "number" then
    return V3.v3(b.x * a, b.y * a, b.z * a)
  end
  assert(false, "unsupported multiplication: " .. type(a) .. "*" .. type(b))
end

function V3.__div(a,b)
  assert(type(b) == "number")
  return V3.v3(a.x / b, a.y / b, a.z / b)
end

function V3.__idiv(a,b)
  assert(type(b) == "number")
  return V3.v3(a.x // b, a.y // b, a.z // b)
end

function V3:copy()
  return V3.v3(self.x, self.y, self.z)
end

function V3:len()
  return sqrt(self.x * self.x + self.y * self.y + self.z * self.z)
end

function V3:normal()
  local l = self:len()
  if l < 0.001 then
    return V3.v3(0,0,0)
  end
  return self / l
end

-- Convenience constructor.
function V3.v3(x, y, z)
  return V3:new{x=x,y=y,z=z}
end

return V3
