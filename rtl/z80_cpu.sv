//------------------------------------------------------------------------------
// Z80 with a clock enable: modules/cpu-tv80's tv80s wrapper, with its
// hard-wired `cen = 1` replaced by a port and the bus-strobe register stepping
// on that enable.  Nothing else differs from tv80s.v (Mode 0, T2Write 1,
// IOWait 1), so the strobes keep their real Z80 shape in T-states: MREQ/RD
// from T1 to T3 of a read, WR one T-state from T2 of a write.
//
// Derived from tv80s.v, TV80 8-Bit Microprocessor Core, Copyright (c) 2004
// Guy Hutchison, based on the VHDL T80 core by Daniel Wallner.  MIT licence:
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the "Software"),
// to deal in the Software without restriction, including without limitation
// the rights to use, copy, modify, merge, publish, distribute, sublicense,
// and/or sell copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
// DEALINGS IN THE SOFTWARE.
//------------------------------------------------------------------------------
`default_nettype none

module z80_cpu (
    input  logic        clk,
    input  logic        cen,
    input  logic        reset_n,
    input  logic        wait_n,
    input  logic        int_n,
    input  logic        nmi_n,
    input  logic        busrq_n,
    output logic        m1_n,
    output logic        mreq_n,
    output logic        iorq_n,
    output logic        rd_n,
    output logic        wr_n,
    output logic        rfsh_n,
    output logic        halt_n,
    output logic        busak_n,
    output logic [15:0] A,
    input  logic  [7:0] di,
    output logic  [7:0] dout
);
    wire       intcycle_n, no_read, write, iorq;
    wire [6:0] mcycle, tstate;
    logic [7:0] di_reg;

    /* verilator lint_off PINCONNECTEMPTY */
    tv80_core #(.Mode(0), .IOWait(1)) u_core (
        .cen(cen), .m1_n(m1_n), .iorq(iorq), .no_read(no_read), .write(write),
        .rfsh_n(rfsh_n), .halt_n(halt_n), .wait_n(wait_n), .int_n(int_n),
        .nmi_n(nmi_n), .reset_n(reset_n), .busrq_n(busrq_n), .busak_n(busak_n),
        .clk(clk), .IntE(), .stop(), .A(A), .dinst(di), .di(di_reg), .dout(dout),
        .mc(mcycle), .ts(tstate), .intcycle_n(intcycle_n)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            rd_n   <= 1'b1;
            wr_n   <= 1'b1;
            iorq_n <= 1'b1;
            mreq_n <= 1'b1;
            di_reg <= 8'h00;
        end else if (cen) begin
            rd_n   <= 1'b1;
            wr_n   <= 1'b1;
            iorq_n <= 1'b1;
            mreq_n <= 1'b1;
            if (mcycle[0]) begin
                if (tstate[1] || (tstate[2] && !wait_n)) begin
                    rd_n   <= ~intcycle_n;
                    mreq_n <= ~intcycle_n;
                    iorq_n <= intcycle_n;
                end
            end else begin
                if ((tstate[1] || (tstate[2] && !wait_n)) && !no_read && !write) begin
                    rd_n   <= 1'b0;
                    iorq_n <= ~iorq;
                    mreq_n <= iorq;
                end
                if ((tstate[1] || (tstate[2] && !wait_n)) && write) begin
                    wr_n   <= 1'b0;
                    iorq_n <= ~iorq;
                    mreq_n <= iorq;
                end
            end
            if (tstate[2] && wait_n && !write && !no_read)
                di_reg <= di;
        end
    end
endmodule

`default_nettype wire
