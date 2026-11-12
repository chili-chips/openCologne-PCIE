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
    input logic clk,
    input logic reset,
    input logic link_active,

    input logic              stp_detected,
    input logic              end_detected,
    input pipe_data_t        data_tl_in,
    input tlp_seq_t          sequence_number,
    input logic       [31:0] lcrc,
    input logic              tlp_valid,
    input logic              tlp_half,

    input seq_num_t next_rcv_seq,

    output logic       nak_scheduled,
    output seq_num_t   nak_seq_num,
    output logic       ack_scheduled,
    output seq_num_t   ack_seq_num,
    output logic       new_tlp_accepted,
    output pipe_data_t rx_data_tl,
    output logic       rx_tlp_valid,
    output logic       rx_tlp_first,
    output logic       rx_tlp_last
);

  typedef logic [BRAM_ADDR_WIDTH-1:0] bram_addr_t;

  // Buffer to store received TLP
  pipe_data_t rx_buffer   [DEPTH];

  pipe_data_t data_tl;
  logic       tlp_en;
  logic       tlp_first;
  logic       tlp_last;

  bram_addr_t write_ptr;
  bram_addr_t read_ptr;
  bram_addr_t word_cnt;
  bram_addr_t read_cnt;
  pipe_data_t buffer_data;


  typedef enum logic [2:0] {
    IDLE        = 3'd0,
    STORE_TLP   = 3'd1,
    DISCARD_TLP = 3'd2,
    CHECK_CRC   = 3'd3,
    PRE_WRITE   = 3'd4,
    WRITE_START = 3'd5,
    SEND_TLP    = 3'd6
  } state_e;
  state_e                  state;


  // CRC also takes sequence number into account
  // Feed sequence number first
  logic   [LFSR_WIDTH-1:0] crc_seq_0;
  logic   [LFSR_WIDTH-1:0] crc_seq_1;
  logic                    crc_en;
  // enabled when sequence number and TLP available
  assign crc_en = tlp_valid & (stp_detected | state == STORE_TLP);

  logic     [LFSR_WIDTH-1:0] crc_state;  // store current CRC state;
  logic     [LFSR_WIDTH-1:0] rx_lcrc;  // store received LCRC for comparison
  seq_num_t                  rx_seq_num;  // store sequence number for comparison

  logic                      seq_crc_en;  // the sequence number enters the LCRC at STP
  assign seq_crc_en = stp_detected & tlp_valid;

  lcrc_byte u_seq_crc_0 (
      .data_in({sequence_number.rsvd, sequence_number.num[11:8]}),
      .crc_en (seq_crc_en),
      .crc_in (crc_state),
      .crc_out(crc_seq_0)
  );

  lcrc_byte u_seq_crc_1 (
      .data_in(sequence_number.num[7:0]),
      .crc_en (seq_crc_en),
      .crc_in (crc_seq_0),
      .crc_out(crc_seq_1)
  );

  logic [LFSR_WIDTH-1:0] crc_tlp_in;
  // crc after sequence number as crc_in for first tlp word
  assign crc_tlp_in = stp_detected ? crc_seq_1 : crc_state;
  logic [DATA_BYTES*LFSR_WIDTH-1:0] lfsr_in;
  logic [DATA_BYTES*LFSR_WIDTH-1:0] lfsr_out;

  generate
    if (DATA_BYTES == 1) begin : g_lfsr_chain_1
      assign lfsr_in = crc_tlp_in;
    end
    else begin : g_lfsr_chain
      assign lfsr_in = {lfsr_out[(DATA_BYTES-1)*LFSR_WIDTH-1:0], crc_tlp_in};
    end
  endgenerate

  logic [LFSR_WIDTH-1:0] crc_next;
  assign crc_next = lfsr_out[DATA_BYTES*LFSR_WIDTH-1-:LFSR_WIDTH];

  genvar i;
  generate
    for (i = 0; i < DATA_BYTES; i = i + 1) begin : g_crc_bytes
      // the half-word end of a TLP: the upper DW is no part of the CRC
      logic byte_en;
      assign byte_en = crc_en & (i < DATA_BYTES / 2 | !tlp_half);

      lcrc_byte u_crc_byte (
          .data_in(data_tl_in[i*8+:8]),
          .crc_en (byte_en),
          .crc_in (lfsr_in[i*LFSR_WIDTH+:LFSR_WIDTH]),
          .crc_out(lfsr_out[i*LFSR_WIDTH+:LFSR_WIDTH])
      );
    end
  endgenerate

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

  // Write port
  // At STP, the word holds the sequence number and the start of the TLP
  always_ff @(posedge clk) begin
    if ((stp_detected || state == STORE_TLP) && tlp_valid) begin
      rx_buffer[write_ptr] <= data_tl_in;
    end
  end

  // Read port
  always_ff @(posedge clk) begin
    buffer_data <= rx_buffer[read_ptr];
  end

  //assign tlp_first = (state == SEND_TLP || state == WRITE_START) && (read_cnt == 0);
  //assign tlp_last  = (state == SEND_TLP || state == WRITE_START) && (read_cnt == word_cnt - 1);

  assign data_tl   = (state == SEND_TLP) ? buffer_data : {DATA_WIDTH{1'b0}};
  assign tlp_en    = (state == SEND_TLP) & (read_cnt <= word_cnt);
  assign tlp_first = (state == SEND_TLP) & (read_cnt == 1);
  assign tlp_last  = (state == SEND_TLP) & (read_cnt == word_cnt);

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

  // FSM
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      state            <= IDLE;
      write_ptr        <= 0;
      read_ptr         <= 0;
      read_cnt         <= 0;
      word_cnt         <= 0;
      crc_state        <= {LFSR_WIDTH{1'b1}};
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

      unique case (state)

        IDLE: begin
          if (stp_detected && link_active) begin  // only process TLP when link is active
            // Check sequence number
            if (sequence_number.num == next_rcv_seq) begin
              write_ptr  <= 1;  // first word has already been written in this cycle
              word_cnt   <= 1;
              rx_seq_num <= sequence_number.num;
              crc_state  <= crc_next;
              state      <= STORE_TLP;
            end
            else if ((next_rcv_seq - sequence_number.num) <= SEQ_HALF) begin
              // (NEXT_RCV_SEQ - sequence number) mod 4096 <= 2048: a duplicate, Ack it
              ack_scheduled <= 1'b1;
              ack_seq_num   <= next_rcv_seq - 1'b1;
              state         <= DISCARD_TLP;
            end
            else begin
              nak_scheduled <= 1'b1;
              nak_seq_num   <= next_rcv_seq - 1'b1;
              state         <= DISCARD_TLP;
            end
          end
        end

        STORE_TLP: begin
          if (stp_detected) begin  // detect STP before END
            nak_scheduled <= 1'b1;
            //nak_seq_num <= rx_seq_num;
            nak_seq_num   <= next_rcv_seq - 1'b1;
            write_ptr     <= 0;
            word_cnt      <= 0;
            crc_state     <= {LFSR_WIDTH{1'b1}};
            state         <= IDLE;
          end
          else begin
            if (tlp_valid) begin
              write_ptr <= write_ptr + 1;
              word_cnt  <= word_cnt + 1;
              crc_state <= crc_next;
            end
            if (end_detected) begin
              rx_lcrc <= lcrc;
              state   <= CHECK_CRC;
            end
            // TODO: What if END has not been detected and buffer is full
          end
        end

        DISCARD_TLP: begin
          state <= IDLE;
        end

        CHECK_CRC: begin
          if (crc_computed == rx_lcrc) begin
            // TODO: issue ACK when AckNak_LATENCY_TIMER exceeds a default value
            ack_scheduled    <= 1'b1;
            ack_seq_num      <= rx_seq_num;
            new_tlp_accepted <= 1'b1;
            read_ptr         <= 0;
            state            <= PRE_WRITE;
          end
          else begin  // crc wrong
            nak_scheduled <= 1'b1;
            //nak_seq_num <= rx_seq_num;
            nak_seq_num   <= next_rcv_seq - 1'b1;
            write_ptr     <= 0;
            word_cnt      <= 0;
            crc_state     <= {LFSR_WIDTH{1'b1}};
            state         <= IDLE;
          end
        end

        // buffer data 0 available here
        PRE_WRITE: begin
          state <= WRITE_START;
        end

        WRITE_START: begin  // TODO: Check timing here
          read_ptr <= 1;  // first word has already been read in this cycle
          read_cnt <= 1;
          state    <= SEND_TLP;
        end

        SEND_TLP: begin
          if (read_cnt == word_cnt) begin
            write_ptr <= 0;
            word_cnt  <= 0;
            crc_state <= {LFSR_WIDTH{1'b1}};
            state     <= IDLE;
          end
          else begin
            read_ptr <= read_ptr + 1;
            read_cnt <= read_cnt + 1;
          end
        end

        default: state <= IDLE;
      endcase
    end
  end

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Jul 11, 2026
// -----------------------------------------------------------------------------
