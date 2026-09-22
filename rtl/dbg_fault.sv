//------------------------------------------------------------------------------
// First-fault capture for hardware bring-up, for a Z80.
//
// Watches the opcode fetches (M1) and freezes on the first thing a healthy run
// never does: an opcode fetched from outside the ROM (at or above 7800, work
// RAM or VRAM) or the CPU halting.  sim/run_system.sh proves it quiet on a
// healthy boot and firing on a sick one (a corrupted ROM image).  What is
// kept is which it was, the two opcode addresses fetched before it, and how
// many such events there have been.
//
// Whether those come out the same on every power-up is the point: the same
// place every time is a logic or timing fault at one instruction, a different
// place each time is a memory that misreads now and then.
//------------------------------------------------------------------------------
`default_nettype none

module dbg_fault (
    input  logic        clk,
    input  logic        rst,
    input  logic        m1,             // one clock per opcode fetch
    input  logic [15:0] addr,           // the fetch address while m1
    input  logic        halted,
    output logic        hit,            // something was caught
    output logic  [7:0] kind,           // 01 fetch outside ROM, 02 halt, 00 none
    output logic [15:0] pc0, pc1,       // the fetch that faulted, and the one before
    output logic  [7:0] faults          // events since, saturating
);
    logic [15:0] h0;
    logic        halted_d;
    wire         bad_fetch = m1 && (addr >= 16'h7800);
    wire         bad_halt  = halted && !halted_d;
    wire         bad       = bad_fetch || bad_halt;

    always_ff @(posedge clk) begin
        halted_d <= halted;
        if (rst) begin
            hit <= 1'b0; faults <= '0; h0 <= '0;
            kind <= '0; pc0 <= '0; pc1 <= '0;          // a clean panel reads all zeros
        end else begin
            if (m1) h0 <= addr;
            if (bad && !(&faults)) faults <= faults + 8'd1;
            if (bad && !hit) begin
                hit  <= 1'b1;
                kind <= bad_fetch ? 8'h01 : 8'h02;
                pc0  <= bad_fetch ? addr : h0;
                pc1  <= h0;
            end
        end
    end
endmodule

`default_nettype wire
