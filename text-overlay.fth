REQUIRE std.fth

REQUIRE font.fth
REQUIRE cgram.fth
REQUIRE snes-std.fth
REQUIRE vram.fth
REQUIRE wram.fth

BANK@
LOWRAM BANK!
CREATE TEXT-OVERLAY-NMI-STATE 1 CELLS ALLOT
BANK!
 
: COPY-FONT
  FONT
  FONT-BANK
  FONT-CHARS 16* 2*
  FONT-BG-TILE-BASE TILE-BASE-TO-VRAM-WORD
  DMA0-VRAM-LONG-TRANSFER
;

: TEXT-PALETTE
  1 0x2121 C!
  0x7FFF SET-PALETTE-ENTRY
;

: TEXT-OVERLAY-COPY-BG3
  BG3-SHADOW-TILEMAP BANK@
  FONT-BG-MAP-BASE MAP-BASE-TO-VRAM-WORD
  COPY-BG-TO-VRAM
;

\ Converts ASCII string (bytes) to tile references (words where 0 = space, 1 =
\ !, etc). Ignores 0x0A (line feed) characters.
: COPY-STRING-TO-TILES ( addr u tilemap-addr -- )
  SWAP CELLS OVER + SWAP DO
    BEGIN
      DUP 1+ SWAP
      C@
      DUP 0x0A =
    WHILE
      DROP
    REPEAT
    \ Convert to text tile offset (missing the first 0x20 control characters).
    0x20 -
    \ Give text tiles priority over others. (bit 5 of $2105 ensures they show
    \ over other backgrounds).
    0x2000 OR I !
  1 CELLS +LOOP DROP
;

\ Converts ASCII string (bytes) to tile references (words where 0 = space, 1 =
\ !, etc) and writes to the current code bank. Ignores 0x0A (line feed) chars.
: TEXT" ( runtime: -- addr bytes )
  ['] DOS" COMPILE,
  CODEHERE 0 COMPILE-WORD
  \ Discard the first space.
  KEY DROP
  \ Keep track of the length.
  0
  BEGIN
    KEY
    DUP [CHAR] " <>
  WHILE
    DUP 0x0A = IF
      \ Ignore newlines.
      DROP
    ELSE
      \ Convert to text tile offset (missing the first 0x20 control characters).
      0x20 -
      \ Give text tiles priority over others. (bit 5 of $2105 ensures they show
      \ over other backgrounds).
      0x2000 OR
      COMPILE-WORD 1+
    THEN
  REPEAT
  DROP
  \ 1 cell per character.
  CELLS SWAP CODE!
; IMMEDIATE

: TEXT-OVERLAY-NMI ( -- done )
  TEXT-OVERLAY-NMI-STATE @ CASE
    \ Happy path first.
    3 OF
      TRUE
    ENDOF
    0 OF
      COPY-FONT
      TEXT-PALETTE

      1 TEXT-OVERLAY-NMI-STATE +!
      FALSE
    ENDOF
    1 OF
      TEXT-OVERLAY-COPY-BG3

      1 TEXT-OVERLAY-NMI-STATE +!
      FALSE
    ENDOF
    2 OF
      FONT-BG-TILE-BASE BG3-TILE-BASE!
      \ Prioritize BG3, BG3 is 8x8
      0x08   0x48   BG-MODE           MASK!
      \ Enable BG3
      0x04   0x04   BG-LAYER-ENABLE   MASK!

      FONT-BG-MAP-BASE 0x2109 C!

      \ No X shift.
      0x00 0x2111 C!
      0x00 0x2111 C!
      \ No Y shift.
      0x00 0x2112 C!
      0x00 0x2112 C!

      1 TEXT-OVERLAY-NMI-STATE +!
      FALSE
    ENDOF
  ENDCASE
;

: TEXT-OVERLAY-INIT
  0 TEXT-OVERLAY-NMI-STATE !

  BG3-SHADOW-TILEMAP ZERO-BGTILEMAP

TEXT"
          Press Start!          
                                
                                
                          Acedio
                       Jason199X
                    CornetTheory
"

  PHK SWAP BG3-SHADOW-TILEMAP 0 21 TILEMAP-XY CELLS + 0 DMA0-WRAM-LONG-TRANSFER
;
