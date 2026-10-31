REQUIRE std.fth

REQUIRE font.fth
REQUIRE cgram.fth
REQUIRE snes-std.fth
REQUIRE vram.fth

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
( addr u tilemap-addr -- )
: COPY-STRING-TO-TILES
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

: TEXT-OVERLAY-NMI
  TEXT-OVERLAY-NMI-STATE @ CASE
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
    3 OF
      TRUE
    ENDOF
  ENDCASE
;

: TEXT-OVERLAY-INIT
  0 TEXT-OVERLAY-NMI-STATE !

  BG3-SHADOW-TILEMAP ZERO-BGTILEMAP

  S"                                
                                
                                
                                
                                
                                
                                
                                
                                
                                
                                
          Press Start!          
                                
                                
                          Acedio
                       Jason199X
                    CornetTheory"
  DROP [ 32 17 * COMPILE-LIT ] BG3-SHADOW-TILEMAP 0 10 TILEMAP-XY CELLS + COPY-STRING-TO-TILES

  \ STEPS-STRING BG3-SHADOW-TILEMAP 26 11 TILEMAP-XY CELLS + COPY-STRING-TO-TILES
;

: TEXT-OVERLAY-MAIN
;
