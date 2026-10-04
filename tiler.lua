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

function Grid:subgrid(x, y, w, h)
  assert(x >= 0)
  assert(w >= 0)
  assert(x + w <= self.width)
  assert(y >= 0)
  assert(h >= 0)
  assert(y + h <= self.height)
  local sub = Grid:new{
    width = w,
    height = h,
    array = {},
  }
  for y=y,y+h-1 do
    for x=x,x+w-1 do
      table.insert(sub.array, self:get(x, y))
    end
  end
  return sub
end

function Grid:hash()
  assert(self.width * self.height <= 256)
  -- Assumes that everything is >= 0 and < 256.
  return string.char(table.unpack(self.array))
end

-- Paste grids one after the other. Their widths must match.
function Grid.cat(grids)
  if #grids <= 0 then
    return Grid:newWithDimensions(0,0)
  end
  local width = grids[1].width
  local height = 0
  local array = {}
  for i=1,#grids do
    assert(width == grids[i].width)
    table.move(grids[i].array, 1, #grids[i].array, #array + 1, array)
    height = height + grids[i].height
  end
  return Grid:new{
    width = width,
    height = height,
    array = array,
  }
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

-- Returns a table of "tilemap" (a grid of tile indices) and "tiles" (the tiles
-- themselves).
function tilify(grid, tile_size)
  assert(grid.width % tile_size == 0, string.format("Width (%d) must be divisible by tile_size (%d)!", grid.width, tile_size))
  assert(grid.height % tile_size == 0, string.format("Height (%d) must be divisible by tile_size (%d)!", grid.height, tile_size))
  local tiles = {}
  local tile_hashes = {}
  local tilemap = Grid:newWithDimensions(grid.width//tile_size, grid.height//tile_size)
  for y=0,grid.height-tile_size,tile_size do
    for x=0,grid.width-tile_size,tile_size do
      local tile = grid:subgrid(x,y,tile_size,tile_size)
      local hash = tile:hash()
      local index = tile_hashes[hash]
      if not index then
        table.insert(tiles, tile)
        index = #tiles
        tile_hashes[hash] = index
      end
      tilemap:set(x//tile_size, y//tile_size, index)
    end
  end
  return {
    tiles = tiles,
    tilemap = tilemap,
  }
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
local image_height = width_tiles * 8 + height_tiles * 8 + 16
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
-- write_pgm(img, 255, io.stdout)

local result = tilify(img, 16)
write_pgm(Grid.cat(result.tiles), 255, io.stdout)
