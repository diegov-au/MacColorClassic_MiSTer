# MacColorClassic timing constraints (read after sys/sys_top.sdc).
#
# The 030 kernel (TG68KdotC_Kernel), M1a, 2026-10-06 (docs/NOTES.md section 9).
#
# Every kernel register assigns under clkena_in or clkena_lw (audited), and the
# wrapper (rtl/tg68k/tg68k030.v) keeps those enables at least two clk_sys
# apart, so kernel register-to-register paths have two periods, as in the
# MacLC core (MacLC.sdc, proven on hardware 2026-09-15). Measured: kernel-
# internal paths up to 38.0 ns, inside 2 x 30.77 ns.
#
# The PMMU (TG68K_PMMU_030, inside the kernel's hierarchy) is clocked on every
# clk_sys, not on clkena, so paths into it keep one period: the second pair
# below overrides the first for them. Measured: worst +7.18 ns, single-cycle.
#
# The decoder's combinational loop (pmmu_reg_sel_int) was removed 2026-10-07
# (NOTES section 9): no 332125 warnings, so STA measures the kernel exactly.
# If "STA met, hardware corrupt" ever returns, look for a new loop first.
set_multicycle_path -setup -end 2 -from [get_keepers {*TG68KdotC_Kernel*}] -to [get_keepers {*TG68KdotC_Kernel*}]
set_multicycle_path -hold  -end 1 -from [get_keepers {*TG68KdotC_Kernel*}] -to [get_keepers {*TG68KdotC_Kernel*}]
set_multicycle_path -setup -end 1 -from [get_keepers {*TG68KdotC_Kernel*}] -to [get_keepers {*PMMU_030*}]
set_multicycle_path -hold  -end 0 -from [get_keepers {*TG68KdotC_Kernel*}] -to [get_keepers {*PMMU_030*}]

# SDRAM interface I/O constraints (2026-10-07), from the MacLC core's
# MacLC.sdc of 2026-09-12. Until now the SDRAM pins had none, so STA never
# checked the read-data eye and the fitter's routing alone set it (rtl/sdram.v,
# the read-capture note).
#
# SDRAM_CLK is altddio_out(datain_h=0, datain_l=1) of clk_64, the INVERTED
# clk_64. Chip: Alliance AS4C32M16SB-7 (Winbond W9825G6KH-6 on the 32 MB
# module is equivalent): tAC(CL2) 6.0 ns, tOH 2.5 ns, tIS 1.5 ns, tIH 0.8 ns,
# ~0.5 ns of board allowance on the max numbers.
#
# The read capture is sdram.v's sd_data_q, an I/O-cell register on the clk_64
# FALLING edge: the chip launches on its rising edge (a clk_64 falling edge)
# and we take it on the next one, the default single-cycle relationship. No
# multicycle. sdram_clk is deliberately in no clock group, so these paths are
# timed against clk_64 rather than cut.
create_generated_clock -name sdram_clk -invert \
  -source [get_pins {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] \
  [get_ports {SDRAM_CLK}]

# chip -> FPGA (read data)
set_input_delay  -clock sdram_clk -max 6.5 [get_ports {SDRAM_DQ[*]}]
set_input_delay  -clock sdram_clk -min 2.5 [get_ports {SDRAM_DQ[*]}]

# FPGA -> chip (address, command, write data, byte masks)
set SDRAM_OUT [get_ports {SDRAM_A[*] SDRAM_BA[*] SDRAM_DQ[*] SDRAM_DQMH SDRAM_DQML SDRAM_nCAS SDRAM_nRAS SDRAM_nWE SDRAM_nCS}]
set_output_delay -clock sdram_clk -max  2.0 $SDRAM_OUT
set_output_delay -clock sdram_clk -min -0.8 $SDRAM_OUT
