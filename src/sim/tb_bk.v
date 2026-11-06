`timescale 1ns / 1ps
// bk_system with a model of the SDRAM and the clock of the board, for sim_bk.
module tb_bk (
    input             clk,
    input             reset,
    input             turbo,
    input             rom_wr,
    input      [24:0] rom_addr,
    input      [7:0]  rom_data,
    input      [7:0]  scancode,
    input             scancode_upd,
    input      [7:0]  img_mounted,
    input      [63:0] img_size,
    input             img_data_wr,
    input      [8:0]  img_data_addr,
    input      [7:0]  img_data,
    input             img_result_wr,
    input      [7:0]  img_result,
    input      [15:0] img_sum,
    output            img_q_wr,
    output     [23:0] img_q_di,
    input             img_q_ack,
    output     [7:0]  r,
    output     [7:0]  g,
    output     [7:0]  b,
    output            hs,
    output            vs,
    output            de,
    output signed [15:0] audio_l,
    output signed [15:0] audio_r,
    output     [31:0] sdr_errors,
    output     [31:0] sdr_reads,
    output     [31:0] sdr_writes
);

wire [12:0] SDR_A;
wire [1:0]  SDR_BA, SDR_DQM;
wire [15:0] SDR_DQ;
wire        SDR_RAS_N, SDR_CAS_N, SDR_WE_N;
wire [7:0]  rtc_a;
reg  [7:0]  rtc_do = 8'd0;

bk_system sys (
    .clk(clk), .lock(1'b1), .reset(reset), .turbo(turbo), .joy_on(1'b0), .covox_714(1'b0), .volume(2'b11),
    .rom_wr(rom_wr), .rom_addr(rom_addr), .rom_data(rom_data),
    .scancode(scancode), .scancode_upd(scancode_upd), .joy(13'd0),
    .img_mounted(img_mounted), .img_size(img_size), .img_wp(8'd0),
    .img_data_wr(img_data_wr), .img_data_addr(img_data_addr), .img_data(img_data),
    .img_result_wr(img_result_wr), .img_result(img_result), .img_sum(img_sum),
    .img_q_wr(img_q_wr), .img_q_di(img_q_di), .img_q_ack(img_q_ack),
    .rtc_a(rtc_a), .rtc_do(rtc_do),
    .hs(hs), .vs(vs), .de(de), .r(r), .g(g), .b(b),
    .audio_l(audio_l), .audio_r(audio_r), .disk_busy(),
    .SDR_A(SDR_A), .SDR_BA(SDR_BA), .SDR_DQ(SDR_DQ), .SDR_RAS_N(SDR_RAS_N), .SDR_CAS_N(SDR_CAS_N),
    .SDR_WE_N(SDR_WE_N), .SDR_DQM(SDR_DQM)
);

sdram16_model chip (
    .clk(clk), .A(SDR_A), .BA(SDR_BA), .DQ(SDR_DQ), .nRAS(SDR_RAS_N), .nCAS(SDR_CAS_N), .nWE(SDR_WE_N), .DQM(SDR_DQM),
    .errors(sdr_errors), .reads(sdr_reads), .writes(sdr_writes)
);

// 2026-11-07 12:34:56, a Saturday: DS1307 registers
always @(posedge clk) case (rtc_a)
    8'd0: rtc_do <= 8'h56;
    8'd1: rtc_do <= 8'h34;
    8'd2: rtc_do <= 8'h12;
    8'd3: rtc_do <= 8'h06;
    8'd4: rtc_do <= 8'h07;
    8'd5: rtc_do <= 8'h11;
    8'd6: rtc_do <= 8'h26;
    default: rtc_do <= 8'h00;
endcase

// +az: the commands of the controller
reg az_log = 1'b0;
initial az_log = $test$plusargs("az");
reg [7:0] done_d = 8'd0;
reg done_p = 1'b1;
integer az_n = 0;
always @(posedge clk) begin
    done_p <= sys.ctl.csr[7];
    if (done_p && !sys.ctl.csr[7]) az_n = az_n + 1;
    if (az_log && !done_p && sys.ctl.csr[7])
        $display("az %04o unit %0d blk %0d %s", sys.ctl.cmd, sys.ctl.unit, sys.ctl.blkn, sys.ctl.csr[15] ? "ERR" : "ok");
end

// +bus: the first bus cycles of the processor, N = +busn=N
reg bus_log = 1'b0;
integer bus_n = 0, bus_max = 400;
initial begin bus_log = $test$plusargs("bus"); if (!$value$plusargs("busn=%d", bus_max)) bus_max = 400; end
reg stb_d = 1'b0;
always @(posedge clk) begin
    stb_d <= sys.b_stb;
    if (bus_log && bus_n < bus_max && sys.b_stb_d && !sys.b_stb) begin
        bus_n = bus_n + 1;
        $display("%0d %s %06o = %06o", bus_n, sys.b_we ? "wr" : "rd", sys.b_adr, sys.b_we ? sys.b_dout : sys.cpu1.cpu_din);
    end
end

endmodule
