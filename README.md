# BK-0011M + AZBK core for Karabas Go / Mini / Mini G

[Русская версия](README.ru.md)

The Soviet home computer **Elektronika BK-0011M** (K1801VM1, 128 KB, BASIC and BOS in ROM) with MAXIOL's
**AZBK** controller (32 MB mapper, 256-colour 1024 x 768 display with three layers, blitter, two AY, Covox,
sound DMA, disk controller on SD card images, EEPROM, clock; no network) on the Karabas Go family boards
(Xilinx Spartan-6 XC6SLX25). Work in progress: see [docs/PLAN.md](docs/PLAN.md).

One core file `bk.kg` for all boards.

| Board | Video | Sound |
|---|---|---|
| Karabas Go | VGA 1024 x 768 | I2S DAC (PCM5102) |
| Karabas Mini | HDMI 1024 x 768 | HDMI, analog (sigma-delta) |
| Karabas Mini G | HDMI 1024 x 768 | HDMI, I2S DAC (PCM5102) |

## Authors

- **The machine**: [retro-tang-bk](https://github.com/lordamot/retro-tang-bk) (BK Nano), **Sergei Lemeshev**
  and contributors, MIT ([docs/licenses/retro-tang-bk-MIT.md](docs/licenses/retro-tang-bk-MIT.md)); the
  K1801VM1 model is by Vslav (1801BM1@gmail.com) in Sorgelig's wrapper of the MiSTer BK0011M core (GPL v2);
  YM2149 by MikeJ and Sorgelig (BSD-style notice in the file). The behaviour of the AZBK follows GID's BKemu
  and MAXIOL's documentation on forum.maxiol.com.
- **The port to Karabas** and the board modules [karabas-go-modules](https://github.com/andykarpov/karabas-go-modules):
  Andy Karpov and contributors.

Origin of every file: [docs/sources.md](docs/sources.md).

## License

GPL-3.0-or-later as a whole, see [LICENSE](LICENSE); each file keeps its own header. The ROMs in `src/roms`
(MAXIOL's AZBK ROMs, the BK-0010 / BK-0011M firmware) are unchanged data of their owners.

## Usage

Copy `bk.kg` to the SD card (SD1), the disk images to `/bk`. The units AZ0..AZ3 are the F items of the OSD;
`eeprom.dat` (the AZBK settings, 510 bytes, from retro-tang-bk `soft/azbk/`) in `/bk` is the EEPROM.

Keys: Esc KT, F1 POVT, F2 VS, F3 GRAF, F5 -!->, F6 INDSU, F7 BLOK RED, F8 SHAG, F9 SBR, F10 STOP, F11 reset,
Alt AR2, right Ctrl SU, left Ctrl RUS / LAT in turn, Caps Lock STR; Alt+F4 (512 / 256) and Alt+left Ctrl (palette): the AZ hotkeys.

## Build

ISE 14.7: `cd src && make minig` (or `go`, `mini`); see [CLAUDE.md](CLAUDE.md).
