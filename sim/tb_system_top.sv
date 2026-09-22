// Whole-machine bench: theglob_core behind the Pocket's own memory glue,
// target/pocket/theglob_mem.sv, with the ROM image sent in through its
// download port the way the Pocket's loader sends it (sim/tb_system.cpp sets
// the rate; the default is the loader's).  The board fits in block RAM, so
// the glue is the download and two read ports -- but it is the core_top path,
// not a bench's copy of it (METHODOLOGY section 5.16).
//
// The hardware's first-fault capture runs here too, so it is proven quiet on
// a healthy boot and firing on a sick one before it is trusted (5.21).
`default_nettype none

module tb_system_top (
    input  logic        clk,
    input  logic        reset,
    input  logic        pause,

    // the ROM image, a byte at a time in the order the MRA builds it
    input  logic        dl_we,
    input  logic [24:0] dl_addr,
    input  logic  [7:0] dl_data,
    output logic [15:0] dl_sum, dl_count,

    input  logic  [7:0] dsw, inputs,
    input  logic        start1_n, start2_n, service_n, coin,

    output logic [23:0] rgb,
    output logic        de, pix_ce, vblank, hsync, vsync,
    output logic signed [15:0] snd,

    output logic        wr, wr_io,
    output logic [15:0] wr_addr,
    output logic  [7:0] wr_data,
    output logic        m1,
    output logic [15:0] pc,
    output logic        watchdog_kick, halted,
    output logic        f_hit,
    output logic  [7:0] f_kind, f_n,
    output logic [15:0] f_pc0, f_pc1
);
    logic [14:0] rom_addr;  logic [7:0] rom_q;
    logic  [4:0] prom_addr; logic [7:0] prom_q;

    theglob_mem u_mem (
        .clk(clk), .clr(1'b0),
        .dl_we(dl_we), .dl_addr(dl_addr), .dl_data(dl_data),
        .dl_sum(dl_sum), .dl_count(dl_count),
        .rom_addr(rom_addr), .rom_q(rom_q), .prom_addr(prom_addr), .prom_q(prom_q)
    );

    /* verilator lint_off PINCONNECTEMPTY */
    theglob_core u_core (
        .clk(clk), .rst(reset), .pause(pause), .pix_sync(1'b0),
        .rom_addr(rom_addr), .rom_q(rom_q), .prom_addr(prom_addr), .prom_q(prom_q),
        .dsw(dsw), .inputs(inputs),
        .start1_n(start1_n), .start2_n(start2_n), .service_n(service_n), .coin(coin),
        .rgb(rgb), .hsync(hsync), .vsync(vsync), .hblank(), .vblank(vblank),
        .pix_ce(pix_ce), .de(de), .snd(snd),
        .dbg_m1(m1), .dbg_addr(pc), .dbg_halted(halted), .watchdog_kick(watchdog_kick),
        .dbg_wr(wr), .dbg_wr_io(wr_io), .dbg_wr_addr(wr_addr), .dbg_wr_data(wr_data),
        .dbg_palette()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    dbg_fault u_fault (
        .clk(clk), .rst(reset), .m1(m1), .addr(pc), .halted(halted),
        .hit(f_hit), .kind(f_kind), .pc0(f_pc0), .pc1(f_pc1), .faults(f_n)
    );
endmodule

`default_nettype wire
