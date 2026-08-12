REQUIRE std.fth

REQUIRE snes-std.fth

BANK@
CBANK@
2 BANK!
2 CBANK!
INCLUDE std.fth

( width height -- )
: COMPILE-MAP
  * 2*
  HERE + >R
  -3
  BEGIN
    DUP 0 < IF
      0 ,
    ELSE
      1 ,
    THEN
    1+
    DUP 3 >= IF
      DROP -3
    THEN
  HERE R@ >= UNTIL
  DROP
  R> DROP
;

\ Width should be a multiple of 2.
64 CONSTANT MAP-WIDTH
64 CONSTANT MAP-HEIGHT

HERE CONSTANT MAP-TILES
MAP-WIDTH MAP-HEIGHT COMPILE-MAP

16 CONSTANT COLUMN-COPY-TILES
32 CONSTANT VRAM-TILEMAP-WIDTH
32 CONSTANT VRAM-TILEMAP-HEIGHT
31 CONSTANT VRAM-TILEMAP-WIDTH-MASK
31 CONSTANT VRAM-TILEMAP-HEIGHT-MASK
VRAM-TILEMAP-HEIGHT CELLS 1- CONSTANT COLUMN-COPY-BUFFER-MASK

\ ALLOT enough bytes to align to the given stride length.
\ stride must be a multiple of 2.
\ e.g. HERE = 0x33, stride = 0x10, we'll ALLOT such that HERE = 0x40
: ALIGN-TO ( stride -- )
  \ First check to see if we're already aligned.
  DUP 1- HERE AND 0= IF
    DROP
  ;THEN

  HERE OVER +
  SWAP 1- INVERT AND
  HERE - ALLOT
;

BANK@
LOWRAM BANK!
\ TODO: Can probably share this between rows and columns, since we probably
\ won't be able to calculate both in a single frame anyway?
VRAM-TILEMAP-HEIGHT CELLS ALIGN-TO
CREATE COLUMN-COPY-BUFFER VRAM-TILEMAP-HEIGHT CELLS ALLOT
CREATE COLUMN-COPY-VMADD 1 CELLS ALLOT
CREATE COLUMN-COPY-NMI-READY 1 CELLS ALLOT
\ For testing
CREATE COLUMN-COPY-COLUMN 1 CELLS ALLOT
BANK!

: 64*
  2* 2* 2* 2* 2* 2*
;

\ Fill the copy buffer with COLUMN-COPY-TILES (potentially wrapping)
\ The column must not exceed the height of the tilemap.
: FILL-COLUMN-COPY-BUFFER ( col rowstart -- )
  BANK@ >R
  2 BANK!

  TUCK \ Save the starting row to determine where to start in COLUMN-COPY-BUFFER
  64* + CELLS \ Byte offset into the map
  MAP-TILES + \ Starting address
  DUP COLUMN-COPY-TILES 64* + >R \ Final address

  SWAP CELLS COLUMN-COPY-BUFFER + \ Copy target based on the starting row.
  BEGIN
    OVER @ OVER COLUMN-COPY-BUFFER-MASK AND COLUMN-COPY-BUFFER + !
    CELL+ SWAP MAP-WIDTH + SWAP
  OVER R@ >= UNTIL
  2DROP
  R> DROP

  R> BANK!
;

\ Initiate a DMA based on the above COLUMN-COPY- registers.
\ TODO: This is a bit wasteful, since we always DMA a full 32-tile column when
\ only 16 were ever updated. That said, I think that's faster than trying to
\ handle wrap-around otherwise (because forth is slowwww).
: COLUMN-COPY-DMA ( -- )
  \ - Increment after writing high byte and
  \ - increment by 32.
  0x81 0x2115 C!
  \ Writing to column (word addressed)
  COLUMN-COPY-VMADD @ 0x2116 !

  \ Number of copies
  VRAM-TILEMAP-HEIGHT CELLS 0x4305 !
  \ Page (LOWRAM so doesn't matter much)
  0 0x4304 C!
  \ Transfer from
  COLUMN-COPY-BUFFER 0x4302 !
  \ Copy to addr (2118), then addr+1 (2119).
  0x1 0x4300 C!
  \ Copy to VRAM reg
  0x18 0x4301 C!

  \ Start DMA transfer.
  0x01 0x420B C!
;

: 32*
  2* 2* 2* 2* 2*
;

\ Determine the index into a row-major map array based on (X,Y)
: XY-TO-MAP-INDEX ( x y -- index )
  32* +
;

: COPY-SUBCOLUMN ( col rowstart -- )
  OVER SWAP FILL-COLUMN-COPY-BUFFER
  \ VMADD is a word address. Mask (modulo) the width so we clamp to valid
  \ columns in the vram tilemap.
  VRAM-TILEMAP-WIDTH-MASK AND COLUMN-COPY-VMADD !
  TRUE COLUMN-COPY-NMI-READY !
;

: MAP-INIT
  FALSE COLUMN-COPY-NMI-READY !
  0 COLUMN-COPY-COLUMN !
;

: MAP-MAIN
  COLUMN-COPY-NMI-READY @ 0= IF
    COLUMN-COPY-COLUMN @
    DUP 1+ COLUMN-COPY-COLUMN !
    \ Always copy from row 0
    24 COPY-SUBCOLUMN
  THEN
;

: MAP-NMI
  \ Enable BG1, disable OBJ. In lowram, so fine to write.
  \ TODO: Maybe creating a vram-lowram.fth file that we can include in other
  \ banks to allow for writing the lowram CREATE vars?
  0x01 0x11 BANK0-CALL BG-LAYER-ENABLE MASK!

  0x01 BANK0-CALL BG1-TILE-BASE!
  \ Tilemap at address 0, 1x1 tilemap.
  0 0x2107 C!
  0x11   0x11   BANK0-CALL BG-MODE           MASK!

  \ Zero X shift for BG1
  0x00 0x210D C!
  0x00 0x210D C!

  COLUMN-COPY-NMI-READY @ IF
    COLUMN-COPY-DMA
    FALSE COLUMN-COPY-NMI-READY !
  THEN
;

CBANK!
BANK!
