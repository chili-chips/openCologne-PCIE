// SPDX-FileCopyrightText: 2026 Chili.CHIPS
//
// SPDX-License-Identifier: BSD-3-Clause
//
// Verilator source list of make IFACE=phy: the EP model behind our PHY
// (models/ep_model_phy.sv), the host on the serial line.

// Packages and the PIPE interface (with EP=rtl, rtl.f has them)
vip/openPCIE_BFM/2.rtl/openPCIE_BFM_pkg.sv
../2.rtl/2.pipe/pipe_pkg.sv
../2.rtl/2.pipe/pipe_if.sv

// The PHY
-F phy.f

// The MAC side of the PIPE, and the EP model on it
vip/openPCIE_BFM/2.rtl/pipe_mac_adapter.sv
models/ep_model_phy.sv
