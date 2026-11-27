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

module retry_buffer
  import pipe_pkg::*;
  import dll_pkg::*;
#(
    parameter  int BRAM_ADDR_WIDTH = 9,
    localparam int DEPTH           = 1 << BRAM_ADDR_WIDTH,
    localparam int LFSR_WIDTH      = LCRC_W
) (
    input  logic       clk,
    input  logic       reset,

    input  logic       tlp_valid,
    input  logic       tlp_first,
    input  logic       tlp_last,
    input  logic       tlp_last_half,    // only for DATA_BYTES=8
    input  pipe_data_t tlp_in_data,

    input  seq_num_t   current_seq_num,  // Sequence number of the TLP being sent

    output logic       empty,

    input  logic       release_flag,
    input  logic       retransmit_flag,

    input  logic       tlp_sending,
    output logic       tlp_scheduled,
    output pipe_sym_t  tlp_out
);

  typedef logic [BRAM_ADDR_WIDTH-1:0] bram_addr_t;

  // K characters

  // GateMate block RAM has no read-first mode, so a read that meets a write
  // of the same word reads X here, as it does in the RAM: Yosys then needs
  // no read-first logic, and simulation matches the hardware (4.build/
  // README.md, "Block RAM without read-first"). They meet only while a TLP
  // is stored, where the read is not used (a_buffer_rw below).
  pipe_data_t buffer    [DEPTH];

  bram_addr_t write_ptr;
  bram_addr_t read_ptr;
  bram_addr_t word_cnt;
  bram_addr_t read_cnt;


  logic  last_half;
  assign last_half = (DATA_BYTES == 8) & tlp_last & tlp_last_half;
  logic  stored_last_half;

  typedef enum logic [2:0] {
    IDLE        = 3'd0,
    STORE_TLP   = 3'd1,
    STORE_CRC   = 3'd2,  // not used
    PRE_WRITE   = 3'd3,
    WRITE_START = 3'd4,
    SEND_TLP    = 3'd5,
    TLP_SENT    = 3'd6
  } state_e;
  state_e state;

  assign empty = (state == IDLE);

  // Block RAM: one write port, one registered read port. The read address
  // is read_ptr's next value, so mem_rdata is buffer[read_ptr], as
  // the combinational read had it
  logic       mem_we;
  bram_addr_t mem_waddr;
  pipe_data_t mem_wdata;
  bram_addr_t mem_raddr;
  pipe_data_t mem_rdata;

  always_ff @(posedge clk) begin
    if (mem_we) begin
      buffer[mem_waddr] <= mem_wdata;
    end
    mem_rdata <= (mem_we & (mem_waddr == mem_raddr)) ? 'x : buffer[mem_raddr];
  end

`ifndef SYNTHESIS
  // a_buffer_rw: mem_rdata is used in WRITE_START and SEND_TLP only, so a
  // read that meets a write is harmless while a TLP is stored, but for the
  // prefetch of word 0 with its last word (a TLP is at least 3 words, so
  // that word is never word 0)
  always @(posedge clk) begin : a_buffer_rw
    if (mem_we && (mem_waddr == mem_raddr) &&
        !(((state == IDLE) || (state == STORE_TLP)) && !tlp_last)) begin
      $error("retry_buffer: read and write of word %0d meet in state %0d", mem_waddr, state);
    end
  end
`endif

  always_comb begin
    mem_raddr = read_ptr;
    unique case (state)
      IDLE:
      if (tlp_valid && tlp_first && tlp_last) begin
        mem_raddr = 0;
      end
      STORE_TLP:
      if (tlp_valid && tlp_last) begin
        mem_raddr = 0;
      end
      WRITE_START:
      if (!release_flag && tlp_sending) begin
        mem_raddr = 1;
      end
      SEND_TLP:
      if (read_cnt != word_cnt - 1) begin
        mem_raddr = read_ptr + 1'b1;
      end
      TLP_SENT:
      if (!release_flag && retransmit_flag) begin
        mem_raddr = 0;
      end
      default: ;
    endcase
  end

  assign tlp_out.data = ((state == WRITE_START) | (state == SEND_TLP))
                      ? mem_rdata
                      : {DATA_WIDTH{1'b0}};

  // K flags: STP in byte 0 of the first word, END in the last byte of the last
  // word, or in the middle of it when its upper half is empty
  pipe_flags_t end_k;
  assign end_k = stored_last_half
               ? {{(DATA_BYTES/2){1'b0}}, 1'b1, {(DATA_BYTES/2-1){1'b0}}}
               : {1'b1, {(DATA_BYTES-1){1'b0}}};
  assign tlp_out.kcode = (state == WRITE_START) ? {{(DATA_BYTES-1){1'b0}}, 1'b1}
                        : ((state == SEND_TLP) & (read_cnt == word_cnt - 1)) ? end_k
                        : {DATA_BYTES{1'b0}};

  // STP and the sequence number, ahead of the TLP; the LCRC covers the
  // sequence number
  tlp_prefix_t stp_prefix;
  always_comb begin
    stp_prefix        = '0;
    stp_prefix.stp    = K_STP;
    stp_prefix.seq_hi = current_seq_num[11:8];
    stp_prefix.seq_lo = current_seq_num[7:0];
  end

  // CRC also takes sequence number into account
  // Feed sequence number first
  logic  crc_en;
  // enabled when sequence number and TLP available
  assign crc_en = tlp_valid & ((state == IDLE & tlp_first) | state == STORE_TLP);

  logic [LFSR_WIDTH-1:0] crc_state;  // the words through the clock before (lcrc_pipe)

  logic  seq_crc_en;  // the sequence number enters the LCRC with the first TLP word
  assign seq_crc_en = (state == IDLE & tlp_first) & tlp_valid;

  // the sequence number's two bytes, byte 0 in [7:0]
  logic [15:0] seq_bytes;
  assign       seq_bytes = {stp_prefix.seq_lo, stp_prefix.rsvd, stp_prefix.seq_hi};

  // two stages; the half-word end of a TLP: the upper DW is no part of the
  // CRC. The last TLP word is in crc_state one clock after it
  lcrc_pipe u_lcrc (
      .clk       (clk),
      .reset     (reset),
      .en        (crc_en),
      .seq       (seq_crc_en),
      .half      (last_half),
      .data      (tlp_in_data),
      .seq_bytes (seq_bytes),
      .crc       (crc_state)
  );

  logic [LFSR_WIDTH-1:0] crc_computed;
  genvar m;
  generate
    for (m = 0; m < 8; m = m + 1) begin : g_compute_lcrc
      assign crc_computed[m]    = ~crc_state[7-m];
      assign crc_computed[m+8]  = ~crc_state[15-m];
      assign crc_computed[m+16] = ~crc_state[23-m];
      assign crc_computed[m+24] = ~crc_state[31-m];
    end
  endgenerate

  // Write port: one whole word a clock. A TLP word straddles two buffer
  // words (STP and the sequence number come first), so the part that starts
  // the next word waits in carry until the next TLP word completes it. The
  // words with the LCRC go in once crc_state has the last TLP word, its TLP
  // bytes waiting in tail_bytes: one clock after it at write_ptr - 1
  // (write_ptr - 2 for a half-word end), then (a half-word end, or 32-bit)
  // one clock later at write_ptr - 1 (write_ptr, 32-bit). Nothing reads them
  // before.
  logic        tlp_beat;
  assign       tlp_beat = tlp_valid & ((state == IDLE & tlp_first) | state == STORE_TLP);
  logic [23:0] carry;
  logic [55:0] tail_bytes;  // the TLP bytes of tail word 0
  logic        tail_we0;
  logic        tail_we1;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      tail_we0 <= 1'b0;
      tail_we1 <= 1'b0;
    end
    else begin
      tail_we0 <= tlp_beat & tlp_last;
      tail_we1 <= tail_we0 & ((DATA_WIDTH == 32) | stored_last_half);
    end
  end

  logic [31:0] lcrc_on_wire;  // byte 0 in [7:0]
  assign       lcrc_on_wire = lcrc_wire(crc_computed);

  generate
    if (DATA_WIDTH == 64) begin : g_64
      always_ff @(posedge clk) begin
        if (tlp_beat) begin
          carry <= tlp_in_data[63:40];
          if (state == STORE_TLP && last_half) begin
            tail_bytes <= {tlp_in_data[31:0], carry};
          end
          else begin
            tail_bytes <= {32'b0, tlp_in_data[63:40]};
          end
        end
      end

      always_comb begin
        mem_we    = 1'b0;
        mem_waddr = write_ptr - 1'b1;
        mem_wdata = {tlp_in_data[39:0], carry};
        if ((state == IDLE && tlp_first) && tlp_valid) begin
          mem_we    = 1'b1;
          mem_waddr = 0;
          mem_wdata = {tlp_in_data[39:0], stp_prefix};
        end
        else if (state == STORE_TLP && tlp_valid) begin
          mem_we = ~last_half;  // a half word waits in tail_bytes for the LCRC
        end
        else if (tail_we0 && stored_last_half) begin
          mem_we    = 1'b1;
          mem_waddr = write_ptr - bram_addr_t'(2);
          mem_wdata = {lcrc_on_wire[7:0], tail_bytes};
        end
        else if (tail_we0) begin
          mem_we    = 1'b1;
          mem_wdata = {K_END, lcrc_on_wire, tail_bytes[23:0]};
        end
        else if (tail_we1) begin
          mem_we    = 1'b1;
          mem_wdata = {32'b0, K_END, lcrc_on_wire[31:8]};
        end
      end
    end
    else if (DATA_WIDTH == 32) begin : g_32
      always_ff @(posedge clk) begin
        if (tlp_beat) begin
          carry      <= tlp_in_data[31:8];
          tail_bytes <= {32'b0, tlp_in_data[31:8]};
        end
      end

      always_comb begin
        mem_we    = 1'b0;
        mem_waddr = write_ptr - 1'b1;
        mem_wdata = {tlp_in_data[7:0], carry};
        if ((state == IDLE && tlp_first) && tlp_valid) begin
          mem_we    = 1'b1;
          mem_waddr = 0;
          mem_wdata = {tlp_in_data[7:0], stp_prefix};
        end
        else if (state == STORE_TLP && tlp_valid) begin
          mem_we = 1'b1;
        end
        else if (tail_we0) begin
          mem_we    = 1'b1;
          mem_wdata = {lcrc_on_wire[7:0], tail_bytes[23:0]};
        end
        else if (tail_we1) begin
          mem_we    = 1'b1;
          mem_waddr = write_ptr;
          mem_wdata = {K_END, lcrc_on_wire[31:8]};
        end
      end
    end
  endgenerate

  // FSM
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      state            <= IDLE;
      write_ptr        <= 0;
      read_ptr         <= 0;
      read_cnt         <= 0;
      word_cnt         <= 0;
      tlp_scheduled    <= 1'b0;
      stored_last_half <= 1'b0;
    end
    else begin
      unique case (state)

        IDLE: begin
          if (tlp_valid && tlp_first) begin
            write_ptr        <= 2;
            stored_last_half <= 1'b0;
            if (tlp_last) begin  // First is last
              read_ptr <= 0;
              state    <= PRE_WRITE;
              // 32-bit datapath needs two extra words in total (one already added at the beginning)
              word_cnt <= (DATA_WIDTH == 32) ? 3 : 2;
            end
            else begin
              state    <= STORE_TLP;
              word_cnt <= 2;
            end
          end
        end

        STORE_TLP: begin
          if (tlp_valid) begin
            write_ptr <= write_ptr + 1;
            word_cnt  <= word_cnt + 1;
            if (tlp_last) begin
              read_ptr <= 0;
              state    <= PRE_WRITE;
              // 32-bit datapath needs two extra words in total (one already added at the beginning)
              if (DATA_WIDTH == 32) begin
                word_cnt <= word_cnt + 1;
              end

              stored_last_half <= last_half;
            end
          end
        end

        PRE_WRITE: begin
          state <= WRITE_START;
        end

        WRITE_START: begin
          tlp_scheduled <= 1'b1;

          // Release the packet
          if (release_flag) begin
            tlp_scheduled <= 1'b0;
            write_ptr     <= 0;
            word_cnt      <= 0;
            state         <= IDLE;
            // We want to wait for the TLP to be allowed to be sent before moving to next state
          end
          else if (tlp_sending) begin
            read_ptr <= 1;
            read_cnt <= 1;
            if (word_cnt == 1) begin
              tlp_scheduled <= 1'b0;
              state         <= TLP_SENT;
            end
            else begin
              state <= SEND_TLP;
            end
          end
        end

        SEND_TLP: begin
          if (read_cnt == word_cnt - 1) begin
            tlp_scheduled <= 1'b0;
            read_cnt      <= 0;
            state         <= TLP_SENT;
          end
          else begin
            read_ptr <= read_ptr + 1;
            read_cnt <= read_cnt + 1;
          end
        end

        TLP_SENT: begin
          tlp_scheduled <= 1'b0;

          // Release the packet
          // Buffer is then empty
          if (release_flag) begin
            write_ptr <= 0;
            word_cnt  <= 0;
            state     <= IDLE;
            // Retransmit the packet
            // TODO: Add a counter for the retransmission
          end
          else if (retransmit_flag) begin
            read_ptr <= 0;
            state    <= PRE_WRITE;
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
