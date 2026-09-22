//------------------------------------------------------------------------------
// Clock enables from the 88 MHz system clock (docs/core-design.md section 1).
//
// The board runs everything off one 11 MHz crystal, and 88 MHz is eight of
// it, so every enable is a plain counter with no fractional accumulator and
// no error against the board:
//
//   cen_cpu   Z80        11 / 4  = 2.75 MHz    88 / 32
//   cen_ay    AY-3-8912  11 / 16 = 687.5 kHz   88 / 128
//   cen_pix   dot clock  11 / 2  = 5.5 MHz     88 / 16
//
// The rates are the board's; the phase between the CPU and the dot counter is
// not (the dot divider follows clk_vid, the CPU divider stops for the menu).
// Nothing on this board depends on it: the CPU never reads the raster.
//------------------------------------------------------------------------------
`default_nettype none

module clk_enables (
    input  logic clk,
    input  logic rst,
    // One pulse just after each edge of the platform's video clock, which
    // restarts the dot divider.  Without it the dot enable would sit at
    // whatever phase the reset left it in, and the pixel handed to the video
    // clock could be sampled while it changes (METHODOLOGY section 5.4).
    input  logic pix_sync,
    input  logic pause,     // hold the CPU and the sound chip; see below
    output logic cen_cpu,
    output logic cen_ay,
    output logic cen_pix
);
    logic [6:0] div;        // 0..127: the CPU and the AY divide this
    logic [3:0] dpix;       // 0..15

    always_ff @(posedge clk) begin
        if (rst) begin
            div  <= 7'd0;
            dpix <= 4'd0;
        end else begin
            if (!pause) div <= div + 7'd1;
            if (pix_sync) dpix <= 4'd0;
            else          dpix <= dpix + 4'd1;
        end
    end

    // Pausing freezes the divider and masks the enables with the same signal,
    // so every count still produces exactly one pulse: nothing is skipped and
    // nothing fires twice.  The dot divider is separate and keeps running,
    // which is what leaves the picture on the screen behind the Pocket's menu
    // (the menu-open signal must never reach reset -- METHODOLOGY 5.5).
    wire run = !pause;
    assign cen_cpu = run && (div[4:0] == 5'd0);
    assign cen_ay  = run && (div      == 7'd0);
    assign cen_pix = (dpix == 4'd0);
endmodule

`default_nettype wire
