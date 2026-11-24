// SPDX-FileCopyrightText: 2026 Chili.CHIPS
//
// SPDX-License-Identifier: BSD-3-Clause
//
// Verilator source list of the openCologne-PCIE co-simulation test bench.
// $VIP_DIR is the VIP that openPCIE_BFM's 4.build/build-vip.sh builds; the make
// file sets it. The DUT here is the EP model, EPPIPEx1__pcieVHost_DUT.

// openPCIE_BFM's package first (the models import it); no include files
vip/openPCIE_BFM/2.rtl/openPCIE_BFM_pkg.sv

// Co-simulation models
$VIP_DIR/hdl/f_VProc.sv
$VIP_DIR/hdl/clkmux.sv
$VIP_DIR/hdl/Serialiser.sv
$VIP_DIR/hdl/pcieVHost.sv
$VIP_DIR/hdl/pcieVHostPipex1.sv
vip/openPCIE_BFM/2.rtl/PIPEx1__pcieVHost.sv
vip/openPCIE_BFM/2.rtl/RCPIPEx1__pcieVHost.sv

// DUT: the EP model (make EP=model)
stubs/EPPIPEx1__pcieVHost_DUT.sv

// Test bench
tb.sv
