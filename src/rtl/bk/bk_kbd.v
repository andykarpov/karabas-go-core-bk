`timescale 1ns / 1ps
//========================================================================
// bk_kbd.v - the keyboard of the БК-0011М out of the PS/2 set 2 scancodes
// of kg_mcu: kbd_tx_bk() of retro-tang-bk mnano/bk.c, which upstream's MCU
// runs, with the same layout (tools/gen_kbd.py has the tables):
//
//   Esc КТ  F1 ПОВТ  F2 ВС  F3 ГРАФ  F5 -!->  F6 ИНДСУ  F7 БЛОК РЕД
//   F8 ШАГ  F9 СБР  F10 СТОП  F11 the reset key
//   Ins |-->  Del |<--  Home/PgUp/End/PgDn the diagonal arrows
//   Shift+Enter УСТ ТАБ  Shift+Tab СБР ТАБ  Right Ctrl СУ  Alt АР2  Caps Lock СТР
//   Left Ctrl РУС / ЛАТ, in turn (karabas: upstream has ЛАТ on Win, which is the board's hotkey
//   key here); the AZ hotkeys Alt+Left Ctrl (palette) and Alt+F4 (512 / 256)
//
// A key held down is sent once: the typematic repeats of the host are dropped (the BK repeats a
// held key itself through 177716 bit 6), and a release goes only for a key that was sent as down,
// so keyboard.v's count of the keys held stays right.
// An event for keyboard.v is key_code with key_flags, one clock of key_stb:
// flags 0 release, 1 АР2, 2 СТОП, 3 the reset key, 4 a controller hotkey
// (АР2+ЛАТ code 1, АР2+РУС code 2).
//========================================================================
module bk_kbd (
    input            clk,
    input      [7:0] scancode,
    input            scancode_upd,    // toggles with each byte
    output reg [7:0] key_code = 8'd0,
    output reg [7:0] key_flags = 8'd0,
    output reg       key_stb = 1'b0
);

localparam [7:0] A_STOP = 8'hF0, A_RESET = 8'hF1, A_CAPS = 8'hF2;
localparam [7:0] F_REL = 8'h01, F_AR2 = 8'h02, F_STOP = 8'h04, F_RESET = 8'h08, F_HOT = 8'h10;

reg upd_d = 1'b0;
reg held_map [0:511];            // {ext, code}: down
integer hi;
initial for (hi = 0; hi < 512; hi = hi + 1) held_map[hi] = 1'b0;
wire was_down = held_map[{ext, scancode}];
reg ext = 1'b0, rel = 1'b0;
reg lsh = 1'b0, rsh = 1'b0, ctl = 1'b0, lalt = 1'b0, ralt = 1'b0;
reg rus = 1'b0;                  // РУС, else ЛАТ (as bk.c, ЛАТ at the start)
reg caps = 1'b0;
reg [9:0] rom_a = 10'd0;
wire [7:0] rom_q;
reg [1:0] st = 2'd0;             // 1 the table's read, 2 its word in
reg pressed = 1'b0;
wire ar2 = lalt | ralt;

bk_kbd_rom rom (.clk(clk), .a(rom_a), .q(rom_q));

// bk.c: a lower case letter minus (rus ^ caps), an upper case one plus it, where its rus is 0x20 in ЛАТ
wire lat_xor = !rus ^ caps;
reg [7:0] v0, v;
always @* begin
    v0 = {1'b0, rom_q[6:0]};
    v = v0;
    if (v0 >= 8'h61 && v0 <= 8'h7A)      v = lat_xor ? v0 - 8'h20 : v0;
    else if (v0 >= 8'h41 && v0 <= 8'h5A) v = lat_xor ? v0 + 8'h20 : v0;
    // the six Cyrillic letters the БК keeps on symbol keys: in РУС the key gives the letter
    if (rus) case (v)
        8'h5B: v = 8'o173;   // Ш
        8'h5D: v = 8'o175;   // Щ
        8'h5C: v = 8'o174;   // Э
        8'h5E: v = 8'o176;   // Ч
        8'h40: v = 8'o140;   // Ю
        8'h7D: v = 8'o177;   // Ъ
        default: ;
    endcase
    if (ctl && v[6]) v = {3'b000, v[4:0]};
end

wire [7:0] flags = (pressed ? 8'h00 : F_REL) | ((rom_q[7] || ar2) ? F_AR2 : 8'h00);

task send; input [7:0] c; input [7:0] f;
    begin key_code <= c; key_flags <= f; key_stb <= 1'b1; end
endtask

always @(posedge clk) begin
    upd_d <= scancode_upd;
    key_stb <= 1'b0;
    if (st == 2'd1) st <= 2'd2;
    if (st == 2'd2) begin
        st <= 2'd0;
        if (rom_q == A_STOP)       send(8'd0, F_STOP  | (pressed ? 8'h00 : F_REL));
        else if (rom_q == A_RESET) send(8'd0, F_RESET | (pressed ? 8'h00 : F_REL));
        else if (rom_q == A_CAPS)  begin if (pressed) caps <= ~caps; end
        else if (rom_q != 8'h00)   send(v, flags);
    end
    if (scancode_upd != upd_d) begin
        if (scancode == 8'hE0) ext <= 1'b1;
        else if (scancode == 8'hF0) rel <= 1'b1;
        else begin
            ext <= 1'b0; rel <= 1'b0;
            case ({ext, scancode})
            9'h012: lsh <= !rel;
            9'h059: rsh <= !rel;
            9'h114: ctl <= !rel;          // right control: СУ
            9'h011: lalt <= !rel;         // Alt: АР2
            9'h111: ralt <= !rel;
            9'h014: begin                 // left control: РУС / ЛАТ in turn, with АР2 the palette hotkey
                held_map[{ext, scancode}] <= !rel;
                if (!rel && !was_down) begin
                    if (ar2) send(8'd2, F_HOT);
                    else begin rus <= !rus; send(rus ? 8'o17 : 8'o16, 8'd0); end
                end else if (rel && was_down && !ar2) send(rus ? 8'o16 : 8'o17, F_REL);
            end
            9'h00C: begin                 // F4: with АР2 the 512/256 hotkey
                held_map[{ext, scancode}] <= !rel;
                if (!rel && !was_down && ar2) send(8'd1, F_HOT);
            end
            default: begin
                held_map[{ext, scancode}] <= !rel;
                if (rel ? was_down : !was_down) begin   // not a repeat, not a release of a key never sent
                    rom_a <= {lsh | rsh, ext, scancode};
                    pressed <= !rel;
                    st <= 2'd1;
                end
            end
            endcase
        end
    end
end

endmodule
