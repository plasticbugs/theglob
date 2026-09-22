// Frozen-state video bench: rtl/theglob_video.sv reading a VRAM that
// sim/tb_video.cpp fills from a MAME state.  The VRAM here is a registered
// read port, one clock, like the block RAM in the core.
`default_nettype none
module tb_video_top (
    input  logic        clk,
    input  logic        rst,
    input  logic        cen_pix,
    input  logic        palbank,
    input  logic        load_we,
    input  logic [14:0] load_addr,
    input  logic  [7:0] load_data,
    output logic  [4:0] pen,
    output logic        de, hblank, vblank, hsync, vsync, vblank_start
);
    logic [7:0]  vram [32768];
    logic [14:0] va;
    logic [7:0]  vq;
    always_ff @(posedge clk) begin
        if (load_we) vram[load_addr] <= load_data;
        vq <= vram[va];
    end
    theglob_video dut (
        .clk(clk), .rst(rst), .cen_pix(cen_pix), .palbank(palbank),
        .vram_addr(va), .vram_q(vq),
        .pen(pen), .de(de), .hblank(hblank), .vblank(vblank),
        .hsync(hsync), .vsync(vsync), .vblank_start(vblank_start)
    );
endmodule
`default_nettype wire
