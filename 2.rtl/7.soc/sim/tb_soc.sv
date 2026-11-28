// SPDX-FileCopyrightText: 2026 Chili.CHIPS
//
// SPDX-License-Identifier: BSD-3-Clause

//==========================================================================
// openCologne-PCIE * NLnet-sponsored open-source implementation
//--------------------------------------------------------------------------
// Description:
//   tb_soc: the SOC alone, eduBOS5 running firmware.hex, for WaveCrux's
//   RISC-V views (tb_soc.RISCV-ISA.wavecrux). Without a check the PCIE side
//   is idle: no TLP arrives, and the SOC's own TLPs are taken and dropped,
//   so the firmware starts up and then waits for a request from the host.
//   +tx_check, +rx_check and +cpl_check test the SOC (below). cpu_view
//   shows the CPU's retired instructions (soc_top's rvfi) under the RVFI
//   names. Run: bash run-soc.sh [tx|rx|cpl]
//==========================================================================

// No `timescale: 1ns/10ps from the simulator command line (run-soc.sh); every
// delay carries its unit.

module tb_soc
  import tl_pkg::*;
  import axis_pkg::*;
  import trn_pkg::*;
;
  localparam int RUN_NS = 20_000;

  logic clk = 1'b0;
  logic resetn = 1'b0;

  always #16ns clk = ~clk;  // 31.25 MHz, the PCLK the SOC runs on in top

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

  // the PCIE stack stand-in: takes every TLP; sends the +rx_check burst. It
  // stalls as a core's throttle does: tready low one clock in three, and
  // four clocks in a row every sixteen, so beats wait in the Tx FIFO. The
  // pattern advances on clocks with a beat only, so the first beat of every
  // run waits: a short test cannot slip between the stalls
  logic [3:0] tx_stall_n = '0;
  always @(posedge clk) if (s_axis_tx.tvalid) tx_stall_n <= tx_stall_n + 4'd1;
  assign s_axis_tx.tready    = (tx_stall_n % 3 != 0) & (tx_stall_n < 4'd12);

  int tx_stalls = 0;  // clocks a Tx beat waited
  always @(posedge clk) if (s_axis_tx.tvalid && !s_axis_tx.tready) tx_stalls <= tx_stalls + 1;
  assign m_axis_rx.tuser     = '0;
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
      // 3-DW MRd, 1 DW (the batch's second)
      {64'h0000050F_00000001, 8'hFF, 1'b0},
      {64'h00000000_00005000, 8'h0F, 1'b1},
      // 4-DW MRd, 1 DW (the batch's third, from an odd entry)
      {64'h0000040F_20000001, 8'hFF, 1'b0},
      {64'h00004000_00000003, 8'hFF, 1'b1}
  };

  // +rx_check (run-soc.sh rx, firmware 3.sw/tests/soc_rx): RX_TLPS TLPs
  // back to back into m_axis_rx, more than the SOC's RX ring holds, with a
  // gap after every seventh. The firmware sends each one back as it came,
  // in TX batches, so s_axis_tx must carry the same beats
  localparam int RX_TLPS = 96;  // soc_rx/main.c: RX_TLPS

  beat_t rx_q[$];  // the RX beats, also the TX beats expected
  int    rx_n = 0;  // the next RX beat
  int    rx_t = 0;  // TLPs sent
  int    rx_gap = 0;
  int    rx_stalls = 0;  // clocks the ring held a beat off

  function automatic void rx_tlp(int t);
    int          kind = t % 4;  // MWr3, MWr4, MRd3, MRd4
    logic [31:0] dw[$];
    int          len = (kind < 2) ? ((t * 7) % 32) + 1 : 1;
    dw.push_back({1'b0, kind < 2, kind % 2 == 1, 19'd0, 10'(len)});
    for (int k = 1; k < ((kind % 2) ? 4 : 3) + ((kind < 2) ? len : 0); k++) begin
      dw.push_back(32'hC0DE_0000 | (t << 8) | k);
    end
    for (int k = 0; k < dw.size(); k += 2) begin
      rx_q.push_back('{data: {(k + 1 < dw.size()) ? dw[k+1] : 32'h0, dw[k]},
                       keep: (k + 1 < dw.size()) ? 8'hFF : 8'h0F,
                       last: k + 2 >= dw.size()});
    end
  endfunction

  // +cpl_check (run-soc.sh cpl, the EP firmware 3.sw/EP): a MemWr fills
  // BAR0, then MemRds that cross the 64-byte Read Completion Boundary, with
  // partial byte enables, a zero-length read, and two IORds. The expected
  // Completions are worked out here from the Base Specification (2.3.1.1,
  // 2.2.9), not from the firmware: its Byte Count what is left of the read
  // from its first byte, its Lower Address that byte; UR for the IORds. One
  // CplD per RCB block is our completer's choice, not a spec rule
  localparam logic [15:0] CPL_REQ_ID = 16'h0100;
  localparam int          CPL_MEM_DW = 32;  // the MemWr: DW i = CPL_DATA | i

  beat_t       exp_q[$];  // +cpl_check: the TX beats expected
  logic [31:0] cpl_mem[CPL_MEM_DW];

  // a TLP's DWORDs as beats, DW 2k low, into rx_q or exp_q
  function automatic void push_tlp(input logic [31:0] dw[$], input bit to_exp);
    for (int k = 0; k < dw.size(); k += 2) begin
      beat_t b = '{data: {(k + 1 < dw.size()) ? dw[k+1] : 32'h0, dw[k]},
                   keep: (k + 1 < dw.size()) ? 8'hFF : 8'h0F,
                   last: k + 2 >= dw.size()};
      if (to_exp) exp_q.push_back(b);
      else rx_q.push_back(b);
    end
  endfunction

  function automatic int be_lo(input logic [3:0] be);
    for (int i = 0; i < 4; i++) if (be[i]) return i;
    return 0;
  endfunction

  function automatic int be_hi(input logic [3:0] be);
    for (int i = 3; i >= 0; i--) if (be[i]) return i;
    return 0;
  endfunction

  // A MemRd of len DW at addr (3-DW or 4-DW header) and its CplDs
  function automatic void cpl_read(input logic [7:0] tag, input bit hdr4, input logic [31:0] addr,
                                   input int len, input logic [3:0] fbe, input logic [3:0] lbe);
    logic [31:0] dw[$];
    int          first = int'(addr) + be_lo(fbe);  // the read's first byte
    int          last  = int'(addr) + 4 * (len - 1) + be_hi((len == 1) ? fbe : lbe);
    int          a = int'(addr);  // the next Completion's first DW
    dw.push_back({1'b0, 1'b0, hdr4, 19'd0, 10'(len)});  // Fmt 00 or 01, Type 0: MemRd
    dw.push_back({CPL_REQ_ID, tag, (len == 1) ? 4'h0 : lbe, fbe});
    if (hdr4) dw.push_back(32'h0);
    dw.push_back(addr);
    push_tlp(dw, 1'b0);
    while (a <= last) begin
      int b = (a == int'(addr)) ? first : a;  // its first byte
      int n = (64 - (a % 64)) / 4;
      if (a + 4 * n > last) n = (last - a) / 4 + 1;
      dw.delete();
      dw.push_back(32'h4A00_0000 | n);
      dw.push_back(32'(last - b + 1));  // Completer ID 0 (cfg.id), SC
      dw.push_back({CPL_REQ_ID, tag, 1'b0, 7'(b)});
      for (int i = 0; i < n; i++) begin
        int w = ((a >> 2) + i) % 1024;
        dw.push_back((w < CPL_MEM_DW) ? cpl_mem[w] : 32'h0);
      end
      push_tlp(dw, 1'b1);
      a += 4 * n;
    end
  endfunction

  function automatic void cpl_tlps();
    logic [31:0] dw[$];
    // MemWr, 3-DW header, CPL_MEM_DW DWORDs at 0
    dw.push_back(32'h4000_0000 | CPL_MEM_DW);
    dw.push_back({CPL_REQ_ID, 8'h00, 8'hFF});
    dw.push_back(32'h0);
    for (int i = 0; i < CPL_MEM_DW; i++) begin
      cpl_mem[i] = 32'hDA7A_0000 | i;
      dw.push_back(cpl_mem[i]);
    end
    push_tlp(dw, 1'b0);
    cpl_read(8'h01, 1'b0, 32'h38, 8, 4'hF, 4'hF);   // crosses 0x40: 2 + 6 DW
    cpl_read(8'h02, 1'b0, 32'h00, 20, 4'hE, 4'h3);  // 16 + 4 DW, BC 77 then 14
    cpl_read(8'h03, 1'b1, 32'h3C, 2, 4'hF, 4'hF);   // 4-DW header: 1 + 1 DW
    cpl_read(8'h04, 1'b0, 32'h7C, 1, 4'hC, 4'h0);   // 1 DW, bytes 2-3: BC 2, LA 0x7E
    cpl_read(8'h06, 1'b0, 32'h24, 1, 4'h0, 4'h0);   // zero-length read: BC 1, LA 0x24
    // IORds: Unsupported Request, a Cpl without data. Not a Memory Read, so
    // Byte Count 4 and Lower Address 0 whatever the byte enables (2.2.9)
    io_read_ur(8'h05, 4'hF);
    io_read_ur(8'h07, 4'h3);
  endfunction

  function automatic void io_read_ur(input logic [7:0] tag, input logic [3:0] fbe);
    logic [31:0] dw[$];
    dw.push_back(32'h0200_0001);
    dw.push_back({CPL_REQ_ID, tag, 4'h0, fbe});
    dw.push_back(32'h0000_0010);
    push_tlp(dw, 1'b0);
    dw.delete();
    dw.push_back(32'h0A00_0000);
    dw.push_back({16'h0000, 3'b001, 1'b0, 12'd4});  // UR, Byte Count 4
    dw.push_back({CPL_REQ_ID, tag, 8'h00});         // Lower Address 0
    push_tlp(dw, 1'b1);
  endfunction

  logic tx_check;
  logic rx_check;
  logic cpl_check;
  int   nbeat = 0;
  int   errors = 0;
  beat_t got;

  initial begin
    tx_check  = $test$plusargs("tx_check");
    rx_check  = $test$plusargs("rx_check");
    cpl_check = $test$plusargs("cpl_check");
    if (rx_check) begin
      for (int t = 0; t < RX_TLPS; t++) rx_tlp(t);
    end
    if (cpl_check) cpl_tlps();
  end

  assign m_axis_rx.tvalid = (rx_check | cpl_check) & resetn & (rx_n < rx_q.size()) & (rx_gap == 0);
  assign m_axis_rx.tdata  = (rx_n < rx_q.size()) ? rx_q[rx_n].data : '0;
  assign m_axis_rx.tkeep  = (rx_n < rx_q.size()) ? rx_q[rx_n].keep : '0;
  assign m_axis_rx.tlast  = (rx_n < rx_q.size()) ? rx_q[rx_n].last : 1'b0;

  always @(posedge clk) begin
    if (rx_gap != 0) begin
      rx_gap <= rx_gap - 1;
    end
    else if (m_axis_rx.tvalid && m_axis_rx.tready) begin
      rx_n <= rx_n + 1;
      if (m_axis_rx.tlast) begin
        rx_t <= rx_t + 1;
        if (rx_t % 7 == 6) rx_gap <= 3;
      end
    end
    else if (m_axis_rx.tvalid) begin
      rx_stalls <= rx_stalls + 1;
    end
  end

  assign got = '{data: s_axis_tx.tdata, keep: s_axis_tx.tkeep, last: s_axis_tx.tlast};

  always @(posedge clk) begin
    if (rx_check && resetn && s_axis_tx.tvalid && s_axis_tx.tready) begin
      if (nbeat >= rx_q.size()) begin
        errors++;
        $display("tb_soc: ERROR beat %0d: none expected, got %h %h %b", nbeat, got.data, got.keep,
                 got.last);
      end
      else if (got.keep != rx_q[nbeat].keep || got.last != rx_q[nbeat].last ||
               got.data[31:0] != rx_q[nbeat].data[31:0] ||
               (got.keep == 8'hFF && got.data[63:32] != rx_q[nbeat].data[63:32])) begin
        if (errors < 10) begin
          $display("tb_soc: ERROR beat %0d: expected %h %h %b, got %h %h %b", nbeat,
                   rx_q[nbeat].data, rx_q[nbeat].keep, rx_q[nbeat].last, got.data, got.keep,
                   got.last);
        end
        errors++;
      end
      nbeat++;
    end
    if (cpl_check && resetn && s_axis_tx.tvalid && s_axis_tx.tready) begin
      if (nbeat >= exp_q.size()) begin
        errors++;
        $display("tb_soc: ERROR beat %0d: none expected, got %h %h %b", nbeat, got.data, got.keep,
                 got.last);
      end
      else if (got.keep != exp_q[nbeat].keep || got.last != exp_q[nbeat].last ||
               got.data[31:0] != exp_q[nbeat].data[31:0] ||
               (got.keep == 8'hFF && got.data[63:32] != exp_q[nbeat].data[63:32])) begin
        if (errors < 10) begin
          $display("tb_soc: ERROR beat %0d: expected %h %h %b, got %h %h %b", nbeat,
                   exp_q[nbeat].data, exp_q[nbeat].keep, exp_q[nbeat].last, got.data, got.keep,
                   got.last);
        end
        errors++;
      end
      nbeat++;
    end
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
    if (tx_check || rx_check) begin  // until the firmware is done, 10 ms at most
      fork
        wait (fw_pass);
        #10ms;
      join_any
      repeat (50) @(posedge clk);  // the last TLP leaves, stalls and all
    end
    else if (cpl_check) begin  // the EP never stops: until every Completion is out
      fork
        wait (nbeat >= exp_q.size());
        #10ms;
      join_any
      repeat (200) @(posedge clk);  // and nothing more comes
    end
    else begin
      #(RUN_NS * 1ns);
    end
    $timeformat(-9, 0, " ns", 0);
    $display("tb_soc: %0t, fw_pass=%0b, Tx beats stalled %0d clocks", $realtime, fw_pass,
             tx_stalls);
    if ((tx_check || rx_check || cpl_check) && tx_stalls == 0) begin
      errors++;
      $display("tb_soc: ERROR no Tx beat was stalled");
    end
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
    if (rx_check) begin
      if (nbeat != rx_q.size()) begin
        errors++;
        $display("tb_soc: ERROR %0d beat(s) sent back, %0d expected", nbeat, rx_q.size());
      end
      if (rx_stalls == 0) begin
        errors++;
        $display("tb_soc: ERROR the RX ring never filled");
      end
      if (!fw_pass) begin
        errors++;
        $display("tb_soc: ERROR the firmware did not finish");
      end
      $display("tb_soc: Rx check, %0d TLPs, %0d beats, ring full %0d clocks, %0d error(s): TEST %s",
               RX_TLPS, rx_q.size(), rx_stalls, errors, errors == 0 ? "PASSED" : "FAILED");
    end
    if (cpl_check) begin
      if (nbeat != exp_q.size()) begin
        errors++;
        $display("tb_soc: ERROR %0d beat(s) sent, %0d expected", nbeat, exp_q.size());
      end
      if (!fw_pass) begin
        errors++;
        $display("tb_soc: ERROR the EP did not report PASS (a MemRd answered)");
      end
      $display("tb_soc: Cpl check, 6 TLPs in, %0d beats out, %0d error(s): TEST %s",
               exp_q.size(), errors, errors == 0 ? "PASSED" : "FAILED");
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
