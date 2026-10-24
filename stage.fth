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
CREATE PLAYER-ISO-Z 1 CELLS ALLOT
CREATE PLAYER-DASH 1 CELLS ALLOT
CREATE BOX-ISO-X 1 CELLS ALLOT
CREATE BOX-ISO-Y 1 CELLS ALLOT
\ Used during draw routine.
CREATE TEMP-X 1 CELLS ALLOT
CREATE TEMP-Y 1 CELLS ALLOT
CREATE TEMP-Z 1 CELLS ALLOT
\ Deltas used during draw routine.
CREATE BOX-ISO-DELTA-X 1 CELLS ALLOT
CREATE BOX-ISO-DELTA-Y 1 CELLS ALLOT
CREATE BOX-VEL-X 1 CELLS ALLOT
CREATE BOX-VEL-Y 1 CELLS ALLOT
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

12 CONSTANT RUN-SPEED
0x2000 CONSTANT DASH-SPEED
0x0400 CONSTANT DASH-DECAY

64 0x100 * CONSTANT MAX-ISO-X
64 0x100 * CONSTANT MAX-ISO-Y

0x0180 CONSTANT BOX-HEIGHT

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

\ iso-x and iso-y are in 8.8 fixed point.
: ISO-TO-SCREEN ( iso-x iso-y -- screen-x screen-y )
  2DUP ISO-TO-SCREEN-X -ROT
  ISO-TO-SCREEN-Y
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

  R@ 0xF0 AND 0x40 = IF
    \ Empty tile, return negative.
    2DROP R> DROP
    0xFF00
  ;THEN

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

: COORD-SUB ( ax ay bx by -- ax-bx ay-by )
  ROT SWAP -
  -ROT -
  SWAP
;

: COORD-ADD ( ax ay bx by -- ax+bx ay+by )
  ROT +
  -ROT +
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

5 CONSTANT NUM-BOXES

1
  DUP CONSTANT BOX0-OAM-OBJECT
  NUM-BOXES +
  DUP CONSTANT PLAYER-TOP-OAM-OBJECT
  1+
  DUP CONSTANT PLAYER-BOTTOM-OAM-OBJECT
  1+
  DUP CONSTANT BOX0-SHADOW-OAM-OBJECT
  NUM-BOXES +
DROP

: ISO-Z-TO-Y-OFFSET ( iso-z -- screen-y-offset )
  2* 2* 2* HIBYTE 
;

: DRAW-BOXES
  BOX-ISO-X @ BOX-ISO-Y @
  PLAYER-ISO-X @ PLAYER-ISO-Y @ COORD-SUB
  2/ 2/ BOX-ISO-DELTA-Y !
  2/ 2/ BOX-ISO-DELTA-X !

  PLAYER-ISO-X @ TEMP-X !
  PLAYER-ISO-Y @ 0x040 + TEMP-Y !
  PLAYER-ISO-Z @ 0x100 + TEMP-Z !

  NUM-BOXES 0 DO
    TEMP-X @ TEMP-Y @ ISO-TO-SCREEN
    TEMP-Z @ ISO-Z-TO-Y-OFFSET -
    CAMERA-OFFSET-X @ CAMERA-OFFSET-Y @ COORD-SUB
    SWAP 8 - SWAP 16 -
    \ For some reason OAM-OBJECT-COORDS! takes y before x.
    SWAP
    BOX0-OAM-OBJECT NUM-BOXES 1- + I - OAM-OBJECT-COORDS-WITHOUT-NEGX!

    \ TODO: For performance reasons, just draw the last shadow for now.
    NUM-BOXES 1- I = IF
      TEMP-X @ TEMP-Y @ ISO-Z
      DUP 0< IF
        DROP
        -32 0 BOX0-SHADOW-OAM-OBJECT NUM-BOXES 1- + I - OAM-OBJECT-COORDS-WITHOUT-NEGX!
      ELSE
        TEMP-X @ TEMP-Y @ ISO-TO-SCREEN
        ROT ISO-Z-TO-Y-OFFSET -
        CAMERA-OFFSET-X @ CAMERA-OFFSET-Y @ COORD-SUB
        SWAP 8 - SWAP 16 -
        \ For some reason OAM-OBJECT-COORDS! takes y before x.
        SWAP
        BOX0-SHADOW-OAM-OBJECT NUM-BOXES 1- + I - OAM-OBJECT-COORDS-WITHOUT-NEGX!
      THEN
    THEN

    BOX-ISO-DELTA-X @ TEMP-X +!
    BOX-ISO-DELTA-Y @ TEMP-Y +!
    BOX-HEIGHT TEMP-Z +!
  LOOP
;

( -- )
: DRAW-PLAYER
  PLAYER-ISO-X @ PLAYER-ISO-Y @ ISO-TO-SCREEN
  PLAYER-ISO-Z @ ISO-Z-TO-Y-OFFSET -
  CAMERA-OFFSET-X @ CAMERA-OFFSET-Y @ COORD-SUB
  SWAP 8 - SWAP 16 -
  \ For some reason OAM-OBJECT-COORDS! takes y before x.
  2DUP SWAP
  PLAYER-BOTTOM-OAM-OBJECT OAM-OBJECT-COORDS-WITHOUT-NEGX!

  16 -
  SWAP PLAYER-TOP-OAM-OBJECT OAM-OBJECT-COORDS-WITHOUT-NEGX!
;

: 3/4 ( i -- 3/4*i )
  2/ DUP 2/ +
;

: GET-JOY-DIR ( -- xsign ysign )
  JOY1-HELD @ >R
    0
    R@ BUTTON-LEFT AND IF
      1-
    THEN
    R@ BUTTON-RIGHT AND IF
      1+
    THEN
    0
    R@ BUTTON-UP AND IF
      1-
    THEN
    R@ BUTTON-DOWN AND IF
      1+
    THEN
  R> DROP
;

: TAKE-SIGN ( sign magnitude -- signed-magnitude )
  OVER 0= IF
    DROP \ Leave the 0.
  ;THEN
  SWAP 0< IF
    NEGATE
  THEN
;

\ Scale ({-1,0,1}, {-1,0,1}) coordinate directions by the `scale` amount,
\ accounting for the case where diagonals scale less (to yield the same-ish
\ magnitude).
: SCALE-DIR ( xsign ysign scale -- x y )
  -ROT OVER 0<> OVER 0<> AND IF
    \ Both directions pressed.
    ROT 3/4
  ELSE
    ROT
  THEN
  TUCK
  TAKE-SIGN
  -ROT
  TAKE-SIGN
  SWAP
;

: HANDLE-JOY
  JOY1-PRESSED @ BUTTON-Y AND IF
    DASH-SPEED PLAYER-DASH !
  ELSE
    \ Decay the dash, stopping at 0.
    PLAYER-DASH @ DASH-DECAY -
    DUP 0 < IF DROP 0 THEN
    PLAYER-DASH !
  THEN

  GET-JOY-DIR
  2DUP 
  RUN-SPEED PLAYER-DASH @ HIBYTE + SCALE-DIR
  PLAYER-ISO-Y +!
  PLAYER-ISO-X +!
  RUN-SPEED 2/ 2/ SCALE-DIR
  BOX-ISO-Y +!
  BOX-ISO-X +!
;

: 8.8-INT-PART ( 8.8-fixed -- int-part )
  \ Using 2/ a bunch here because it preserves sign while HIBYTE does not.
  2/ 2/ 2/ 2/ 2/ 2/ 2/ 2/ 
;

\ The amount of acceleration based on how far away the top box is.
: ACCEL-FROM-DISTANCE ( iso-distance -- acceleration )
  2/ 2/ 2/ 2/
;

: UPDATE-BOX
  BOX-ISO-X @ PLAYER-ISO-X @ - ACCEL-FROM-DISTANCE BOX-VEL-X +!
  BOX-ISO-Y @ PLAYER-ISO-Y @ - ACCEL-FROM-DISTANCE BOX-VEL-Y +!
  BOX-VEL-X @ 8.8-INT-PART BOX-ISO-X +!
  BOX-VEL-Y @ 8.8-INT-PART BOX-ISO-Y +!
;

: STAGE-NMI
  STAGE-NMI-STATE @ CASE
    0 OF
      COPY-SPRITES
      COPY-SPRITES-PALETTE
      1 STAGE-NMI-STATE +!
    ENDOF
    1 OF
      \ TODO: This doesn't actually have to be in NMI since we're operating on
      \ the shadow OAM
      TRUE PLAYER-TOP-OAM-OBJECT OAM-OBJECT-LARGE!
      0x30 SHADOW-OAM-LOWER PLAYER-TOP-OAM-OBJECT OAM-LOWER-OBJECTS + OAM-ATTRIBUTES C!
      4 SHADOW-OAM-LOWER PLAYER-TOP-OAM-OBJECT OAM-LOWER-OBJECTS + OAM-TILE-NUMBER C!
      FALSE PLAYER-TOP-OAM-OBJECT OAM-OBJECT-NEGATIVE-X!
      TRUE PLAYER-BOTTOM-OAM-OBJECT OAM-OBJECT-LARGE!
      0x30 SHADOW-OAM-LOWER PLAYER-BOTTOM-OAM-OBJECT OAM-LOWER-OBJECTS + OAM-ATTRIBUTES C!
      6 SHADOW-OAM-LOWER PLAYER-BOTTOM-OAM-OBJECT OAM-LOWER-OBJECTS + OAM-TILE-NUMBER C!
      FALSE PLAYER-BOTTOM-OAM-OBJECT OAM-OBJECT-NEGATIVE-X!

      NUM-BOXES 0 DO
        TRUE BOX0-OAM-OBJECT I + OAM-OBJECT-LARGE!
        0x30 SHADOW-OAM-LOWER BOX0-OAM-OBJECT I + OAM-LOWER-OBJECTS + OAM-ATTRIBUTES C!
        0 SHADOW-OAM-LOWER BOX0-OAM-OBJECT I + OAM-LOWER-OBJECTS + OAM-TILE-NUMBER C!

        TRUE BOX0-SHADOW-OAM-OBJECT I + OAM-OBJECT-LARGE!
        0x30 SHADOW-OAM-LOWER BOX0-SHADOW-OAM-OBJECT I + OAM-LOWER-OBJECTS + OAM-ATTRIBUTES C!
        2 SHADOW-OAM-LOWER BOX0-SHADOW-OAM-OBJECT I + OAM-LOWER-OBJECTS + OAM-TILE-NUMBER C!
      LOOP

      1 STAGE-NMI-STATE +!
    ENDOF
    2 OF
      BANK2-CALL MAP-NMI

      OAM-TILE-BASE 0x2101 C!

      \ TODO: Copying this below STARS-NMI causes issues.
      COPY-OAM

      \ Enable sprite layer.
      0x10 0x10 BANK0-CALL BG-LAYER-ENABLE MASK!
    ENDOF
  ENDCASE
;

: INIT-BOXES ( -- )
  \ We'll just assume boxes are always on screen.
  NUM-BOXES 0 DO
    FALSE BOX0-OAM-OBJECT I + OAM-OBJECT-NEGATIVE-X!
    FALSE BOX0-SHADOW-OAM-OBJECT I + OAM-OBJECT-NEGATIVE-X!
  LOOP
;

: STAGE-INIT
  \ TODO: Should turn off the screen until all the loading NMIs have run.
  BANK2-CALL MAP-INIT
  0 STAGE-NMI-STATE !
  0x0180 PLAYER-ISO-X !
  0x0180 PLAYER-ISO-Y !
  0x0000 PLAYER-ISO-Z !
  0x0000 PLAYER-DASH !
  0x0180 BOX-ISO-X !
  0x0180 BOX-ISO-Y !
  0x0000 BOX-VEL-X !
  0x0000 BOX-VEL-Y !
  0 CAMERA-OFFSET-X !
  128 CAMERA-OFFSET-Y !

  INIT-BOXES
;

: STAGE-MAIN
  HANDLE-JOY

  PLAYER-ISO-X @ PLAYER-ISO-Y @ ISO-Z

  DUP 0< IF
    DROP STAGE-INIT
  ELSE
    PLAYER-ISO-Z !
  THEN

  UPDATE-BOX

  \ TODO: Why are these the correct offsets?
  PLAYER-ISO-X @ PLAYER-ISO-Y @ ISO-TO-SCREEN
  128 - CAMERA-OFFSET-Y !
  128 - CAMERA-OFFSET-X !

  CAMERA-OFFSET-X @ CAMERA-OFFSET-Y @ BANK2-CALL MAP-MAIN

  DRAW-PLAYER

  DRAW-BOXES
;
