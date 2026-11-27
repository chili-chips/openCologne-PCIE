// SPDX-FileCopyrightText: 2026 Chili.CHIPS
//
// SPDX-License-Identifier: BSD-3-Clause

//==========================================================================
// tb_rx_ring: tlp_rx_buffer on its own, with TLPs back to back (#4).
//   1. 8 TLPs, each STP in the clock right after the END before it: every
//      one must come out to the TL, whole and in order, Acked, no Nak.
//   2. A TLP with a bad LCRC, then at once its replay: one Nak, then the
//      replay comes out and is Acked.
// The LCRC of each TLP comes from a second lcrc_pipe, fed the same words
// beforehand. bash run-rx-ring.sh
//==========================================================================

`timescale 1ns / 1ps

module tb_rx_ring;
  import pipe_pkg::*;
  import dll_pkg::*;

  localparam int MAXW = 8;  // words of a test TLP

  logic       clk = 1'b0;
  logic       reset = 1'b1;
  always #2 clk = ~clk;

  // DUT inputs
  logic       stp, endd, valid;
  pipe_data_t din;
  tlp_seq_t   seqn;
  logic [31:0] lcrc;
  seq_num_t   next_rcv_seq;

  // DUT outputs
  logic       nak, ack, accepted;
  seq_num_t   nak_seq, ack_seq;
  pipe_data_t dout;
  logic       ovalid, ofirst, olast;

  tlp_rx_buffer #(.BRAM_ADDR_WIDTH(9)) dut (
      .clk             (clk),
      .reset           (reset),
      .link_active     (1'b1),
      .stp_detected    (stp),
      .end_detected    (endd),
      .data_tl_in      (din),
      .sequence_number (seqn),
      .lcrc            (lcrc),
      .tlp_valid       (valid),
      .tlp_half        (1'b0),
      .next_rcv_seq    (next_rcv_seq),
      .nak_scheduled   (nak),
      .nak_seq_num     (nak_seq),
      .ack_scheduled   (ack),
      .ack_seq_num     (ack_seq),
      .new_tlp_accepted(accepted),
      .rx_data_tl      (dout),
      .rx_tlp_valid    (ovalid),
      .rx_tlp_first    (ofirst),
      .rx_tlp_last     (olast)
  );

  // as virtual_channel_rx
  always_ff @(posedge clk) begin
    if (reset) next_rcv_seq <= '0;
    else if (accepted) next_rcv_seq <= next_rcv_seq + 1'b1;
  end

  // ---- reference LCRC ------------------------------------------------------
  logic       r_en, r_seq;
  pipe_data_t r_data;
  logic [15:0] r_seqb;
  lcrc_t      r_crc;

  lcrc_pipe u_ref (
      .clk(clk), .reset(reset), .en(r_en), .seq(r_seq), .half(1'b0),
      .data(r_data), .seq_bytes(r_seqb), .crc(r_crc)
  );

  function automatic logic [15:0] seq_bytes_of(input seq_num_t n);
    return {n[7:0], 4'h0, n[11:8]};
  endfunction

  function automatic logic [31:0] lcrc_of(input lcrc_t c);  // as crc_computed
    logic [31:0] r;
    for (int l = 0; l < 8; l++) begin
      r[l] = ~c[7-l]; r[l+8] = ~c[15-l]; r[l+16] = ~c[23-l]; r[l+24] = ~c[31-l];
    end
    return r;
  endfunction

  // the test TLPs
  pipe_data_t words[16][MAXW];
  int         len  [16];
  seq_num_t   sq   [16];
  logic [31:0] crc [16];

  task automatic ref_crc(input int t);
    @(negedge clk);
    for (int w = 0; w < len[t]; w++) begin
      r_en = 1'b1; r_seq = (w == 0); r_data = words[t][w]; r_seqb = seq_bytes_of(sq[t]);
      @(negedge clk);
    end
    r_en = 1'b0; r_seq = 1'b0;
    @(negedge clk);  // the last word is in r_crc a clock after it
    crc[t] = lcrc_of(r_crc);
    repeat (2) @(negedge clk);
  endtask

  // drive TLPs t0..t1 back to back: each STP right after the END before it
  task automatic drive(input int t0, input int t1, input logic bad_first);
    @(negedge clk);
    for (int t = t0; t <= t1; t++) begin
      for (int w = 0; w < len[t]; w++) begin
        stp = (w == 0); endd = (w == len[t] - 1); valid = 1'b1; din = words[t][w];
        seqn = '{rsvd: 4'h0, num: sq[t]};
        lcrc = (bad_first && (t == t0)) ? ~crc[t] : crc[t];
        @(negedge clk);
      end
    end
    stp = 1'b0; endd = 1'b0; valid = 1'b0;
  endtask

  // ---- checks --------------------------------------------------------------
  int errors = 0;
  int naks = 0, acks = 0;
  int got = 0;  // TLPs out
  int expect_tlp[$];  // test TLP index, in the order they must come out
  int ow = 0;

  always @(posedge clk) begin
    if (!reset && nak) naks++;
    if (!reset && ack) acks++;
    if (!reset && ovalid) begin
      int t;
      t = (expect_tlp.size() != 0) ? expect_tlp[0] : -1;
      if (t < 0) begin
        errors++; $display("[%0t] ERROR: a TLP word out, none expected", $time);
      end
      else begin
        if (ofirst != (ow == 0)) begin errors++; $display("[%0t] ERROR: first at word %0d", $time, ow); end
        if (dout !== words[t][ow]) begin
          errors++; $display("[%0t] ERROR: TLP %0d word %0d: %h, expected %h", $time, t, ow, dout, words[t][ow]);
        end
        if (olast != (ow == len[t] - 1)) begin errors++; $display("[%0t] ERROR: last at word %0d", $time, ow); end
        ow++;
        if (olast) begin void'(expect_tlp.pop_front()); ow = 0; got++; end
      end
    end
  end

  initial begin
    stp = 0; endd = 0; valid = 0; din = '0; seqn = '0; lcrc = '0; r_en = 0; r_seq = 0; r_data = '0; r_seqb = '0;
    // 8 TLPs of 3 to 8 words, sequence 0 to 7, then TLP 8 (seq 8) twice: bad, then good
    for (int t = 0; t < 9; t++) begin
      len[t] = 3 + (t * 5) % 6;
      sq[t]  = seq_num_t'(t);
      for (int w = 0; w < MAXW; w++) words[t][w] = {16'(t), 16'(w), 32'hC0DE_0000 + 32'(t * 16 + w)};
    end
    len[9] = len[8]; sq[9] = sq[8];
    for (int w = 0; w < MAXW; w++) words[9][w] = words[8][w];
    repeat (4) @(negedge clk);
    reset = 1'b0;
    for (int t = 0; t < 10; t++) ref_crc(t);

    $display("=== 1: 8 TLPs back to back ===");
    for (int t = 0; t < 8; t++) expect_tlp.push_back(t);
    drive(0, 7, 1'b0);
    repeat (40) @(negedge clk);
    if (got != 8) begin errors++; $display("ERROR: %0d of 8 TLPs out", got); end
    if (naks != 0) begin errors++; $display("ERROR: %0d Naks", naks); end
    if (acks != 8) begin errors++; $display("ERROR: %0d Acks, expected 8", acks); end
    if (next_rcv_seq != 8) begin errors++; $display("ERROR: next_rcv_seq %0d, expected 8", next_rcv_seq); end

    $display("=== 2: a bad LCRC, then its replay at once ===");
    got = 0; naks = 0; acks = 0;
    expect_tlp.push_back(9);
    drive(8, 9, 1'b1);
    repeat (40) @(negedge clk);
    if (got != 1) begin errors++; $display("ERROR: %0d TLPs out, expected the replay only", got); end
    if (naks != 1) begin errors++; $display("ERROR: %0d Naks, expected 1", naks); end
    if (acks != 1) begin errors++; $display("ERROR: %0d Acks, expected 1", acks); end
    if (next_rcv_seq != 9) begin errors++; $display("ERROR: next_rcv_seq %0d, expected 9", next_rcv_seq); end

    $display("  SUMMARY: %0d errors", errors);
    if (errors == 0) $display("  TEST PASSED");
    else $display("  TEST FAILED");
    $finish;
  end
endmodule
