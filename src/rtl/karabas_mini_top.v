`timescale 1ns / 1ps
`default_nettype wire

/*
 BK-0011M + AZBK core for Karabas Mini before rev.G (HDMI, sigma-delta audio on AUDIO_L / AUDIO_R).
 The same as karabas_minig_top.v except the pins (as core-orion128): no PCM5102, MCU_SCK not on a clock
 pin (bursts at the link clock, no IBUFG / BUFG), FT_CLK_OUT on E7 (MCU_IO<4> of the FT812 clock mod).

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
	inout wire [3:0] MCU_IO, // [0] burst cs_n, [1] burst ready, [2] sd2 cs_n, [3] ft cs_n

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
wire mcu_burst_ready;
assign MCU_IO[1] = mcu_burst_ready;
assign MCU_IO[0] = 1'bz;
assign MCU_IO[3:2] = 2'bzz;

wire [7:0] kb_scancode;
wire kb_scancode_upd;
wire [12:0] joy_l, joy_r;
wire rom_active, rom_wr;
wire [31:0] rom_addr;
wire [7:0] rom_data;
wire [15:0] softsw_command, osd_command;
wire mcu_busy;
wire dvi_only;
wire ft_cs_n, ft_mosi, ft_spi_on, sd2_cs_n, sd2_mosi;
wire [7:0] img_mounted, img_data, img_result, img_wp;
wire [63:0] img_size;
wire img_data_wr, img_result_wr, img_q_wr, img_q_ack;
wire [8:0] img_data_addr;
wire [15:0] img_sum;
wire [23:0] img_q_di;
wire [7:0] rtc_a, rtc_do;

kg_mcu #(
	.BURST_MAX_MHZ(0),  // MCU_SCK is not on a clock pin before rev.G: bursts at the link clock
	.CS_FILTER(3),
	.ENABLE_RTC(1),      // the clock of the AZ controller (rtc_mode 1: DS1307 registers)
	.RTC_SKIP_0D(0),
	.ENABLE_UART(0),
	.ENABLE_MATRIX(0),
	.ENABLE_DEBUG(0),
	.ENABLE_IMG(1),      // the AZ units and the EEPROM: the images of the F items
	.ENABLE_IMG_WP(1),
	.ENABLE_FILE(0),
	.ENABLE_FT(1),
	.ENABLE_SD2(1)
) mcu (
	.CLK(clk_sys),
	.N_RESET(~areset),

	.MCU_MOSI(MCU_MOSI),
	.MCU_MISO(MCU_MISO),
	.MCU_SCK(mcu_sck),
	.MCU_SS(MCU_CS_N),
	.MCU_SPI_FT_SS(MCU_IO[3]),
	.MCU_SPI_SD2_SS(MCU_IO[2]),
	.MCU_BURST_CS_N(MCU_IO[0]),
	.MCU_BURST_READY(mcu_burst_ready),

	.KB_SCANCODE(kb_scancode),
	.KB_SCANCODE_UPD(kb_scancode_upd),
	.JOY_L(joy_l),
	.JOY_R(joy_r),

	.ROMLOADER_ACTIVE(rom_active),
	.ROMLOAD_ADDR(rom_addr),
	.ROMLOAD_DATA(rom_data),
	.ROMLOAD_WR(rom_wr),

	.FILELOAD_ACTIVE(),
	.FILELOAD_ADDR(),
	.FILELOAD_DATA(),
	.FILELOAD_WR(),
	.FILELOAD_SLOT(),

	.SOFTSW_COMMAND(softsw_command),
	.OSD_COMMAND(osd_command),
	.BUSY(mcu_busy),

	.FT_SPI_ON(ft_spi_on),
	.FT_CS_N(ft_cs_n),
	.FT_MOSI(ft_mosi),
	.FT_MISO(FT_SPI_MISO),
	.FT_SCK(),
	.SD2_CS_N(sd2_cs_n),
	.SD2_MOSI(sd2_mosi),
	.SD2_MISO(SD_DO),
	.SD2_SCK(),

	.DVI_ONLY(dvi_only),

	.RTC_A(rtc_a),
	.RTC_DI(8'h00),
	.RTC_DO(rtc_do),
	.RTC_CS(1'b0),
	.RTC_WR_N(1'b1),
	.IMG_MOUNTED(img_mounted),
	.IMG_SIZE(img_size),
	.IMG_WP(img_wp),
	.IMG_DATA_WR(img_data_wr),
	.IMG_DATA_ADDR(img_data_addr),
	.IMG_DATA(img_data),
	.IMG_RESULT_WR(img_result_wr),
	.IMG_RESULT(img_result),
	.IMG_SUM(img_sum),
	.IMG_Q_WR(img_q_wr),
	.IMG_Q_DI(img_q_di),
	.IMG_Q_ACK(img_q_ack),

	// not used by this core
	.PS2_COMMAND(16'h0000),
	.PS2_COMMAND_WR(1'b0),
	.UART_RX_DATA(),
	.UART_RX_IDX(),
	.UART_TX_DATA(8'h00),
	.UART_TX_WR(1'b0),
	.UART_TX_MODE(1'b0),
	.UART_DLM(8'h00),
	.UART_DLL(8'h00),
	.UART_DLM_WR(1'b0),
	.UART_DLL_WR(1'b0),
	.MATRIX_CMD(24'h000000),
	.MATRIX_CMD_WR(1'b0),
	.DEBUG_ADDR(16'h0000),
	.DEBUG_DATA(16'h0000),
	.ESP_UART_RX_DATA(8'h00),
	.ESP_UART_RX_WR(1'b0),
	.FLASHBOOT_START(1'b0),
	.FLASHBOOT_COREID(5'd0)
);

assign FT_SPI_CS_N = ft_spi_on ? ft_cs_n : 1'b1;
assign FT_SPI_SCK = ft_spi_on ? mcu_sck_ibufg : 1'b1;
assign FT_SPI_MOSI = ft_spi_on ? ft_mosi : 1'b1;
assign SD_CS_N = sd2_cs_n;
assign SD_DI = sd2_mosi;
assign SD_CLK = mcu_sck_ibufg;

// ------------------------------------------------------------------ soft switches

// the index of an item = its position in "osd" of core.json, the F items and the separator included
`include "bk_switches.vh"
wire [SW_N*8-1:0] sw;
kg_soft_switches #(.N(SW_N)) soft_switches (
	.clk(clk_sys),
	.command(softsw_command),
	.regs(sw),
	.upd()
);
wire sw_turbo = sw[SW_CPU*8];
wire sw_joy = sw[SW_JOY*8];
wire sw_covox = sw[SW_COVOX*8];
wire [1:0] sw_volume = sw[SW_VOLUME*8 +: 2];
wire sw_reset = sw[SW_RESET*8];

// ------------------------------------------------------------------ the machine

wire [7:0] vid_r, vid_g, vid_b;
wire vid_hs, vid_vs, vid_de;
wire signed [15:0] audio_l, audio_r;
wire disk_busy;

bk_system bk (
	.clk(clk_sys),
	.lock(locked),
	.reset(sw_reset || mcu_busy || rom_active),
	.turbo(sw_turbo),
	.joy_on(sw_joy),
	.covox_714(sw_covox),
	.volume(sw_volume),
	.rom_wr(rom_wr),
	.rom_addr(rom_addr[24:0]),
	.rom_data(rom_data),
	.scancode(kb_scancode),
	.scancode_upd(kb_scancode_upd),
	.joy(joy_l | joy_r),
	.img_mounted(img_mounted),
	.img_size(img_size),
	.img_wp(img_wp),
	.img_data_wr(img_data_wr),
	.img_data_addr(img_data_addr),
	.img_data(img_data),
	.img_result_wr(img_result_wr),
	.img_result(img_result),
	.img_sum(img_sum),
	.img_q_wr(img_q_wr),
	.img_q_di(img_q_di),
	.img_q_ack(img_q_ack),
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

// 1024 x 768: the counters start at the leading edge of the syncs (1048 pixels / 771 lines into the
// frame), a step is two pixels / lines (V_DIV4_HEIGHT above the 806 lines of the frame): the OSD
// (512 x 416) in the middle starts 296 + 256 pixels and 35 + 176 lines after them
wire [23:0] osd_rgb;
kg_osd_overlay #(.H_OFFSET(276), .V_OFFSET(105), .H_DIV4_WIDTH(1400), .V_DIV4_HEIGHT(900)) osd (
	.clk(clk_sys),
	.rgb_i({vid_r, vid_g, vid_b}),
	.rgb_o(osd_rgb),
	.hsync_i(vid_hs),
	.vsync_i(vid_vs),
	.v_offset(11'd0),
	.h_offset(11'd0),
	.osd_command(osd_command)
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

// osd_rgb is one clock behind the syncs of the overlay's input: the syncs and de go with it
reg hdmi_hs = 1'b0, hdmi_vs = 1'b0, hdmi_de = 1'b0;
always @(posedge clk_sys) begin
	hdmi_hs <= ~vid_hs;   // 1024 x 768 at 60 Hz: negative syncs (VESA)
	hdmi_vs <= ~vid_vs;
	hdmi_de <= vid_de;
end

hdmi_tx #(.SAMPLE_FREQ(48000)) hdmi (
	.clk(clk_sys),
	.sclk(clk_ser),
	.sclk_n(clk_ser_n),
	.reset(areset),
	.rgb(osd_rgb),
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
