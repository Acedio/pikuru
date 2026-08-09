0 BANK!

REQUIRE snes-std.fth
REQUIRE std.fth

REQUIRE audio.fth
REQUIRE joypad.fth
REQUIRE oam.fth
REQUIRE vram.fth
REQUIRE map.fth


BANK@
LOWRAM BANK!
CREATE MISSED-FRAMES 1 CELLS ALLOT
BANK!

BANK@
LOWRAM BANK!
CREATE NMI-READY 1 CELLS ALLOT
CREATE NMI-STATE 1 CELLS ALLOT
BANK!

: SNES-NMI
  NMI-READY @ 0= IF
    \ We missed a frame.
    1 MISSED-FRAMES +!
    EXIT
  THEN

  FALSE NMI-READY !

  NMI-STATE @ CASE
    0 OF
      \ Disable all layers initially.
      0x00 BG-LAYER-ENABLE C!
      \ Set Mode 1 BG3 high priority (0x.9), BG1 BG2 BG3 tile size 16x16 (0x7.)
      0x79 BG-MODE C!

      \ Minimum screen brightness
      0 SET-SCREEN-BRIGHTNESS

      1 NMI-STATE +!
    ENDOF
    1 OF
      BANK2-CALL MAP-NMI
    ENDOF
  ENDCASE

  \ Wait for copying until the subcomponents had a chance to modify.
  COPY-BASE-REGISTERS
;

: SNES-MAIN
  FALSE NMI-READY !
  0 NMI-STATE !
  0 MISSED-FRAMES !

  INIT-BASE-REGISTERS

  INIT-JOYPAD

  ZERO-SHADOW-TILEMAPS

  AUDIO-INIT
  NMI-ENABLE

  ZERO-OAM

  BANK2-CALL MAP-INIT

  AUDIO-PLAY-SONG

  0
  BEGIN
    1+

    READ-JOY1

    BANK2-CALL MAP-MAIN

    AUDIO-UPDATE

    TRUE NMI-READY !
    BEGIN
      NMI-WAIT
    NMI-READY @ 0= UNTIL
  FALSE UNTIL
;
