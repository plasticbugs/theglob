//------------------------------------------------------------------------------
// The Pocket's side of the core's memories (docs/core-design.md section 2).
//
// The whole board is 30 KB of program ROM and a 32-byte colour PROM, so it all
// lives in block RAM and nothing here touches the SDRAM or the SRAM
// (METHODOLOGY section 6: "if it fits, do it").  With them go the arbiter, the
// fetch latency and the download FIFO: a block RAM takes a byte on any clock,
// so the loader's pace can never outrun it.
//
//   image 0x0000-0x77FF  Z80 program  -> rom, 32 KB block RAM (top 2 KB unused)
//   image 0x7800-0x781F  colour PROM  -> prom, 32 x 8 block RAM
//
// The layout is theglob.mra's; tools/verify_rom.py checks it against MAME.
//
// The Pocket holds its write strobe for several clocks with address and data
// stable (METHODOLOGY section 5.8).  A RAM write repeated is harmless, but the
// checksum and the byte count are not, so every byte is taken exactly once,
// on the strobe's rising edge.  The checksum is of the whole image, not its
// first word, because reading back the first word proves the path and not
// the image (section 5.21).
//------------------------------------------------------------------------------
`default_nettype none

module theglob_mem (
    input  logic        clk,
    input  logic        clr,            // clears the checksum and the count

    // the ROM image arriving from the Pocket
    input  logic        dl_we,
    input  logic [24:0] dl_addr,
    input  logic  [7:0] dl_data,
    output logic [15:0] dl_sum,         // sum of every byte taken, mod 2^16
    output logic [15:0] dl_count,       // bytes taken (saturates)

    // core ports: registered reads, one clock
    input  logic [14:0] rom_addr,  output logic [7:0] rom_q,
    input  logic  [4:0] prom_addr, output logic [7:0] prom_q
);
    localparam logic [24:0] PROM_B = 25'h007800;
    localparam logic [24:0] END_B  = 25'h007820;

    logic dl_we_d;
    wire  nb      = dl_we && !dl_we_d;          // one byte, once
    wire  to_rom  = nb && (dl_addr < PROM_B);
    wire  to_prom = nb && (dl_addr >= PROM_B) && (dl_addr < END_B);

    always_ff @(posedge clk) begin
        dl_we_d <= dl_we;
        if (clr) begin
            dl_sum   <= '0;
            dl_count <= '0;
        end else if (nb) begin
            dl_sum <= dl_sum + 16'(dl_data);
            if (!(&dl_count)) dl_count <= dl_count + 16'd1;
        end
    end

    // One-dimensional, power-of-two, one write port and one read port: the
    // shape Quartus can only infer one way (section 5.18).
    logic [7:0] rom [32768];
    always_ff @(posedge clk) begin
        if (to_rom) rom[dl_addr[14:0]] <= dl_data;
        rom_q <= rom[rom_addr];
    end

    logic [7:0] prom [32];
    always_ff @(posedge clk) begin
        if (to_prom) prom[dl_addr[4:0]] <= dl_data;
        prom_q <= prom[prom_addr];
    end
endmodule

`default_nettype wire
