// SPDX-FileCopyrightText: 2026 Chili.CHIPS
//
// SPDX-License-Identifier: BSD-3-Clause

//==========================================================================
// openCologne-PCIE * NLnet-sponsored open-source implementation
//--------------------------------------------------------------------------
// Description:
//   tb_glue_ep_rtl: EP=rtl IFACE=pipe, tb.g_ep_rtl. The dump (make DUMP=1).
//   Compiled only with that mode (Makefile TB_GLUE) and bound into tb:
//   its dotted references reach a module the other modes do not compile,
//   and Verilator resolves those even in a generate block not taken (tb.sv).
//==========================================================================

module tb_glue_ep_rtl #(
    parameter bit DUMP = 1'b0  // tb's
) ();

  if (DUMP) begin : g_dump
    initial begin
      $dumpfile("tb_rtl.fst");
      $dumpvars(1, tb);
      $dumpvars(1, tb.g_rc.u_rc);
      $dumpvars(2, tb.g_ep_rtl.dut.u_core.wavecrux);
      $dumpvars(1, tb.g_ep_rtl.dut.u_soc.cpu_view);
    end
  end : g_dump

endmodule : tb_glue_ep_rtl

bind tb tb_glue_ep_rtl #(.DUMP(DUMP)) u_glue ();

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Nov 24, 2026
// -----------------------------------------------------------------------------
