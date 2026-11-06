`timescale 1ns / 1ps
//========================================================================
// bk_loader.v - the ROM set of the .kg into the SDRAM: the bytes of kg_mcu
// (ROMLOAD_*, while the machine is held in reset), a byte write each on
// port p of bk_sdram.v. From retro-tang-bk's poke.v, without its peek.
//========================================================================
module bk_loader (
    input             clk,
    input             reset,

    input             stb,          // a byte
    input      [24:0] adr,
    input      [7:0]  data,

    output            p_req,
    output     [22:0] p_adr,
    output     [31:0] p_wdata,
    output     [3:0]  p_wmask,
    input             p_take
);

reg [32:0] fifo [0:15];
reg [4:0]  wp = 5'd0, rp = 5'd0;
wire empty = (wp == rp);
wire full  = (wp[3:0] == rp[3:0]) && (wp[4] != rp[4]);

wire [32:0] head = fifo[rp[3:0]];
wire [24:0] head_adr = head[32:8];
wire [7:0]  head_dat = head[7:0];

assign p_req   = !empty;
assign p_adr   = head_adr[24:2];
assign p_wdata = {4{head_dat}};
assign p_wmask = (head_adr[1:0] == 2'd0) ? 4'b0001 : (head_adr[1:0] == 2'd1) ? 4'b0010 :
                 (head_adr[1:0] == 2'd2) ? 4'b0100 : 4'b1000;

always @(posedge clk) begin
    if (reset) begin
        wp <= 5'd0; rp <= 5'd0;
    end else begin
        if (stb && !full) begin
            fifo[wp[3:0]] <= {adr, data};
            wp <= wp + 5'd1;
        end
        if (p_take) rp <= rp + 5'd1;
    end
end

endmodule
