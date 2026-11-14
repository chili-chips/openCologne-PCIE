// SPDX-FileCopyrightText: 2026 Chili.CHIPS
//
// SPDX-License-Identifier: BSD-3-Clause

//==========================================================================
// openCologne-PCIE * NLnet-sponsored open-source implementation
//--------------------------------------------------------------------------
// Description:
//   tb_soc: the SOC alone, eduBOS5 running firmware.hex, for WaveCrux's
//   RISC-V views (tb_soc.RISCV-ISA.wavecrux). The PCIE side is idle: no TLP
//   arrives, and the SOC's own TLPs are taken and dropped, so the firmware
//   starts up and then waits for a request from the host. cpu_view shows
//   the CPU's retired instructions (soc_top's rvfi) under the RVFI
//   names. Run: bash run-soc.sh
//==========================================================================

`timescale 1ns / 1ps

module tb_soc
  import tl_pkg::*;
  import axis_pkg::*;
  import trn_pkg::*;
;
  localparam int RUN_NS = 20_000;

  logic clk = 1'b0;
  logic resetn = 1'b0;

  always #16 clk = ~clk;  // 31.25 MHz, the PCLK the SOC runs on in top

  initial begin
    repeat (10) @(posedge clk);
    resetn = 1'b1;
  end

  axis_if #(
      .DATA_W(TRN_DATA_W),
      .USER_W($bits(tx_tuser_t))
  ) s_axis_tx ();
  axis_if #(
      .DATA_W(TRN_DATA_W),
      .USER_W($bits(rx_tuser_t))
  ) m_axis_rx ();
  cfg_if cfg ();

  // the PCIE stack stand-in: takes every TLP, sends none
  assign s_axis_tx.tready    = 1'b1;
  assign m_axis_rx.tdata     = '0;
  assign m_axis_rx.tkeep     = '0;
  assign m_axis_rx.tuser     = '0;
  assign m_axis_rx.tlast     = 1'b0;
  assign m_axis_rx.tvalid    = 1'b0;
  assign cfg.msg_err_fatal   = 1'b0;
  assign cfg.tx_buf_avail    = 6'd8;  // the core always has room
  assign cfg.id              = '0;

  logic fw_pass;

  soc_top dut (
      .clk      (clk),
      .resetn   (resetn),
      .s_axis_tx(s_axis_tx),
      .m_axis_rx(m_axis_rx),
      .cfg      (cfg),
      .fw_pass  (fw_pass)
  );

  // The CPU under RVFI names, for WaveCrux (CPU.eduBOS5/wavecrux/soc_cpu_view.sv)
  soc_cpu_view cpu_view (
      .clk      (clk),
      .valid    (dut.rvfi.rvfi_valid),
      .order    (dut.rvfi.rvfi_order),
      .insn     (dut.rvfi.rvfi_insn),
      .trap     (dut.rvfi.rvfi_trap),
      .halt     (dut.rvfi.rvfi_halt),
      .intr     (dut.rvfi.rvfi_intr),
      .rs1_addr (dut.rvfi.rvfi_rs1_addr),
      .rs2_addr (dut.rvfi.rvfi_rs2_addr),
      .rs1_rdata(dut.rvfi.rvfi_rs1_rdata),
      .rs2_rdata(dut.rvfi.rvfi_rs2_rdata),
      .rd_addr  (dut.rvfi.rvfi_rd_addr),
      .rd_wdata (dut.rvfi.rvfi_rd_wdata),
      .pc_rdata (dut.rvfi.rvfi_pc_rdata),
      .pc_wdata (dut.rvfi.rvfi_pc_wdata),
      .mem_addr (dut.rvfi.rvfi_mem_addr),
      .mem_rmask(dut.rvfi.rvfi_mem_rmask),
      .mem_wmask(dut.rvfi.rvfi_mem_wmask),
      .mem_rdata(dut.rvfi.rvfi_mem_rdata),
      .mem_wdata(dut.rvfi.rvfi_mem_wdata)
  );

  // +tx_check (run-soc.sh tx, firmware 3.sw/tests/soc_tx): every s_axis_tx
  // beat against the requests that firmware sends, 3-DW and 4-DW. A beat
  // with tkeep 0F is compared on its low DW only
  typedef struct packed {
    logic [63:0] data;  // [72:9]
    logic [7:0]  keep;  // [8:1]
    logic        last;  // [0]
  } beat_t;

  localparam int NBEATS = 12;
  localparam beat_t EXP[NBEATS] = '{
      // 3-DW MWr, 1 DW
      {64'h0000010F_40000001, 8'hFF, 1'b0},
      {64'hA1B2C3D4_00001000, 8'hFF, 1'b1},
      // 4-DW MWr, 1 DW
      {64'h0000020F_60000001, 8'hFF, 1'b0},
      {64'h00002000_00000001, 8'hFF, 1'b0},
      {64'h00000000_11223344, 8'h0F, 1'b1},
      // 4-DW MWr, 2 DW
      {64'h000003FF_60000002, 8'hFF, 1'b0},
      {64'h00003000_00000002, 8'hFF, 1'b0},
      {64'h99AABBCC_55667788, 8'hFF, 1'b1},
      // 4-DW MRd, 1 DW
      {64'h0000040F_20000001, 8'hFF, 1'b0},
      {64'h00004000_00000003, 8'hFF, 1'b1},
      // 3-DW MRd, 1 DW
      {64'h0000050F_00000001, 8'hFF, 1'b0},
      {64'h00000000_00005000, 8'h0F, 1'b1}
  };

  logic tx_check;
  int   nbeat = 0;
  int   errors = 0;
  beat_t got;

  initial tx_check = $test$plusargs("tx_check");

  assign got = '{data: s_axis_tx.tdata, keep: s_axis_tx.tkeep, last: s_axis_tx.tlast};

  always @(posedge clk) begin
    if (tx_check && resetn && s_axis_tx.tvalid && s_axis_tx.tready) begin
      if (nbeat >= NBEATS) begin
        errors++;
        $display("tb_soc: ERROR beat %0d: none expected, got %h %h %b", nbeat, got.data, got.keep,
                 got.last);
      end
      else if (got.keep != EXP[nbeat].keep || got.last != EXP[nbeat].last ||
               got.data[31:0] != EXP[nbeat].data[31:0] ||
               (got.keep == 8'hFF && got.data[63:32] != EXP[nbeat].data[63:32])) begin
        errors++;
        $display("tb_soc: ERROR beat %0d: expected %h %h %b, got %h %h %b", nbeat,
                 EXP[nbeat].data, EXP[nbeat].keep, EXP[nbeat].last, got.data, got.keep, got.last);
      end
      nbeat++;
    end
  end

  initial begin
    $dumpfile("tb_soc.fst");
    $dumpvars(1, cpu_view);
    if (tx_check) begin  // until the firmware is done, 1 ms at most
      fork
        wait (fw_pass);
        #(1_000_000);
      join_any
      repeat (20) @(posedge clk);  // the last TLP leaves
    end
    else begin
      #(RUN_NS);
    end
    $timeformat(-9, 0, " ns", 0);
    $display("tb_soc: %0t, fw_pass=%0b", $realtime, fw_pass);
    if (tx_check) begin
      if (nbeat != NBEATS) begin
        errors++;
        $display("tb_soc: ERROR %0d beat(s) sent, %0d expected", nbeat, NBEATS);
      end
      if (!fw_pass) begin
        errors++;
        $display("tb_soc: ERROR the firmware did not finish");
      end
      $display("tb_soc: Tx check, %0d error(s): TEST %s", errors, errors == 0 ? "PASSED" : "FAILED");
    end
    $finish;
  end

endmodule : tb_soc

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Oct 18, 2026
// -----------------------------------------------------------------------------
