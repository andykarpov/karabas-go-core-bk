`timescale 1ns / 1ps
// bk_kbd alone: a key with typematic repeats, its release, Left Ctrl twice, an E0 arrow with repeats.
module tb_kbd;
reg clk = 0; always #5 clk = ~clk;
reg [7:0] sc = 0; reg upd = 0;
wire [7:0] code, flags; wire stb;
bk_kbd k (.clk(clk), .scancode(sc), .scancode_upd(upd), .key_code(code), .key_flags(flags), .key_stb(stb));
integer downs = 0, ups = 0, errors = 0;
always @(posedge clk) if (stb) begin
    if (flags[0]) ups = ups + 1; else downs = downs + 1;
    $display("event %03o flags %02x", code, flags);
end
task b; input [7:0] v; begin @(negedge clk); sc = v; upd = ~upd; repeat (20) @(negedge clk); end endtask
initial begin
    repeat (5) @(negedge clk);
    b(8'h1C); b(8'h1C); b(8'h1C); b(8'hF0); b(8'h1C);              // a, two repeats, release
    b(8'hE0); b(8'h75); b(8'hE0); b(8'h75); b(8'hE0); b(8'hF0); b(8'h75);   // up, a repeat, release
    b(8'hF0); b(8'h32);                                             // a release of a key never pressed
    b(8'h14); b(8'hF0); b(8'h14); b(8'h14); b(8'hF0); b(8'h14);     // Left Ctrl twice: РУС, ЛАТ
    if (downs != 4 || ups != 4) errors = 1;
    $display("tb_kbd: %0d downs %0d ups, %0d errors", downs, ups, errors);
    $finish;
end
endmodule
