// SPDX-FileCopyrightText: 2026 Chili.CHIPS
//
// SPDX-License-Identifier: BSD-3-Clause

//==========================================================================
// openCologne-PCIE * NLnet-sponsored open-source implementation
//--------------------------------------------------------------------------
//                   Copyright (C) 2026 Chili.CHIPS
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions
// are met:
//
// 1. Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright
// notice, this list of conditions and the following disclaimer in the
// documentation and/or other materials provided with the distribution.
//
// 3. Neither the name of the copyright holder nor the names of its
// contributors may be used to endorse or promote products derived
// from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
// IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
// TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
// PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
//              https://opensource.org/license/bsd-3-clause
//==========================================================================

module tlp_rx_buffer
  import pipe_pkg::*;
  import dll_pkg::*;
#(
    parameter  int BRAM_ADDR_WIDTH = 9,
    localparam int DEPTH           = 1 << BRAM_ADDR_WIDTH,
    localparam int LFSR_WIDTH      = LCRC_W
) (
    input  logic              clk,
    input  logic              reset,
    input  logic              link_active,

    input  logic              stp_detected,
    input  logic              end_detected,
    input  pipe_data_t        data_tl_in,
    input  tlp_seq_t          sequence_number,
    input  logic       [31:0] lcrc,
    input  logic              tlp_valid,
    input  logic              tlp_half,

    input  seq_num_t          next_rcv_seq,

    output logic              nak_scheduled,
    output seq_num_t          nak_seq_num,
    output logic              ack_scheduled,
    output seq_num_t          ack_seq_num,
    output logic              new_tlp_accepted,
    output pipe_data_t        rx_data_tl,
    output logic              rx_tlp_valid,
    output logic              rx_tlp_first,
    output logic              rx_tlp_last
);

  typedef logic [BRAM_ADDR_WIDTH-1:0] bram_addr_t;

  // The received TLPs in a ring. The writer stores a TLP while the reader
  // forwards the ones before it, so an STP right after an END is taken: the
  // writer checks the LCRC in the clock after END and takes the next STP in
  // that same clock (#4). A TLP with a bad LCRC, or cut short by an STP, is
  // rewound, so the ring holds good TLPs only, back to back.
  localparam int ROOM   = 64;  // words an STP needs free: over a largest TLP
  localparam int DESC_N = 4;   // TLPs checked and not yet forwarded

  pipe_data_t rx_buffer [DEPTH];

  pipe_data_t data_tl;
  logic       tlp_en;
  logic       tlp_first;
  logic       tlp_last;

  // ---- Writer ----------------------------------------------------------------
  typedef enum logic [1:0] {
    W_IDLE  = 2'd0,
    W_STORE = 2'd1,
    W_CHECK = 2'd2   // the clock after END: the LCRC is checked, an STP taken
  } w_state_e;
  w_state_e   w_state;

  bram_addr_t write_ptr;  // next word to write
  bram_addr_t tlp_start;  // first word of the TLP being stored
  bram_addr_t word_cnt;  // its words so far
  bram_addr_t base;  // where an STP's word goes: write_ptr, or the rewound start
  bram_addr_t free_words;  // the ring's free words from base on
  logic       crc_ok;  // in W_CHECK: the stored TLP's LCRC is good
  logic       stp_take;  // an STP the writer looks at
  logic       seq_next;  // its sequence number is the next one expected
  logic       room_ok;  // and the ring has room for it
  logic       we;
  bram_addr_t waddr;
  seq_num_t   exp_seq;  // the next sequence number, with the TLPs just accepted

  // CRC also takes sequence number into account
  // Feed sequence number first
  logic  crc_en;
  // enabled when sequence number and TLP available
  assign crc_en = tlp_valid & (stp_detected | (w_state == W_STORE));

  logic     [LFSR_WIDTH-1:0] crc_state;  // the words through the clock before (lcrc_pipe)
  logic     [LFSR_WIDTH-1:0] rx_lcrc;  // store received LCRC for comparison
  seq_num_t                  rx_seq_num;  // store sequence number for comparison

  logic  seq_crc_en;  // the sequence number enters the LCRC at STP
  assign seq_crc_en = stp_detected & tlp_valid;

  // the sequence number's two bytes, byte 0 in [7:0]
  logic [15:0] seq_bytes;
  assign seq_bytes = {sequence_number.num[7:0], sequence_number.rsvd, sequence_number.num[11:8]};

  // two stages; the half-word end of a TLP: the upper DW is no part of the
  // CRC. An STP restarts it, so a dropped TLP leaves nothing behind. The
  // last word, with END, is in crc_state in W_CHECK, while an STP in that
  // clock starts the next TLP's CRC
  lcrc_pipe u_lcrc (
      .clk       (clk),
      .reset     (reset),
      .en        (crc_en),
      .seq       (seq_crc_en),
      .half      (tlp_half),
      .data      (data_tl_in),
      .seq_bytes (seq_bytes),
      .crc       (crc_state)
  );

  // bit complemented and bit-reversed for each byte
  logic [LFSR_WIDTH-1:0] crc_computed;
  genvar l;
  generate
    for (l = 0; l < 8; l = l + 1) begin : g_compute_lcrc
      assign crc_computed[l]    = ~crc_state[7-l];
      assign crc_computed[l+8]  = ~crc_state[15-l];
      assign crc_computed[l+16] = ~crc_state[23-l];
      assign crc_computed[l+24] = ~crc_state[31-l];
    end
  endgenerate

  // ---- Reader ----------------------------------------------------------------
  typedef enum logic {
    R_IDLE = 1'b0,
    R_SEND = 1'b1
  } r_state_e;
  r_state_e r_state;

  bram_addr_t rd_ptr;  // next word to read
  bram_addr_t r_len;  // words of the TLP being forwarded
  bram_addr_t r_cnt;  // the word out now, from 1
  logic r_go;  // a checked TLP waits: start it
  logic r_last;
  pipe_data_t buffer_data;

  bram_addr_t desc_len[DESC_N];  // the checked TLPs' lengths, oldest first
  logic [1:0] desc_wr;
  logic [1:0] desc_rd;
  logic [2:0] desc_cnt;
  logic push;
  logic pop;

  assign crc_ok = (crc_computed == rx_lcrc);
  assign exp_seq    = next_rcv_seq
                    + seq_num_t'(new_tlp_accepted)
                    + seq_num_t'((w_state == W_CHECK) & crc_ok);
  assign base = ((w_state == W_CHECK) & ~crc_ok) ? tlp_start : write_ptr;
  assign free_words = rd_ptr - base - 1'b1;
  assign stp_take = stp_detected & link_active & (w_state != W_STORE);
  assign seq_next = (sequence_number.num == exp_seq);
  assign room_ok = (free_words >= bram_addr_t'(ROOM)) & (desc_cnt < 3'(DESC_N - 1));

  assign we         = tlp_valid
                    & ((stp_take & seq_next & room_ok) | ((w_state == W_STORE) & ~stp_detected));
  assign waddr = (w_state == W_STORE) ? write_ptr : base;

  assign push = (w_state == W_CHECK) & crc_ok;
  assign r_go = (r_state == R_IDLE) & (desc_cnt != '0);
  assign r_last = (r_state == R_SEND) & (r_cnt == r_len);
  assign pop = r_last;

  // GateMate block RAM has no read-first mode, so a read that meets a write
  // of the same word reads X here, as it does in the RAM: Yosys then needs
  // no read-first logic, and simulation matches the hardware (4.build/
  // README.md, "Block RAM without read-first"). The reader reads checked
  // TLPs only, which the writer never writes (a_ring_rw below).
  always_ff @(posedge clk) begin
    if (we) begin
      rx_buffer[waddr] <= data_tl_in;
    end
  end

  always_ff @(posedge clk) begin
    buffer_data <= (we & (waddr == rd_ptr)) ? 'x : rx_buffer[rd_ptr];
  end

`ifndef SYNTHESIS
  always @(posedge clk) begin : a_ring_rw
    if (we && (waddr == rd_ptr) && (r_go || ((r_state == R_SEND) && !r_last))) begin
      $error("tlp_rx_buffer: a write meets the read of word %0d", rd_ptr);
    end
  end

  always @(posedge clk) begin : a_desc_full
    if (push && !pop && (desc_cnt == 3'(DESC_N))) begin
      $error("tlp_rx_buffer: more than %0d checked TLPs wait", DESC_N);
    end
  end

  // An STP the ring has no room for is Naked (ep_sva's RXBUSY reads it)
  logic  stp_no_room;
  assign stp_no_room = stp_take & seq_next & ~room_ok;

  always @(posedge clk) begin : a_room
    if (stp_no_room) begin
      $error("tlp_rx_buffer: no room for the TLP of STP %0d", sequence_number.num);
    end
  end
`endif

  assign data_tl   = (r_state == R_SEND) ? buffer_data : {DATA_WIDTH{1'b0}};
  assign tlp_en    = (r_state == R_SEND);
  assign tlp_first = (r_state == R_SEND) & (r_cnt == bram_addr_t'(1));
  assign tlp_last  = r_last;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      rx_data_tl   <= {DATA_WIDTH{1'b0}};
      rx_tlp_valid <= 1'b0;
      rx_tlp_first <= 1'b0;
      rx_tlp_last  <= 1'b0;
    end
    else begin
      rx_data_tl   <= data_tl;
      rx_tlp_valid <= tlp_en;
      rx_tlp_first <= tlp_first;
      rx_tlp_last  <= tlp_last;
    end
  end

  // ---- Checked TLPs: their lengths, for the reader ---------------------------
  always_ff @(posedge clk) begin
    if (push) begin
      desc_len[desc_wr] <= word_cnt;
    end
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      desc_wr  <= '0;
      desc_rd  <= '0;
      desc_cnt <= '0;
    end
    else begin
      if (push) begin
        desc_wr <= desc_wr + 1'b1;
      end
      if (pop) begin
        desc_rd <= desc_rd + 1'b1;
      end
      desc_cnt <= desc_cnt + 3'(push) - 3'(pop);
    end
  end

  // ---- Reader FSM: a checked TLP out, word by word ---------------------------
  // r_go reads its first word; the next clocks put one word a clock out while
  // the following one is read. On the last, rd_ptr is the next TLP's start
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      r_state <= R_IDLE;
      rd_ptr  <= '0;
      r_len   <= '0;
      r_cnt   <= '0;
    end
    else begin
      unique case (r_state)
        R_IDLE: begin
          if (r_go) begin
            r_len   <= desc_len[desc_rd];
            r_cnt   <= bram_addr_t'(1);
            rd_ptr  <= rd_ptr + 1'b1;
            r_state <= R_SEND;
          end
        end
        R_SEND: begin
          if (r_last) begin
            r_state <= R_IDLE;
          end
          else begin
            r_cnt  <= r_cnt + 1'b1;
            rd_ptr <= rd_ptr + 1'b1;
          end
        end
        default: r_state <= R_IDLE;
      endcase
    end
  end

  // ---- Writer FSM ------------------------------------------------------------
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      w_state          <= W_IDLE;
      write_ptr        <= '0;
      tlp_start        <= '0;
      word_cnt         <= '0;
      rx_lcrc          <= {LFSR_WIDTH{1'b0}};
      rx_seq_num       <= 12'b0;
      nak_scheduled    <= 1'b0;
      nak_seq_num      <= 12'b0;
      ack_scheduled    <= 1'b0;
      ack_seq_num      <= 12'b0;
      new_tlp_accepted <= 1'b0;
    end
    else begin
      nak_scheduled    <= 1'b0;
      ack_scheduled    <= 1'b0;
      new_tlp_accepted <= 1'b0;

      // the TLP that ended: its LCRC, one clock after END
      if (w_state == W_CHECK) begin
        if (crc_ok) begin
          // TODO: issue ACK when AckNak_LATENCY_TIMER exceeds a default value
          ack_scheduled    <= 1'b1;
          ack_seq_num      <= rx_seq_num;
          new_tlp_accepted <= 1'b1;
        end
        else begin  // crc wrong: rewind
          nak_scheduled <= 1'b1;
          nak_seq_num   <= exp_seq - 1'b1;
          write_ptr     <= tlp_start;
        end
        w_state <= W_IDLE;
      end

      if (stp_take) begin  // in W_IDLE or W_CHECK; only when link is active
        if (seq_next && room_ok) begin
          tlp_start  <= base;
          write_ptr  <= base + 1'b1;  // its first word is written this clock
          word_cnt   <= bram_addr_t'(1);
          rx_seq_num <= sequence_number.num;
          w_state    <= W_STORE;
        end
        else if (!seq_next && ((exp_seq - sequence_number.num) <= SEQ_HALF)) begin
          // (NEXT_RCV_SEQ - sequence number) mod 4096 <= 2048: a duplicate, Ack it
          ack_scheduled <= 1'b1;
          ack_seq_num   <= exp_seq - 1'b1;
        end
        else begin  // out of sequence, or no room
          nak_scheduled <= 1'b1;
          nak_seq_num   <= exp_seq - 1'b1;
        end
      end
      else if (w_state == W_STORE) begin
        if (stp_detected) begin  // detect STP before END: rewind
          nak_scheduled <= 1'b1;
          nak_seq_num   <= exp_seq - 1'b1;
          write_ptr     <= tlp_start;
          w_state       <= W_IDLE;
        end
        else begin
          if (tlp_valid) begin
            write_ptr <= write_ptr + 1'b1;
            word_cnt  <= word_cnt + 1'b1;
          end
          if (end_detected) begin
            rx_lcrc <= lcrc;
            w_state <= W_CHECK;
          end
          // TODO: What if END has not been detected and buffer is full
        end
      end
    end
  end

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Jul 11, 2026
// -----------------------------------------------------------------------------
