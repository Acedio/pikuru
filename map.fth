REQUIRE std.fth

REQUIRE snes-std.fth

BANK@
CBANK@
2 BANK!
2 CBANK!
INCLUDE std.fth

( width height -- )
: COMPILE-MAP
  * CELLS
  HERE + >R
  BEGIN
    0 , 0 , 0 , 0 , 0 , 0 , 0 , 0 ,
    0 , 0 , 0 , 0 , 0 , 0 , 0 , 0 ,
    0 , 0 , 0 , 0 , 0 , 0 , 0 , 0 ,
    0 , 0 , 0 , 0 , 0 , 0 , 0 , 0 ,
  HERE R@ >= UNTIL
  R> DROP
;

\ Width should be a multiple of 2.
64 CONSTANT MAP-WIDTH
64 CONSTANT MAP-HEIGHT

HERE \ Store HERE so we can create the label for it later.
MAP-WIDTH MAP-HEIGHT COMPILE-MAP
CONSTANT MAP-TILES

16 CONSTANT TILE-SIZE-PIXELS
18 CONSTANT COLUMN-COPY-TILES
20 CONSTANT ROW-COPY-TILES
32 CONSTANT VRAM-TILEMAP-WIDTH
32 CONSTANT VRAM-TILEMAP-HEIGHT
31 CONSTANT VRAM-TILEMAP-WIDTH-MASK
31 CONSTANT VRAM-TILEMAP-HEIGHT-MASK
VRAM-TILEMAP-HEIGHT CELLS 1- CONSTANT COLUMN-COPY-BUFFER-MASK

64 16 - TILE-SIZE-PIXELS * CONSTANT MAX-X-SCROLL
64 14 - TILE-SIZE-PIXELS * CONSTANT MAX-Y-SCROLL

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
VRAM-TILEMAP-HEIGHT CELLS ALIGN-TO
\ We use a buffer to copy columns, as DMA doesn't support non-1 stride-lengths
\ from the source (which is row-major).
CREATE COLUMN-COPY-BUFFER VRAM-TILEMAP-HEIGHT CELLS ALLOT
CREATE COLUMN-COPY-VMADDR 1 CELLS ALLOT
CREATE COLUMN-COPY-NMI-READY 1 CELLS ALLOT
\ Rows can just copy as-is from the source.
CREATE ROW-COPY-SRC-ADDR 1 CELLS ALLOT
CREATE ROW-COPY-VMADDR 1 CELLS ALLOT
CREATE ROW-COPY-NMI-READY 1 CELLS ALLOT
BANK!

: 64*
  2* 2* 2* 2* 2* 2*
;

\ Fill the copy buffer with COLUMN-COPY-TILES (potentially wrapping)
\ The column must not exceed the height of the tilemap.
: FILL-COLUMN-COPY-BUFFER ( col rowstart -- )
  BANK@ >R
  PHK BANK! \ Use the map in the current bank.

  TUCK \ Save the starting row to determine where to start in COLUMN-COPY-BUFFER
  64* + CELLS \ Byte offset into the map
  MAP-TILES + \ Starting address
  DUP COLUMN-COPY-TILES 64* CELLS + >R \ Final address

  SWAP CELLS COLUMN-COPY-BUFFER + \ Copy target based on the starting row.
  BEGIN ( &map-tiles &buf )
    OVER @ OVER COLUMN-COPY-BUFFER-MASK AND COLUMN-COPY-BUFFER + !
    CELL+ SWAP MAP-WIDTH CELLS + SWAP
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
  COLUMN-COPY-VMADDR @ 0x2116 !

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

: BREAK-INTO-TWO-ROW-COUNTS
( starting-vram-x desired-width -- pre-wrap-count post-wrap-count )
  2DUP + VRAM-TILEMAP-WIDTH < IF
    SWAP DROP 0
  ;THEN
  VRAM-TILEMAP-WIDTH ROT -
  TUCK -
;

: ROW-COPY-DMA ( -- )
  \ - Increment after writing high byte and
  \ - increment by 1.
  0x80 0x2115 C!
  \ Writing to row (word addressed)
  ROW-COPY-VMADDR @ DUP 0x2116 !
  \ Determine how many tiles to write, in case we're crossing a tilemap
  \ boundary. Store the second count for later.
  VRAM-TILEMAP-WIDTH-MASK AND ROW-COPY-TILES BREAK-INTO-TWO-ROW-COUNTS >R

  \ Number of copies
  CELLS 0x4305 !
  \ Page (compiled to the current page)
  PHK 0x4304 C!
  \ Transfer from
  ROW-COPY-SRC-ADDR @ 0x4302 !
  \ Copy to addr (2118), then addr+1 (2119).
  0x1 0x4300 C!
  \ Copy to VRAM reg
  0x18 0x4301 C!

  \ Start DMA transfer.
  0x01 0x420B C!

  \ Now for the remaining (wrapped) tiles (the remainder from the
  \ BREAK-INTO-TWO-ROW-COUNTS above). If zero, just exit.
  R> DUP 0= IF DROP ;THEN

  \ Number of copies
  CELLS 0x4305 !
  \ Start copying to the beginning of the row the above copy was for.
  ROW-COPY-VMADDR @ VRAM-TILEMAP-WIDTH-MASK INVERT AND 0x2116 !
  \ Don't need to change the source address, it's been incremented to copy from
  \ the correct place. Also don't need to change the other config registers.

  \ Start DMA transfer.
  0x01 0x420B C!
;

: TILE-DMA ( vram-addr -- )
  \ - Increment after writing high byte and
  \ - increment by 1.
  0x80 0x2115 C!
  \ Writing to row (word addressed)
  0x2116 !

  \ Number of copies
  32 0x4305 !
  \ Page (compiled to the current page)
  PHK 0x4304 C!
  \ Transfer from
  MAP-TILES 0x4302 !
  \ Copy to addr (2118), then addr+1 (2119). No increment.
  0x09 0x4300 C!
  \ Copy to VRAM reg
  0x18 0x4301 C!

  \ Start DMA transfer.
  0x01 0x420B C!
;

: COPY-SUBCOLUMN ( col rowstart -- )
  OVER SWAP FILL-COLUMN-COPY-BUFFER
  \ VMADDR is a word address. Mask (modulo) the width so we clamp to valid
  \ columns in the vram tilemap. We always write a 32-tile column and start at
  \ row 0.
  VRAM-TILEMAP-WIDTH-MASK AND COLUMN-COPY-VMADDR !
  TRUE COLUMN-COPY-NMI-READY !
;

: 32* 2* 2* 2* 2* 2* ;

\ Does not support wrapping.
: COPY-SUBROW ( col row -- )
  OVER VRAM-TILEMAP-WIDTH-MASK AND
  OVER VRAM-TILEMAP-HEIGHT-MASK AND 32* + ROW-COPY-VMADDR !
  64* + CELLS MAP-TILES + ROW-COPY-SRC-ADDR !
  \ 2DROP MAP-TILES ROW-COPY-SRC-ADDR !
  TRUE ROW-COPY-NMI-READY !
;

BANK@
LOWRAM BANK!
CREATE X-SCROLL 1 CELLS ALLOT
CREATE Y-SCROLL 1 CELLS ALLOT
\ These are in pixels but should always align to 16px tile sizes.
CREATE X-BORDER 1 CELLS ALLOT
CREATE Y-BORDER 1 CELLS ALLOT
BANK!

2 TILE-SIZE-PIXELS * CONSTANT BORDER-MARGIN

: MAP-INIT
  FALSE COLUMN-COPY-NMI-READY !
  FALSE ROW-COPY-NMI-READY !
  16 X-SCROLL !
  16 Y-SCROLL !
  \ Start with a centered border.
  X-SCROLL @ BORDER-MARGIN LSR - X-BORDER !
  Y-SCROLL @ BORDER-MARGIN LSR - Y-BORDER !
;

: HANDLE-JOY
  BANK0-CALL JOY1-HELD @
    DUP BANK0-CALL BUTTON-LEFT AND X-SCROLL @ 0 > AND IF
      -1 X-SCROLL +!
    THEN
    DUP BANK0-CALL BUTTON-RIGHT AND X-SCROLL @ MAX-X-SCROLL < AND IF
      1 X-SCROLL +!
    THEN
    DUP BANK0-CALL BUTTON-UP AND Y-SCROLL @ 0 > AND IF
      -1 Y-SCROLL +!
    THEN
    DUP BANK0-CALL BUTTON-DOWN AND Y-SCROLL @ MAX-Y-SCROLL < AND IF
      1 Y-SCROLL +!
    THEN
  DROP
;

: 16/ LSR LSR LSR LSR ;

: UPDATE-X-SCROLL
  X-SCROLL @ X-BORDER @ < IF
    \ Shift border left by one tile, then draw the next column over.
    TILE-SIZE-PIXELS NEGATE X-BORDER +!
    X-BORDER @ 16/ 1- 63 AND Y-BORDER @ 16/ 1- 63 AND COPY-SUBCOLUMN
  ;THEN
  X-SCROLL @ X-BORDER @ BORDER-MARGIN + >= IF
    \ Shift border right by one tile and draw the next right column.
    TILE-SIZE-PIXELS X-BORDER +!
    \ TODO: 18 should probably be calculated somehow?
    X-BORDER @ 16/ 18 + 63 AND Y-BORDER @ 16/ 1- 63 AND COPY-SUBCOLUMN
  ;THEN
;

: UPDATE-Y-SCROLL
  Y-SCROLL @ Y-BORDER @ < IF
    \ Shift border up by one tile, then draw the next row above.
    TILE-SIZE-PIXELS NEGATE Y-BORDER +!
    X-BORDER @ 16/ 1- 63 AND Y-BORDER @ 16/ 1- 63 AND COPY-SUBROW
  ;THEN
  Y-SCROLL @ Y-BORDER @ BORDER-MARGIN + >= IF
    \ Shift border down by one tile and draw the next column below.
    TILE-SIZE-PIXELS Y-BORDER +!
    \ TODO: 16 Should be calculated as well.
    X-BORDER @ 16/ 1- 63 AND Y-BORDER @ 16/ 16 + 63 AND COPY-SUBROW
  ;THEN
;

: UPDATE-SCROLL
  COLUMN-COPY-NMI-READY @ 0= IF
    UPDATE-X-SCROLL
  THEN
  ROW-COPY-NMI-READY @ 0= IF
    UPDATE-Y-SCROLL
  THEN
;

: MAP-MAIN
  HANDLE-JOY

  UPDATE-SCROLL
;

: SET-BG1-X-SCROLL ( 10-bit-val -- )
  DUP 0xFF AND 0x210D C!
  HIBYTE 0x210D C!
;

: SET-BG1-Y-SCROLL ( 10-bit-val -- )
  DUP 0xFF AND 0x210E C!
  HIBYTE 0x210E C!
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

  X-SCROLL @ SET-BG1-X-SCROLL
  Y-SCROLL @ SET-BG1-Y-SCROLL

  0x1000 TILE-DMA

  COLUMN-COPY-NMI-READY @ IF
    COLUMN-COPY-DMA
    FALSE COLUMN-COPY-NMI-READY !
  THEN
  ROW-COPY-NMI-READY @ IF
    ROW-COPY-DMA
    FALSE ROW-COPY-NMI-READY !
  THEN
;

CBANK!
BANK!
