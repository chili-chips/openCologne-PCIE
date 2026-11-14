// SPDX-FileCopyrightText: 2026 Chili.CHIPS
//
// SPDX-License-Identifier: BSD-3-Clause
//
// Verilator source list of the PHY: phy_top, Cologne Chip's PIPE logic and the
// opensource SerDes BFM, so the host drives the serial line. With EP=rtl
// IFACE=serial under top (the Makefile adds ../2.rtl/top.sv), with IFACE=phy
// under the EP model (ep_phy.f).

../2.rtl/1.phy/phy_top.sv
../2.rtl/2.pipe/ccfpga_pipe_clk_counter.sv
../2.rtl/2.pipe/ccfpga_pipe_clk_divider.sv
../2.rtl/2.pipe/ccfpga_pipe_fsm.sv
../2.rtl/2.pipe/ccfpga_pipe_fsm_word_align.sv
../2.rtl/2.pipe/ccfpga_pipe_top.sv
../2.rtl/2.pipe/ccfpga_pipe_rx_mux.sv
../2.rtl/2.pipe/ccfpga_pipe_tx_demux.sv
../2.rtl/1.phy/2.opensource-serdes-model/ccfpga_serdes_pkg.sv
../2.rtl/1.phy/2.opensource-serdes-model/ccfpga_serdes.BFM.sv
