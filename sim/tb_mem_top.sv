// Bench wrapper for target/pocket/theglob_mem.sv.  sim/tb_mem.cpp pushes an
// image in through the download port at the APF loader's rate, with the
// strobe held as the Pocket holds it, and reads every byte back through the
// core's ports (METHODOLOGY sections 5.8 and 5.16).
`default_nettype none
module tb_mem_top (
    input  logic        clk, clr,
    input  logic        dl_we, input logic [24:0] dl_addr, input logic [7:0] dl_data,
    output logic [15:0] dl_sum, dl_count,
    input  logic [14:0] rom_addr,  output logic [7:0] rom_q,
    input  logic  [4:0] prom_addr, output logic [7:0] prom_q
);
    theglob_mem dut (
        .clk(clk), .clr(clr), .dl_we(dl_we), .dl_addr(dl_addr), .dl_data(dl_data),
        .dl_sum(dl_sum), .dl_count(dl_count),
        .rom_addr(rom_addr), .rom_q(rom_q), .prom_addr(prom_addr), .prom_q(prom_q)
    );
endmodule
`default_nettype wire
