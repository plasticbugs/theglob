//------------------------------------------------------------------------------
// The Glob -- the Epos Tristar 8000 board, platform-agnostic.
//
// docs/hardware.md is the specification; each block below names its section.
//
//   Z80 at 2.75 MHz (z80_cpu, tv80)          0000-77FF ROM   (theglob_mem)
//   2 KB work RAM, 32 KB VRAM (block RAM)    7800-7FFF RAM, 8000-FFFF VRAM
//   bitmap video (theglob_video) + PROM      one IRQ per frame, IM 1
//   AY-3-8912 at 687.5 kHz (jt49)
//
// The ROM and the colour PROM live on the platform side (the Pocket's
// download writes them), behind two registered read ports.  Everything else
// is here.
//------------------------------------------------------------------------------
`default_nettype none

module theglob_core (
    input  logic        clk,            // 88 MHz
    input  logic        rst,
    input  logic        pause,          // freeze the CPU and sound, keep the picture
    input  logic        pix_sync,       // see clk_enables.sv

    // ---------------- ROM image, registered reads (target/pocket/theglob_mem.sv)
    output logic [14:0] rom_addr,  input  logic [7:0] rom_q,
    output logic  [4:0] prom_addr, input  logic [7:0] prom_q,

    // ---------------- inputs, as the board's ports read them (hardware.md 3)
    input  logic  [7:0] dsw,            // port 00, MAME's default is 00
    input  logic  [7:0] inputs,         // port 02, active low: 0 R, 1 L, 2 b1, 3 b2, 4 U, 5 D
    input  logic        start1_n, start2_n, service_n,
    input  logic        coin,           // the coin switch, active high

    // ---------------- video, one pixel per pix_ce in the clk domain
    output logic [23:0] rgb,
    output logic        hsync, vsync, hblank, vblank,
    output logic        pix_ce, de,

    output logic signed [15:0] snd,

    // ---------------- bring-up (the panel in core_top, sim/)
    output logic        dbg_m1,         // one clock per opcode fetch, address on dbg_addr
    output logic [15:0] dbg_addr,
    output logic        dbg_halted,
    output logic        watchdog_kick,  // one clock per OUT 00
    output logic        dbg_wr,         // one clock per CPU write (bus-trace benches)
    output logic        dbg_wr_io,
    output logic [15:0] dbg_wr_addr,
    output logic  [7:0] dbg_wr_data,
    output logic  [7:0] dbg_palette     // output latch, port 01
);
    // ------------------------------------------------------------ clocks
    logic cen_cpu, cen_ay, cen_pix;
    clk_enables u_cen (
        .clk(clk), .rst(rst), .pause(pause), .pix_sync(pix_sync),
        .cen_cpu(cen_cpu), .cen_ay(cen_ay), .cen_pix(cen_pix)
    );

    // ------------------------------------------------------------ CPU
    logic        m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n, halt_n, busak_n;
    logic [15:0] A;
    logic  [7:0] cpu_dout, cpu_din;
    logic        int_n;

    z80_cpu u_cpu (
        .clk(clk), .cen(cen_cpu), .reset_n(!rst),
        .wait_n(1'b1), .int_n(int_n), .nmi_n(1'b1), .busrq_n(1'b1),
        .m1_n(m1_n), .mreq_n(mreq_n), .iorq_n(iorq_n), .rd_n(rd_n), .wr_n(wr_n),
        .rfsh_n(rfsh_n), .halt_n(halt_n), .busak_n(busak_n),
        .A(A), .di(cpu_din), .dout(cpu_dout)
    );

    // ------------------------------------------------------------ writes
    // Every write happens once, in the clock after the CPU lets go of WR,
    // with the address and data it held on the last clock WR was low.  A
    // RAM write repeated would be harmless; an AY envelope restart or a
    // watchdog count repeated would not.
    logic        wr_n_d, wq_io;
    logic [15:0] wq_a;
    logic  [7:0] wq_d;
    always_ff @(posedge clk) begin
        wr_n_d <= wr_n;
        if (!wr_n) begin wq_a <= A; wq_d <= cpu_dout; wq_io <= !iorq_n; end
    end
    wire wr_pulse = wr_n && !wr_n_d && !rst;
    wire wr_mem   = wr_pulse && !wq_io;
    wire wr_io    = wr_pulse &&  wq_io;

    // ------------------------------------------------------------ memory map (hardware.md 2)
    // Work RAM and VRAM: one-dimensional, power-of-two block RAMs.  The
    // VRAM's second port is the video's.
    logic [7:0] ram [2048];
    logic [7:0] ram_q;
    always_ff @(posedge clk) begin
        if (wr_mem && wq_a[15:11] == 5'b01111) ram[wq_a[10:0]] <= wq_d;
        ram_q <= ram[A[10:0]];
    end

    // One write port, two read ports (the CPU's and the video's).  Quartus
    // builds that as two copies of the RAM, both written together -- its
    // standard answer for a second read port, 52 of the device's 308 M10K
    // blocks, which this board can afford.
    logic [7:0]  vram [32768];
    logic [7:0]  vram_cpu_q, vram_vid_q;
    logic [14:0] vram_vid_a;
    always_ff @(posedge clk) begin
        if (wr_mem && wq_a[15]) vram[wq_a[14:0]] <= wq_d;
        vram_cpu_q <= vram[A[14:0]];
    end
    always_ff @(posedge clk) vram_vid_q <= vram[vram_vid_a];

    assign rom_addr = A[14:0];

    // ------------------------------------------------------------ I/O (hardware.md 3)
    // outputs: port 01 latch (D3 palette bank), AY address latch
    logic [7:0] out01;
    logic [3:0] ay_reg;
    logic       ay_active;
    logic       coin_latch, coin_d;
    always_ff @(posedge clk) begin
        coin_d <= coin;
        if (rst) begin
            out01 <= 8'h00; ay_reg <= 4'd0; ay_active <= 1'b0; coin_latch <= 1'b0;
        end else begin
            // the 74LS74 is clocked by the coin switch; OUT 03 clears it
            if (coin && !coin_d) coin_latch <= 1'b1;
            if (wr_io) case (wq_a[7:0])
                8'h01: out01 <= wq_d;
                8'h03: coin_latch <= 1'b0;
                // the AY answers an address only when its top four bits
                // are the mask-programmed 0000 (ay8910.cpp, address_w)
                8'h06: begin ay_active <= (wq_d[7:4] == 4'd0); ay_reg <= wq_d[3:0]; end
                default: ;
            endcase
        end
    end
    wire palbank = out01[3];

    // SYSTEM: 0 coin latch, 1 second coin latch (not connected), 2 start 1,
    // 3 start 2, 4 service, 5 unused, 6 must read 0, 7 must read 1
    wire [7:0] system = {1'b1, 1'b0, 1'b1, service_n, start2_n, start1_n, 1'b0, coin_latch};

    // ------------------------------------------------------------ read mux
    // IM 1 ignores the data bus in the acknowledge; 0xFF is RST 38 anyway.
    wire intack = !m1_n && !iorq_n;
    always_comb begin
        if (intack)                     cpu_din = 8'hFF;
        else if (!iorq_n) case (A[7:0])
            8'h00:   cpu_din = dsw;
            8'h01:   cpu_din = system;
            8'h02:   cpu_din = inputs;
            default: cpu_din = 8'hFF;       // never read (hardware.md 9)
        endcase
        else if (A[15])                 cpu_din = vram_cpu_q;
        else if (A[15:11] == 5'b01111)  cpu_din = ram_q;
        else                            cpu_din = rom_q;
    end

    // ------------------------------------------------------------ interrupt (hardware.md 4)
    // MAME's irq0_line_hold: asserted as vblank begins, held until the CPU
    // acknowledges it.
    logic vbl_start;
    always_ff @(posedge clk) begin
        if (rst)            int_n <= 1'b1;
        else if (vbl_start) int_n <= 1'b0;
        else if (intack)    int_n <= 1'b1;
    end

    // ------------------------------------------------------------ video (hardware.md 7)
    logic [4:0] pen;
    logic       v_de, v_hb, v_vb, v_hs, v_vs;
    theglob_video u_video (
        .clk(clk), .rst(rst), .cen_pix(cen_pix), .palbank(palbank),
        .vram_addr(vram_vid_a), .vram_q(vram_vid_q),
        .pen(pen), .de(v_de), .hblank(v_hb), .vblank(v_vb),
        .hsync(v_hs), .vsync(v_vs), .vblank_start(vbl_start)
    );

    // The PROM is a registered read: the pen goes in on one dot and its
    // colour comes out registered on the next, with the timing beside it.
    assign prom_addr = pen;
    function automatic [23:0] prom_rgb(input logic [7:0] d);
        logic [7:0] r, g, b;
        r = (d[7] ? 8'h92 : 8'h00) + (d[6] ? 8'h4A : 8'h00) + (d[5] ? 8'h23 : 8'h00);
        g = (d[4] ? 8'h92 : 8'h00) + (d[3] ? 8'h4A : 8'h00) + (d[2] ? 8'h23 : 8'h00);
        b = (d[1] ? 8'hAD : 8'h00) + (d[0] ? 8'h52 : 8'h00);
        return {r, g, b};
    endfunction
    always_ff @(posedge clk) begin
        if (cen_pix) begin
            rgb    <= v_de ? prom_rgb(prom_q) : 24'h000000;
            de     <= v_de;
            hblank <= v_hb;
            vblank <= v_vb;
            hsync  <= v_hs;
            vsync  <= v_vs;
        end
    end
    assign pix_ce = cen_pix;

    // ------------------------------------------------------------ sound (hardware.md 6)
    // AY-3-8912: jt49 with its enable at the chip's own clock (sel = 1, no
    // extra divide).  The 8912 has one I/O port and nothing is wired to it.
    wire       ay_wr = wr_io && (wq_a[7:0] == 8'h02) && ay_active;
    wire [9:0] ay_sound;
    /* verilator lint_off PINCONNECTEMPTY */
    jt49 u_ay (
        .rst_n(!rst), .clk(clk), .clk_en(cen_ay),
        .addr(ay_reg), .cs_n(!ay_wr), .wr_n(!ay_wr), .din(wq_d), .sel(1'b1),
        .dout(), .sound(ay_sound), .A(), .B(), .C(), .sample(),
        .IOA_in(8'hFF), .IOA_out(), .IOA_oe(), .IOB_in(8'hFF), .IOB_out(), .IOB_oe()
    );
    /* verilator lint_on PINCONNECTEMPTY */
    // three channels summed, 0..1023 unsigned; centred and scaled to 16 bits
    assign snd = 16'($signed({1'b0, ay_sound, 5'd0}) - 16'sd16384);

    // ------------------------------------------------------------ bring-up
    logic m1_n_d;
    always_ff @(posedge clk) m1_n_d <= m1_n;
    assign dbg_m1        = !m1_n && m1_n_d;     // falling edge of M1: A is the PC
    assign dbg_addr      = A;
    assign dbg_halted    = !halt_n;
    assign watchdog_kick = wr_io && (wq_a[7:0] == 8'h00);
    assign dbg_wr        = wr_pulse;
    assign dbg_wr_io     = wq_io;
    assign dbg_wr_addr   = wq_a;
    assign dbg_wr_data   = wq_d;
    assign dbg_palette   = out01;

    wire _unused = &{1'b0, rd_n, rfsh_n, busak_n, 1'b0};
endmodule

`default_nettype wire
