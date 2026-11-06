`timescale 1ns / 1ps
//========================================================================
// azctrl.v - the AZ controller: registers 177220-177226, and the STM32
// behind them, which here is the FPGA.
//
// On the real AZBK the four words are the STM32's: a command and status
// register (CSR, 177220), a data register (DR, 177222) through which
// every block moves a word at a time, and two boot ROMs of one word
// (177224/177226, unused on the BK).  The commands are the pseudo-disk
// controller's (MAXIOL: "Команды контролера AZ", "Новые команды") and
// GID's AZBK_ctrl.cpp is the model this follows: a command is accepted
// only while DONE (bit 7) is set; while it runs DONE is clear and DR is
// not acknowledged (a bus timeout, as the doc says); ERR (15) and BIG
// (14) are set with DONE; IE (6) is written with every command and NOP
// (030) exists to write it alone; a finished READ or WRITE with IE set
// interrupts through vector 174.
//
// Here the commands are split as upstream has them (retro-tang-bk), but
// what its BL616 does over SPI target 4 (mnano/azbk.c) is the FPGA's own
// here, the service below: the Karabas firmware gives the core sectors of
// the images of the OSD's F items (img_sdc.v of the modules) and the
// clock of the board, and no files by name.
//   local on the spot: RESET, the unit select (001: the size from the mount,
//     the software does not wait for it, see below), the block number
//     (002/012), the sizes (007/017), the buffer transfers
//     (015/016/022/023), NOP, NET, the feature and diagnostic words
//     (027, 020), the time buffer (032/033), the IP and card size reads
//     (041/057), 035/036/040/043 (no network, answered empty), 037 (reset)
//   the service, DONE clear meanwhile:
//     005/006  a sector of unit 0..3 = slot 0..3 of the F items
//     021/024  the EEPROM block: sector 0 of slot 4 (a file of the F item
//              "AZ EEPROM"), no image = status 1 and zeros
//     031/042  the clock of the board into the timestamp buffer; 034 is
//              answered and dropped (a program's clock prompt must not
//              set the clock of the board)
//     011      the units table: sizes and flags, the names "AZn"
//     025/026  the JSON of a HOF upload without a network
//     056      the card's size: a constant, the firmware does not say
//     050/053, 051, 054  the file commands answer "no such file" (051:
//              the code in CMOS); 003/013, 004/014, 047, 052, 055 and
//              the screenshot 044 answer ERR
//
// The buffer is 8192 words of block RAM, laid out as the emulator's several
// arrays: IOBUF at 0 (256 words: the block), CMOS at 256 (256: the
// EEPROM image and the file commands' data), IP at 512 (12), SIZE at
// 528 (2), TS at 544 (14: the timestamp), FEAT at 560 (2), DIAG at 562
// (2), and the units table at 1024 (32 x 198 words, command 011).
//
// The select is local because the software does not wait for it: the
// 337 boot ROM (AZ337, 160314) writes 001 and goes straight on to the
// block number and the read, and a command written while DONE is
// clear is dropped - GID's emulator completes the select in the write
// and MAXIOL's controller evidently as fast (retro-tang-bk's third
// board report).
//========================================================================
module azctrl (
    input             clk,
    input             cold,

    // the bus
    input             sync,
    input      [15:0] adr,
    input             stb,
    input             we,
    input      [15:0] din,
    output     [15:0] dout,
    output            ack,
    input             wr_stb,
    input             rd_stb,

    output reg        virq174,      // vector 174 request
    input             vack174,
    output reg        az_reset,     // one clock: command 037

    // the images: img_sdc.v
    input      [7:0]  img_mounted,  // a pulse a slot, with img_size
    input      [63:0] img_size,     // bytes
    input      [7:0]  img_wp,
    output reg [7:0]  sdc_rd = 8'd0,
    output reg [7:0]  sdc_wr = 8'd0,
    output reg [31:0] sdc_sector = 32'd0,
    input             sdc_busy,
    input             sdc_done,
    input             sdc_error,
    input             sdc_byte_in_strobe,
    input      [8:0]  sdc_byte_addr,
    input      [7:0]  sdc_byte_in_data,
    output reg [7:0]  sdc_byte_out_data = 8'd0,

    // the clock of the board: the registers of kg_mcu (DS1307, BCD: rtc_mode 1)
    output reg [7:0]  rtc_a = 8'd0,
    input      [7:0]  rtc_do,

    output            busy          // the service is running: a lamp
);

localparam CS_IE = 6, CS_DONE = 7, CS_BIG = 14, CS_ERR = 15;

// buffer regions, in words
localparam [12:0] R_IOBUF = 13'd0, R_CMOS = 13'd256, R_IP = 13'd512, R_SIZE = 13'd528, R_FSZ = 13'd530,
                  R_TS = 13'd544, R_FEAT = 13'd560, R_DIAG = 13'd562, R_TABLE = 13'd1024;
localparam [2:0]  SLOT_EEPROM = 3'd4;
localparam [31:0] CARD_MB = 32'd4096;     // the size command 056 reports

//------------------------------------------------------------------------
// The buffer: port A the processor's and the local commands', port B
// the MCU's
//------------------------------------------------------------------------
reg [15:0] buf_mem [0:8191];
reg [12:0] a_adr = 13'd0, b_adr = 13'd0;
reg        a_we = 1'b0, b_we = 1'b0;
reg [15:0] a_wdata = 16'd0, b_wdata = 16'd0;
reg [15:0] a_rdata = 16'd0, b_rdata = 16'd0;
// a port reads or writes in a clock, never both (upstream: Gowin's DPB
// has no read-old-data mode), so a write clock leaves the read data as it
// was and the address is put back to the read pointer after
always @(posedge clk) begin
    if (a_we) buf_mem[a_adr] <= a_wdata;
    else      a_rdata <= buf_mem[a_adr];
end
always @(posedge clk) begin
    if (b_we) buf_mem[b_adr] <= b_wdata;
    else      b_rdata <= buf_mem[b_adr];
end

//------------------------------------------------------------------------
// The registers
//------------------------------------------------------------------------
reg [15:0] csr = 16'o200;        // DONE at power-up
reg [15:0] dr = 16'd0;           // the last word through the DR
reg [5:0]  cmd = 6'd0;
reg [4:0]  unit = 5'd0;
reg        unit_ok = 1'b0;
reg [31:0] unit_size = 32'd0;    // blocks
reg [31:0] blkn = 32'd0;
reg [12:0] init_wcnt = 13'd256;
reg [12:0] rd_buf = R_IOBUF;     // what 015 starts from
reg [12:0] rd_ptr = 13'd0, wr_ptr = 13'd0;
reg [12:0] rd_cnt = 13'd0, wr_cnt = 13'd0;
reg [12:0] wr_written = 13'd0;
reg        pending = 1'b0;       // a service command is running
reg [2:0]  local_st = 3'd0;      // a few local commands need clocks
reg        blk_err = 1'b0;

wire sel220 = sync && (adr[15:1] == (16'o177220 >> 1));
wire sel222 = sync && (adr[15:1] == (16'o177222 >> 1));
wire sel224 = sync && (adr[15:1] == (16'o177224 >> 1));
wire sel226 = sync && (adr[15:1] == (16'o177226 >> 1));
wire done   = csr[CS_DONE];

// the DR read data: `dr`, which holds the buffer word at rd_ptr while a
// stream is up - loaded between strobes, so that it stands still for
// the whole of one (19 Sep 2026: with a_rdata on the bus the pointer's
// step at the strobe's start changed the word under the processor's
// sample, and every second word of the time went missing)
wire [15:0] dr_rd = dr;

assign dout = sel220 ? csr : (sel222 && done) ? dr_rd : (sel226 && done) ? 16'o776 : 16'd0;
assign ack  = stb && (sel220 || (done && (sel222 || sel224 || sel226)));

wire wr220 = wr_stb && sel220;
wire wr222 = wr_stb && sel222 && done;
wire rd222 = rd_stb && sel222 && done;

//------------------------------------------------------------------------
// The service: the commands the BL616 serves upstream (azbk.c)
//------------------------------------------------------------------------
assign busy = pending;

function is_svc; input [5:0] c;
    case (c)
        6'o03, 6'o04, 6'o05, 6'o06, 6'o11, 6'o13, 6'o14,
        6'o21, 6'o24, 6'o25, 6'o26, 6'o31, 6'o34, 6'o42, 6'o44, 6'o47,
        6'o50, 6'o51, 6'o52, 6'o53, 6'o54, 6'o55, 6'o56: is_svc = 1'b1;
        default: is_svc = 1'b0;
    endcase
endfunction

localparam [3:0] SV_IDLE = 4'd0, SV_REQ = 4'd1, SV_XFER = 4'd2, SV_FILL = 4'd3, SV_RTC = 4'd4,
                 SV_TIME = 4'd5, SV_DONE = 4'd6, SV_STAT = 4'd7;

reg [3:0]  sv = SV_IDLE;
reg        sv_err = 1'b0;
reg [12:0] sv_rd_base = 13'd0, sv_rd_cnt = 13'd0, sv_wr_base = 13'd0, sv_wr_cnt = 13'd0;
reg [12:0] sv_rd_buf = R_IOBUF, sv_init = 13'd256;
reg [12:0] sv_base = 13'd0;      // the region of a transfer or a fill
reg [12:0] sv_i = 13'd0, sv_n = 13'd0;
reg [7:0]  lobyte = 8'd0;
reg        req_up = 1'b0;
reg        xfer_hi = 1'b0;
reg        io_read = 1'b0;       // 050 was the last of 050/053

// the sizes of the units, in blocks
reg [31:0] usz0 = 32'd0, usz1 = 32'd0, usz2 = 32'd0, usz3 = 32'd0;
function [31:0] blocks; input [63:0] bytes;
    blocks = bytes[40:9] + ((bytes[8:0] != 9'd0) ? 32'd1 : 32'd0);
endfunction
wire [31:0] usz_sel = (dr[4:2] != 3'd0) ? 32'd0 :
                      (dr[1:0] == 2'd0) ? usz0 : (dr[1:0] == 2'd1) ? usz1 : (dr[1:0] == 2'd2) ? usz2 : usz3;
reg         eeprom_on = 1'b0;

// the clock: the registers as they are read, in binary
function [7:0] bcd; input [7:0] v; bcd = {v[7:4], 3'b000} + {v[7:4], 1'b0} + v[3:0]; endfunction
reg [2:0]  rtc_i = 3'd0;
reg        rtc_w = 1'b0;
reg [7:0]  t_s = 8'd0, t_mi = 8'd0, t_h = 8'd0, t_wd = 8'd0, t_d = 8'd0, t_mo = 8'd0, t_y = 8'd0;
reg [16:0] t_sod = 17'd0;        // the seconds of the day
reg [22:0] t_50 = 23'd0, t_60 = 23'd0;
reg [2:0]  t_st = 3'd0;
wire [7:0]  t_ry = t_y + 8'd28;  // the year from 1972
wire [11:0] t_ye = 12'd2000 + {4'd0, t_y};

// the word of a fill
reg [15:0] fill_word;
reg [7:0]  tab_row = 8'd0;
reg [7:0]  tab_col = 8'd0;
wire [31:0] tab_size = (tab_row == 8'd0) ? usz0 : (tab_row == 8'd1) ? usz1 : (tab_row == 8'd2) ? usz2 :
                       (tab_row == 8'd3) ? usz3 : 32'd0;
function [15:0] hof_word; input [4:0] i;   // {"RESULT":"ERROR","DESCRIPTION":"CONNECTION_ERROR"}
    case (i)
        5'd0:  hof_word = 16'h227B; 5'd1:  hof_word = 16'h4552; 5'd2:  hof_word = 16'h5553; 5'd3:  hof_word = 16'h544C;
        5'd4:  hof_word = 16'h3A22; 5'd5:  hof_word = 16'h4522; 5'd6:  hof_word = 16'h5252; 5'd7:  hof_word = 16'h524F;
        5'd8:  hof_word = 16'h2C22; 5'd9:  hof_word = 16'h4422; 5'd10: hof_word = 16'h5345; 5'd11: hof_word = 16'h5243;
        5'd12: hof_word = 16'h5049; 5'd13: hof_word = 16'h4954; 5'd14: hof_word = 16'h4E4F; 5'd15: hof_word = 16'h3A22;
        5'd16: hof_word = 16'h4322; 5'd17: hof_word = 16'h4E4F; 5'd18: hof_word = 16'h454E; 5'd19: hof_word = 16'h5443;
        5'd20: hof_word = 16'h4F49; 5'd21: hof_word = 16'h5F4E; 5'd22: hof_word = 16'h5245; 5'd23: hof_word = 16'h4F52;
        5'd24: hof_word = 16'h2252; 5'd25: hof_word = 16'h007D;
        default: hof_word = 16'd0;
    endcase
endfunction
always @* case (cmd)
    6'o31, 6'o42: case (sv_i[3:0])
        4'd0:  fill_word = {t_ry[6:5], t_mo[3:0], t_d[4:0], t_ry[4:0]};
        4'd1:  fill_word = {9'd0, t_50[22:16]};
        4'd2:  fill_word = t_50[15:0];
        4'd3:  fill_word = {9'd0, t_60[22:16]};
        4'd4:  fill_word = t_60[15:0];
        4'd5:  fill_word = {t_y[6:0] + 7'd20, t_mo[3:0], t_d[4:0]};    // the year from 1980
        4'd6:  fill_word = {t_h[4:0], t_mi[5:0], t_s[5:1]};
        4'd7:  fill_word = {4'd0, t_ye};
        4'd8:  fill_word = {8'd0, t_mo};
        4'd9:  fill_word = {8'd0, t_d};
        4'd10: fill_word = {8'd0, t_wd};
        4'd11: fill_word = {8'd0, t_h};
        4'd12: fill_word = {8'd0, t_mi};
        default: fill_word = {8'd0, t_s};
    endcase
    6'o25, 6'o26: fill_word = (sv_i[12:5] == 8'd0) ? hof_word(sv_i[4:0]) : 16'd0;
    6'o56: fill_word = CARD_MB[15:0];
    6'o51: fill_word = sv_i[0] ? 16'h8000 : (io_read ? 16'd4 : 16'd7);
    6'o11: case (tab_col)
        8'd0:  fill_word = (tab_size == 32'd0) ? 16'd0 : tab_size[15:0];
        8'd1:  fill_word = tab_size[31:16];
        8'd4:  fill_word = (tab_size == 32'd0) ? 16'd0 : 16'h0005;      // flags CFG|MTD, attr 0
        8'd5:  fill_word = (tab_size == 32'd0) ? 16'd0 : 16'h5A41;      // "AZ"
        8'd6:  fill_word = (tab_size == 32'd0) ? 16'd0 : {8'd0, 6'b001100, tab_row[1:0]};   // "0".."3"
        default: fill_word = 16'd0;
    endcase
    default: fill_word = 16'd0;     // 021: the rest of CMOS with no EEPROM
endcase

always @(posedge clk) begin
    a_we <= 1'b0; b_we <= 1'b0;
    az_reset <= 1'b0;
    if (vack174) virq174 <= 1'b0;
    sdc_rd <= 8'd0; sdc_wr <= 8'd0;

    // a mount: the size of a unit, the EEPROM's image
    if (img_mounted[0]) usz0 <= blocks(img_size);
    if (img_mounted[1]) usz1 <= blocks(img_size);
    if (img_mounted[2]) usz2 <= blocks(img_size);
    if (img_mounted[3]) usz3 <= blocks(img_size);
    if (img_mounted[SLOT_EEPROM]) eeprom_on <= (img_size != 64'd0);

    if (cold) begin
        csr <= 16'o200; pending <= 1'b0; rd_cnt <= 13'd0; wr_cnt <= 13'd0;
        init_wcnt <= 13'd256; rd_buf <= R_IOBUF; local_st <= 3'd0; virq174 <= 1'b0;
        sv <= SV_IDLE; req_up <= 1'b0;
    end else begin
        //----------------------------------------------------------------
        // The processor
        //----------------------------------------------------------------
        if (!stb && rd_cnt != 13'd0 && local_st == 3'd0) dr <= a_rdata;   // the next word, between strobes
        if (rd222) begin
            if (rd_cnt != 13'd0) begin
                rd_ptr <= rd_ptr + 13'd1;
                rd_cnt <= rd_cnt - 13'd1;
            end
        end
        if (wr222) begin
            dr <= din;
            if (wr_cnt != 13'd0) begin
                a_we <= 1'b1; a_adr <= wr_ptr; a_wdata <= din;
                wr_ptr <= wr_ptr + 13'd1;
                wr_cnt <= wr_cnt - 13'd1;
                wr_written <= wr_written + 13'd1;
            end
        end

        if (wr220) begin
            csr[CS_IE] <= din[CS_IE];
            if (din[5:0] == 6'd0) begin
                // RESET: on the spot, whatever is going on
                rd_cnt <= 13'd0; wr_cnt <= 13'd0; init_wcnt <= 13'd256; blkn <= 32'd0;
                csr <= 16'o200;
                pending <= 1'b0; local_st <= 3'd0; sv <= SV_IDLE; req_up <= 1'b0;
            end else if (done) begin
                cmd <= din[5:0];
                csr[CS_DONE] <= 1'b0; csr[CS_BIG] <= 1'b0; csr[CS_ERR] <= 1'b0;
                if (din[5:0] != 6'o15) init_wcnt <= 13'd256;
                if (is_svc(din[5:0]))
                    pending <= 1'b1;
                else
                    local_st <= 3'd1;
            end
        end

        //----------------------------------------------------------------
        // The local commands, a few clocks after the write
        //----------------------------------------------------------------
        if (local_st != 3'd0) begin
            local_st <= local_st + 3'd1;
            case (cmd)
            6'o01: if (local_st == 3'd1) begin
                // select: the unit from the DR, its size from the mount
                unit <= dr[4:0];
                unit_size <= usz_sel;
            end else begin
                unit_ok <= (unit_size != 32'd0);
                if (unit_size == 32'd0) csr[CS_ERR] <= 1'b1;   // nothing mounted there
                csr[CS_DONE] <= 1'b1; local_st <= 3'd0;
            end
            6'o02, 6'o12: if (local_st == 3'd1) begin
                if (cmd == 6'o02) blkn <= {16'd0, dr}; else blkn[31:16] <= dr;
            end else if (local_st == 3'd2) begin
                if (!unit_ok || unit_size <= blkn) csr[CS_ERR] <= 1'b1;
                csr[CS_DONE] <= 1'b1; local_st <= 3'd0;
            end
            6'o07: if (local_st == 3'd1) begin
                if (!unit_ok || unit_size <= blkn) begin csr[CS_ERR] <= 1'b1; csr[CS_DONE] <= 1'b1; local_st <= 3'd0; end
                else begin
                    a_we <= 1'b1; a_adr <= R_IOBUF;
                    a_wdata <= (unit_size > 32'd65535) ? 16'hFFFF : unit_size[15:0];
                    if (unit_size > 32'd65535) csr[CS_BIG] <= 1'b1;
                end
            end else if (local_st == 3'd2) begin
                rd_ptr <= R_IOBUF; rd_cnt <= 13'd1; wr_cnt <= 13'd0; a_adr <= R_IOBUF;
            end else begin csr[CS_DONE] <= 1'b1; local_st <= 3'd0; end
            6'o17: if (local_st == 3'd1) begin
                if (!unit_ok || unit_size <= blkn) begin csr[CS_ERR] <= 1'b1; csr[CS_DONE] <= 1'b1; local_st <= 3'd0; end
                else begin a_we <= 1'b1; a_adr <= R_IOBUF; a_wdata <= unit_size[15:0]; end
            end else if (local_st == 3'd2) begin
                a_we <= 1'b1; a_adr <= R_IOBUF + 13'd1; a_wdata <= unit_size[31:16];
            end else if (local_st == 3'd3) begin
                rd_ptr <= R_IOBUF; rd_cnt <= 13'd2; wr_cnt <= 13'd0; a_adr <= R_IOBUF;
            end else begin csr[CS_DONE] <= 1'b1; local_st <= 3'd0; end
            6'o15: begin   // read the buffer
                rd_ptr <= rd_buf; rd_cnt <= init_wcnt; wr_cnt <= 13'd0; a_adr <= rd_buf;
                if (local_st == 3'd2) begin csr[CS_DONE] <= 1'b1; local_st <= 3'd0; end
            end
            6'o16: begin   // write the buffer
                wr_ptr <= R_IOBUF; wr_cnt <= init_wcnt; wr_written <= 13'd0; rd_cnt <= 13'd0;
                csr[CS_DONE] <= 1'b1; local_st <= 3'd0;
            end
            6'o22: begin
                rd_ptr <= R_CMOS; rd_cnt <= 13'd256; wr_cnt <= 13'd0; a_adr <= R_CMOS;
                if (local_st == 3'd2) begin csr[CS_DONE] <= 1'b1; local_st <= 3'd0; end
            end
            6'o23: begin
                wr_ptr <= R_CMOS; wr_cnt <= 13'd256; wr_written <= 13'd0; rd_cnt <= 13'd0;
                csr[CS_DONE] <= 1'b1; local_st <= 3'd0;
            end
            6'o27: if (local_st == 3'd1) begin
                a_we <= 1'b1; a_adr <= R_FEAT; a_wdata <= 16'h1204;      // STM 18, hardware 4
            end else if (local_st == 3'd2) begin
                a_we <= 1'b1; a_adr <= R_FEAT + 13'd1; a_wdata <= 16'd31;
            end else if (local_st == 3'd3) begin
                rd_ptr <= R_FEAT; rd_cnt <= 13'd2; wr_cnt <= 13'd0; a_adr <= R_FEAT;
            end else begin csr[CS_DONE] <= 1'b1; local_st <= 3'd0; end
            6'o20: if (local_st == 3'd1) begin
                a_we <= 1'b1; a_adr <= R_DIAG; a_wdata <= 16'd0;
            end else if (local_st == 3'd2) begin
                a_we <= 1'b1; a_adr <= R_DIAG + 13'd1; a_wdata <= 16'd0;
            end else if (local_st == 3'd3) begin
                rd_ptr <= R_DIAG; rd_cnt <= 13'd2; wr_cnt <= 13'd0; a_adr <= R_DIAG;
            end else begin csr[CS_DONE] <= 1'b1; local_st <= 3'd0; end
            6'o32: begin
                rd_ptr <= R_TS; rd_cnt <= 13'd14; wr_cnt <= 13'd0; a_adr <= R_TS;
                if (local_st == 3'd2) begin csr[CS_DONE] <= 1'b1; local_st <= 3'd0; end
            end
            6'o33: begin
                wr_ptr <= R_TS + 13'd7; wr_cnt <= 13'd7; wr_written <= 13'd0; rd_cnt <= 13'd0;
                csr[CS_DONE] <= 1'b1; local_st <= 3'd0;
            end
            6'o41: begin
                rd_ptr <= R_IP; rd_cnt <= 13'd12; wr_cnt <= 13'd0; a_adr <= R_IP;
                if (local_st == 3'd2) begin csr[CS_DONE] <= 1'b1; local_st <= 3'd0; end
            end
            6'o57: begin
                rd_ptr <= R_SIZE; rd_cnt <= 13'd2; wr_cnt <= 13'd0; a_adr <= R_SIZE;
                if (local_st == 3'd2) begin csr[CS_DONE] <= 1'b1; local_st <= 3'd0; end
            end
            6'o40, 6'o43: begin
                // no network: the IP block reads as zeros (twelve clocks)
                a_we <= 1'b1; a_adr <= R_IP + {10'd0, local_st}; a_wdata <= 16'd0;
                if (local_st == 3'd6) begin csr[CS_DONE] <= 1'b1; local_st <= 3'd0; end
            end
            6'o37: begin
                az_reset <= 1'b1;
                csr[CS_DONE] <= 1'b1; local_st <= 3'd0;
            end
            6'o10: begin
                // NET: with IE set it only clears it (and does nothing else)
                if (csr[CS_IE]) csr[CS_IE] <= 1'b0;
                csr[CS_DONE] <= 1'b1; local_st <= 3'd0;
            end
            6'o30, 6'o35, 6'o36: begin
                csr[CS_DONE] <= 1'b1; local_st <= 3'd0;
            end
            default: begin
                csr[CS_ERR] <= 1'b1; csr[CS_DONE] <= 1'b1; local_st <= 3'd0;
            end
            endcase
        end

        //----------------------------------------------------------------
        // The service
        //----------------------------------------------------------------
        case (sv)
        SV_IDLE: if (pending) begin
            sv_err <= 1'b0;
            sv_rd_base <= 13'd0; sv_rd_cnt <= 13'd0; sv_wr_base <= 13'd0; sv_wr_cnt <= 13'd0;
            sv_rd_buf <= R_IOBUF; sv_init <= 13'd256;
            sv_i <= 13'd0; tab_row <= 8'd0; tab_col <= 8'd0;
            sv <= SV_DONE;
            case (cmd)
            6'o05, 6'o06: begin
                sv_base <= R_IOBUF; sdc_sector <= blkn;
                if (!unit_ok || blkn >= unit_size || (cmd == 6'o06 && img_wp[unit[2:0]])) sv_err <= 1'b1;
                else sv <= SV_REQ;
            end
            6'o21: begin
                sv_base <= R_CMOS + 13'd1; sdc_sector <= 32'd0;   // CMOS[0] is the status
                if (eeprom_on) sv <= SV_REQ;
                else begin sv_base <= R_CMOS; sv_n <= 13'd256; sv <= SV_FILL; end
            end
            6'o24: begin
                sv_base <= R_CMOS; sdc_sector <= 32'd0;
                if (eeprom_on) sv <= SV_REQ; else sv_err <= 1'b1;
            end
            6'o31, 6'o42: begin rtc_i <= 3'd0; rtc_a <= 8'd0; rtc_w <= 1'b0; sv <= SV_RTC; end
            6'o11: begin sv_base <= R_TABLE; sv_n <= 13'd6336; sv_rd_buf <= R_TABLE; sv_init <= 13'd6336; sv <= SV_FILL; end
            6'o25, 6'o26: begin sv_base <= R_CMOS; sv_n <= 13'd256; sv <= SV_FILL; end
            6'o56: begin sv_base <= R_SIZE; sv_n <= 13'd2; sv <= SV_FILL; end
            6'o51: begin sv_base <= R_CMOS; sv_n <= 13'd2; sv_rd_base <= R_CMOS; sv_rd_cnt <= 13'd2; sv <= SV_FILL; end
            6'o50: io_read <= 1'b1;
            6'o53: io_read <= 1'b0;
            6'o54: begin sv_wr_base <= R_FSZ; sv_wr_cnt <= 13'd2; end
            6'o34: ;                                       // the clock of the board stays
            default: sv_err <= 1'b1;
            endcase
        end
        SV_REQ: begin
            // after a request a RESET has left running; held until img_sdc takes it (sdc_busy)
            if (req_up && sdc_busy) begin
                req_up <= 1'b0;
                sv <= SV_XFER;
            end else if (req_up || !sdc_busy) begin
                req_up <= 1'b1;
                if (cmd == 6'o05) sdc_rd[unit[2:0]] <= 1'b1;
                if (cmd == 6'o06) sdc_wr[unit[2:0]] <= 1'b1;
                if (cmd == 6'o21) sdc_rd[SLOT_EEPROM] <= 1'b1;
                if (cmd == 6'o24) sdc_wr[SLOT_EEPROM] <= 1'b1;
            end
        end
        SV_XFER: begin
            // a read: the bytes as words into the region. A write: img_sdc
            // copies the sector out of the buffer, OUT_LATENCY clocks a byte
            if (sdc_byte_in_strobe) begin
                if (!sdc_byte_addr[0]) lobyte <= sdc_byte_in_data;
                else if (!(cmd == 6'o21 && sdc_byte_addr[8:1] == 8'd255)) begin   // 255 words fit behind the status
                    b_we <= 1'b1;
                    b_adr <= sv_base + {5'd0, sdc_byte_addr[8:1]};
                    b_wdata <= {sdc_byte_in_data, lobyte};
                end
            end else begin
                b_adr <= sv_base + {5'd0, sdc_byte_addr[8:1]};
                xfer_hi <= sdc_byte_addr[0];
            end
            sdc_byte_out_data <= xfer_hi ? b_rdata[15:8] : b_rdata[7:0];
            if (sdc_done) begin
                sv_err <= sdc_error;
                sv <= (cmd == 6'o21) ? SV_STAT : SV_DONE;
            end
        end
        SV_STAT: begin
            // the status word of 021
            b_we <= 1'b1; b_adr <= R_CMOS; b_wdata <= {15'd0, sv_err};
            sv_err <= 1'b0;
            sv <= SV_DONE;
        end
        SV_FILL: begin
            b_we <= 1'b1;
            b_adr <= sv_base + sv_i;
            b_wdata <= (cmd == 6'o21 && sv_i == 13'd0) ? 16'd1 : fill_word;
            sv_i <= sv_i + 13'd1;
            if (tab_col == 8'd197) begin tab_col <= 8'd0; tab_row <= tab_row + 8'd1; end
            else tab_col <= tab_col + 8'd1;
            if (sv_i + 13'd1 == sv_n) sv <= SV_DONE;
        end
        SV_RTC: begin
            // seconds, minutes, hours, weekday, date, month, year: a register a clock later
            rtc_w <= 1'b1;
            if (rtc_w) begin
                rtc_w <= 1'b0;
                case (rtc_i)
                    3'd0: t_s  <= bcd({1'b0, rtc_do[6:0]});
                    3'd1: t_mi <= bcd(rtc_do);
                    3'd2: t_h  <= bcd({2'b00, rtc_do[5:0]});
                    3'd3: t_wd <= (rtc_do[2:0] == 3'd7) ? 8'd0 : {5'd0, rtc_do[2:0]};
                    3'd4: t_d  <= bcd(rtc_do);
                    3'd5: t_mo <= bcd({3'b000, rtc_do[4:0]});
                    default: t_y <= bcd(rtc_do);
                endcase
                rtc_i <= rtc_i + 3'd1;
                rtc_a <= {5'd0, rtc_i + 3'd1};
                if (rtc_i == 3'd6) begin t_st <= 3'd0; sv <= SV_TIME; end
            end
        end
        SV_TIME: begin
            t_st <= t_st + 3'd1;
            case (t_st)
                3'd0: t_sod <= t_h * 12'd3600;
                3'd1: t_sod <= t_sod + t_mi * 6'd60 + t_s;
                3'd2: t_50 <= t_sod * 6'd50;
                3'd3: t_60 <= t_sod * 6'd60;
                default: begin sv_base <= R_TS; sv_n <= 13'd14; sv <= SV_FILL; end
            endcase
        end
        SV_DONE: if (!b_we) begin
            sv <= SV_IDLE;
            pending <= 1'b0;
            csr[CS_DONE] <= 1'b1;
            csr[CS_ERR] <= sv_err;
            csr[CS_BIG] <= 1'b0;
            rd_ptr <= sv_rd_base; rd_cnt <= sv_rd_cnt; a_adr <= sv_rd_base;
            wr_ptr <= sv_wr_base; wr_cnt <= sv_wr_cnt; wr_written <= 13'd0;
            rd_buf <= sv_rd_buf; init_wcnt <= sv_init;
            if ((cmd == 6'o05 || cmd == 6'o06) && csr[CS_IE]) virq174 <= 1'b1;
        end
        default: sv <= SV_IDLE;
        endcase

        // keep port A on the read pointer when idle, so dr_rd is ready
        if (!a_we && local_st == 3'd0 && !wr222) a_adr <= rd_ptr;
    end
end

endmodule
