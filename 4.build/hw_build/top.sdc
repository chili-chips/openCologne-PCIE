# SPDX-FileCopyrightText: 2026 Chili.CHIPS
#
# SPDX-License-Identifier: BSD-3-Clause
#
# Clocks of top for nextpnr-himbaechel (run-pnr.sh). The 10 MHz board clock is
# clk_aon in clk_rst_gen.sv (reset sequencing); everything from the MAC up to
# the SOC runs on PCLK, the SerDes PLL clock, 31.25 MHz at Gen1.

create_clock -period 100 [get_ports clk_brd]
create_clock -period 32 [get_nets pipe_mac.pclk]
