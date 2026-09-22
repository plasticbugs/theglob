# ==============================================================================
# The Glob on the Pocket: timing constraints beyond the BSP's
# sys_constr.sdc. The 88 MHz system clock and its 5.5 MHz video pair come
# from core_pll and are timed as one related group; the two 74.25 MHz inputs
# and the audio PLL are asynchronous to it.  The PLL's fourth and fifth
# outputs drive nothing in core_top, so no clock of theirs reaches the
# netlist and they are not named here -- naming one only bought an
# ignored-filter warning that hid the ones that mattered.
# ==============================================================================
set_clock_groups -asynchronous \
 -group { bridge_spiclk } \
 -group { clk_74a } \
 -group { clk_74b } \
 -group { ic|core_pll|core_pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk \
          ic|core_pll|core_pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk \
          ic|core_pll|core_pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk } \
 -group { ic|pocket_audio_mixer|audio_pll|mf_audio_pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk } \
 -group { ic|pocket_audio_mixer|audio_pll|mf_audio_pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk }

# The pixel hand-over to the 5.5 MHz video clock. The dot enable's phase is
# pinned to clk_vid (core_top.sv's pix_sync into clk_enables.sv), so the
# colour and sync registers are launched a fixed number of system clocks
# before the clk_vid edge that samples them, and the setup check starts from
# that launch edge. The toggle the other way (vt -> vt_s) is a plain
# flop-to-flop path, checked as it stands.
set VID_OUT [get_registers {ic|vr_q[*] ic|vg_q[*] ic|vb_q[*] ic|vhs_q ic|vvs_q ic|vde_q}]
set_multicycle_path -setup 3 -start -from [get_clocks {ic|core_pll|core_pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -to $VID_OUT
set_multicycle_path -hold  2 -start -from [get_clocks {ic|core_pll|core_pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -to $VID_OUT

# The SDRAM, the SRAM and the PSRAMs are unused on this board (the whole
# machine is in block RAM); core_top ties their pins off, and the BSP still
# brings them out.
set_false_path -to   [get_ports {dram_* sram_*}]
set_false_path -from [get_ports {dram_dq[*] sram_dq[*]}]
set_false_path -to   [get_ports {cram0_* cram1_*}]
set_false_path -from [get_ports {cram0_dq[*] cram1_dq[*] cram0_wait cram1_wait}]

# ------------------------------------------------------------------------------
# The Z80 (rtl/z80_cpu.sv around modules/cpu-tv80) steps on cen_cpu, one
# system clock in 32 (rtl/clk_enables.sv).  Why EVERYTHING this filter matches
# qualifies (METHODOLOGY 5.11), checked in the source:
#   * every sequential block in tv80_core.v is inside `if (ClkEn)` (ClkEn =
#     cen && ~BusAck) or `if (cen)`, apart from its asynchronous reset;
#   * tv80_reg.v writes RegsH/RegsL only under CEN;
#   * z80_cpu.sv's own strobe registers and di_reg step only on cen.
# So a path that starts and ends inside z80_cpu has 32 clocks; 4 is claimed,
# which is ample (the worst such path is ~12.1 ns) and far from the edge.
# Paths INTO the CPU -- the read-data mux from the block RAMs and ports, and
# INT -- start outside it, are not matched, and stay single-cycle, as do
# paths OUT of it into the RAM address and write registers.  Anything added
# inside z80_cpu later must be cen-gated too, or it does not belong there.
set Z80 [get_keepers {*|z80_cpu:u_cpu|*}]
set_multicycle_path -setup 4 -from $Z80 -to $Z80
set_multicycle_path -hold  3 -from $Z80 -to $Z80
