# BK-0011M + AZBK core for Karabas Go / Mini / Mini G

[Русская версия](README.ru.md)

The Soviet home computer **Elektronika BK-0011M** with MAXIOL's **AZBK** controller on the Karabas Go family
boards (Xilinx Spartan-6 XC6SLX25). A port of [retro-tang-bk](https://github.com/lordamot/retro-tang-bk)
(BK Nano for the Tang Nano 20K). One core file `bk.kg` for all three boards.

Status: build 26110703. Checked on Mini G: the AZBK BIOS, ANDOS, the keyboard, the display modes, all of the
sound and the memory test; not yet run on Go and Mini. Next steps: [docs/BACKLOG.md](docs/BACKLOG.md).

## The machine

**BK-0011M** (Elektronika, 1990):

- K1801VM1 processor (PDP-11 without EIS) at 4 MHz, 8 MHz from the OSD;
- 128 KB of RAM in 16 KB pages, BASIC and BOS ROMs, register 177716 (pages, speaker, STOP);
- the BK screen: 512 x 256 monochrome or 256 x 256 in 4 colours, 16 palettes, scroll, 50 Hz interrupt;
- keyboard with RUS / LAT, AR2, SU, STOP and the reset key;
- the AY on port 177714 (the music of most BK games), the speaker.

**AZBK** (MAXIOL's controller, as its software sees it):

- **32 MB** memory mapper: 16 windows of 4 KB (177300-177352), the BK-0011M's 177716 word and the SMK-512
  modes (177130) translated, shadows, ROM pages;
- its own **1024 x 768, 60 Hz** display: 1/2/4/8 bits a point, up to three layers, stretch, scroll, a
  256-colour palette plus the legacy palette sets (177230-177256); the BK screen is shown through it;
- **blitter** (177270/177272): copy, overlay, fill, save and restore the background;
- sound: **two YM2149** (177172-177175), 16- and 8-bit **Covox** (177200-177212), **sound DMA** (16-bit PCM
  and IMA ADPCM mono / stereo, 44100 Hz), the BK speaker;
- **disk controller** (177220-177226): up to four units AZ0-AZ3 on `.img` / `.bkd` / `.dsk` images, boot
  from AZ0, interrupt at the end of a transfer;
- settings **EEPROM** (the Setup program), real time **clock** (from the board's clock);
- the **AZBK BIOS** with the machine test, the logo, Setup and the loader.

No network: the network and "hall of fame" commands answer as a controller without a cable.

## Boards

| | Karabas Go | Karabas Mini | Karabas Mini G |
|---|---|---|---|
| Video | VGA 1024 x 768 60 Hz (video DAC) | HDMI 1024 x 768 60 Hz | HDMI 1024 x 768 60 Hz |
| Sound | I2S DAC PCM5102 (line out) | HDMI, analog out (sigma-delta) | HDMI, I2S DAC PCM5102 |
| AZBK memory | 32 MB SDRAM | 32 MB SDRAM | 32 MB SDRAM |
| Keyboard, joystick | USB (through the board's MCU) | USB | USB |
| Disk images, EEPROM | SD card (SD1) | SD1 | SD1 |
| Clock | board RTC | board RTC | board RTC |

Not used: the board's SRAM, the second SD card, the floppy connector of the Go (outputs off), tape, UART,
MIDI, the FT812 (on Mini / Mini G it only gets its clock).

## What goes where

- **SD card (SD1)**, FAT32 or exFAT:
  - `bk.kg` in the root (next to the other cores);
  - the `/bk` folder: disk images and `eeprom.dat`. A ready set is in [sd/bk](sd/bk) of this repository:
    copy the whole folder.
- **Monitor**: HDMI (Mini, Mini G) or VGA (Go). 1024 x 768 at 60 Hz, VESA syncs.
- **Sound**: HDMI, the board's headphone / line out.
- **USB**: keyboard, gamepad (through a hub to use both).
- The ROMs (AZBOOT, the AZ library, the disk controller ROM, the BK-0011M and BK-0010 ROMs, Setup, the logo)
  are inside `bk.kg`: nothing else to copy. Stock MCU firmware with `.kg` support.

## First start

1. Copy `bk.kg` and the `sd/bk` folder to the card, pick **BK-0011M** in the boot menu.
2. The machine starts by itself: first about 64 short beeps and a reset (AZBOOT's first pass, by design),
   then the blue AZBK BIOS screen with the hardware test, the date and "Press KT to run Setup": Esc (KT)
   opens Setup.
3. After about 10 seconds ANDOS boots from AZ0 (`WRKANDOS2.IMG` by default): the splash, Space, then the
   two-panel shell. Run a program by typing its name at the `A>` line or Enter on the file.
4. Another disk: the OSD (Menu + Esc), item AZ0 (or Menu+F1), an image from `/bk`, then Reset.

## OSD

| Item | Hotkey | |
|---|---|---|
| AZ0 .. AZ3 | Menu+F1 .. Menu+F4 | the images of units AZ0-AZ3 (`.img`, `.bkd`, `.dsk` from `/bk`); boot from AZ0 |
| AZ EEPROM | | the controller settings file (`/bk/eeprom.dat`, 510 bytes); without it Setup is not saved |
| CPU | Menu+C | 4 MHz / 8 MHz |
| Joystick | | gamepad on port 177714 (up 1, right 2, down 4, left 10, A 20, fire 40, fire 2 100, B 200) |
| Covox 177714 | | the legacy Covox on 177714: Off (default, otherwise the AY music of games crackles) / AZ setup |
| Volume | Menu+V | off, 25 %, 50 %, 100 % |
| Display | Menu+M | Color / Grayscale (everything in grey) / Mono (the 4-colour BK screen as on a monochrome monitor, 512 points) |
| Reset | Menu+F12 | machine reset (AZ cold reset) |

## Keyboard

| PC key | BK | PC key | BK |
|---|---|---|---|
| Esc | KT | F9 | SBR (clear screen) |
| F1 | POVT | F10 | STOP |
| F2 | VS | F11 | the reset key |
| F3 | GRAF | Insert / Delete | \|--> / \|<-- |
| F5 | -!-> | Home, PgUp, End, PgDn | diagonal arrows |
| F6 | IND SU | Alt | AR2 |
| F7 | BLOK RED | right Ctrl | SU |
| F8 | SHAG | left Ctrl | RUS / LAT in turn |
| Shift+Enter | UST TAB | Caps Lock | STR |
| Shift+Tab | SBR TAB | Alt+F4 | BK screen: 512 mono / 256 colour (AZ hotkey) |
| | | Alt+left Ctrl | default palettes (AZ hotkey) |

In RUS the keys `[ ] \ ^ @ }` give Ш Щ Э Ч Ю Ъ, as the BK keyboard does. Win (Menu) belongs to the board
firmware.

## Demo software ([sd/bk](sd/bk))

The disks of the AZBK package from retro-tang-bk (MAXIOL and the program authors):

| File | What |
|---|---|
| `WRKANDOS2.IMG` | ANDOS 3.30 work disk: shell, utilities, BASIC, debuggers, `AY_TEST` (AY test, GID). AZ0 by default |
| `SNDTEST.IMG` | the same disk plus retro-tang-bk's sound and memory tests: `SPKTEST` speaker, `AYTEST` both AYs, `AY714` the AY through 177714, `COVTEST` Covox, `DMATEST` sound DMA, `MEMTEST` AZ memory (7 MB, a key stops it) |
| `AZKV.BKD` | AZ disk: blitter tests `blttst*`, graphics demos `gdemo*` |
| `GAMES1.IMG` | ANDOS with BK games (Ninja, Sheriff, Super War and others) |
| `toolkit.img` | ANDOS with the Dangerous Dave level tools (`NLAB`, `DAVEBL`, tiles, animations) |
| `MKDOS317.IMG` | MKDOS 3.17 system disk |
| `rt11bk.DSK` | RT-11 for the BK |
| `eeprom.dat` | AZBK controller settings (BK11 mode off, YM2149, Covox stereo, 48 Hz timer) |

Dangerous Dave in the Haunted Mansion (grf, 2025) is not included: download the image from hof.maxiol.com
after registering, put it in `/bk` and select it as AZ0.

## Limitations

- No network, screenshot (command 044), RS-232, tape.
- The controller's file-by-name commands (047, 050-055), directory (003 / 013) and mounting from a program
  (004 / 014) answer an error: the Karabas firmware gives the core no files by name. Images are chosen in
  the OSD.
- A clock set by a program (034) is not written to the board's clock.
- The processor runs faster than a real BK (the BIOS says "6MHz"): the BK memory wait states are not
  modelled.
- The BK-0010 mode (its ROMs are there) is untested.
- Writes to disk images and the EEPROM are not yet checked on a board.

## Authors

- **The machine**: [retro-tang-bk](https://github.com/lordamot/retro-tang-bk) (BK Nano), **Sergei Lemeshev**
  and contributors, MIT ([docs/licenses/retro-tang-bk-MIT.md](docs/licenses/retro-tang-bk-MIT.md)); the
  K1801VM1 model by Vslav (1801BM1@gmail.com) in Sorgelig's wrapper of the MiSTer BK0011M core (GPL v2);
  YM2149 by MikeJ and Sorgelig (BSD-style notice in the file). The AZBK behaviour follows GID's BKemu and
  MAXIOL's documentation on forum.maxiol.com.
- **AZBK**, its ROMs and the disk package: MAXIOL; the BK-0010 / BK-0011M ROMs: Elektronika.
- **The port to Karabas** and the board modules [karabas-go-modules](https://github.com/andykarpov/karabas-go-modules):
  Andy Karpov and contributors.

Origin of every file: [docs/sources.md](docs/sources.md). Port plan and decisions: [docs/PLAN.md](docs/PLAN.md).

## License

GPL-3.0-or-later as a whole, see [LICENSE](LICENSE); each file keeps its own header. The ROMs in `src/roms`
and the images in `sd/bk` are unchanged data of their owners.

## Build

ISE 14.7: `cd src && make minig` (or `go`, `mini`; no target: all three), result `src/bk.kg`. Machine
simulation: `src/sim/run_bk.sh --ms 4000 --ppm sim/build/bios.ppm` (Verilator). More: [CLAUDE.md](CLAUDE.md).
