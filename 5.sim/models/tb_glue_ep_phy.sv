// SPDX-FileCopyrightText: 2026 Chili.CHIPS
//
// SPDX-License-Identifier: BSD-3-Clause

//==========================================================================
// openCologne-PCIE * NLnet-sponsored open-source implementation
//--------------------------------------------------------------------------
// Description:
//   tb_glue_ep_phy: IFACE=phy, tb.g_ep_phy. The dump (make DUMP=1).
//   Compiled only with that mode (Makefile TB_GLUE) and bound into tb:
//   its dotted references reach a module the other modes do not compile,
//   and Verilator resolves those even in a generate block not taken (tb.sv).
//==========================================================================

module tb_glue_ep_phy #(
    parameter bit DUMP = 1'b0  // tb's
) ();

  if (DUMP) begin : g_dump
    initial begin
      $dumpfile("tb_phy.fst");
      $dumpvars(1, tb);
      $dumpvars(1, tb.g_rc_serial.u_rc);
      $dumpvars(1, tb.g_ep_phy.dut);           // the PIPE at the adapter, the resets
      $dumpvars(1, tb.g_ep_phy.dut.pipe_mac);  // our PHY's PIPE
      $dumpvars(1, tb.g_ep_phy.dut.bfm_pcie);  // the EP model's decoder page
    end
  end : g_dump

endmodule : tb_glue_ep_phy

bind tb tb_glue_ep_phy #(.DUMP(DUMP)) u_glue ();

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Nov 24, 2026
// -----------------------------------------------------------------------------
