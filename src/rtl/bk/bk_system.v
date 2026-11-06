`timescale 1ns / 1ps
//========================================================================
// bk_system.v - the machine: a БК-0011М with an AZBK. The middle of
// retro-tang-bk's top.v: the processor and its bus, the memory path, the
// mapper, the display, the blitter, the sound, the controller. The host
// is in the tops of the boards (the PLL, kg_mcu, the OSD, HDMI).
//
// One clock, as upstream: 65 MHz (the VESA pixel clock of 1024 x 768 at
// 60 Hz; upstream 64.8), the processor at enables every sixteen clocks
// (4.06 MHz, eight in turbo), the AY at an enable every 38.
//
// Differences from upstream's top.v:
//   - the memory is bk_sdram.v, the 32 MB straight, no page table;
//   - the ROM set comes from the .kg (roms of core.json, kg_mcu ROMLOAD_*)
//     into bk_loader.v, at the addresses upstream's firmware uses;
//   - azctrl.v serves the commands of upstream's BL616 itself, on the
//     images of the F items (img_sdc.v) and the clock of kg_mcu;
//   - the keyboard is bk_kbd.v, upstream's mnano/bk.c in RTL.
//========================================================================
module bk_system (
    input             clk,
    input             lock,         // the PLL
    input             reset,        // a level: the machine held
    input             turbo,        // 8 MHz
    input             joy_on,
    input             covox_714,    // the legacy Covox on 177714
    input      [1:0]  volume,

    // the ROM set
    input             rom_wr,
    input      [24:0] rom_addr,
    input      [7:0]  rom_data,

    input      [7:0]  scancode,
    input             scancode_upd,
    input      [12:0] joy,          // kg_mcu: up, down, left, right, start, a, b, c in bits 1..8

    // the images, kg_mcu
    input      [7:0]  img_mounted,
    input      [63:0] img_size,
    input      [7:0]  img_wp,
    input             img_data_wr,
    input      [8:0]  img_data_addr,
    input      [7:0]  img_data,
    input             img_result_wr,
    input      [7:0]  img_result,
    input      [15:0] img_sum,
    output            img_q_wr,
    output     [23:0] img_q_di,
    input             img_q_ack,

    // the clock of the board, kg_mcu
    output     [7:0]  rtc_a,
    input      [7:0]  rtc_do,

    output            hs,           // positive
    output            vs,
    output            de,
    output     [7:0]  r,
    output     [7:0]  g,
    output     [7:0]  b,

    output reg signed [15:0] audio_l = 16'sd0,
    output reg signed [15:0] audio_r = 16'sd0,

    output            disk_busy,

    output     [12:0] SDR_A,
    output     [1:0]  SDR_BA,
    inout      [15:0] SDR_DQ,
    output            SDR_RAS_N,
    output            SDR_CAS_N,
    output            SDR_WE_N,
    output     [1:0]  SDR_DQM
);

//------------------------------------------------------------------------
// Resets. Every one of them is a COLD reset of the AZ controller too, the
// STM32's HALT sequence on the real board, which maps the start ROM in
// and clears the mapper's modes (upstream's top.v).
//------------------------------------------------------------------------
wire init;
wire az_reset, key_reset;

reg  [19:0] rst_hold = 20'd0;    // a pulse request held for 16 ms
wire        rst_pulse = az_reset | key_reset;
always @(posedge clk) begin
    if (rst_pulse) rst_hold <= 20'hFFFFF;
    else if (rst_hold != 20'd0) rst_hold <= rst_hold - 20'd1;
end
reg  cpu_rst_req = 1'b1;
always @(posedge clk) cpu_rst_req <= reset | ~init | (rst_hold != 20'd0);
reg  cpu_rst_d = 1'b0;           // 0: the power up is a cold reset too
always @(posedge clk) cpu_rst_d <= cpu_rst_req;
wire cold = cpu_rst_req && !cpu_rst_d;     // one clock at the start of every reset

//------------------------------------------------------------------------
// The processor and its bus
//------------------------------------------------------------------------
wire        ce_bus, cpu_init;
wire [15:0] b_adr, b_dout;
wire        b_sync, b_stb, b_we, b_wr_stb, b_rd_stb;
wire [1:0]  b_wtbt;
wire        irq2, key_stop, key_down, stop_block;
wire [2:0]  vreq, vack;
wire        sel1_wr, sel2_wr, sel1_start, sel1_bk11;
wire [15:0] port_din;

wire [15:0] d_kbd, d_map, d_vid, d_blt, d_snd, d_ctl, d_msc, d_mem;
wire        a_kbd, a_map, a_vid, a_blt, a_snd, a_ctl, a_msc, a_mem;

cpu cpu1 (
    .clk(clk), .reset_req(cpu_rst_req), .turbo(turbo),
    .ce_bus(ce_bus), .init(cpu_init),
    .addr(b_adr), .dout(b_dout), .sync(b_sync), .stb(b_stb), .we(b_we), .wtbt(b_wtbt),
    .wr_stb(b_wr_stb), .rd_stb(b_rd_stb),
    .din(d_kbd | d_map | d_vid | d_blt | d_snd | d_ctl | d_msc | d_mem),
    .ack(a_kbd | a_map | a_vid | a_blt | a_snd | a_ctl | a_msc | a_mem),
    .irq1(key_stop && !stop_block), .irq2(irq2),
    .vreq(vreq), .vack(vack),
    .start_addr(sel1_start ? 8'o360 : sel1_bk11 ? 8'o300 : 8'o200), .key_down(key_down),   // 170000 at a start, then 140000 or 100000 (GID's AZ_716_Out)
    .sel1_wr(sel1_wr), .stop_block(stop_block),
    .port_din(port_din), .sel2_wr(sel2_wr),
    .pc_dbg()
);

//------------------------------------------------------------------------
// The memory: every address below 177000 through the mapper into the
// SDRAM. A cycle is one request; the acknowledge is a level from the
// data's arrival (or the write's acceptance) to the strobe's end. A
// window the mapper does not allow gets no acknowledge, and the
// processor times out through vector 4.
//------------------------------------------------------------------------
wire        is_io  = (b_adr[15:9] == 7'b1111111);   // 177000-177777
wire        is_mem = b_sync && !is_io;
wire [12:0] mpage;
wire        rd_ok, wr_ok, wr_drop;
wire [15:0] map_rdata;
wire [15:0] mapper_ctrl;

// the processor has taken its start address: the end of a read of 177716
// (cleared at the strobe's start, the word would change under the read)
reg  b_stb_d = 1'b0;
always @(posedge clk) b_stb_d <= b_stb;
wire sel1_rd_end = b_stb_d && !b_stb && !b_we && (b_adr[15:1] == (16'o177716 >> 1));

azmap map (
    .clk(clk), .cold(cold),
    .wr_stb(b_wr_stb), .wr_adr(b_adr), .wr_data(b_dout), .wr_wtbt(b_wtbt),
    .adr(b_adr), .page(mpage), .rd_ok(rd_ok), .wr_ok(wr_ok), .wr_drop(wr_drop),
    .rd_reg({1'b0, b_adr[5:1]}), .rd_data(map_rdata),   // (adr - 177300) >> 1: bit 6 is 177300's own
    .mapper_ctrl(mapper_ctrl), .sel1_rd(sel1_rd_end),
    .sel1_start(sel1_start), .sel1_bk11(sel1_bk11)
);

wire        sel_mapr = b_sync && (b_adr[15:6] == (16'o177300 >> 6)) && (b_adr[5:1] <= 5'd21);   // 177300-177352
assign d_map = sel_mapr ? map_rdata : 16'd0;
assign a_map = b_stb && (b_sync && ((b_adr[15:5] == (16'o177300 >> 5)) || (b_adr[15:4] == (16'o177340 >> 4))));   // 177300-177356, writes too

wire [23:0] mem_word = {mpage, b_adr[11:1]};
wire        c_req, c_take, c_ack;
wire [31:0] c_rdata;
reg         mem_pend = 1'b0, mem_done = 1'b0;
reg  [15:0] mem_rdata = 16'd0;
wire        mem_ok = b_we ? wr_ok : rd_ok;
wire        mem_go = is_mem && b_stb && mem_ok;
wire        mem_drop = is_mem && b_stb && b_we && wr_drop;   // answered, not written (ROM)

always @(posedge clk) begin
    if (!b_stb) begin mem_pend <= 1'b0; mem_done <= 1'b0; end
    else if (mem_go && !mem_pend && !mem_done) mem_pend <= 1'b1;
    else if (mem_drop) mem_done <= 1'b1;
    if (c_take) mem_pend <= 1'b0;
    if (c_ack) begin
        mem_done <= 1'b1;
        mem_rdata <= mem_word[0] ? c_rdata[31:16] : c_rdata[15:0];
    end
end
assign c_req = mem_pend;
assign a_mem = mem_done;
assign d_mem = (is_mem && mem_done && !b_we) ? mem_rdata : 16'd0;

wire        v_req, v_take, v_dv;
wire [22:0] v_adr;
wire [31:0] v_rdata;
wire        bl_req, bl_we, bl_take, bl_ack;
wire [22:0] bl_adr;
wire [31:0] bl_wdata, bl_rdata;
wire [3:0]  bl_wmask;
wire        dm_req, dm_take, dm_ack;
wire [22:0] dm_adr;
wire [31:0] dm_rdata;
wire        p_req, p_take;
wire [22:0] p_adr;
wire [31:0] p_wdata;
wire [3:0]  p_wmask;

bk_sdram mem (
    .clk(clk), .lock(lock), .init(init),
    .v_req(v_req), .v_adr(v_adr), .v_take(v_take), .v_dv(v_dv), .v_rdata(v_rdata),
    .c_req(c_req), .c_we(b_we), .c_adr(mem_word[23:1]),
    .c_wdata({b_dout, b_dout}), .c_wmask(mem_word[0] ? {b_wtbt, 2'b00} : {2'b00, b_wtbt}),
    .c_take(c_take), .c_ack(c_ack), .c_rdata(c_rdata),
    .b_req(bl_req), .b_we(bl_we), .b_adr(bl_adr), .b_wdata(bl_wdata), .b_wmask(bl_wmask),
    .b_take(bl_take), .b_ack(bl_ack), .b_rdata(bl_rdata),
    .d_req(dm_req), .d_adr(dm_adr), .d_take(dm_take), .d_ack(dm_ack), .d_rdata(dm_rdata),
    .p_req(p_req), .p_adr(p_adr), .p_wdata(p_wdata), .p_wmask(p_wmask), .p_take(p_take),
    .SDRAM_A(SDR_A), .SDRAM_BA(SDR_BA), .SDRAM_DQ(SDR_DQ),
    .SDRAM_nRAS(SDR_RAS_N), .SDRAM_nCAS(SDR_CAS_N), .SDRAM_nWE(SDR_WE_N), .SDRAM_DQM(SDR_DQM)
);

bk_loader loader (
    .clk(clk), .reset(~lock),
    .stb(rom_wr), .adr(rom_addr), .data(rom_data),
    .p_req(p_req), .p_adr(p_adr), .p_wdata(p_wdata), .p_wmask(p_wmask), .p_take(p_take)
);

//------------------------------------------------------------------------
// The keyboard, the display, the blitter, the sound, the controller
//------------------------------------------------------------------------
wire [7:0] kbd_code, kbd_flags;
wire       kbd_stb;
wire [1:0] hotkey;

bk_kbd kbd_host (
    .clk(clk), .scancode(scancode), .scancode_upd(scancode_upd),
    .key_code(kbd_code), .key_flags(kbd_flags), .key_stb(kbd_stb)
);

keyboard kbd (
    .clk(clk), .reset(cpu_init),
    .sync(b_sync), .adr(b_adr), .stb(b_stb), .we(b_we), .wtbt(b_wtbt), .din(b_dout),
    .dout(d_kbd), .ack(a_kbd),
    .key_code(kbd_code), .key_flags(kbd_flags), .key_stb(kbd_stb),
    .key_down(key_down), .key_stop(key_stop), .key_reset(key_reset), .hotkey(hotkey),
    .req60(vreq[0]), .ack60(vack[0]), .req274(vreq[1]), .ack274(vack[1])
);

wire frame_end;

azvideo vid (
    .clk(clk),
    .sync(b_sync), .adr(b_adr), .stb(b_stb), .we(b_we), .wtbt(b_wtbt), .din(b_dout),
    .dout(d_vid), .ack(a_vid), .wr_stb(b_wr_stb),
    .mapper_ctrl(mapper_ctrl), .cold(cold), .hotkey(hotkey),
    .v_req(v_req), .v_adr(v_adr), .v_take(v_take), .v_dv(v_dv), .v_rdata(v_rdata),
    .hs(hs), .vs(vs), .de(de), .r(r), .g(g), .b(b),
    .frame_end(frame_end), .irq2(irq2), .reg664_out(), .scr_csr_out()
);

azblit blt (
    .clk(clk), .cold(cold),
    .sync(b_sync), .adr(b_adr), .stb(b_stb), .we(b_we), .din(b_dout),
    .dout(d_blt), .ack(a_blt), .wr_stb(b_wr_stb),
    .frame_end(frame_end),
    .b_req(bl_req), .b_we(bl_we), .b_adr(bl_adr), .b_wdata(bl_wdata), .b_wmask(bl_wmask),
    .b_take(bl_take), .b_ack(bl_ack), .b_rdata(bl_rdata)
);

wire signed [15:0] snd_l, snd_r;
azsound snd (
    .clk(clk), .reset(cpu_init),
    .sync(b_sync), .adr(b_adr), .stb(b_stb), .we(b_we), .wtbt(b_wtbt), .din(b_dout),
    .dout(d_snd), .ack(a_snd), .wr_stb(b_wr_stb),
    .sel2_wr(sel2_wr), .sel1_wr(sel1_wr), .cpu_dout(b_dout), .cpu_wtbt(b_wtbt),
    .covox_714(covox_714),
    .d_req(dm_req), .d_adr(dm_adr), .d_take(dm_take), .d_ack(dm_ack), .d_rdata(dm_rdata),
    .out_l(snd_l), .out_r(snd_r)
);

// the OSD's volume divides the mix down
always @(posedge clk)
    case (volume)
        2'b00: begin audio_l <= 16'sd0;      audio_r <= 16'sd0;      end
        2'b01: begin audio_l <= snd_l >>> 2; audio_r <= snd_r >>> 2; end
        2'b10: begin audio_l <= snd_l >>> 1; audio_r <= snd_r >>> 1; end
        2'b11: begin audio_l <= snd_l;       audio_r <= snd_r;       end
    endcase

// the images of the F items: units 0..3 on slots 0..3, the EEPROM on slot 4
wire [7:0]  sdc_img_mounted;
wire [63:0] sdc_img_size;
wire [7:0]  sdc_rd, sdc_wr;
wire [31:0] sdc_sector;
wire        sdc_busy, sdc_done, sdc_error, sdc_byte_in_strobe;
wire [8:0]  sdc_byte_addr;
wire [7:0]  sdc_byte_in_data, sdc_byte_out_data;

img_sdc #(.OUT_LATENCY(4), .TIMEOUT(24'd13000000)) sdc (   // ~200 ms at 65 MHz
    .clk(clk), .reset(~lock),
    .img_mounted(img_mounted), .img_size(img_size),
    .img_data_wr(img_data_wr), .img_data_addr(img_data_addr), .img_data(img_data),
    .img_result_wr(img_result_wr), .img_result(img_result), .img_sum(img_sum),
    .img_q_wr(img_q_wr), .img_q_di(img_q_di), .img_q_ack(img_q_ack),
    .sdc_img_mounted(sdc_img_mounted), .sdc_img_size(sdc_img_size),
    .sdc_rd(sdc_rd), .sdc_wr(sdc_wr), .sdc_sector(sdc_sector),
    .sdc_busy(sdc_busy), .sdc_done(sdc_done), .sdc_error(sdc_error), .sdc_slot(),
    .sdc_byte_in_strobe(sdc_byte_in_strobe), .sdc_byte_addr(sdc_byte_addr),
    .sdc_byte_in_data(sdc_byte_in_data), .sdc_byte_out_data(sdc_byte_out_data),
    .active()
);

azctrl ctl (
    .clk(clk), .cold(cold),
    .sync(b_sync), .adr(b_adr), .stb(b_stb), .we(b_we), .din(b_dout),
    .dout(d_ctl), .ack(a_ctl), .wr_stb(b_wr_stb), .rd_stb(b_rd_stb),
    .virq174(vreq[2]), .vack174(vack[2]), .az_reset(az_reset),
    .img_mounted(sdc_img_mounted), .img_size(sdc_img_size), .img_wp(img_wp),
    .sdc_rd(sdc_rd), .sdc_wr(sdc_wr), .sdc_sector(sdc_sector),
    .sdc_busy(sdc_busy), .sdc_done(sdc_done), .sdc_error(sdc_error),
    .sdc_byte_in_strobe(sdc_byte_in_strobe), .sdc_byte_addr(sdc_byte_addr),
    .sdc_byte_in_data(sdc_byte_in_data), .sdc_byte_out_data(sdc_byte_out_data),
    .rtc_a(rtc_a), .rtc_do(rtc_do),
    .busy(disk_busy)
);

azmisc msc (
    .clk(clk),
    .sync(b_sync), .adr(b_adr), .stb(b_stb), .we(b_we), .din(b_dout),
    .dout(d_msc), .ack(a_msc), .wr_stb(b_wr_stb)
);

//------------------------------------------------------------------------
// The joystick on 177714, GID's default bits: up 1, right 2, down 4,
// left 10, A 20, fire 40, alt fire 100, B 200.
//------------------------------------------------------------------------
assign port_din = joy_on ? {8'd0, joy[8], joy[7], joy[6], joy[5], joy[3], joy[2], joy[4], joy[1]} : 16'd0;

endmodule
