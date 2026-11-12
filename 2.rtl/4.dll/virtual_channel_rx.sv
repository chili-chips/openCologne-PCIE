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

module virtual_channel_rx
  import pipe_pkg::*;
  import dll_pkg::*;
(
    input logic clk,
    input logic reset,
    input logic link_active,
    input logic link_inactive,

    input dllp_wire_t dllp_data,
    input logic       sdp_detected,

    input pipe_data_t        tlp_data,
    input logic              stp_detected,
    input logic              end_detected,
    input tlp_seq_t          sequence_number,
    input logic       [31:0] lcrc,
    input logic              tlp_valid,
    input logic              tlp_half,

    output dllp_sub_t  update_type,
    output dllp_type_e packet_type,
    output fc_hdr_t    hdrfc,
    output fc_data_t   datafc,
    output logic       crc_valid,

    output pipe_data_t rx_tlp_data,
    output logic       rx_tlp_valid,
    output logic       rx_tlp_first,
    output logic       rx_tlp_last,

    output logic     nak_trigger,
    output seq_num_t nak_seq_num,
    output logic     ack_trigger,
    output seq_num_t ack_seq_num
);

  pipe_data_t        tlp_data_w;
  logic              tlp_valid_w;
  logic              tlp_first_w;
  logic              tlp_last_w;

  // DLLP RX Handler
  logic              dllp_valid;
  logic       [15:0] calc_crc;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      update_type <= '0;  // FC_P, DLLP_ACK
      packet_type <= DLLP_INITFC2;
      hdrfc       <= 8'b0;
      datafc      <= 12'b0;
      crc_valid   <= 1'b0;
    end
    else begin
      crc_valid <= 1'b0;
      if (sdp_detected) begin
        update_type <= dllp_data.dtype.update_type;
        packet_type <= dllp_data.dtype.packet_type;
        hdrfc       <= {dllp_data.body.fc.hdrfc_hi, dllp_data.body.fc.hdrfc_lo};
        datafc      <= {dllp_data.body.fc.datafc_hi, dllp_data.body.fc.datafc_lo};
        crc_valid   <= dllp_valid;
      end
    end
  end

  crc_gen u_crc (
      .crc_en (sdp_detected),
      .data_in({dllp_data.body, dllp_data.dtype}),

      .calc_crc(calc_crc)
  );

  assign dllp_valid = calc_crc == dllp_data.crc;


  // TLP RX Handler
  logic     nak_scheduled;
  seq_num_t nak_seq_number;
  logic     ack_scheduled;
  seq_num_t ack_seq_number;
  logic     new_tlp_accepted;

  seq_num_t next_rcv_seq;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      nak_trigger <= 1'b0;
      nak_seq_num <= 12'b0;
      ack_trigger <= 1'b0;
      ack_seq_num <= 12'b0;
    end
    else begin
      nak_trigger <= nak_scheduled;
      nak_seq_num <= nak_seq_number;
      ack_trigger <= ack_scheduled;
      ack_seq_num <= ack_seq_number;
    end
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      next_rcv_seq <= 12'b0;
    end
    else if (link_inactive) begin
      next_rcv_seq <= 12'b0;
    end
    else if (new_tlp_accepted) begin
      next_rcv_seq <= next_rcv_seq + 1;
    end
  end

  tlp_rx_buffer #(
      .BRAM_ADDR_WIDTH(9)
  ) u_tlp_rx_buffer (
      .clk        (clk),
      .reset      (reset),
      .link_active(link_active),

      .stp_detected   (stp_detected),
      .end_detected   (end_detected),
      .data_tl_in     (tlp_data),
      .sequence_number(sequence_number),
      .lcrc           (lcrc),
      .tlp_valid      (tlp_valid),
      .tlp_half       (tlp_half),

      .next_rcv_seq(next_rcv_seq),

      .nak_scheduled   (nak_scheduled),
      .nak_seq_num     (nak_seq_number),
      .ack_scheduled   (ack_scheduled),
      .ack_seq_num     (ack_seq_number),
      .new_tlp_accepted(new_tlp_accepted),

      .rx_data_tl  (tlp_data_w),
      .rx_tlp_valid(tlp_valid_w),
      .rx_tlp_first(tlp_first_w),
      .rx_tlp_last (tlp_last_w)
  );

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      rx_tlp_data  <= {DATA_WIDTH{1'b0}};
      rx_tlp_valid <= 1'b0;
      rx_tlp_first <= 1'b0;
      rx_tlp_last  <= 1'b0;
    end
    else begin
      rx_tlp_data  <= tlp_data_w;
      rx_tlp_valid <= tlp_valid_w;
      rx_tlp_first <= tlp_first_w;
      rx_tlp_last  <= tlp_last_w;
    end
  end

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Jan 10, 2026
// -----------------------------------------------------------------------------
