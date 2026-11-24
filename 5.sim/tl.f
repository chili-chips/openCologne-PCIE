// SPDX-FileCopyrightText: 2026 Chili.CHIPS
//
// SPDX-License-Identifier: BSD-3-Clause
//
// make TL=1: the shadow TL (models/tl_shadow.sv, bound into tb) and the RTL
// it needs, our Transaction Layer; paths from 5.sim, as in rtl.f

../2.rtl/2.pipe/pipe_pkg.sv
../2.rtl/4.dll/dll_pkg.sv
../2.rtl/5.tlp/trn_pkg.sv
../2.rtl/5.tlp/tl_pkg.sv
../2.rtl/5.tlp/trn_tx_if.sv
../2.rtl/5.tlp/trn_rx_if.sv
../2.rtl/5.tlp/cfg_if.sv
../2.rtl/4.dll/dll_if.sv
../2.rtl/5.tlp/tlp_queue.sv
../2.rtl/5.tlp/tlp_order.sv
../2.rtl/5.tlp/tlp_rx_handler.sv
../2.rtl/5.tlp/tlp_rx_dispatch.sv
../2.rtl/5.tlp/config_space.sv
../2.rtl/5.tlp/cpl_gen.sv
../2.rtl/5.tlp/fc_credit.sv
../2.rtl/5.tlp/tlp_tx_arbiter.sv
../2.rtl/5.tlp/tl_top.sv
models/tl_shadow.sv
