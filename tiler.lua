#!/usr/bin/lua

local v2 = require("v2")
local v3 = require("v3")

local input_csv = arg[1]
local name_prefix = arg[2]

local Grid = {}

local TILEMAP_PALETTE = 3

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

function load_level_csv(csv_text)
  local array = {}
  local start = nil
  local finish = nil
  local cell_i = 0
  for cell in string.gmatch(csv_text, "(%-?%w+)") do
    local num = nil
    -- Special character cells assume the height value to their right.
    if cell == 'S' then
      assert(not start)
      local x = (cell_i & 63) // 2
      local y = (cell_i // 64) // 2
      start = v2.v2(x,y)
      num = array[#array]
    elseif cell == 'F' then
      assert(not finish)
      local x = (cell_i & 63) // 2
      local y = (cell_i // 64) // 2
      finish = v2.v2(x,y)
      num = array[#array]
    else
      num = tonumber(cell)
    end
    assert(num, "is not a number: " .. cell)
    table.insert(array, num)
    cell_i = cell_i + 1
  end
  assert(#array == 64*64)
  assert(start)
  assert(finish)

  return {
    grid = Grid:new{
      width = 64,
      height = 64,
      array = array,
    },
    start = start,
    finish = finish,
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

-- Writes `img` (a Grid of grayscale values) as a PGM to file.
function write_pgm(img, max_value, file)
  file:write(string.format("P2\n%d %d\n%d\n", img.width, img.height, max_value))
  for y=0,img.height-1 do
    for x=0,img.width-1 do
      file:write(string.format("%d ", img:get(x,y)))
    end
    file:write("\n")
  end
end

-- Returns a table of "tilemap" (a grid of tile indices) and "tiles" (the tiles
-- themselves).
function tilify(img, tile_size)
  assert(img.width % tile_size == 0, string.format("Width (%d) must be divisible by tile_size (%d)!", img.width, tile_size))
  assert(img.height % tile_size == 0, string.format("Height (%d) must be divisible by tile_size (%d)!", img.height, tile_size))
  local tiles = {}
  local tile_hashes = {}
  local tilemap = Grid:newWithDimensions(img.width//tile_size, img.height//tile_size)
  for y=0,img.height-tile_size,tile_size do
    for x=0,img.width-tile_size,tile_size do
      local tile = img:subgrid(x,y,tile_size,tile_size)
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
      local plane_1_byte = row_as_byte(tiles[i], y, 2)
      file:write(string.char(plane_0_byte, plane_1_byte))
    end
    -- Planes 2 and 3 are empty.
    for y=0,7 do
      local plane_2_byte = row_as_byte(tiles[i], y, 4)
      local plane_3_byte = row_as_byte(tiles[i], y, 8)
      file:write(string.char(plane_2_byte, plane_3_byte))
    end
  end
end

function word_to_char(word)
  local word_low = word & 0xFF
  local word_high = word >> 8
  return string.char(word_low, word_high)
end

function write_tilemap16(tilemap, file)
  assert(tilemap.width == 64, "Tilemap must be 64 wide.")
  for y=0,tilemap.height-1 do
    for x=0,tilemap.width-1 do
      local tile = tilemap:get(x,y) | (TILEMAP_PALETTE << 10)
      file:write(word_to_char(tile))
    end
  end
end

function eight_to_five_bit_color(r, g, b)
  assert(r >= 0)
  assert(r < 256)
  assert(g >= 0)
  assert(g < 256)
  assert(b >= 0)
  assert(b < 256)
  local r5 = r >> 3
  local g5 = g >> 3
  local b5 = b >> 3
  local word = (b5 << 10) | (g5 << 5) | r5
  return {word & 0xFF, (word & 0xFF00) >> 8}
end

function eight_to_pal_entry(r, g, b)
  local five_bit_bytes = eight_to_five_bit_color(r, g, b)
  return string.char(five_bit_bytes[1], five_bit_bytes[2])
end

function hex_to_pal_entry(hexcode)
  assert(hexcode <= 0xFFFFFF)
  assert(hexcode >= 0)
  local r = hexcode >> 16
  local g = (hexcode >> 8) & 0xFF
  local b = hexcode & 0xFF
  return eight_to_pal_entry(r, g, b)
end

function write_palette(file)
  file:write(hex_to_pal_entry(0x000000))
  file:write(hex_to_pal_entry(0x3A7085))
  file:write(hex_to_pal_entry(0x528DA4))
  file:write(hex_to_pal_entry(0x71ABC2))
  file:write(hex_to_pal_entry(0xA8D1E1))
  file:write(hex_to_pal_entry(0xC8DFE8))
end

function count(tbl)
  local sum = 0
  for i=1,#tbl do
    if tbl[i] then
      sum = sum + 1
    end
  end
  return sum
end

-- Assumes that only two heights are present and that they are 1 away from each
-- other.
function get_tile_byte(x0y0, x1y0, x0y1, x1y1)
  local lowest = math.min(x0y0, x1y0, x0y1, x1y1)
  local highest = math.max(x0y0, x1y0, x0y1, x1y1)
  assert(highest-lowest <= 1)
  assert(lowest >= 0)
  assert(lowest < 16)
  local low_count = count{
    x0y0 == lowest,
    x1y0 == lowest,
    x0y1 == lowest,
    x1y1 == lowest,
  }
  if low_count == 4 then
    -- flat
    return lowest
  end
  local x_increasing = x0y0 < x1y0 or x0y1 < x1y1
  local y_increasing = x0y0 < x0y1 or x1y0 < x1y1
  local prefix = 0
  if x0y0 == x1y0 and x0y1 == x1y1 then
    -- ignore x, but set it to 1 so we don't accidentally write out zero (flat)
    x_increasing = 1
    prefix = 4
  elseif x0y0 == x0y1 and x1y0 == x1y1 then
    -- ignore y, but set it to 1 so we don't accidentally write out zero (flat)
    y_increasing = 1
    prefix = 0
  elseif low_count == 1 then
    -- use max() to combine x and y
    prefix = 12
  elseif low_count == 3 then
    -- use min() to combine x and y
    prefix = 8
  else
    assert(false, "Invalid tile combination?")
  end
  local dir = (x_increasing and 1 or 0) + (y_increasing and 2 or 0)
  return ((prefix + dir) << 4) + lowest
end

function write_heightmap(grid, file)
  for y=0,grid.height-2,2 do
    for x=0,grid.width-2,2 do
      local x0y0 = grid:get(x,y)
      local x1y0 = grid:get(x+1,y)
      local x0y1 = grid:get(x,y+1)
      local x1y1 = grid:get(x+1, y+1)
      if x0y0 < 0 or x1y0 < 0 or x0y1 < 0 or x1y1 < 0 then
        -- Write a "void" tile (which is 0b0100....) if empty.
        file:write(string.char(0x40))
      else
        local tile_byte = get_tile_byte(x0y0, x1y0, x0y1, x1y1)
        file:write(string.char(tile_byte))
      end
    end
  end
end

function write_metadata(level, file)
  file:write(word_to_char(level.start.x))
  file:write(word_to_char(level.start.y))
  file:write(word_to_char(level.finish.x))
  file:write(word_to_char(level.finish.y))
end

-- For when W > H.
function draw_line_shallow(img, value, p1, p2)
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
    img:set(x,y,value)
    if D > 0 then
      y = y + yi
      D = D + (2 * (dy - dx))
    else
      D = D + 2 * dy
    end
  end
end

-- For when H > W.
function draw_line_steep(img, value, p1, p2)
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
    img:set(x,y,value)
    if D > 0 then
      x = x + xi
      D = D + (2 * (dx - dy))
    else
      D = D + 2 * dx
    end
  end
end

function draw_line(img, value, p1, p2)
  if math.abs(p1.y - p2.y) < math.abs(p1.x - p2.x) then
    if p1.x < p2.x then
      draw_line_shallow(img, value, p1, p2)
    else
      draw_line_shallow(img, value, p2, p1)
    end
  else
    if p1.y < p2.y then
      draw_line_steep(img, value, p1, p2)
    else
      draw_line_steep(img, value, p2, p1)
    end
  end
end

--    p2
--   /  ---
-- p1___   --
--      -----p3
--
-- Draw two sub triangles with vertical lines, first the left then the right.
function draw_tri(img, value, p1, p2, p3)
  local p = {p1, p2, p3}
  table.sort(p, function (a, b) return a.x < b.x end)

  for x=p[1].x,p[2].x do
    local w1 = p[3].x - p[1].x
    local y1
    if w1 > 0 then
      y1 = p[1].y + math.floor((p[3].y-p[1].y)*(x-p[1].x)/w1)
    else
      y1 = p[1].y
    end

    local w2 = p[2].x - p[1].x
    local y2
    if w2 > 0 then
      y2 = p[1].y + math.floor((p[2].y-p[1].y)*(x-p[1].x)/w2)
    else
      y2 = p[2].y
    end

    draw_line(img, value, v2.v2(x,y1), v2.v2(x,y2))
  end
  for x=p[2].x,p[3].x do
    local w1 = p[3].x - p[1].x
    local y1
    if w1 > 0 then
      y1 = p[1].y + math.floor((p[3].y-p[1].y)*(x-p[1].x)/w1)
    else
      y1 = p[3].y
    end

    local w2 = p[3].x - p[2].x
    local y2
    if w2 > 0 then
      y2 = p[2].y + math.floor((p[3].y-p[2].y)*(x-p[2].x)/w2)
    else
      y2 = p[2].y
    end

    draw_line(img, value, v2.v2(x,y1), v2.v2(x,y2))
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
function iso_to_screen(x, y, z)
  return v2.v2(x * 16 + y * 16, y * 8 - x * 8 - z * 8)
end

-- Return a v3 representing the corner (cx, cy) of the square at (x, y).
--
-- cx and cy should be 0 or 1. (0,0) is the upper-left corner.
function corner_iso(grid, x, y, cx, cy)
  local z = grid:get(x*2+cx, y*2+cy)
  return v3.v3(x+cx,y+cy,z)
end

function draw_iso_square_outline(grid, screen, origin_screen, color, x, y)
  local ul = corner_iso(grid, x, y, 0, 0)
  local ur = corner_iso(grid, x, y, 1, 0)
  local bl = corner_iso(grid, x, y, 0, 1)
  local br = corner_iso(grid, x, y, 1, 1)

  local line = function(p1,p2)
    if p1.z >= 0 and p2.z >= 0 then
      local screen_p1 = origin_screen + iso_to_screen(p1.x, p1.y, p1.z)
      local screen_p2 = origin_screen + iso_to_screen(p2.x, p2.y, p2.z)
      draw_line(screen, color, screen_p1, screen_p2)
    end
  end
  line(ul,ur)
  line(bl,br)
  line(ul,bl)
  line(ur,br)

  if ul.z ~= br.z and bl.z == ur.z then
    line(ul,br)
  elseif ul.z == br.z and bl.z ~= ur.z then
    line(bl,ur)
  end
end

function tri_color(corner, c1, c2)
  local v1 = c1 - corner
  local v2 = c2 - corner

  if v1.z ~= 0 then
    if v1.x == 0 then
      if v1.y == v1.z then
        return 1
      else
        return 4
      end
    else
      if v1.x == v1.z then
        return 3
      else
        return 2
      end
    end
  elseif v2.z ~= 0 then
    if v2.x == 0 then
      if v2.y == v2.z then
        return 1
      else
        return 4
      end
    else
      if v2.x == v2.z then
        return 3
      else
        return 2
      end
    end
  else
    -- flat
    return 5
  end
end

function draw_iso_square(grid, screen, origin_screen, x, y)
  local ul = corner_iso(grid, x, y, 0, 0)
  local ur = corner_iso(grid, x, y, 1, 0)
  local bl = corner_iso(grid, x, y, 0, 1)
  local br = corner_iso(grid, x, y, 1, 1)

  -- TODO: Support tiles with one missing point (triangles).
  if ul.z < 0 or ur.z < 0 or bl.z < 0 or br.z < 0 then
    return
  end

  local sul = origin_screen + iso_to_screen(ul.x, ul.y, ul.z)
  local sur = origin_screen + iso_to_screen(ur.x, ur.y, ur.z)
  local sbl = origin_screen + iso_to_screen(bl.x, bl.y, bl.z)
  local sbr = origin_screen + iso_to_screen(br.x, br.y, br.z)

  if ul.z ~= br.z and bl.z == ur.z then
    local c1 = tri_color(ur, ul, br)
    draw_tri(screen, c1, sur, sul, sbr)
    local c2 = tri_color(bl, ul, br)
    draw_tri(screen, c2, sbl, sul, sbr)
  elseif ul.z == br.z and bl.z ~= ur.z then
    local c1 = tri_color(ul, ur, bl)
    draw_tri(screen, c1, sul, sur, sbl)
    local c2 = tri_color(br, ur, bl)
    draw_tri(screen, c2, sbr, sur, sbl)
  else
    local c = tri_color(ul, ur, bl)
    draw_tri(screen, c, sul, sur, sbl)
    draw_tri(screen, c, sbr, sur, sbl)
  end
end

-- Draws the given heightmap on an isometric grid.
function draw_iso_heightmap(grid)
  local image_width = (grid.width / 2) * 16 + (grid.height / 2) * 16
  local image_height = (grid.width / 2) * 8 + (grid.height / 2) * 8 + 16
  local origin_screen = v2.v2(0,image_height/2-1)
  local screen = Grid:newWithDimensions(image_width, image_height)
  screen:fill(0)
  for y=0,grid.height/2-1 do
    for x=0,grid.width/2-1 do
      draw_iso_square(grid, screen, origin_screen, x, y)
      draw_iso_square_outline(grid, screen, origin_screen, 0, x, y)
    end
  end

  return screen
end

local csv_file = assert(io.open(input_csv, "r"))
local csv_text = csv_file:read("*all")
csv_file:close()

-- z values of the corners of each tile (so each tile is 4 values).
local level = load_level_csv(csv_text)
assert(#level.grid.array == 64*64)
local img = draw_iso_heightmap(level.grid)

local pgm_file = io.open(name_prefix .. ".pgm", "w")
assert(pgm_file)
write_pgm(img, 6, pgm_file)
pgm_file:close()

local result = tilify(img, 16)
local sixteen_result = sixteen_to_eight(result.tiles, result.tilemap)
assert(#sixteen_result.tiles < 1024, "Too many tiles generated: " .. #sixteen_result.tiles)

local tiles_pgm = io.open(name_prefix .. ".tiles.pgm", "w")
assert(tiles_pgm)
write_pgm(Grid.cat(sixteen_result.tiles), 6, tiles_pgm)
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

local heightmap_file = io.open(name_prefix .. ".map.heightmap.out", "wb")
assert(heightmap_file)
write_heightmap(level.grid, heightmap_file)
heightmap_file:close()

local metadata_file = io.open(name_prefix .. ".map.metadata.out", "wb")
assert(metadata_file)
write_metadata(level, metadata_file)
metadata_file:close()
