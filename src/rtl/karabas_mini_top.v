`timescale 1ns / 1ps
`default_nettype wire

/*
 BK-0011M + AZBK core for Karabas Mini before rev.G (HDMI, sigma-delta audio on AUDIO_L / AUDIO_R).
 The same as karabas_minig_top.v except the pins (as core-orion128): no PCM5102, MCU_SCK not on a clock
 pin (no IBUFG / BUFG), FT_CLK_OUT on E7 (MCU_IO<4> of the FT812 clock mod).

 Clocks: one PLL, VCO 650 MHz (50 * 13): clk_sys 65.0 MHz (/10: the machine, the SDRAM (its clock an
 ODDR2 of the inverse), 1024 x 768 at 60 Hz, the OSD, the MCU link, audio), the HDMI serial clock 325 MHz
 and its inverse (/2), clk_8 8.125 MHz (/80, FT_CLK_OUT: the FT812 must always have its clock, see
 karabas-go-notes ft-clk-out-required).
*/

module karabas_mini_top (
	input wire CLK_50MHZ,

	inout wire UART_RX,
	inout wire UART_TX,
	inout wire UART_CTS,
	inout wire ESP_RESET_N,
	inout wire ESP_BOOT_N,

	output wire [20:0] MA,
	inout wire [15:0] MD,
	output wire [1:0] MWR_N,
	output wire [1:0] MRD_N,

	output wire [1:0] SDR_BA,
	output wire [12:0] SDR_A,
	output wire SDR_CLK,
	output wire [1:0] SDR_DQM,
	output wire SDR_WE_N,
	output wire SDR_CAS_N,
	output wire SDR_RAS_N,
	inout wire [15:0] SDR_DQ,

	output wire SD_CS_N,
	output wire SD_CLK,
	output wire SD_DI,
	input wire SD_DO,
	input wire SD_DET_N,

	input wire [7:0] VGA_R,
	input wire [7:0] VGA_G,
	input wire [7:0] VGA_B,
	input wire VGA_HS,
	input wire VGA_VS,

	output wire [3:0] TMDS_P,
	output wire [3:0] TMDS_N,

	output wire FT_SPI_CS_N,
	output wire FT_SPI_SCK,
	input wire FT_SPI_MISO,
	output wire FT_SPI_MOSI,
	input wire FT_INT_N,
	input wire FT_CLK,
	input wire FT_DE,
	input wire FT_AUDIO,
	input wire FT_DISP,
	output wire FT_RESET,
	output wire FT_CLK_OUT,

	output wire [2:0] WA,
	output wire [1:0] WCS_N,
	output wire WRD_N,
	output wire WWR_N,
	output wire WRESET_N,
	inout wire [15:0] WD,

	output wire TAPE_OUT,
	input wire TAPE_IN,

	output wire AUDIO_L,
	output wire AUDIO_R,

	output wire ADC_CLK,
	inout wire ADC_BCK,
	inout wire ADC_LRCK,
	input wire ADC_DOUT,

	input wire MCU_CS_N,
	input wire MCU_SCK,
	inout wire MCU_MOSI,
	output wire MCU_MISO,
	inout wire [3:0] MCU_IO, // [1] INT of link v2, [2] sd2 cs_n, [3] ft cs_n

	output wire MIDI_TX,

	output wire MIDI_CLK,
	output wire MIDI_RESET_N,

	output wire FLASH_CS_N,
	input wire FLASH_DO,
	output wire FLASH_DI,
	output wire FLASH_SCK,
	output wire FLASH_WP_N,
	output wire FLASH_HOLD_N
);

// ------------------------------------------------------------------ unused


assign WA = 3'b000;
assign WCS_N = 2'b11;
assign WRD_N = 1'b1;
assign WWR_N = 1'b1;
assign WRESET_N = 1'b1;
assign WD = 16'bz;

assign ESP_RESET_N = 1'bz;
assign ESP_BOOT_N = 1'bz;
assign FT_RESET = 1'b1;
assign MIDI_CLK = 1'b1;
assign MIDI_RESET_N = 1'b1;
assign MIDI_TX = 1'b1;
assign UART_RX = 1'bz;
assign UART_TX = 1'bz;
assign UART_CTS = 1'bz;

assign FLASH_CS_N = 1'b1;
assign FLASH_DI = 1'b1;
assign FLASH_SCK = 1'b0;
assign FLASH_WP_N = 1'b1;
assign FLASH_HOLD_N = 1'b1;

assign ADC_CLK = 1'b0;
assign ADC_BCK = 1'bz;
assign ADC_LRCK = 1'bz;

assign MA = 21'd0;
assign MD = 16'bz;
assign MWR_N = 2'b11;
assign MRD_N = 2'b11;  // the SRAM is not used

assign TAPE_OUT = 1'b0;
// ------------------------------------------------------------------ clocks

// one PLL, VCO 650 MHz (50 * 13): clk_sys 65 MHz (/10: everything), the HDMI serial clock 325 MHz and
// its inverse (/2, 0 and 180 degrees), clk_8 8.125 MHz (/80: FT_CLK_OUT)
wire clk_sys, clk_ser, clk_ser_n, clk_8;
wire locked;
wire [5:0] pll_clk;
kg_pll #(
	.CLKIN_PERIOD(20.0),
	.DIVCLK_DIVIDE(1),
	.CLKFBOUT_MULT(13),
	.CLKOUT0_DIVIDE(10),
	.CLKOUT1_DIVIDE(2),
	.CLKOUT2_DIVIDE(2), .CLKOUT2_PHASE(180.0),
	.CLKOUT3_DIVIDE(80),
	.BUFG_MASK(6'b001111)
) pll (
	.clk_in(CLK_50MHZ),
	.rst(1'b0),
	.clk_out(pll_clk),
	.locked(locked)
);
assign clk_sys = pll_clk[0];
assign clk_ser = pll_clk[1];
assign clk_ser_n = pll_clk[2];
assign clk_8 = pll_clk[3];
wire areset = ~locked;

// the clock of the FT812: it must always have one (karabas-go-notes ft-clk-out-required)
ODDR2 oddr_ft_clk (.Q(FT_CLK_OUT), .C0(clk_8), .C1(~clk_8), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));

// the clock of the SDRAM: clk_sys inverted (bk_sdram.v says why)
ODDR2 oddr_sdr_clk (.Q(SDR_CLK), .C0(clk_sys), .C1(~clk_sys), .CE(1'b1), .D0(1'b0), .D1(1'b1), .R(1'b0), .S(1'b0));

// ------------------------------------------------------------------ MCU

wire mcu_sck = MCU_SCK, mcu_sck_ibufg = MCU_SCK;  // not on a clock pin before rev.G

// karabas: MCU link v2 (karabas-go-firmware docs/link_v2.md, kg_mcu2); INT on IO1
wire mcu_int;
assign MCU_IO[1] = mcu_int;
assign MCU_IO[0] = 1'bz;
assign MCU_IO[3:2] = 2'bzz;

`include "bk_switches.vh"
wire [7:0] kb_scancode;
wire [15:0] joy_l16, joy_r16;
wire [12:0] joy_l = joy_l16[12:0], joy_r = joy_r16[12:0];
wire [1:0] ld_kind;
wire [7:0] ld_data;
wire [31:0] ld_addr;
wire ld_active, ld_wr;
wire [SW_N*8-1:0] sw;
wire mcu_busy;
wire dvi_only;
wire ft_cs_n, ft_mosi, ft_spi_on, sd2_cs_n, sd2_mosi;
wire [7:0] img_wp;
wire [7:0] rtc_a, rtc_do;
wire [7:0] ps2_code;
wire ps2_kind, ps2_wr;
wire osd_wr, osd_en, osd_zoom;
wire [11:0] osd_waddr;
wire [7:0] osd_wdata;
wire [23:0] osd_fg, osd_bg;
wire [1:0] osd_alpha, osd_place;
wire [4:0] osd_px, osd_ph;
wire [3:0] osd_py;
wire [5:0] osd_pw;
// the AZ units and the EEPROM: the mounter of kg_mcu2 (the sector interface of img_sdc) to bk_system
wire [7:0] sdc_img_mounted, sdc_rd, sdc_wr, sdc_byte_in_data, sdc_byte_out_data;
wire [63:0] sdc_img_size;
wire [31:0] sdc_sector;
wire sdc_busy, sdc_done, sdc_error, sdc_byte_in_strobe;
wire [8:0] sdc_byte_addr;

kg_mcu2 #(
	.CAPS(16'h0004),     // write protected images
	.SW_N(SW_N),
	.CS_FILTER(3),
	.ENABLE_OSD(1),
	.ENABLE_IMG(1),      // the AZ units and the EEPROM: the images of the F items
	.IMG_OUT_LATENCY(4),
	.ENABLE_RTC(1),      // the clock of the AZ controller (rtc_mode 1: DS1307 registers)
	.RTC_SKIP_0D(0),
	.ENABLE_FT(1),
	.ENABLE_SD2(1)
) mcu (
	.CLK(clk_sys),
	.N_RESET(~areset),

	.MCU_SCK(mcu_sck),
	.MCU_MOSI(MCU_MOSI),
	.MCU_MISO(MCU_MISO),
	.MCU_SS(MCU_CS_N),
	.MCU_INT(mcu_int),
	.MCU_SPI_FT_SS(MCU_IO[3]),
	.MCU_SPI_SD2_SS(MCU_IO[2]),

	.SW(sw), .SW_WR(), .SW_INDEX(), .SW_VALUE(), .HW_ID(), .DVI_ONLY(dvi_only), .CORE_BUILD(), .FW_BUILD(),
	.BUSY(mcu_busy), .BTNS(), .RELOAD_REQ(1'b0), .RELOAD_CORE(8'd0),

	.KBD(), .KBD_WR(), .PS2_CODE(ps2_code), .PS2_KIND(ps2_kind), .PS2_WR(ps2_wr),
	.MS_X(), .MS_Y(), .MS_Z(), .MS_B(), .MS_WR(),
	.JOY_L(joy_l16), .JOY_R(joy_r16), .JOY_WR(),
	.PS2_CMD(16'h0000), .PS2_CMD_WR(1'b0),

	.LD_KIND(ld_kind), .LD_SLOT(), .LD_SIZE(), .LD_START(), .LD_ACTIVE(ld_active), .LD_END(),
	.LD_ADDR(ld_addr), .LD_DATA(ld_data), .LD_WR(ld_wr), .LD_READY(1'b1),

	.OSD_WR(osd_wr), .OSD_WADDR(osd_waddr), .OSD_WDATA(osd_wdata), .OSD_EN(osd_en),
	.OSD_FG(osd_fg), .OSD_BG(osd_bg), .OSD_ALPHA(osd_alpha), .OSD_PX(osd_px), .OSD_PY(osd_py),
	.OSD_PW(osd_pw), .OSD_PH(osd_ph), .OSD_PLACE(osd_place), .OSD_ZOOM(osd_zoom),

	.SDC_IMG_MOUNTED(sdc_img_mounted), .SDC_IMG_SIZE(sdc_img_size),
	.SDC_RD(sdc_rd), .SDC_WR(sdc_wr), .SDC_SECTOR(sdc_sector),
	.SDC_BUSY(sdc_busy), .SDC_DONE(sdc_done), .SDC_ERROR(sdc_error), .SDC_SLOT(),
	.SDC_BYTE_IN_STROBE(sdc_byte_in_strobe), .SDC_BYTE_ADDR(sdc_byte_addr),
	.SDC_BYTE_IN_DATA(sdc_byte_in_data), .SDC_BYTE_OUT_DATA(sdc_byte_out_data),
	.IMG_WP(img_wp), .IMG_PHYS_WR(), .IMG_PHYS(), .IMG_FLUSH(), .FDD_CHNG_WR(), .FDD_CHNG(),
	.FDD_CHNG_REQ(1'b0), .FDD_CHNG_DS(2'd0), .IMG_ACTIVE(),

	.PORT_OUT_DATA(), .PORT_OUT_WR(), .PORT_OUT_READY(4'b1111), .PORT_IN_DATA(32'd0), .PORT_IN_WR(4'd0),
	.PORT_CFG(128'd0), .PORT_IN_FULL(), .PORT_STAT(), .PORT_STAT_WR(),
	.RTC_A(rtc_a), .RTC_DI(8'd0), .RTC_CS(1'b0), .RTC_WR_N(1'b1), .RTC_DO(rtc_do),
	.MATRIX_CMD(24'd0), .MATRIX_CMD_WR(1'b0), .DEBUG_ADDR(16'd0), .DEBUG_DATA(16'd0),

	.FT_SPI_ON(ft_spi_on), .FT_VGA_ON(), .FT_RESET(), .FT_SCK(), .FT_MOSI(ft_mosi), .FT_MISO(FT_SPI_MISO),
	.FT_CS_N(ft_cs_n),
	.SD2_SCK(), .SD2_MOSI(sd2_mosi), .SD2_MISO(SD_DO), .SD2_CS_N(sd2_cs_n)
);

// the roms of the core file (LD kind 0) on the rom loader signals of bk_system
wire rom_active = ld_active && ld_kind == 2'd0;
wire rom_wr = ld_wr && ld_kind == 2'd0;
wire [31:0] rom_addr = ld_addr;
wire [7:0] rom_data = ld_data;

// the PS/2 scancode (set 2) as the toggle of v1 (bk_system takes a change of it)
reg kb_upd_t = 1'b0;
reg [7:0] kb_code_r = 8'd0;
always @(posedge clk_sys)
	if (ps2_wr && !ps2_kind) begin
		kb_code_r <= ps2_code;
		kb_upd_t <= ~kb_upd_t;
	end
assign kb_scancode = kb_code_r;
wire kb_scancode_upd = kb_upd_t;

assign FT_SPI_CS_N = ft_spi_on ? ft_cs_n : 1'b1;
assign FT_SPI_SCK = ft_spi_on ? mcu_sck_ibufg : 1'b1;
assign FT_SPI_MOSI = ft_spi_on ? ft_mosi : 1'b1;
assign SD_CS_N = sd2_cs_n;
assign SD_DI = sd2_mosi;
assign SD_CLK = mcu_sck_ibufg;

// ------------------------------------------------------------------ soft switches

// the index of an item = its position in "osd" of core.json, the F items and the separator included
// the switches: the SW registers of kg_mcu2 (bk_switches.vh above)
wire sw_turbo = sw[SW_CPU*8];
wire sw_joy = sw[SW_JOY*8];
wire sw_covox = sw[SW_COVOX*8];
wire [1:0] sw_volume = sw[SW_VOLUME*8 +: 2];
wire sw_reset = sw[SW_RESET*8];
wire [1:0] sw_monitor = sw[SW_MONITOR*8 +: 2];

// ------------------------------------------------------------------ the machine

wire [7:0] vid_r, vid_g, vid_b;
wire vid_hs, vid_vs, vid_de;
wire signed [15:0] audio_l, audio_r;
wire disk_busy;

bk_system #(.LINK(2)) bk (
	.clk(clk_sys),
	.lock(locked),
	.reset(sw_reset || mcu_busy || rom_active),
	.turbo(sw_turbo),
	.joy_on(sw_joy),
	.covox_714(sw_covox),
	.volume(sw_volume),
	.mono(sw_monitor == 2'd1),
	.gray(sw_monitor == 2'd2),
	.rom_wr(rom_wr),
	.rom_addr(rom_addr[24:0]),
	.rom_data(rom_data),
	.scancode(kb_scancode),
	.scancode_upd(kb_scancode_upd),
	.joy(joy_l | joy_r),
	.img_mounted(8'd0),
	.img_size(64'd0),
	.img_wp(img_wp),
	.img_data_wr(1'b0),
	.img_data_addr(9'd0),
	.img_data(8'd0),
	.img_result_wr(1'b0),
	.img_result(8'd0),
	.img_sum(16'd0),
	.img_q_wr(),
	.img_q_di(),
	.img_q_ack(1'b0),
	.sdc_img_mounted_i(sdc_img_mounted), .sdc_img_size_i(sdc_img_size), .sdc_rd_o(sdc_rd), .sdc_wr_o(sdc_wr),
	.sdc_sector_o(sdc_sector), .sdc_busy_i(sdc_busy), .sdc_done_i(sdc_done), .sdc_error_i(sdc_error),
	.sdc_byte_in_strobe_i(sdc_byte_in_strobe), .sdc_byte_addr_i(sdc_byte_addr),
	.sdc_byte_in_data_i(sdc_byte_in_data), .sdc_byte_out_data_o(sdc_byte_out_data),
	.rtc_a(rtc_a),
	.rtc_do(rtc_do),
	.hs(vid_hs),
	.vs(vid_vs),
	.de(vid_de),
	.r(vid_r),
	.g(vid_g),
	.b(vid_b),
	.audio_l(audio_l),
	.audio_r(audio_r),
	.disk_busy(disk_busy),
	.SDR_A(SDR_A),
	.SDR_BA(SDR_BA),
	.SDR_DQ(SDR_DQ),
	.SDR_RAS_N(SDR_RAS_N),
	.SDR_CAS_N(SDR_CAS_N),
	.SDR_WE_N(SDR_WE_N),
	.SDR_DQM(SDR_DQM)
);

// ------------------------------------------------------------------ OSD

// the bitmap OSD of link v2 (kg_l2_osd_overlay): centred in de, the scale from its size,
// 2 clocks of latency with its syncs and de
wire [23:0] osd_rgb;
wire osd_hs, osd_vs, osd_de;
kg_l2_osd_overlay osd (
	.wclk(clk_sys),
	.osd_wr(osd_wr), .osd_waddr(osd_waddr), .osd_wdata(osd_wdata), .osd_en(osd_en),
	.osd_fg(osd_fg), .osd_bg(osd_bg), .osd_alpha(osd_alpha), .osd_px(osd_px), .osd_py(osd_py),
	.osd_pw(osd_pw), .osd_ph(osd_ph), .osd_place(osd_place), .osd_zoom(osd_zoom),
	.icon_on(8'd0), .icon_act(8'd0),
	.clk(clk_sys),
	.rgb_i({vid_r, vid_g, vid_b}), .hs_i(vid_hs), .vs_i(vid_vs), .de_i(vid_de),
	.rgb_o(osd_rgb), .hs_o(osd_hs), .vs_o(osd_vs), .de_o(osd_de)
);

// ------------------------------------------------------------------ audio

kg_sigma_delta_dac dac_l (.clk(clk_sys), .reset(areset), .din(audio_l ^ 16'h8000), .dout(AUDIO_L));
kg_sigma_delta_dac dac_r (.clk(clk_sys), .reset(areset), .din(audio_r ^ 16'h8000), .dout(AUDIO_R));

// ------------------------------------------------------------------ HDMI

// the audio sample clock of hdmi_tx: 48 kHz of clk_sys (+ 48 per clock modulo 65000)
reg [16:0] aud_acc = 17'd0;
reg aud_stb = 1'b0;
reg [47:0] hdmi_smp = 48'd0;
always @(posedge clk_sys) begin
	aud_stb <= 1'b0;
	if (aud_acc >= 17'd65000 - 17'd48) begin
		aud_acc <= aud_acc + 17'd48 - 17'd65000;
		aud_stb <= 1'b1;
		hdmi_smp <= { audio_l, 8'd0, audio_r, 8'd0 };
	end
	else
		aud_acc <= aud_acc + 17'd48;
end

// the picture of the overlay with its syncs and de, registered together
reg hdmi_hs = 1'b0, hdmi_vs = 1'b0, hdmi_de = 1'b0;
reg [23:0] hdmi_rgb = 24'd0;
always @(posedge clk_sys) begin
	hdmi_hs <= ~osd_hs;   // 1024 x 768 at 60 Hz: negative syncs (VESA)
	hdmi_vs <= ~osd_vs;
	hdmi_de <= osd_de;
	hdmi_rgb <= osd_rgb;
end

hdmi_tx #(.SAMPLE_FREQ(48000)) hdmi (
	.clk(clk_sys),
	.sclk(clk_ser),
	.sclk_n(clk_ser_n),
	.reset(areset),
	.rgb(hdmi_rgb),
	.vsync(hdmi_vs),
	.hsync(hdmi_hs),
	.de(hdmi_de),
	.audio_en(~dvi_only),
	.audio_l(hdmi_smp[47:24]),
	.audio_r(hdmi_smp[23:0]),
	.audio_clk(aud_stb),
	.tx_clk_n(TMDS_N[3]),
	.tx_clk_p(TMDS_P[3]),
	.tx_d_n(TMDS_N[2:0]),
	.tx_d_p(TMDS_P[2:0])
);

endmodule
