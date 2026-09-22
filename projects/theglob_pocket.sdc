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
# Multicycle exceptions for clock-enabled blocks go here.  None are claimed
# yet, because the skeleton has nothing that needs one.  Before adding any,
# read METHODOLOGY.md sections 5.11 and 5.20:
#
#   * write down why EVERYTHING the filter matches qualifies, and register
#     every input at the edge of the relaxed region;
#   * a register Quartus merges into a block RAM's output no longer exists by
#     name, the filter matches nothing, and the line is ignored with a warning
#     -- CI fails the build on that (Check every constraint was applied);
#   * a block RAM read closes on one clock.  Leave it alone.
#
# The shape the sibling cores use, proven on hardware, for a CPU that steps on
# clock enables four or more system clocks apart:
#
#   set M68K [get_keepers {*|fx68k:*|*}]
#   set_multicycle_path -setup 4 -from $M68K -to $M68K
#   set_multicycle_path -hold  3 -from $M68K -to $M68K
# ------------------------------------------------------------------------------
