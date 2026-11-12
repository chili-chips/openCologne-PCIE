// SPDX-FileCopyrightText: 2026 Chili.CHIPS
//
// SPDX-License-Identifier: BSD-3-Clause
//
// Verilator source list of the EP RTL for make EP=rtl: pcie_top (MAC, DLL, TL,
// SOC with firmware) in the order of 4.build/hw_build/sources.sh, without
// top and phy_top: with IFACE=pipe the host sits in the phy_top socket
// (models/phy_vproc_rc.sv).

// Packages
models/pipe_sym_pkg.sv
../2.rtl/2.pipe/pipe_pkg.sv
../2.rtl/3.mac/mac_pkg.sv
../2.rtl/4.dll/dll_pkg.sv
../2.rtl/5.tlp/trn_pkg.sv
../2.rtl/5.tlp/tl_pkg.sv
../2.rtl/6.trn_bridge/axis_pkg.sv
../4.build/csr_build/generated-files/csr_pkg.sv
../2.rtl/7.soc/CPU.eduBOS5/edubos5_pkg.sv

// Interfaces
../2.rtl/6.trn_bridge/axis_if.sv
../2.rtl/5.tlp/trn_tx_if.sv
../2.rtl/5.tlp/trn_rx_if.sv
../2.rtl/5.tlp/cfg_if.sv
../2.rtl/7.soc/mem_if.sv
../2.rtl/2.pipe/pipe_if.sv
../2.rtl/3.mac/mac_if.sv
../2.rtl/4.dll/dll_if.sv
../2.rtl/7.soc/rvfi_if.sv

// Modules: ours, the generated CSRs, eduBOS5
../2.rtl/pcie_top.sv
../2.rtl/clk_rst_gen.sv
../2.rtl/pcie_core.sv
../2.rtl/5.tlp/tl_top.sv
../2.rtl/5.tlp/tlp_rx_handler.sv
../2.rtl/5.tlp/tlp_queue.sv
../2.rtl/5.tlp/tlp_order.sv
../2.rtl/5.tlp/tlp_rx_dispatch.sv
../2.rtl/5.tlp/config_space.sv
../2.rtl/5.tlp/cpl_gen.sv
../2.rtl/5.tlp/fc_credit.sv
../2.rtl/5.tlp/tlp_tx_arbiter.sv
../2.rtl/6.trn_bridge/trn_bridge.sv
../2.rtl/6.trn_bridge/trn_rx.sv
../2.rtl/6.trn_bridge/trn_tx.sv
../2.rtl/6.trn_bridge/trn_tx_throttle.sv
../2.rtl/7.soc/riscv_pcie_soc.sv
../2.rtl/7.soc/soc_csr.sv
../4.build/csr_build/generated-files/csr.sv
../2.rtl/7.soc/CPU.eduBOS5/edubos5.sv
../2.rtl/7.soc/CPU.eduBOS5/edubos5_alu.sv
../2.rtl/7.soc/CPU.eduBOS5/edubos5_rf.sv

// Cologne Chip's MAC, and the DLL
../2.rtl/3.mac/ccfpga_LTSSM_fsm.sv
../2.rtl/3.mac/ccfpga_mac_top.sv
../2.rtl/3.mac/ccfpga_OS_process.sv
../2.rtl/3.mac/ccfpga_SKP_generator.sv
../2.rtl/3.mac/ccfpga_clk_counter.sv
../2.rtl/3.mac/ccfpga_data_assembly.sv
../2.rtl/3.mac/ccfpga_rx_MAC.sv
../2.rtl/3.mac/ccfpga_rx_MAC_IDLE.sv
../2.rtl/3.mac/ccfpga_rx_MAC_OS.sv
../2.rtl/3.mac/ccfpga_rx_MAC_data.sv
../2.rtl/3.mac/ccfpga_scrambler.sv
../2.rtl/3.mac/ccfpga_scrambler_byte.sv
../2.rtl/3.mac/ccfpga_scrambler_data.sv
../2.rtl/3.mac/ccfpga_send_IDLE.sv
../2.rtl/3.mac/ccfpga_send_OS.sv
../2.rtl/3.mac/ccfpga_send_data.sv
../2.rtl/3.mac/ccfpga_tx_MAC.sv
../2.rtl/3.mac/ccfpga_tx_count.sv
../2.rtl/4.dll/crc_byte.sv
../2.rtl/4.dll/crc_gen.sv
../2.rtl/4.dll/dll_clk_counter.sv
../2.rtl/4.dll/dll_fsm.sv
../2.rtl/4.dll/dll_top.sv
../2.rtl/4.dll/lcrc_byte.sv
../2.rtl/4.dll/packet_handler.sv
../2.rtl/4.dll/retry_buffer.sv
../2.rtl/4.dll/send_dllp.sv
../2.rtl/4.dll/tlp_rx_buffer.sv
../2.rtl/4.dll/virtual_channel.sv
../2.rtl/4.dll/virtual_channel_rx.sv
../2.rtl/4.dll/virtual_channel_tx.sv

// GateMate primitives for simulation, and the phy_top socket
models/gatemate_cells_sim.sv
models/pipe_phy_core.sv
models/phy_vproc_rc.sv
