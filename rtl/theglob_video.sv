//------------------------------------------------------------------------------
// The Tristar 8000's video: a raster counter and a 4-bit-per-pixel bitmap
// read out of VRAM.  docs/hardware.md section 7; tools/render_model.py is the
// specification, and sim/run_video.sh holds this to it on frozen states.
//
//   dot clock 5.5 MHz, 352 x 258, 272 x 236 visible from 0,0 (60.562 Hz)
//   VRAM byte y * 136 + x / 2; LOW nibble is the left (even) pixel
//   pen = palette_bank << 4 | nibble
//
// The bitmap is read live, a byte per two dots, as the board does, so a CPU
// write during the visible area shows on the lines not yet drawn.  MAME
// draws the whole frame from VRAM at the start of vblank instead, which is
// the same picture whenever the program writes VRAM only in vblank.
//
// Pipeline, in the system clock between two dot enables: the counters move
// on a dot enable, the VRAM address follows, the byte arrives a clock later,
// and the next dot enable registers the pen with the position it belongs to.
// So every output (pen, de, syncs, blanks) is one dot behind the counters,
// together.
//------------------------------------------------------------------------------
`default_nettype none

module theglob_video (
    input  logic        clk,
    input  logic        rst,
    input  logic        cen_pix,
    input  logic        palbank,

    output logic [14:0] vram_addr,      // to a registered VRAM read port
    input  logic  [7:0] vram_q,

    output logic  [4:0] pen,            // palette index, 0 outside the picture
    output logic        de, hblank, vblank, hsync, vsync,
    output logic        vblank_start    // one clock, as line 236 begins: the IRQ
);
    localparam int HTOTAL = 352, VTOTAL = 258, W = 272, H = 236;
    // Sync positions are not in MAME's driver; these sit inside the blanking
    // and are what the Pocket's scaler locks to.
    localparam int HS0 = 296, HS1 = 328, VS0 = 240, VS1 = 243;

    // Out of reset the raster starts at the top of vblank, as MAME's does:
    // its first frame ends a whole frame after power-on, not 236 lines after
    // (measured: 22 lines, 3,872 CPU cycles, of constant offset between the
    // two write traces until this matched).  A real board's power-on phase is
    // arbitrary; this one makes a trace from reset comparable with MAME's.
    logic [8:0] hc, vc;
    always_ff @(posedge clk) begin
        if (rst) begin
            hc <= 9'd1;
            vc <= 9'(H);
        end else if (cen_pix) begin
            if (hc == 9'(HTOTAL - 1)) begin
                hc <= '0;
                vc <= (vc == 9'(VTOTAL - 1)) ? 9'd0 : vc + 9'd1;
            end else hc <= hc + 9'd1;
        end
    end

    // y * 136 = y * 128 + y * 8; only lines 0..235 are ever shown, which
    // stay inside 15 bits
    wire [15:0] line_base = {vc, 7'd0} + {4'd0, vc, 3'd0};
    wire [15:0] byte_addr = line_base + {8'd0, hc[8:1]};
    assign vram_addr = byte_addr[14:0];

    wire vis = (hc < 9'(W)) && (vc < 9'(H));
    always_ff @(posedge clk) begin
        if (rst) begin
            pen <= '0; de <= 1'b0; hblank <= 1'b1; vblank <= 1'b1;
            hsync <= 1'b0; vsync <= 1'b0;
        end else if (cen_pix) begin
            pen    <= vis ? {palbank, hc[0] ? vram_q[7:4] : vram_q[3:0]} : 5'd0;
            de     <= vis;
            hblank <= !(hc < 9'(W));
            vblank <= !(vc < 9'(H));
            hsync  <= (hc >= 9'(HS0)) && (hc < 9'(HS1));
            vsync  <= (vc >= 9'(VS0)) && (vc < 9'(VS1));
        end
    end

    assign vblank_start = cen_pix && (hc == 9'd0) && (vc == 9'(H));
endmodule

`default_nettype wire
