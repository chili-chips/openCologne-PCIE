# SPDX-FileCopyrightText: 2026 Chili.CHIPS
#
# SPDX-License-Identifier: BSD-3-Clause
#
# Clocks of top on the ULX5M-M2 card (run-pnr.sh, BOARD=m2): as top.sdc, but
# the board clock is 25 MHz (CLK_25MHz). It is clk_aon in clk_rst_gen.sv,
# which only times reset synchronizers, so its rate changes no behaviour.

create_clock -period 40 [get_ports clk_brd]
create_clock -period 32 [get_nets pipe_mac.pclk]
