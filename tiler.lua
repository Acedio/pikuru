#!/usr/bin/lua

local v2 = require("v2")

local Grid = {}

-- 0-based
function Grid:new(o)
  o = o or {
    width = 0,
    height = 0,
    array = {},
  }
  setmetatable(o, self)
  self.__index = self
  return o
end

function Grid:newWithDimensions(w, h)
  return self:new{
    width = w,
    height = h,
    -- Still 1-indexed.
    array = {},
  }
end

function Grid:get(x, y)
  assert(x >= 0 and y >= 0 and x < self.width and y < self.height)
  return self.array[y*self.width + x + 1]
end

function Grid:set(x, y, value)
  assert(x >= 0 and y >= 0 and x < self.width and y < self.height)
  self.array[y*self.width + x + 1] = value
end

function Grid:fill(value)
  for x=0,self.width-1 do
    for y=0,self.height-1 do
      self:set(x,y,value)
    end
  end
end

-- Writes `grid` (a Grid of grayscale values) as a PGM to file.
function write_pgm(grid, max_value, file)
  file:write(string.format("P2\n%d %d\n%d\n", grid.width, grid.height, max_value))
  for y=0,grid.height-1 do
    for x=0,grid.width-1 do
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

-- Returns the origin-relative pixel that point (x, y, z) should be located at.
-- 
-- The origin is this point:
--
--           x-axis
--          /
--         /\-
-- origin /\/\-
--        \/\/.
--         \/.
--          \
--           y-axis
--
-- The returned point is in (x,y) screen coordinates.
function iso_point(x, y, z)
  return v2.v2(x * 16 + y * 16, y * 8 - x * 8 - z * 8)
end

local width_tiles = 8
local height_tiles = 8
-- z values of each coordinate. The number of "tiles" is actually one less than
-- the width and height here.
local grid = Grid:new{
  width = 8,
  height = 8,
  array = {
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 1, 1, 1, 1, 1, 1, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 1, 1, 1, 1, 1, 1, 0,
    0, 1, 1, 2, 2, 1, 1, 0,
    0, 1, 1, 2, 2, 1, 1, 0,
    0, 1, 1, 1, 1, 1, 1, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
  },
}
local tile_size = 16
local image_width = width_tiles * 16 + height_tiles * 16
local image_height = width_tiles * 8 + height_tiles * 8 + 2
local origin = v2.v2(0,image_height/2-1)
local img = Grid:newWithDimensions(image_width, image_height)
img:fill(0)
for y=0,height_tiles-1 do
  for x=0,width_tiles-1 do
    if x+1 <= width_tiles - 1 then
      draw_line(img, 255, origin + iso_point(x, y, grid:get(x,y)), origin + iso_point(x+1, y, grid:get(x+1,y)))
    end
    if y+1 <= height_tiles - 1 then
      draw_line(img, 255, origin + iso_point(x, y, grid:get(x,y)), origin + iso_point(x, y+1, grid:get(x,y+1)))
    end
  end
end
write_pgm(img, 255, io.stdout)
