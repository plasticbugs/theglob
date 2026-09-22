//------------------------------------------------------------------------------
// DC blocker on the 48 kHz samples handed to the Pocket: what the coupling
// capacitor between a board's sound chip and its amplifier does.
//
//     y[n] = x[n] - x[n-1] + (1 - 2^-9) * y[n-1]        corner 14.9 Hz
//
// The AY's output reaches the Pocket never negative -- silence at 0, the
// channels above it (rtl/ay8912.sv) -- so a note that stops or starts moves
// the average level in one step, and that step is the thump at each end of
// the jump sound: channel A, a 42 Hz square ramping to volume 10 and then
// cut to 0.  Measured with tools/dc_block_model.py on 25 s of this core's
// play: energy below ~20 Hz during the jump sounds (12-16 s) 649 -> 132
// (-14 dB), DC 227 -> 0.  What it cannot remove, and does not claim to: the
// square wave's own edges while a note sounds (largest step 8062 before and
// after).  14.9 Hz sits well below the game's lowest note (42 Hz); 29.8 Hz
// took the thump to 89 but tilts that note's flat tops.
//
// The form and its two lessons are the BBC Micro core's: the accumulator
// carries 8 fractional bits, or `y >>> 9` is zero for small |y|, the leak
// never fires and the DC goes straight through; and the output is clamped,
// not wrapped.  MAME does not model this stage, so the benches that compare
// with MAME take the AY before it; sim/run_reverb.sh holds this to its model.
//------------------------------------------------------------------------------
`default_nettype none

module dc_block (
    input  logic               clk,
    input  logic               reset,
    input  logic               ce,          // one 48 kHz sample, `in` valid with it
    input  logic signed [15:0] in,
    output logic signed [15:0] out,         // valid from out_tick, three clocks after ce
    output logic               out_tick
);
    localparam int K = 9, FRAC = 8;
    // Three clocks per sample, each one short: take the sample, update the
    // accumulator, clamp.  In one clock the path ran from the DSP block that
    // averages the sample (core_top) through both adds and the clamp and
    // missed 88 MHz by 0.307 ns; the arithmetic is the same either way.
    logic signed [15:0] x_q, x_d;
    logic signed [25:0] y;
    logic               s1, s2;
    wire  signed [25:0] y_next = y - (y >>> K) + ((26'(x_q) - 26'(x_d)) <<< FRAC);
    wire  signed [25:0] y_out  = y >>> FRAC;
    always_ff @(posedge clk) begin
        out_tick <= 1'b0;
        s1 <= 1'b0;
        s2 <= 1'b0;
        if (reset) begin
            x_q <= '0; x_d <= '0; y <= '0; out <= '0;
        end else begin
            if (ce) begin x_q <= in; s1 <= 1'b1; end
            if (s1) begin y <= y_next; x_d <= x_q; s2 <= 1'b1; end
            if (s2) begin
                out <= (y_out > 26'sd32767) ? 16'sd32767 : (y_out < -26'sd32768) ? -16'sd32768 : 16'(y_out);
                out_tick <= 1'b1;
            end
        end
    end
endmodule

`default_nettype wire
