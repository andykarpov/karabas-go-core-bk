// sim_bk: tb_bk (bk_system + a model of the SDRAM) under verilator.
//
//   sim_bk --rom FILE:ADDR ... [--core core.json is expanded by run_bk.sh] [--ms N] [--ppm OUT] [--every MS]
//          [--unit N FILE] [--eeprom FILE] [--key MS:CODE,CODE..] ... [--save-unit N OUT]
//
// The ROMs go in through bk_loader (one byte every 26 clocks) with the machine in reset. The machine then
// runs N ms of its time. --ppm writes the last frame, 1024 x 768, --every writes one each MS more
// (OUT.NNNN.ppm). --unit: the image of AZ unit N (F slot N) on a model of the file mounter of the firmware.
// --key sends PS/2 set 2 codes (hex) at a time in ms, 1 ms apart.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include "Vtb_bk.h"
#include "verilated.h"

#define CLK_KHZ 65000
static Vtb_bk *top;
static uint64_t clks = 0;
static void mcu_clk();

static void tick() {
	top->clk = 0; top->eval();
	mcu_clk();
	top->clk = 1; top->eval();
	clks++;
}

// ---- the file mounter of the firmware (docs/protocol.md section 6), as core-orion128 sim_boot: a read is
// answered with 512 bytes (one per 11 clk), the sum, the result; a write is taken with its bytes.
static std::vector<uint8_t> disks[8];
static int mcu_slot = 0;
static uint32_t mcu_lba = 0;
static int mcu_op = 0, mcu_pos = -1, mcu_gap = 0, mcu_bank = 0, mcu_wsum_parts = 0;
static int64_t mcu_wait = -1;
static uint8_t mcu_wbuf[512];
static uint16_t mcu_wsum = 0, rsum = 0;
static int mount_wait = 20000, mount_slot = 0;
static int disk_reads = 0, disk_writes = 0;
#define disk disks[mcu_slot]

static void mcu_clk() {
	top->img_q_ack = 0;
	top->img_data_wr = 0;
	top->img_result_wr = 0;
	top->img_mounted = 0;
	if (mount_slot < 8 && --mount_wait == 0) {
		mount_wait = 2000;
		if (!disks[mount_slot].empty()) {
			top->img_size = disks[mount_slot].size();
			top->img_mounted = 1 << mount_slot;
		}
		mount_slot++;
	}
	if (top->img_q_wr && !top->img_q_ack) {
		uint32_t w = top->img_q_di;
		uint8_t c = w >> 16, a = w >> 8, d = w;
		top->img_q_ack = 1;
		if (c == 0x42) {
			if (a == 0) mcu_lba = 0;
			mcu_lba |= (uint32_t)d << (8 * a);
		}
		else if (c == 0x43) {
			mcu_op = d;
			mcu_slot = a;
			mcu_wsum_parts = 0; mcu_wsum = 0;
			if (d == 1) { mcu_wait = 8000; disk_reads++; }
		}
		else if (c == 0x44 && mcu_op == 2) {
			if (a == 0) mcu_bank = d & 1;
			else if (a == 0x10) { mcu_wsum = (mcu_wsum & 0xFF00) | d; mcu_wsum_parts++; }
			else if (a == 0x11) {
				mcu_wsum = (mcu_wsum & 0x00FF) | (d << 8); mcu_wsum_parts++;
				if (mcu_wsum_parts == 2) {
					if (mcu_lba * 512ull + 512 <= disk.size()) memcpy(&disk[mcu_lba * 512ull], mcu_wbuf, 512);
					disk_writes++;
					mcu_op = 3;
					mcu_wait = 8000;
				}
			}
		}
		else if (c == 0x45 && mcu_op == 2) mcu_wbuf[mcu_bank * 256 + a] = d;
	}
	if (mcu_wait > 0) mcu_wait--;
	else if (mcu_wait == 0) {
		mcu_wait = -1;
		if (mcu_op == 1) { mcu_pos = 0; mcu_gap = 0; rsum = 0; }
		else { mcu_op = 0; top->img_result = 1; top->img_result_wr = 1; }
	}
	if (mcu_pos >= 0 && ++mcu_gap == 22) {
		mcu_gap = 0;
		if (mcu_pos < 512) {
			size_t o = mcu_lba * 512ull + mcu_pos;
			uint8_t b = o < disk.size() ? disk[o] : 0;
			rsum += b;
			top->img_data_addr = mcu_pos;
			top->img_data = b;
			top->img_data_wr = 1;
			top->img_sum = rsum;
			mcu_pos++;
		}
		else {
			mcu_pos = -1;
			mcu_op = 0;
			top->img_result = 1;
			top->img_result_wr = 1;
		}
	}
}

static std::vector<uint8_t> last(1024 * 768 * 3);
static void write_ppm(const char *name) {
	FILE *f = fopen(name, "wb");
	fprintf(f, "P6\n1024 768\n255\n");
	fwrite(last.data(), 1, last.size(), f);
	fclose(f);
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	top = new Vtb_bk;
	std::vector<std::pair<std::string, uint32_t>> roms;
	struct Key { uint64_t at; int code; };
	std::vector<Key> keys;
	int ms = 1000, every = 0;
	const char *ppm = nullptr;
	int save_n = -1; const char *save_name = nullptr;
	for (int i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--rom")) {
			std::string s = argv[++i];
			size_t c = s.rfind(':');
			roms.push_back({ s.substr(0, c), (uint32_t)strtoul(s.c_str() + c + 1, nullptr, 0) });
		}
		else if (!strcmp(argv[i], "--key")) {
			char *p = argv[++i];
			uint64_t at = strtoul(p, &p, 10) * CLK_KHZ;
			while (*p == ':' || *p == ',') { keys.push_back({ at, (int)strtoul(p + 1, &p, 16) }); at += CLK_KHZ; }
		}
		else if (!strcmp(argv[i], "--unit") || !strcmp(argv[i], "--eeprom")) {
			int n = argv[i][2] == 'e' ? 4 : atoi(argv[++i]);
			std::vector<uint8_t> &d = disks[n];
			FILE *f = fopen(argv[++i], "rb");
			if (!f) { perror(argv[i]); return 2; }
			fseek(f, 0, SEEK_END); d.resize(ftell(f)); fseek(f, 0, SEEK_SET);
			if (fread(d.data(), 1, d.size(), f) != d.size()) return 2;
			fclose(f);
		}
		else if (!strcmp(argv[i], "--save-unit")) { save_n = atoi(argv[++i]); save_name = argv[++i]; }
		else if (!strcmp(argv[i], "--ms")) ms = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--every")) every = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--ppm")) ppm = argv[++i];
		else if (argv[i][0] != '+') { fprintf(stderr, "bad option %s\n", argv[i]); return 2; }
	}
	top->img_q_ack = 0; top->img_data_wr = 0; top->img_result_wr = 0; top->img_mounted = 0;
	top->reset = 1; top->rom_wr = 0; top->scancode = 0; top->scancode_upd = 0; top->turbo = 0;
	for (int i = 0; i < 70000; i++) tick();   // the power up of the SDRAM
	uint32_t bytes = 0;
	for (auto &r : roms) {
		FILE *f = fopen(r.first.c_str(), "rb");
		if (!f) { perror(r.first.c_str()); return 2; }
		int c; uint32_t a = r.second;
		while ((c = fgetc(f)) != EOF) {
			top->rom_addr = a++; top->rom_data = c; top->rom_wr = 1; tick();
			top->rom_wr = 0;
			for (int i = 0; i < 25; i++) tick();
			bytes++;
		}
		fclose(f);
	}
	for (int i = 0; i < 400; i++) tick();
	top->reset = 0;
	uint64_t start = clks, end = clks + (uint64_t)ms * CLK_KHZ, next_ppm = every ? start + (uint64_t)every * CLK_KHZ : ~0ull;
	std::vector<uint8_t> frame(1024 * 768 * 3);
	int fx = 0, fy = 0, frames = 0, prev_de = 0, prev_vs = 0, ppm_n = 0, bad = 0;
	size_t kn = 0;
	while (clks < end) {
		tick();
		if (kn < keys.size() && clks - start >= keys[kn].at) {
			top->scancode = keys[kn++].code;
			top->scancode_upd ^= 1;
		}
		if (top->de) {
			if (fx < 1024 && fy < 768) {
				uint8_t *p = &frame[(fy * 1024 + fx) * 3];
				p[0] = top->r; p[1] = top->g; p[2] = top->b;
			}
			fx++;
		}
		if (!top->de && prev_de) { if (fx != 1024 && bad < 5) { printf("bad line: %d pixels at y %d\n", fx, fy); bad++; } fx = 0; fy++; }
		if (top->vs && !prev_vs) {
			if (frames && fy != 768 && bad < 5) { printf("bad frame: %d lines\n", fy); bad++; }
			fy = 0; fx = 0; frames++; last = frame;
			if (clks >= next_ppm && ppm) {
				char n[512]; snprintf(n, sizeof n, "%s.%04d.ppm", ppm, ppm_n++);
				write_ppm(n);
				next_ppm += (uint64_t)every * CLK_KHZ;
				printf("%s at %llu ms\n", n, (unsigned long long)((clks - start) / CLK_KHZ));
				fflush(stdout);
			}
		}
		prev_de = top->de; prev_vs = top->vs;
	}
	uint32_t sum = 0, lit = 0;
	for (size_t i = 0; i < last.size(); i++) { sum = sum * 31 + last[i]; lit += last[i] != 0; }
	printf("%d ms: %u ROM bytes, %d frames, frame sum %08x lit %u, %d sectors read %d written, sdram %u reads %u writes %u errors\n",
		ms, bytes, frames, sum, lit, disk_reads, disk_writes, top->sdr_reads, top->sdr_writes, top->sdr_errors);
	if (ppm) write_ppm(ppm);
	if (save_name) { FILE *f = fopen(save_name, "wb"); fwrite(disks[save_n].data(), 1, disks[save_n].size(), f); fclose(f); }
	int err = top->sdr_errors != 0;
	delete top;
	return err;
}
