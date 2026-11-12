# SPDX-FileCopyrightText: 2026 Chili.CHIPS
#
# SPDX-License-Identifier: BSD-3-Clause
#
# The RTL file lists, one place for run-lint.sh, run-format.sh and
# run-synth.sh. Source it, then call a function with the 2.rtl directory:
#
#   own_rtl <2.rtl>         our own RTL: what run-format.sh formats
#   design_rtl <2.rtl> <csr generated-files dir> [sim]
#                           every file of top, in compile order: packages,
#                           interfaces, then modules. The SerDes
#                           (ccfpga_serdes): ccfpga_serdes.SYNTH.sv, CC_SERDES
#                           for the chip; with "sim", the opensource SerDes BFM
#                           instead.

own_rtl() {
  local r=$1
  echo "$r"/5.tlp/*.sv "$r"/6.trn_bridge/*.sv "$r"/7.soc/*.sv \
       "$r"/1.phy/phy_top.sv "$r"/*.sv \
       "$r"/2.pipe/pipe_pkg.sv "$r"/2.pipe/pipe_if.sv "$r"/3.mac/mac_pkg.sv "$r"/3.mac/mac_if.sv \
       "$r"/4.dll/dll_pkg.sv "$r"/4.dll/dll_if.sv
}

design_rtl() {
  local r=$1 g=$2 e=$1/7.soc/CPU.eduBOS5 p=$1/2.pipe m=$1/3.mac d=$1/4.dll
  # packages
  echo "$r"/2.pipe/pipe_pkg.sv "$r"/3.mac/mac_pkg.sv "$r"/4.dll/dll_pkg.sv "$r"/5.tlp/trn_pkg.sv "$r"/5.tlp/tl_pkg.sv "$r"/6.trn_bridge/axis_pkg.sv "$g"/csr_pkg.sv "$e"/edubos5_pkg.sv
  # interfaces
  echo "$r"/6.trn_bridge/axis_if.sv "$r"/5.tlp/trn_tx_if.sv "$r"/5.tlp/trn_rx_if.sv "$r"/5.tlp/cfg_if.sv "$r"/7.soc/mem_if.sv "$r"/7.soc/rvfi_if.sv \
       "$p"/pipe_if.sv "$m"/mac_if.sv "$d"/dll_if.sv
  # modules: ours, the generated CSRs, eduBOS5, Cologne Chip's PIPE logic,
  # MAC and DLL
  echo "$r"/top.sv "$r"/pcie_top.sv "$r"/clk_rst_gen.sv "$r"/pcie_core.sv "$r"/5.tlp/tl_top.sv \
       "$r"/1.phy/phy_top.sv
  echo "$r"/5.tlp/tlp_rx_handler.sv "$r"/5.tlp/tlp_queue.sv "$r"/5.tlp/tlp_order.sv \
       "$r"/5.tlp/tlp_rx_dispatch.sv "$r"/5.tlp/config_space.sv "$r"/5.tlp/cpl_gen.sv \
       "$r"/5.tlp/fc_credit.sv "$r"/5.tlp/tlp_tx_arbiter.sv
  echo "$r"/6.trn_bridge/trn_bridge.sv "$r"/6.trn_bridge/trn_rx.sv "$r"/6.trn_bridge/trn_tx.sv "$r"/6.trn_bridge/trn_tx_throttle.sv
  echo "$r"/7.soc/riscv_pcie_soc.sv "$r"/7.soc/soc_csr.sv "$g"/csr.sv
  echo "$e"/edubos5.sv "$e"/edubos5_alu.sv "$e"/edubos5_rf.sv
  ls "$p"/*.sv | grep -v -E '_(if|pkg)\.sv'
  ls "$m"/*.sv | grep -v -E '_(if|pkg)\.sv'
  ls "$d"/*.sv | grep -v -E '_(if|pkg)\.sv'
  if [ "${3:-}" = sim ]; then
    echo "$r"/1.phy/2.serdes-model/ccfpga_serdes_pkg.sv "$r"/1.phy/2.serdes-model/ccfpga_serdes.BFM.sv
  else
    echo "$r"/1.phy/2.serdes-model/ccfpga_serdes.SYNTH.sv
  fi
}

# -----------------------------------------------------------------------------
# Project:     openCologne-PCIE
# Description: NLnet-sponsored open-source implementation
# Version:     1.0
# Date:        Oct 18, 2026
# -----------------------------------------------------------------------------
