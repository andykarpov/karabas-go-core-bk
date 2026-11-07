# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

БК-0011М with MAXIOL's AZBK controller (32 MB mapper, 256-colour 1024 x 768 display with three layers, blitter, two AYs, Covox, sound DMA, disk controller, EEPROM, clock; no network) on the Karabas Go, Mini and Mini G boards: Xilinx Spartan-6 XC6SLX25-2, ISE 14.7 (XST). The machine is [retro-tang-bk](https://github.com/lordamot/retro-tang-bk) `b4b5850` (Sergei Lemeshev and contributors, MIT; the VM1 is Vslav's model in Sorgelig's wrapper, GPL v2). The port is ours: `src/` holds the sources, edited directly; `docs/sources.md` lists the origin of every file and the changes to the taken ones. Plan and decisions, in Russian: `docs/PLAN.md` (phases; record a changed decision there).

Status: released 26110703 (all boards; Mini G checked on hardware, Go and Mini not). What is next: `docs/BACKLOG.md`.

## Layout

- `src/rtl/bk/`: the machine. upstream's files (`cpu.v`, `azmap.v`, `azvideo.v`, `az_palette.v`, `azblit.v`, `azsound.v`, `azmisc.v`, `keyboard.v`, `ym2149.v`, `vm1/`), `azctrl.v` with the service of the controller (what upstream's BL616 did in `mnano/azbk.c`), and ours: `bk_system.v` (the machine without the host), `bk_sdram.v` (the 32 MB SDRAM of the boards), `bk_loader.v` (the ROMs of the `.kg`), `bk_kbd.v` + `bk_kbd_rom.v` (upstream's `mnano/bk.c` on PS/2 scancodes; `src/tools/gen_kbd.py` generates the ROM).
- `src/rtl/karabas_{go,mini,minig}_top.v`: the boards (kg_pll, kg_mcu, kg_soft_switches, kg_osd_overlay, zhdmi or VGA, the DAC). `src/rtl/bk_switches.vh`: the OSD switch registers (index = position in `osd` of `core.json`, F items and the separator included). Change both together.
- `src/core.json`: kgo2, one `bk.kg` for all boards. The ROM set of upstream's `AZ.INI` is its `roms` (slot n of 4 KB at 0x40000 + n * 4096, the logo at 0x20000). F items: AZ0..AZ3 = slots 0..3 (the AZ units), AZ EEPROM = slot 4 (`eeprom.dat`, sector 0).
- `src/sim/run_bk.sh`: verilator harness (`tb_bk.v`, `sdram16_model.v` which counts SDRAM timing violations, `sim_bk.cpp` with a model of the firmware's file mounter). `--ms`, `--ppm`, `--every`, `--unit N IMAGE`, `--eeprom FILE`, `--key MS:CODES`, `+az` (controller commands), `+bus +busn=N` (bus cycles). About 15 s of wall time per 1 s of machine time. The BIOS screen is at 4 s.
- `modules/`: the git submodule [karabas-go-modules](https://github.com/andykarpov/karabas-go-modules); its rules are in `modules/CLAUDE.md`. A change there is made in `../karabas-go-modules` (branch, PR) and taken here by moving the submodule.

## Build

- `cd src && make minig` (or `go`, `mini`; no target: all boards), steps `<board>-xst`, `-impl`, `-core`, `make <board>-report`; `make bk-xst` / `bk-report`: the machine alone (fit check). The boards share `xst/` and `_ngo/`: one build at a time, in the background. Map / PAR `-t 2` (`MAP_T_<board>`).
- The `.bin` and `.kg` files of a release are committed; `build` of `core.json` is `YYMMDDNN`.

## Rules of the core

- **One clock, 65 MHz** (`clk_sys`), with enables, as upstream: no derived clocks. Only the MCU link crosses clocks; the HDMI serialiser runs on 325 MHz of the same PLL.
- **SDRAM:** `bk_sdram.v` header has the timing; the chip clock is the inverse of `clk_sys` (ODDR2), the read data is taken on the falling edge. Change the controller only with `sdram16_model.v` checked (0 errors in every run).
- **Video:** VESA 1024 x 768 at 60 Hz, negative syncs, always present.
- **Mini / Mini G: `FT_CLK_OUT` always carries a clock** (8.125 MHz, ODDR2). **Go: unused `FDC_*` outputs are 0.** SRAM unused (`MRD_N`, `MWR_N` = 1).
- **The controller's service** (`azctrl.v`): a command the BL616 served upstream is served here from images and the board's clock; DONE stays clear meanwhile. The select (001) must complete at once (upstream's lesson: AZ337 does not wait for it).
- **Verilog-2001 that XST accepts**: no declarations in unnamed blocks, no SystemVerilog. Imported code keeps its form; local changes are marked `// karabas:`.
- Upstream's `.claude/docs/` (platform.md, fpga.md, video.md) are the reference of the machine: read them there before changing a machine file. Its "traps" in CLAUDE.md apply here too.
- Before a step that needs the board or the HDMI capture, tell the user. Ask before a firmware flash.

## Memory

The Claude Code memory of this repo is shared with all karabas-go repos: `~/.claude/projects/<this project>/memory` is a symlink to `../karabas-go-notes` (private repo `andykarpov/karabas-go-notes`). Its `MEMORY.md` is split by repo; commit and push it after every memory change.
