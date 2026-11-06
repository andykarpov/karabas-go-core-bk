#!/bin/bash
# Builds sim_bk (verilator) into src/sim/build, runs it from src/ with the ROM set of core.json and the
# arguments given: run_bk.sh --ms 4000 --ppm sim/build/bios.ppm +az [--unit 0 IMAGE] [--eeprom FILE] ...
# BUILD_ONLY=1: only the build.
set -eu
H=$(cd "$(dirname "$0")" && pwd)
S=$(cd "$H/.." && pwd)
B=$H/build
mkdir -p "$B"
SRC="$H/tb_bk.v $H/sdram16_model.v $(grep -E '^verilog' "$S/bk.prj" | sed 's/verilog work "\(.*\)"/\1/' | sed "s#^#$S/#")"
verilator --language 1364-2005 --cc --exe --build -j 8 -O3 --top-module tb_bk -Mdir "$B/obj" -o sim_bk \
	-Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-PINMISSING -Wno-PINNOTFOUND \
	--x-initial fast -CFLAGS -O2 $SRC "$H/sim_bk.cpp" > "$B/build.log" 2>&1 || { tail -30 "$B/build.log"; exit 1; }
[ -z "${BUILD_ONLY:-}" ] || exit 0
cd "$S"
ROMS=$(python3 -c "
import json
for r in json.load(open('core.json'))['roms']: print('--rom', r['filename'] + ':' + hex(r['address']), end=' ')")
exec "$B/obj/sim_bk" $ROMS "$@"
