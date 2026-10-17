REQUIRE std.fth

REQUIRE cgram.fth
REQUIRE joypad.fth
REQUIRE map.fth
REQUIRE oam.fth
REQUIRE snes-std.fth
REQUIRE vram.fth
REQUIRE build/pickles.spr.fth

BANK@
LOWRAM BANK!
CREATE STAGE-STATE 1 CELLS ALLOT
CREATE STAGE-NMI-STATE 1 CELLS ALLOT
\ 8.8 fixed point
CREATE PLAYER-ISO-X 1 CELLS ALLOT
CREATE PLAYER-ISO-Y 1 CELLS ALLOT
CREATE CAMERA-OFFSET-X 1 CELLS ALLOT
CREATE CAMERA-OFFSET-Y 1 CELLS ALLOT
BANK!

\ Where iso 0,0 is in screen space
0      CONSTANT ISO-ORIGIN-SCREEN-X
32 8 * 8 + CONSTANT ISO-ORIGIN-SCREEN-Y

\ TODO: These are pulled from map.fth.
16 CONSTANT TILE-SIZE-PIXELS
64 16 - TILE-SIZE-PIXELS * CONSTANT MAX-X-SCROLL
64 14 - TILE-SIZE-PIXELS * CONSTANT MAX-Y-SCROLL

64 0x100 * CONSTANT MAX-ISO-X
64 0x100 * CONSTANT MAX-ISO-Y

: 16/ 2/ 2/ 2/ 2/ ; LABEL DIV16

\ sx = ox+c(x+y)    sy = oy+0.5*c(y-x)
\ Need to multiply 8.8 fixed by 16 and then truncate to an unsigned word, so
\ divide by 16.
: ISO-TO-SCREEN-X ( iso-x iso-y -- screen-x )
  + 16/ ISO-ORIGIN-SCREEN-X +
;

\ Need to multiply 8.8 fixed by 8 and then truncate to an unsigned word, so
\ divide by 32.
: ISO-TO-SCREEN-Y ( iso-x iso-y -- screen-y )
  SWAP - 16/ 2/ ISO-ORIGIN-SCREEN-Y +
;

\ TODO: This should be a native word, also unsure about the signature order.
: FC@ ( addr bank -- byte )
  BANK@ >R
  BANK! C@ R> BANK!
;

\ Grab the byte that represents what kind of tile (and height) is at iso-coords.
: TILE-BYTE ( iso-x iso-y -- tile-byte )
  \ Multiply iso-y (8.8) by 32 so LSR thrice and mask.
  2/ 2/ 2/ 0xFFE0 AND
  \ Get only the top 8 of X.
  SWAP HIBYTE
  + \ Add to get coord offset
  BANK2-CALL TEST-HEIGHTMAP +
  BANK2-CALL TEST-HEIGHTMAP-BANK
  FC@
;

: NEGATE-X?
  0x10 AND 0=
;

: NEGATE-Y?
  0x20 AND 0=
;

: ISO-Z ( iso-x iso-y -- iso-z )
  2DUP TILE-BYTE >R

  R@ 0xF0 AND 0= IF
    \ Flat, just return height.
    2DROP R> 0x0F AND SWAPBYTES
  ;THEN
  
  \ We're in some sort of slope case.
  R@ NEGATE-X? IF
    0xFF ROT 0xFF AND - SWAP
  ELSE
    SWAP 0xFF AND SWAP
  THEN
  R@ NEGATE-Y? IF
    0xFF SWAP 0xFF AND -
  ELSE
    0xFF AND
  THEN

  R@ 0xC0 AND CASE
    0x00 OF
      \ Only x
      DROP R> 0x0F AND SWAPBYTES +
    ENDOF
    0x40 OF
      \ Only y
      SWAP DROP R> 0x0F AND SWAPBYTES +
    ENDOF
    0x80 OF
      \ Min combine
      MIN R> 0x0F AND SWAPBYTES +
    ENDOF
    0xC OF
      \ Max combine
      MAX R> 0x0F AND SWAPBYTES +
    ENDOF
  ENDCASE
;

\ TODO: z?
\ iso-x and iso-y are in 8.8 fixed point.
: ISO-TO-SCREEN ( iso-x iso-y -- screen-x screen-y )
  2DUP ISO-TO-SCREEN-X -ROT
  2DUP ISO-TO-SCREEN-Y -ROT
  ISO-Z 2* 2* 2* HIBYTE -
;

: COORD-SUB ( ax ay bx by -- ax-bx ay-by )
  ROT SWAP -
  -ROT -
  SWAP
;

: COPY-SPRITES
  \ The bottom two 8x8 tiles of a 16x16 tile are 16 8x8 tiles ahead (1 row
  \ below) the first 8x8 tile.
  PICKLES-TILES
  PICKLES-TILES-BANK
  PICKLES-TILES-BYTES
  OAM-TILE-BASE OAM-TILE-BASE-TO-VRAM-WORD
  DMA0-VRAM-LONG-TRANSFER
;

: COPY-SPRITES-PALETTE
  PICKLES-PAL
  PICKLES-PAL-BANK
  PICKLES-PAL-BYTES
  0x80
  COPY-CGRAM-PALETTE-LONG
;

3 CONSTANT PLAYER-OAM-OBJECT

( -- )
: DRAW-PLAYER
  PLAYER-ISO-X @ PLAYER-ISO-Y @ ISO-TO-SCREEN
  CAMERA-OFFSET-X @ CAMERA-OFFSET-Y @ COORD-SUB
  SWAP 8 - SWAP 16 -
  \ For some reason OAM-OBJECT-COORDS! takes y before x.
  SWAP
  PLAYER-OAM-OBJECT OAM-OBJECT-COORDS!
  0x30 SHADOW-OAM-LOWER PLAYER-OAM-OBJECT OAM-LOWER-OBJECTS + OAM-ATTRIBUTES C!
  TRUE PLAYER-OAM-OBJECT OAM-OBJECT-LARGE!
;

: TAKE-SIGN ( sign-donor number -- signed-number )
  SWAP 0< IF NEGATE THEN
;

: HANDLE-JOY
  JOY1-HELD @ >R
    0
    R@ BUTTON-LEFT AND PLAYER-ISO-X @ 0 > AND IF
      -10 +
    THEN
    R@ BUTTON-RIGHT AND PLAYER-ISO-X @ MAX-ISO-X < AND IF
      10 +
    THEN
    0
    R@ BUTTON-UP AND PLAYER-ISO-Y @ 0 > AND IF
      -10 +
    THEN
    R@ BUTTON-DOWN AND PLAYER-ISO-Y @ MAX-ISO-Y < AND IF
      10 +
    THEN
    \ If we're moving in two directions, shrink the magnitude.
    OVER 0<> OVER 0<> AND IF
      7 TAKE-SIGN SWAP 7 TAKE-SIGN SWAP
    THEN
    PLAYER-ISO-Y +!
    PLAYER-ISO-X +!
  R> DROP
;

: STAGE-NMI
  STAGE-NMI-STATE @ CASE
    0 OF
      COPY-SPRITES
      COPY-SPRITES-PALETTE
      1 STAGE-NMI-STATE +!
    ENDOF
    1 OF
      BANK2-CALL MAP-NMI

      OAM-TILE-BASE 0x2101 C!

      \ TODO: Copying this below STARS-NMI causes issues.
      COPY-OAM

      \ Enable sprite layer.
      0x10 0x10 BANK0-CALL BG-LAYER-ENABLE MASK!
    ENDOF
  ENDCASE
;

: STAGE-INIT
  BANK2-CALL MAP-INIT
  0 STAGE-NMI-STATE !
  0x0000 PLAYER-ISO-X !
  0x0000 PLAYER-ISO-Y !
  0 CAMERA-OFFSET-X !
  128 CAMERA-OFFSET-Y !
;

: STAGE-MAIN
  HANDLE-JOY

  CAMERA-OFFSET-X @ CAMERA-OFFSET-Y @ BANK2-CALL MAP-MAIN

  DRAW-PLAYER
;
