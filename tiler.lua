#!/usr/bin/lua

local v2 = require("v2")

local name_prefix = arg[1]

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
      -- `tiles` is 1-indexed, but the tilemap is 0-indexed.
      tilemap:set(x//tile_size, y//tile_size, index-1)
    end
  end
  return {
    tiles = tiles,
    tilemap = tilemap,
  }
end

function sixteen_to_eight(tiles, tilemap)
  -- 16x16 tiles on the SNES are identified by the top left 8x8 tile. The
  -- remaining tiles are x+1, x+16, and x+17.

  -- First, pad our tiles so the count is divisible by 16, which makes our loop
  -- easier below.
  if #tiles % 16 ~= 0 then
    local to_add = 16 - (#tiles % 16)
    for i=1,to_add do
      local blank_tile = Grid:newWithDimensions(16,16)
      blank_tile:fill(0)
      table.insert(tiles, blank_tile)
    end
  end

  local eight_tiles = {}
  for y=0,#tiles // 8 - 1 do
    for x=0,7 do  -- each row is 8 16x16 tiles wide
      -- Tiles is a 1-indexed array.
      local tile_i = y * 8 + x + 1
      table.insert(eight_tiles, tiles[tile_i]:subgrid(0,0,8,8))
      table.insert(eight_tiles, tiles[tile_i]:subgrid(8,0,8,8))
    end
    for x=0,7 do  -- each row is 8 16x16 tiles wide
      -- Tiles is a 1-indexed array.
      local tile_i = y * 8 + x + 1
      table.insert(eight_tiles, tiles[tile_i]:subgrid(0,8,8,8))
      table.insert(eight_tiles, tiles[tile_i]:subgrid(8,8,8,8))
    end
  end

  -- The tilemap is still the same resolution, but we need to adjust the tile
  -- indices to map to the newly rearranged eight_tiles.
  local eight_tilemap = Grid:newWithDimensions(tilemap.width, tilemap.height)
  for y=0,tilemap.height-1 do
    for x=0,tilemap.width-1 do
      local index = tilemap:get(x,y)
      local x_part = index & 7
      local y_part = index >> 3
      local eight_index = x_part * 2 + ((y_part * 2) << 4)
      eight_tilemap:set(x,y,eight_index)
    end
  end
  return {
    tiles = eight_tiles,
    tilemap = eight_tilemap,
  }
end

function row_as_byte(tile, row, mask)
  local byte = 0
  for x=0,7 do
    byte = byte << 1
    if tile:get(x, row) & mask ~= 0 then
      byte = byte | 1
    end
  end
  return byte
end

function write_tiles(tiles, file)
  for i=1,#tiles do
    assert(tiles[i].width == 8)
    assert(tiles[i].height == 8)
    -- Planes 0 and 1 (1 is empty).
    for y=0,7 do
      local plane_0_byte = row_as_byte(tiles[i], y, 1)
      file:write(string.char(plane_0_byte, 0))
    end
    -- Planes 2 and 3 are empty.
    for y=0,7 do
      file:write(string.char(0, 0))
    end
  end
end

function write_tilemap16(tilemap, file)
  for y=0,tilemap.height-1 do
    for x=0,tilemap.width-1 do
      file:write(string.char(tilemap:get(x,y), 0))
    end
  end
end

function write_palette(file)
  file:write(string.char(0,0,0xFF,0x7F))
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

-- Draws the given heightmap on an isometric grid.
function draw_iso_heightmap(grid)
  local image_width = grid.width * 16 + grid.height * 16
  local image_height = grid.width * 8 + grid.height * 8 + 16
  local origin = v2.v2(0,image_height/2-1)
  local img = Grid:newWithDimensions(image_width, image_height)
  img:fill(0)
  for y=0,grid.height-1 do
    for x=0,grid.width-1 do
      if x+1 <= grid.width - 1 then
        draw_line(img, 255, origin + iso_point(x, y, grid:get(x,y)), origin + iso_point(x+1, y, grid:get(x+1,y)))
      end
      if y+1 <= grid.height - 1 then
        draw_line(img, 255, origin + iso_point(x, y, grid:get(x,y)), origin + iso_point(x, y+1, grid:get(x,y+1)))
      end
    end
  end

  return img
end

-- z values of each coordinate. The number of "tiles" is actually one less than
-- the width and height here.
local grid = Grid:new{
  width = 32,
  height = 32,
  array = {
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 1, 1, 2, 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 1, 1, 2, 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  },
}
local img = draw_iso_heightmap(grid)

local pgm_file = io.open(name_prefix .. ".pgm", "w")
assert(pgm_file)
write_pgm(img, 255, pgm_file)
pgm_file:close()

local result = tilify(img, 16)
local sixteen_result = sixteen_to_eight(result.tiles, result.tilemap)

local tiles_pgm = io.open(name_prefix .. ".tiles.pgm", "w")
assert(tiles_pgm)
write_pgm(Grid.cat(sixteen_result.tiles), 255, tiles_pgm)
tiles_pgm:close()

local tilemap_file = io.open(name_prefix .. ".map.map.out", "wb")
assert(tilemap_file)
write_tilemap16(sixteen_result.tilemap, tilemap_file)
tilemap_file:close()

local tiles_file = io.open(name_prefix .. ".map.tiles.out", "wb")
assert(tiles_file)
write_tiles(sixteen_result.tiles, tiles_file)
tiles_file:close()

local pal_file = io.open(name_prefix .. ".map.pal.out", "wb")
assert(pal_file)
write_palette(pal_file)
pal_file:close()
