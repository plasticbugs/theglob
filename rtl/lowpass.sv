//------------------------------------------------------------------------------
// Audio Filter: a low-pass on the 48 kHz samples handed to the Pocket, after
// the DC blocker and before the reverb.  An option, not the board -- MAME
// does not filter this driver, so the benches that compare with MAME take the
// AY before it.
//
// Why: the jump sound is a 42 Hz square, and at 42 Hz each edge of a square
// is heard as its own tick -- the first and the last most of all.  Measured
// on this core's play, those edges are steps of ~8000 in one sample; the
// volume writes that start and stop the sound are only ~200 (a glide on them
// was tried and removed: it did not touch the tick).  So the edges are what
// has to be softened, and that is a low-pass.
//
// Two one-pole sections in cascade, y += a * (x - y) each, with a a sum of two
// shifts, 8 fractional bits.  Measured with tools/lowpass_model.py on the
// jump sounds (12-16 s; the edge step is 8066 with no filter):
//   mode 1 Light  a = 3/8,  -3 dB at 2.35 kHz: edge step 1448,
//                 1.2-4 kHz kept 0.88, 4-12 kHz 0.35          (the default)
//   mode 2 Heavy  a = 3/16, -3 dB at 1.03 kHz: edge step  646,
//                 1.2-4 kHz kept 0.61, 4-12 kHz 0.10
// Chosen on hardware by ear: a first Light at a = 1/2 (3.5 kHz, step 2066)
// "barely did anything"; this Light sits between it and the first Medium
// (a = 1/4, 1.4 kHz), and Heavy a little past that Medium.
// Mode 0 passes the input through with the same latency, so switching never
// clicks.  Three clocks per sample, each one short (the DC blocker's lesson).
//------------------------------------------------------------------------------
`default_nettype none

module lowpass (
    input  logic               clk,
    input  logic               reset,
    input  logic               ce,          // one 48 kHz sample, `in` valid with it
    input  logic        [1:0]  mode,        // 0 off, 1 light, 2 heavy (3 = heavy)
    input  logic signed [15:0] in,
    output logic signed [15:0] out,         // valid from out_tick, three clocks after ce
    output logic               out_tick
);
    logic signed [15:0] x_q;
    logic        [1:0]  m_q;
    logic signed [23:0] y1, y2;             // 16 bits and 8 of fraction
    logic               s1, s2;
    // a * d: 3/8 (d>>2 + d>>3) for Light, 3/16 (d>>3 + d>>4) for Heavy
    function automatic logic signed [23:0] step(input logic signed [23:0] d, input logic heavy);
        step = heavy ? (d >>> 3) + (d >>> 4) : (d >>> 2) + (d >>> 3);
    endfunction
    wire  heavy = (m_q != 2'd1);
    wire  signed [23:0] v   = 24'(x_q) <<< 8;
    wire  signed [23:0] y1n = y1 + step(v - y1, heavy);
    wire  signed [23:0] y2n = y2 + step(y1 - y2, heavy);  // y1 as updated below, one clock later
    always_ff @(posedge clk) begin
        out_tick <= 1'b0;
        s1 <= 1'b0;
        s2 <= 1'b0;
        if (reset) begin
            x_q <= '0; m_q <= '0; y1 <= '0; y2 <= '0; out <= '0;
        end else begin
            if (ce) begin x_q <= in; m_q <= mode; s1 <= 1'b1; end
            if (s1) begin y1 <= y1n; s2 <= 1'b1; end
            if (s2) begin
                y2       <= y2n;
                out      <= (m_q == 2'd0) ? x_q : 16'(y2n >>> 8);
                out_tick <= 1'b1;
            end
        end
    end
endmodule

`default_nettype wire
