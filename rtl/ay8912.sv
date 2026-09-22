//------------------------------------------------------------------------------
// AY-3-8912, written from MAME 0.288's model (ref/mame/ay8910.cpp,
// sound_stream_update, ay8910_write_reg, and the tone/envelope helpers in
// ay8910.h) for an AY in 8910-compatible mode with MAME's default legacy
// output -- which is what theglob's machine config gets (docs/hardware.md 6).
//
// Why not a vendored AY: the core is held to MAME, and a chip model with its
// own volume curve and its own resampling can only be held to it by band
// energy.  This is MAME's arithmetic step for step, so the whole core's audio
// can be compared with MAME's recording directly (sim/run_system.sh -wav,
// tools/audio_seconds.py).  The volume table is MAME's active ay8910_param
// (Matthew Westcott's measurements of a real chip: r_up 800k, r_down 8M, the
// resistor ladder below) through build_single_table -- derived, not fitted
// (METHODOLOGY 5.12), and checked against MAME by writing each of the 16
// levels to channel C from Lua before the game touches the AY: all 16 match
// to a flat 0.994 (the resampler's loss on a square wave).
//
// Step by step, once per 8 chip clocks (MAME's stream runs at clock / 8):
//   1. each tone counter counts up; while it is at or past the period
//      (at least 1) it loses a period and the square output flips -- a
//      period lowered below the count flips it once per whole period, so the
//      remainder and the parity of the quotient are what matter;
//   2. the noise counter counts up; at or past the noise period it clears
//      and a prescaler flips, and every second flip clocks the 17-bit LFSR
//      (input bit0 ^ bit3), whose bit 0 is the noise;
//   3. a channel sounds when (tone | tone-disable) & (noise | noise-disable);
//   4. the envelope counter counts up; at or past twice its period it clears
//      and the 4-bit step counts down, holding or wrapping by the shape;
//   5. each channel is vol_table[vol] or, with bit 4 of its volume, the
//      env_table[envelope] -- index 0 when it is not sounding -- and the
//      three are summed.
//
// Output, in units of 1/32768 of full scale as MAME's WAV writes them:
//   mame   the sum exactly, -12288 at silence (three channels at -4096);
//          the benches compare this with MAME's recording
//   snd    (mame + 12288) / 2: silence at 0 and nothing clipped, for the
//          Pocket.  A known 0.5 and a known offset, not a fit.
//------------------------------------------------------------------------------
`default_nettype none

module ay8912 (
    input  logic        clk,
    input  logic        rst,
    input  logic        cen,            // the chip clock, 687.5 kHz
    input  logic        we,             // one clock: write data to register addr
    input  logic  [3:0] addr,
    input  logic  [7:0] din,
    output logic signed [17:0] mame,
    output logic signed [15:0] snd
);
    // MAME's two tables for ay8910_param (r_up 800k, r_down 8M, ladder
    // 15950 15350 15090 14760 14275 13620 12890 11370 10600 8590 7190 5985
    // 4820 3945 3017 2345, load 1000 ohm),
    // normalised as build_single_table does: ((t - min) / (max - min) - 0.25)
    // * 0.5, times 32768 and rounded.  vol has zero_is_off, env does not.
    function automatic logic signed [15:0] vol_table(input logic [3:0] i);
        case (i)
            4'd0:  return -16'sd4096; 4'd1:    return -16'sd3874;
            4'd2:  return -16'sd3806; 4'd3:    return -16'sd3718;
            4'd4:  return -16'sd3581; 4'd5:    return -16'sd3382;
            4'd6:  return -16'sd3138; 4'd7:    return -16'sd2537;
            4'd8:  return -16'sd2172; 4'd9:    return -16'sd944;
            4'd10: return  16'sd267; 4'd11:   return  16'sd1698;
            4'd12: return  16'sd3646; 4'd13:   return  16'sd5712;
            4'd14: return  16'sd8888; default: return  16'sd12288;
        endcase
    endfunction
    function automatic logic signed [15:0] env_table(input logic [3:0] i);
        case (i)
            4'd0:  return -16'sd4096; 4'd1:    return -16'sd3948;
            4'd2:  return -16'sd3881; 4'd3:    return -16'sd3792;
            4'd4:  return -16'sd3654; 4'd5:    return -16'sd3454;
            4'd6:  return -16'sd3209; 4'd7:    return -16'sd2605;
            4'd8:  return -16'sd2239; 4'd9:    return -16'sd1005;
            4'd10: return  16'sd212; 4'd11:   return  16'sd1650;
            4'd12: return  16'sd3606; 4'd13:   return  16'sd5682;
            4'd14: return  16'sd8872; default: return  16'sd12288;
        endcase
    endfunction

    // ------------------------------------------------------------ registers
    logic [7:0]  r_afine, r_bfine, r_cfine, r_noise, r_enable, r_efine, r_ecoarse;
    logic [3:0]  r_acoarse, r_bcoarse, r_ccoarse;
    logic [4:0]  r_avol, r_bvol, r_cvol;

    // tone generators, noise, envelope (MAME's tone_t, m_rng, envelope_t)
    // three named registers, not an array: nothing for synthesis to interpret
    // (METHODOLOGY 5.18)
    logic [12:0] t_count0, t_count1, t_count2;
    logic        t_out0, t_out1, t_out2;
    logic [4:0]  n_count;
    logic        n_prescale;
    logic [16:0] rng;
    logic [16:0] e_count;
    logic [3:0]  e_step;
    logic        e_neg;                 // step went below zero this tick
    logic [3:0]  e_attack;
    logic        e_hold, e_alt, e_holding;

    // ------------------------------------------------------------ the tick
    // cen / 8, then a short sequence of system clocks: a 13-step divide for
    // each tone channel, then noise, envelope and the mix.
    logic [2:0]  pre;
    logic        tick_req;              // a tick is due
    logic        pend;                  // a write is waiting
    logic [3:0]  pend_a;
    logic [7:0]  pend_d;
    logic [5:0]  seq;                   // 0 idle
    logic [1:0]  ch;
    logic [3:0]  bitn;
    logic [12:0] num, rem;
    logic        qpar;
    logic [11:0] per;

    logic [12:0] cnt;
    always_comb begin
        case (ch)
            2'd0:    begin per = {r_acoarse, r_afine}; cnt = t_count0; end
            2'd1:    begin per = {r_bcoarse, r_bfine}; cnt = t_count1; end
            default: begin per = {r_ccoarse, r_cfine}; cnt = t_count2; end
        endcase
        if (per == 12'd0) per = 12'd1;  // std::max(1, period)
    end

    wire [12:0] rem_sh = {rem[11:0], num[bitn]};
    wire        ge     = rem_sh >= {1'b0, per};

    wire [16:0] e_per2 = {r_ecoarse, r_efine, 1'b0};     // period * m_step (2)

    logic signed [17:0] mix;
    always_comb begin
        logic sa, sb, sc;
        logic [3:0] ev;
        ev = e_step ^ e_attack;
        sa = (t_out0 | r_enable[0]) & (rng[0] | r_enable[3]);
        sb = (t_out1 | r_enable[1]) & (rng[0] | r_enable[4]);
        sc = (t_out2 | r_enable[2]) & (rng[0] | r_enable[5]);
        mix = 18'(r_avol[4] ? env_table(sa ? ev : 4'd0) : vol_table(sa ? r_avol[3:0] : 4'd0))
            + 18'(r_bvol[4] ? env_table(sb ? ev : 4'd0) : vol_table(sb ? r_bvol[3:0] : 4'd0))
            + 18'(r_cvol[4] ? env_table(sc ? ev : 4'd0) : vol_table(sc ? r_cvol[3:0] : 4'd0));
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            // ay8910_reset_ym: every register 0, and writing 0 to the shape
            // register leaves the envelope holding at step 15, attack 0
            r_afine <= '0; r_bfine <= '0; r_cfine <= '0; r_noise <= '0;
            r_enable <= '0; r_efine <= '0; r_ecoarse <= '0;
            r_acoarse <= '0; r_bcoarse <= '0; r_ccoarse <= '0;
            r_avol <= '0; r_bvol <= '0; r_cvol <= '0;
            t_count0 <= '0; t_count1 <= '0; t_count2 <= '0;
            t_out0 <= 1'b0; t_out1 <= 1'b0; t_out2 <= 1'b0;
            n_count <= '0; n_prescale <= 1'b0; rng <= 17'd1;
            e_count <= '0; e_step <= 4'd15; e_attack <= 4'd0;
            e_hold <= 1'b1; e_alt <= 1'b0; e_holding <= 1'b0;
            pre <= '0; seq <= '0; ch <= '0; tick_req <= 1'b0; pend <= 1'b0;
            mame <= -18'sd12288;
        end else begin
            if (cen) pre <= pre + 3'd1;
            if (cen && pre == 3'd7) tick_req <= 1'b1;
            if (we) begin pend <= 1'b1; pend_a <= addr; pend_d <= din; end

            // ---- a write and a tick never overlap: MAME applies a write
            // between two samples, so here a write waits for the sequence to
            // finish and a tick waits for the write
            if (seq == 6'd0) begin
                if (pend && !we) begin
                    pend <= 1'b0;
                    case (pend_a)   // ay8910_write_reg
                        4'd0:  r_afine   <= pend_d;
                        4'd1:  r_acoarse <= pend_d[3:0];
                        4'd2:  r_bfine   <= pend_d;
                        4'd3:  r_bcoarse <= pend_d[3:0];
                        4'd4:  r_cfine   <= pend_d;
                        4'd5:  r_ccoarse <= pend_d[3:0];
                        4'd6:  r_noise   <= pend_d;
                        4'd7:  r_enable  <= pend_d;
                        4'd8:  r_avol    <= pend_d[4:0];
                        4'd9:  r_bvol    <= pend_d[4:0];
                        4'd10: r_cvol    <= pend_d[4:0];
                        4'd11: r_efine   <= pend_d;
                        4'd12: r_ecoarse <= pend_d;
                        4'd13: begin    // set_shape; the counter is left alone
                            e_attack  <= pend_d[2] ? 4'd15 : 4'd0;
                            e_hold    <= pend_d[3] ? pend_d[0] : 1'b1;
                            e_alt     <= pend_d[3] ? pend_d[1] : pend_d[2];
                            e_step    <= 4'd15;
                            e_holding <= 1'b0;
                        end
                        default: ;      // 14, 15: the I/O port, unconnected
                    endcase
                end else if (tick_req && !pend) begin
                    tick_req <= 1'b0;
                    seq <= 6'd1; ch <= 2'd0;
                end
            end else if (seq == 6'd1) begin
                // load a channel: n = count + 1
                num  <= cnt + 13'd1;
                rem  <= '0;
                qpar <= 1'b0;
                bitn <= 4'd12;
                seq  <= 6'd2;
            end else if (seq == 6'd2) begin
                // one step of restoring division of num by per
                rem  <= ge ? rem_sh - {1'b0, per} : rem_sh;
                qpar <= qpar ^ ge;
                if (bitn == 4'd0) seq <= 6'd3;
                else bitn <= bitn - 4'd1;
            end else if (seq == 6'd3) begin
                case (ch)
                    2'd0:    begin t_count0 <= rem; if (qpar) t_out0 <= !t_out0; end
                    2'd1:    begin t_count1 <= rem; if (qpar) t_out1 <= !t_out1; end
                    default: begin t_count2 <= rem; if (qpar) t_out2 <= !t_out2; end
                endcase
                if (ch == 2'd2) seq <= 6'd4;
                else begin ch <= ch + 2'd1; seq <= 6'd1; end
            end else if (seq == 6'd4) begin
                // noise: ++count >= period (5 bits)
                if (5'(n_count + 5'd1) >= r_noise[4:0]) begin
                    n_count    <= '0;
                    n_prescale <= !n_prescale;
                    if (n_prescale)             // flips to 0: clock the LFSR
                        rng <= {rng[0] ^ rng[3], rng[16:1]};
                end else n_count <= n_count + 5'd1;
                // envelope: ++count >= period * 2, then step down
                e_neg <= 1'b0;
                if (!e_holding) begin
                    if (e_count + 17'd1 >= e_per2) begin
                        e_count <= '0;
                        if (e_step == 4'd0) e_neg <= 1'b1;
                        e_step <= e_step - 4'd1;
                    end else e_count <= e_count + 17'd1;
                end
                seq <= 6'd5;
            end else if (seq == 6'd5) begin
                // the step went below zero: hold, or wrap (e_step is already
                // 15, which is MAME's step &= 15)
                if (e_neg) begin
                    if (e_hold) begin
                        if (e_alt) e_attack <= ~e_attack;
                        e_holding <= 1'b1;
                        e_step    <= 4'd0;
                    end else if (e_alt) e_attack <= ~e_attack;
                end
                seq <= 6'd6;
            end else begin
                mame <= mix;
                seq  <= 6'd0;
            end

        end
    end

    wire signed [18:0] lifted = 19'(mame) + 19'sd12288;
    assign snd = 16'(lifted >>> 1);
endmodule

`default_nettype wire
