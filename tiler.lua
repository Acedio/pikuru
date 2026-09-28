#!/usr/bin/lua

local v2 = require("v2")

local Grid = {}

function Grid:new(w, h)
  local o = {
    width = w,
    height = h,
    array = {},
  }
  setmetatable(o, self)
  self.__index = self
  return o
end

function Grid:get(x, y)
  assert(x > 0 and y > 0 and x <= self.width and y <= self.height)
  return self.array[y*self.width + x]
end

function Grid:set(x, y, value)
  assert(x > 0 and y > 0 and x <= self.width and y <= self.height)
  self.array[y*self.width + x] = value
end

function Grid:fill(value)
  for x=1,self.width do
    for y=1,self.height do
      self:set(x,y,value)
    end
  end
end

-- Writes `grid` (a Grid of grayscale values) as a PGM to file.
function write_pgm(grid, max_value, file)
  file:write(string.format("P2\n%d %d\n%d\n", grid.width, grid.height, max_value))
  for y=1,grid.height do
    for x=1,grid.width do
      file:write(string.format("%d ", grid:get(x,y)))
    end
    file:write("\n")
  end
end

-- For when W > H.
function draw_line_shallow(grid, value, p1, p2)
  local dx = p2.x - p1.x
  local dy = p2.y - p1.y
  local y = p1.y
  local yi = 1
  if dy < 0 then
    dy = -dy
    yi = -1
  end
  local D = 2 * dy - dx
  for x=p1.x,p2.x do
    grid:set(x,y,value)
    if D > 0 then
      y = y + yi
      D = D + (2 * (dy - dx))
    else
      D = D + 2 * dy
    end
  end
end

-- For when H > W.
function draw_line_steep(grid, value, p1, p2)
  local dx = p2.x - p1.x
  local dy = p2.y - p1.y
  local x = p1.x
  local xi = 1
  if dx < 0 then
    dx = -dx
    xi = -1
  end
  local D = 2 * dx - dy
  for y=p1.y,p2.y do
    grid:set(x,y,value)
    if D > 0 then
      x = x + xi
      D = D + (2 * (dx - dy))
    else
      D = D + 2 * dx
    end
  end
end

function draw_line(grid, value, p1, p2)
  if math.abs(p1.y - p2.y) < math.abs(p1.x - p2.x) then
    if p1.x < p2.x then
      draw_line_shallow(grid, value, p1, p2)
    else
      draw_line_shallow(grid, value, p2, p1)
    end
  else
    if p1.y < p2.y then
      draw_line_steep(grid, value, p1, p2)
    else
      draw_line_steep(grid, value, p2, p1)
    end
  end
end

local g = Grid:new(100,100)
g:fill(0)
for x=0,4 do
  for y=0,4 do
    if x == 0 or x == 4 or y == 0 or y == 4 then
      draw_line(g, 255, v2.v2(50,50), v2.v2(x*24+1,y*24+1))
    end
  end
end
write_pgm(g, 255, io.stdout)
