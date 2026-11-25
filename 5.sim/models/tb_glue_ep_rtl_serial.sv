// SPDX-FileCopyrightText: 2026 Chili.CHIPS
//
// SPDX-License-Identifier: BSD-3-Clause

//==========================================================================
// openCologne-PCIE * NLnet-sponsored open-source implementation
//--------------------------------------------------------------------------
// Description:
//   tb_glue_ep_rtl_serial: EP=rtl IFACE=serial, tb.g_ep_rtl_serial. The SerDes
//   pins of top, which are not its ports (no GateMate netlist reaches
//   them): its nets, by hierarchy. And the dump (make DUMP=1).
//   Compiled only with that mode (Makefile TB_GLUE) and bound into tb:
//   its dotted references reach a module the other modes do not compile,
//   and Verilator resolves those even in a generate block not taken (tb.sv).
//==========================================================================

module tb_glue_ep_rtl_serial #(
    parameter bit DUMP = 1'b0  // tb's
) ();

  assign tb.g_ep_rtl_serial.dut.refclk  = tb.refclk;
  assign tb.g_ep_rtl_serial.dut.ser_rxp = tb.ser_dn_p;
  assign tb.g_ep_rtl_serial.dut.ser_rxn = tb.ser_dn_n;
  assign tb.ser_up                      = tb.g_ep_rtl_serial.dut.ser_txp;
  assign tb.ser_up_n                    = tb.g_ep_rtl_serial.dut.ser_txn;

  if (DUMP) begin : g_dump
    initial begin
      $dumpfile("tb_rtl_serial.fst");
      $dumpvars(1, tb);
      $dumpvars(1, tb.g_rc_serial.u_rc);
      $dumpvars(2, tb.g_ep_rtl_serial.dut.u_pcie_top.u_core.wavecrux);
      $dumpvars(1, tb.g_ep_rtl_serial.dut.u_pcie_top.u_soc.cpu_view);
    end
  end : g_dump

endmodule : tb_glue_ep_rtl_serial

bind tb tb_glue_ep_rtl_serial #(.DUMP(DUMP)) u_glue ();

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Nov 24, 2026
// -----------------------------------------------------------------------------
