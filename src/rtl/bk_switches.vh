// The registers of kg_soft_switches: the index of an item is its position in "osd" of core.json, the F items
// and the separator included (karabas-go-notes osd-switch-index). Change core.json and this file together.
localparam SW_CPU = 6;      // 4 / 8 MHz
localparam SW_JOY = 7;      // the joystick on 177714
localparam SW_COVOX = 8;    // the legacy Covox on 177714
localparam SW_VOLUME = 9;   // off, 1/4, 1/2, 1
localparam SW_RESET = 10;
localparam SW_MONITOR = 11; // Display: 0 colour, 1 mono (the BK monitor), 2 grey (option values); pinned "index" in core.json
localparam SW_N = 12;
