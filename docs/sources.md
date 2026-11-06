# Sources

Upstream: [lordamot/retro-tang-bk](https://github.com/lordamot/retro-tang-bk) at `b4b5850` (VERSION 0.1.28),
"BK Nano" by Sergei Lemeshev and contributors, MIT (`docs/licenses/retro-tang-bk-MIT.md`).

| Path here | From upstream | Changes |
|---|---|---|
| `src/rtl/bk/vm1/vm1_qbus_se.v` | `tang/src/bk/vm1/vm1_qbus_se.sv` | `vm1_reg_ram` / `vm1_aram` removed (SystemVerilog, built only with `VM1_CORE_REG_USES_RAM`) |
| `src/rtl/bk/vm1/vm1_se.v` | same | locals of two always blocks moved to the module (XST: no declarations in unnamed blocks) |
| `src/rtl/bk/vm1/vm1_plm.v`, `vm1_tve.v`, `vm1_vic.v` | same | none |
| `src/rtl/bk/ym2149.v` | `tang/src/bk/ym2149.sv` | Verilog-2001: locals at module level with initial values, `volTable` as a function, the three tone counters unrolled; same logic |
| `src/rtl/bk/cpu.v`, `azmap.v`, `azvideo.v`, `az_palette.v`, `azblit.v`, `azsound.v`, `azmisc.v`, `keyboard.v` | same | none |
| `src/rtl/bk/azctrl.v` | same | the MCU target (SPI target 4) replaced by the service in the FPGA: sectors through `img_sdc.v`, the clock of `kg_mcu`, the EEPROM image, the units table, the network and file answers (the header lists them); the select takes the size of the mounted image |
| `src/rtl/bk/bk_system.v` | the middle of `tang/src/top.v` | the machine without the host; `bk_sdram.v`, `bk_loader.v`, `bk_kbd.v`, `img_sdc.v` |
| `src/rtl/bk/bk_sdram.v` | after `tang/src/bk/sdram.v` | new controller for the 16-bit 32 MB chip, the same ports and priorities, no page table, no phase sweep |
| `src/rtl/bk/bk_loader.v` | after `tang/src/bk/poke.v` | the ROM bytes of `kg_mcu`, no peek |
| `src/rtl/bk/bk_kbd.v`, `bk_kbd_rom.v` (`src/tools/gen_kbd.py`) | the tables and rules of `mnano/bk.c` | PS/2 set 2 scancodes instead of USB codes |
| `src/roms/*` | `soft/azbk/ROM/*` | none (MAXIOL's AZBK ROMs, the БК-0010/0011М ROMs) |
| `src/rtl/karabas_*_top.v`, `src/karabas_*.ucf`, `.ut`, `.xst`, `src/Makefile`, `src/tools/check_osd.py` | karabas-go-core-orion128 | the board glue of this core |
| `src/sim/*` | new | verilator harness (after core-orion128 `sim_boot`) |
