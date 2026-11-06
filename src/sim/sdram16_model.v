`timescale 1ns / 1ps
// A model of the 16M x 16 SDRAM for tb_bk: CAS latency 2, burst length 1. It is clocked on the clock of
// the FPGA, as many clocks after a launch as the chip on the inverted clock with the pad delays is: a
// command launched at edge E is sampled at E + 1, a read's word is on DQ from E + 2 to E + 3, around the
// falling edge E + 2.5 of bk_sdram.v. It counts the violations of tRCD, tRP, tRC, tRFC and a closed row.
module sdram16_model (
    input             clk,
    input      [12:0] A,
    input      [1:0]  BA,
    inout      [15:0] DQ,
    input             nRAS,
    input             nCAS,
    input             nWE,
    input      [1:0]  DQM,
    output reg [31:0] errors = 0,
    output reg [31:0] reads = 0,
    output reg [31:0] writes = 0
);

reg [15:0] mem [0:(1 << 24) - 1];
reg [12:0] row [0:3];
reg [3:0]  open = 4'd0;
integer    busy_until [0:3];    // the clock from which ACTIVE may go to a bank
integer    act_at [0:3];
integer    now = 0, i;
initial for (i = 0; i < 4; i = i + 1) begin busy_until[i] = 0; act_at[i] = -100; row[i] = 0; end

reg [23:0] rd_a = 24'd0;
reg        rd_v = 1'b0, dq_en = 1'b0;
reg [1:0]  rd_m = 2'b11;
reg [15:0] dq_q = 16'd0;
assign DQ = dq_en ? dq_q : 16'hzzzz;

wire [2:0]  cmd = {nRAS, nCAS, nWE};
wire [23:0] wa  = {BA, row[BA], A[8:0]};

always @(posedge clk) begin
    now = now + 1;
    rd_v <= 1'b0;
    dq_en <= rd_v;
    if (rd_v) dq_q <= {rd_m[1] ? 8'hFF : mem[rd_a][15:8], rd_m[0] ? 8'hFF : mem[rd_a][7:0]};
    case (cmd)
    3'b011: begin   // ACTIVE
        if (open[BA] || now < busy_until[BA] || now - act_at[BA] < 5) begin
            errors <= errors + 1; $display("sdram: ACTIVE too early, bank %0d at %0d (free %0d)", BA, now, busy_until[BA]);
        end
        open[BA] <= 1'b1; row[BA] <= A; act_at[BA] = now;
    end
    3'b101: begin   // READ
        if (!open[BA] || now - act_at[BA] < 2) begin errors <= errors + 1; $display("sdram: READ, closed or tRCD, bank %0d at %0d", BA, now); end
        rd_a <= wa; rd_m <= DQM; rd_v <= 1'b1; reads <= reads + 1;
        if (A[10]) begin open[BA] <= 1'b0; busy_until[BA] = now + 3; end
    end
    3'b100: begin   // WRITE
        if (!open[BA] || now - act_at[BA] < 2) begin errors <= errors + 1; $display("sdram: WRITE, closed or tRCD, bank %0d at %0d", BA, now); end
        if (!DQM[0]) mem[wa][7:0] <= DQ[7:0];
        if (!DQM[1]) mem[wa][15:8] <= DQ[15:8];
        writes <= writes + 1;
        if (A[10]) begin open[BA] <= 1'b0; busy_until[BA] = now + 4; end
    end
    3'b001: begin   // REFRESH
        if (|open) begin errors <= errors + 1; $display("sdram: REFRESH with a bank open at %0d", now); end
        for (i = 0; i < 4; i = i + 1) begin if (now < busy_until[i]) begin errors <= errors + 1; $display("sdram: REFRESH in tRP at %0d", now); end busy_until[i] = now + 6; end
    end
    default: ;
    endcase
end

endmodule
