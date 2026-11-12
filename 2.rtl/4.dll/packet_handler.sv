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

module packet_handler
  import pipe_pkg::*;
  import dll_pkg::*;
#(
    localparam int PATTERN_WIDTH = DLLP_W
) (
    input logic      clk,      // Clock
    input logic      reset,    // Asynchronous reset
    input pipe_sym_t rx_sym,   // Received symbols and their K flags
    input logic      end_lost, // Receive buffer is full but no END is detected

    output logic sdp_detected,  // SDP detected flag
    output logic stp_detected,  // STP detected flag
    output logic end_detected,  // END detected flag
    output logic [PATTERN_WIDTH-1:0] data_dllp,  // Extracted DLLP
    output pipe_data_t data_tl,  // Data forwarded to Transaction Layer
    output tlp_seq_t sequence_number,  // Sequence number
    output logic [31:0] lcrc,  // Extract LCRC when END symbol detected
    output logic tlp_valid,  // TLP valid signal to Transaction Layer
    output logic tlp_half  // Only the lower half of data_tl is TLP data (last word, 64-bit)
);

  // K characters

  // SDP/STP can now start at any byte
  // Only support 32 and 64-bit data width
  // WIN_WORDS = 2 + ceil(7 / DATA_BYTES)
  localparam int WIN_WORDS = 2 + (7 + DATA_BYTES - 1) / DATA_BYTES;
  // STP on the last byte of the oldest word, then we need at least one word for payload
  // 7 = 2 byte sequence number + 4 byte LCRC + 1 byte END
  localparam int WIN_BYTES = WIN_WORDS * DATA_BYTES;
  localparam int POS_WIDTH = $clog2(WIN_BYTES) + 1;
  localparam int MAX_TLP_WORDS = (4096 + 16 + 4 + DATA_BYTES - 1) / DATA_BYTES + 1;
  localparam logic HALF_WORDS = (DATA_BYTES == 8);  //  only possible for 64-bit data width

  // Shift registers to store received data, the oldest word is the base of the window
  pipe_data_t rx_data_shift[WIN_WORDS];
  integer     i;

  always_ff @(posedge clk) begin
    rx_data_shift[0] <= rx_sym.data;
    for (i = 1; i < WIN_WORDS; i = i + 1) begin
      rx_data_shift[i] <= rx_data_shift[i-1];
    end
  end

  pipe_flags_t rx_data_k_shift[WIN_WORDS];
  integer j;  // a loop variable of its own: one shared by two always blocks has two drivers
  always_ff @(posedge clk) begin
    rx_data_k_shift[0] <= rx_sym.kcode;
    for (j = 1; j < WIN_WORDS; j = j + 1) begin
      rx_data_k_shift[j] <= rx_data_k_shift[j-1];
    end
  end

  logic [WIN_BYTES*8-1:0] win;  // flatten out the received window
  logic [  WIN_BYTES-1:0] win_k;  // flatten out the received window control flags

  genvar w;
  generate
    for (w = 0; w < WIN_WORDS; w = w + 1) begin : g_window
      assign win[w*DATA_WIDTH+:DATA_WIDTH] = rx_data_shift[WIN_WORDS-1-w];
    end

    for (w = 0; w < WIN_WORDS; w = w + 1) begin : g_window_k
      assign win_k[w*DATA_BYTES+:DATA_BYTES] = rx_data_k_shift[WIN_WORDS-1-w];
    end
  endgenerate

  logic                        in_tlp;  // TLP detected, wait for END
  logic        [POS_WIDTH-1:0] q;  // window position
  // the first byte the last packet detection did not consume: where the search starts
  logic        [POS_WIDTH-1:0] ptr;
  logic        [         12:0] word_cnt;  // words of the current TLP

  // Lowest SDP/STP at or after ptr in the oldest word
  logic                        start_found;
  logic                        start_is_stp;
  logic        [POS_WIDTH-1:0] start_pos;
  integer                      p;
  tlp_prefix_t                 prefix;  // STP and the sequence number, when a TLP starts
  assign prefix = win[8*start_pos+:$bits(tlp_prefix_t)];

  always_comb begin
    start_found  = 1'b0;
    start_is_stp = 1'b0;
    start_pos    = {POS_WIDTH{1'b0}};
    for (p = DATA_BYTES - 1; p >= 0; p = p - 1) begin
      // the lowest SDP/STP at or after ptr in the oldest word
      if (p >= ptr && win_k[p] && (win[8*p+:8] == K_SDP || win[8*p+:8] == K_STP)) begin
        start_found  = 1'b1;
        start_is_stp = (win[8*p+:8] == K_STP);
        start_pos    = POS_WIDTH'(p);
      end
    end
  end

  logic [7:0] end_full;
  // if the last word is full, END should be here
  assign end_full = win[8*(int'(q)+DATA_BYTES+4)+:8];
  logic end_full_k;
  assign end_full_k = win_k[int'(q)+DATA_BYTES+4];  // if the last word is full, END should be here
  logic [7:0] end_half;
  // if the last word is half, END should be here
  assign end_half = HALF_WORDS ? win[8*(q+8)+:8] : 8'h00;
  logic end_half_k;
  assign end_half_k = HALF_WORDS ? win_k[q+8] : 1'b0;

  logic [31:0] lcrc_full;
  assign lcrc_full = {
    win[8*(int'(q)+DATA_BYTES)+:8],
    win[8*(int'(q)+DATA_BYTES+1)+:8],
    win[8*(int'(q)+DATA_BYTES+2)+:8],
    win[8*(int'(q)+DATA_BYTES+3)+:8]
  };  // if the last word is full, LCRC should be here
  logic [31:0] lcrc_half;
  assign lcrc_half = {
    win[8*(q+4)+:8], win[8*(q+5)+:8], win[8*(q+6)+:8], win[8*(q+7)+:8]
  };  // if the last word is half, LCRC should be here

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      sdp_detected    <= 1'b0;
      stp_detected    <= 1'b0;
      end_detected    <= 1'b0;
      data_dllp       <= {PATTERN_WIDTH{1'b0}};
      data_tl         <= {DATA_WIDTH{1'b0}};
      tlp_valid       <= 1'b0;
      tlp_half        <= 1'b0;
      sequence_number <= '0;
      lcrc            <= 32'b0;
      in_tlp          <= 1'b0;
      q               <= {POS_WIDTH{1'b0}};
      ptr             <= {POS_WIDTH{1'b0}};
      word_cnt        <= 13'd0;
    end
    else begin
      sdp_detected    <= 1'b0;
      stp_detected    <= 1'b0;
      end_detected    <= 1'b0;
      data_dllp       <= {PATTERN_WIDTH{1'b0}};
      data_tl         <= {DATA_WIDTH{1'b0}};
      tlp_valid       <= 1'b0;
      tlp_half        <= 1'b0;
      sequence_number <= '0;
      lcrc            <= 32'b0;

      if (in_tlp) begin
        word_cnt <= word_cnt + 1'b1;
        if (HALF_WORDS && end_half == K_END && end_half_k) begin  // Half word TLP
          end_detected <= 1'b1;
          data_tl      <= {{(DATA_WIDTH / 2) {1'b0}}, win[8*q+:DATA_WIDTH/2]};
          tlp_valid    <= 1'b1;
          tlp_half     <= 1'b1;
          lcrc         <= lcrc_half;
          in_tlp       <= 1'b0;
          // = 4 byte LCRC + 1 byte END + 4 bytes of the last half word - DATA_BYTES
          ptr          <= q + POS_WIDTH'(9 - DATA_BYTES);
        end
        else if (end_full == K_END && end_full_k) begin  // Full word TLP
          end_detected <= 1'b1;
          data_tl      <= win[8*q+:DATA_WIDTH];
          tlp_valid    <= 1'b1;
          lcrc         <= lcrc_full;
          in_tlp       <= 1'b0;
          ptr          <= q + 5;  // = 4 byte LCRC + 1 byte END + last word - DATA_BYTES
        end
        else if (end_lost || word_cnt == 13'(MAX_TLP_WORDS)) begin
          // TLP is too long or END is lost
          in_tlp <= 1'b0;
          ptr    <= {POS_WIDTH{1'b0}};
        end
        else begin  // Extract normal payload
          data_tl   <= win[8*q+:DATA_WIDTH];
          tlp_valid <= 1'b1;
        end
      end
      else if (start_found && start_is_stp) begin  // TLP
        stp_detected    <= 1'b1;
        sequence_number <= {prefix.rsvd, prefix.seq_hi, prefix.seq_lo};
        data_tl         <= win[8*(int'(start_pos)+TLP_PREFIX_BYTES)+:DATA_WIDTH];
        tlp_valid       <= 1'b1;
        in_tlp          <= 1'b1;
        q               <= start_pos + POS_WIDTH'(TLP_PREFIX_BYTES);
        word_cnt        <= 13'd1;
      end
      else if (start_found) begin  // DLLP
        sdp_detected <= 1'b1;
        data_dllp    <= win[8*start_pos+:PATTERN_WIDTH];
        ptr          <= start_pos + POS_WIDTH'(8 - DATA_BYTES);  // DLLP is always 8 bytes
      end
      else begin
        // nothing
        ptr <= (ptr >= POS_WIDTH'(DATA_BYTES)) ? ptr - POS_WIDTH'(DATA_BYTES) : {POS_WIDTH{1'b0}};
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
