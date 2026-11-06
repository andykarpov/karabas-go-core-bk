`timescale 1ns / 1ps
//========================================================================
// bk_sdram.v - the AZBK's 32 MB in the 32 MB SDRAM of the Karabas boards
// (16M x 16: 4 banks, 8192 rows, 512 columns).
//
// The ports are those of upstream's sdram.v (a 32-bit word of the space,
// byte lanes, the same arbiter and priorities), the chip is not: upstream
// has an 8 MB 32-bit chip behind a page table, a clock phase sweep and a
// self-test. Here the space maps straight onto the chip, so no table, and
// the clock is fixed:
//
// One clock, 65 MHz (15.4 ns). CAS latency 2, burst length 1: a burst is
// one READ a clock on consecutive columns, the last with auto precharge.
//   read   ACTIVE, NOP, READ x n (t = 1..n), the words land 5 clocks after
//          their READ's t, the next ACTIVE from t = n + 3 (tRP after the
//          last READ); the data pipe keeps running across it
//   write  ACTIVE, NOP, WRITE x n, tWR + tRP after the last
//   n      8 words for the display's bursts (a 32-bit burst of 4), else 2
// A display burst costs 11 clocks against upstream's 10..11, a processor
// access 7. tRCD 2 clocks = 31 ns, tRC >= 6 clocks = 92 ns, tRFC 6 = 92 ns.
//
// The pads: the chip gets the inverted clock (the tops, an ODDR2), so
// that it takes commands and write data in the middle of their bit, half
// a clock after our edge, setup and hold about 7 ns each whatever the
// pad delay. A READ launched at our edge E is taken at E + 0.5, its word
// is on the pins from about (E + 1.5) + tAC 6 ns until (E + 2.5) + tOH
// 2.5 ns, plus the pad delay of the clock out and of the data in; at 65
// MHz that is the falling edge E + 2.5, in its middle (a margin of about
// 3 ns either way), so the input flip-flops run on the falling edge and
// dq_in hands the word over at E + 3.
//
// Refresh: 8192 rows in 64 ms, one per 7.8 us = 507 clocks: counted as
// due every 480, taken between cycles, forced at two due.
//========================================================================
module bk_sdram (
    input             clk,
    input             lock,         // the PLL has locked
    output            init,         // the memory is initialised

    // v: the display, burst reads of four 32-bit words (a[1:0] ignored)
    input             v_req,
    input      [22:0] v_adr,
    output            v_take,       // one clock: the burst is starting
    output reg        v_dv = 1'b0,  // one clock a word, four times
    output reg [31:0] v_rdata = 32'd0,

    // c: the processor, one 32-bit word with byte lanes
    input             c_req,
    input             c_we,
    input      [22:0] c_adr,
    input      [31:0] c_wdata,
    input      [3:0]  c_wmask,
    output            c_take,
    output reg        c_ack = 1'b0, // one clock, with c_rdata on a read
    output reg [31:0] c_rdata = 32'd0,

    // b: the blitter
    input             b_req,
    input             b_we,
    input      [22:0] b_adr,
    input      [31:0] b_wdata,
    input      [3:0]  b_wmask,
    output            b_take,
    output reg        b_ack = 1'b0,
    output reg [31:0] b_rdata = 32'd0,

    // d: the DMA sound, reads only
    input             d_req,
    input      [22:0] d_adr,
    output            d_take,
    output reg        d_ack = 1'b0,
    output reg [31:0] d_rdata = 32'd0,

    // p: the ROM loader, byte writes
    input             p_req,
    input      [22:0] p_adr,
    input      [31:0] p_wdata,
    input      [3:0]  p_wmask,
    output            p_take,

    // the chip (~CS is tied on the boards)
    output reg [12:0] SDRAM_A = 13'd0,
    output reg [1:0]  SDRAM_BA = 2'd0,
    inout      [15:0] SDRAM_DQ,
    output reg        SDRAM_nRAS = 1'b1,
    output reg        SDRAM_nCAS = 1'b1,
    output reg        SDRAM_nWE = 1'b1,
    output reg [1:0]  SDRAM_DQM = 2'b11
);

localparam [2:0] CMD_NOP = 3'b111, CMD_ACTIVE = 3'b011, CMD_READ = 3'b101, CMD_WRITE = 3'b100,
                 CMD_PRECHARGE = 3'b010, CMD_REFRESH = 3'b001, CMD_MODE = 3'b000;

// burst length 1, sequential, CAS latency 2
localparam [12:0] MODE = 13'b000_0_00_010_0_000;

localparam [2:0] P_NONE = 3'd0, P_V = 3'd1, P_C = 3'd2, P_B = 3'd3, P_D = 3'd4, P_P = 3'd5, P_REF = 3'd6;

// the data lines: a flip-flop each, so that they all go into the IOBs
(* EQUIVALENT_REGISTER_REMOVAL = "no" *) reg [15:0] dq_t = 16'hFFFF;
reg  [15:0] dq_out = 16'd0;
genvar gi;
generate for (gi = 0; gi < 16; gi = gi + 1) begin : dq_pad
    assign SDRAM_DQ[gi] = dq_t[gi] ? 1'bz : dq_out[gi];
end endgenerate

reg  [15:0] dq_neg = 16'd0, dq_in = 16'd0;
always @(negedge clk) dq_neg <= SDRAM_DQ;
always @(posedge clk) dq_in <= dq_neg;

// power up: 65536 clocks of NOP after the lock, then the JEDEC steps
reg  [15:0] settle = 16'd0;
reg  [6:0]  istep = 7'd127;
reg         started = 1'b0;
wire        running = started && (istep == 7'd0);
assign init = running;

reg  [8:0]  ref_cnt = 9'd0;
reg  [2:0]  ref_due = 3'd0;

// the cycle in flight
reg  [2:0]  who = P_NONE;
reg  [3:0]  t = 4'd0;
reg         act_we = 1'b0;
reg         act_8 = 1'b0;           // eight words, else two
reg  [22:0] act_adr = 23'd0;
reg  [31:0] act_data = 32'd0;
reg  [3:0]  act_mask = 4'd0;
wire        idle = (who == P_NONE);

// who the word landing in dq_in belongs to: {who, the second half of a
// 32-bit word}, five clocks behind its READ
reg  [3:0]  pipe0 = 4'd0, pipe1 = 4'd0, pipe2 = 4'd0, pipe3 = 4'd0;
reg  [15:0] lo = 16'd0;

wire ref_force = (ref_due >= 3'd2);
wire pick_ref  = ref_force || (ref_due != 3'd0 && !v_req && !c_req && !b_req && !d_req && !p_req);
wire [2:0] pick = !running ? P_NONE :
                  pick_ref ? P_REF  :
                  c_req    ? P_C    :    // the processor first: one access a few of its clocks and a
                  v_req    ? P_V    :    // 60-clock timeout; the video has the whole line for its bursts
                  d_req    ? P_D    :
                  b_req    ? P_B    :
                  p_req    ? P_P    : P_NONE;

assign v_take = idle && (pick == P_V);
assign c_take = idle && (pick == P_C);
assign b_take = idle && (pick == P_B);
assign d_take = idle && (pick == P_D);
assign p_take = idle && (pick == P_P);

// the address the arbiter is about to start
reg  [22:0] pick_adr;
always @* case (pick)
    P_V:     pick_adr = {v_adr[22:2], 2'b00};
    P_C:     pick_adr = c_adr;
    P_B:     pick_adr = b_adr;
    P_D:     pick_adr = d_adr;
    default: pick_adr = p_adr;
endcase

// the word of this clock, t = 1 .. n
wire [3:0] n_words = act_8 ? 4'd8 : 4'd2;
wire [2:0] w = t[2:0] - 3'd1;       // 0 .. 7
wire       w_last = (t == n_words);
wire       in_cols = (t >= 4'd1) && (t <= n_words);
wire [1:0] w21 = act_8 ? w[2:1] : act_adr[1:0];   // a burst starts at a[1:0] = 0
wire [8:0] col = {act_adr[7:2], w21, w[0]};

always @(posedge clk) begin
    {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_NOP;
    SDRAM_DQM <= 2'b11;
    dq_t <= 16'hFFFF;
    v_dv <= 1'b0; c_ack <= 1'b0; b_ack <= 1'b0; d_ack <= 1'b0;

    // the data pipe
    pipe0 <= 4'd0;
    pipe1 <= pipe0; pipe2 <= pipe1; pipe3 <= pipe2;
    if (!pipe3[3]) lo <= dq_in;
    else case (pipe3[2:0])
        P_V: begin v_rdata <= {dq_in, lo}; v_dv <= 1'b1; end
        P_C: begin c_rdata <= {dq_in, lo}; c_ack <= 1'b1; end
        P_B: begin b_rdata <= {dq_in, lo}; b_ack <= 1'b1; end
        P_D: begin d_rdata <= {dq_in, lo}; d_ack <= 1'b1; end
        default: ;
    endcase

    if (!lock) begin
        settle <= 16'd0; istep <= 7'd127; started <= 1'b0;
        ref_due <= 3'd0; ref_cnt <= 9'd0; who <= P_NONE; t <= 4'd0;
    end else if (!started) begin
        if (&settle) started <= 1'b1;
        else settle <= settle + 16'd1;
    end else if (istep != 7'd0) begin
        // the JEDEC steps, eight clocks apart
        istep <= istep - 7'd1;
        case (istep)
            7'd64: begin {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_PRECHARGE; SDRAM_A <= 13'h0400; end
            7'd56, 7'd48, 7'd40, 7'd32: {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_REFRESH;
            7'd16: begin {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_MODE; SDRAM_A <= MODE; SDRAM_BA <= 2'd0; end
            default: ;
        endcase
    end else begin
        if (ref_cnt == 9'd479) begin
            ref_cnt <= 9'd0;
            if (ref_due != 3'd7) ref_due <= ref_due + 3'd1;
        end else
            ref_cnt <= ref_cnt + 9'd1;

        if (idle) begin
            t <= 4'd0;
            who <= pick;
            case (pick)
            P_NONE: ;
            P_REF: begin
                {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_REFRESH;
                ref_due <= (ref_cnt == 9'd479) ? ref_due : ref_due - 3'd1;
            end
            default: begin
                {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_ACTIVE;
                SDRAM_BA <= pick_adr[22:21];
                SDRAM_A  <= pick_adr[20:8];
                act_adr  <= pick_adr;
                act_8    <= (pick == P_V);
                act_we   <= (pick == P_C) ? c_we : (pick == P_B) ? b_we : (pick == P_P);
                act_data <= (pick == P_C) ? c_wdata : (pick == P_B) ? b_wdata : p_wdata;
                act_mask <= (pick == P_C) ? c_wmask : (pick == P_B) ? b_wmask : p_wmask;
            end
            endcase
        end else begin
            t <= t + 4'd1;
            if (who == P_REF) begin
                if (t == 4'd4) who <= P_NONE;
            end else begin
                if (in_cols) begin
                    SDRAM_A <= {2'b00, w_last, 1'b0, col};   // A10 with the last word: auto precharge
                    SDRAM_BA <= act_adr[22:21];
                    if (act_we) begin
                        {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_WRITE;
                        dq_out    <= w[0] ? act_data[31:16] : act_data[15:0];
                        dq_t      <= 16'h0000;
                        SDRAM_DQM <= w[0] ? ~act_mask[3:2] : ~act_mask[1:0];
                    end else begin
                        {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_READ;
                        SDRAM_DQM <= 2'b00;
                        pipe0 <= {w[0], who};
                    end
                end
                if (act_we && t == 4'd1) begin
                    if (who == P_C) c_ack <= 1'b1;
                    if (who == P_B) b_ack <= 1'b1;
                end
                if (t == n_words + (act_we ? 4'd3 : 4'd2)) who <= P_NONE;
            end
        end
    end
end

endmodule
