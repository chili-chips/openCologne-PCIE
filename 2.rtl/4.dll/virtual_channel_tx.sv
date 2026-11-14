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

// Separate sending InitFC logic
module virtual_channel_tx
  import pipe_pkg::*;
  import dll_pkg::*;
#(
    parameter int RETRY_ADDR_WIDTH = 9
) (
    input  logic             clk,
    input  logic             reset,
    input  logic             link_inactive,

    input  logic       [2:0] virtual_channel,
    input  fc_dllp_t         tl_dllp,              // from the TL; valid is a pulse
    input  logic             updatefc_req,         // Periodic UpdateFC schedule (pulse)

    input  logic             initfc1_en,           // Sending InitFC1 sequence
    input  logic             initfc2_en,           // Sending InitFC2 sequence
    input  logic             initfc1_req,          // Request one InitFC1 set (pulse)
    input  logic             initfc2_req,          // Request one InitFC2 set (pulse)
    //input  seq_num_t  nack_sequence_number, // Sequence number for NAK/ACK DLLP

    input  logic             tlp_valid,
    input  logic             tlp_first,
    input  logic             tlp_last,
    input  logic             tlp_last_half,        // only for DATA_BYTES=8
    input  pipe_data_t       tlp_data,

    input  logic             release_flag,
    input  logic             retransmit_flag,

    input  logic             nak_trigger,          //pulse
    input  logic             ack_trigger,          //pulse
    input  seq_num_t         nak_sequence_number,
    input  seq_num_t         ack_sequence_number,

    output logic             dllp_initfc1_sent,
    output logic             dllp_initfc2_sent,

    output logic             retry_buffer_empty,
    //output logic                          dllp_sent,
    //output logic                          tlp_sent,
    output pipe_sym_t        tx_sym
);


  logic             dllp_sent;
  logic             tlp_scheduled;

  logic             ack_sending;
  logic             nak_sending;
  logic             dllp_sending;
  logic             tlp_sending;

  fc_cred_t         credit;
  fc_class_e        update_type;
  dllp_type_e       packet_type;
  logic             dllp_scheduled;

  logic             ack_scheduled;
  logic             nak_scheduled;
  seq_num_t         nack_sequence_number;


  logic       [2:0] fc_needed;
  assign fc_needed = {
    (INIT_CPLH != 0) | (INIT_CPLD != 0),
    (INIT_NPH != 0) | (INIT_NPD != 0),
    (INIT_PH != 0) | (INIT_PD != 0)
  };

  fc_hdr_t         fc_hdr       [3];
  fc_data_t        fc_data      [3];
  logic      [2:0] fc_pending;
  logic            fc_sending;
  fc_class_e       fc_sel;
  fc_hdr_t         fc_send_hdr;
  fc_data_t        fc_send_data;

  logic            tl_fc_update;
  assign tl_fc_update = tl_dllp.valid
                      & (tl_dllp.packet_type == DLLP_UPDATEFC)
                      & (tl_dllp.update_type != FC_RSVD);
  fc_class_e fc_next_sel;  // send the updates one by one: P, then NP, then Cpl
  always_comb begin
    if (fc_pending[FC_P]) begin
      fc_next_sel = FC_P;
    end
    else if (fc_pending[FC_NP]) begin
      fc_next_sel = FC_NP;
    end
    else begin
      fc_next_sel = FC_CPL;
    end
  end

  // Sorted after priority: NAK > ACK > UpdateFC > DLLP > TLP
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      ack_sending  <= 1'b0;
      nak_sending  <= 1'b0;
      fc_sending   <= 1'b0;
      fc_sel       <= FC_P;
      fc_send_hdr  <= 8'd0;
      fc_send_data <= 12'd0;
      dllp_sending <= 1'b0;
      tlp_sending  <= 1'b0;
    end
    else begin
      if (dllp_sending && dllp_sent) begin
        ack_sending  <= 1'b0;
        nak_sending  <= 1'b0;
        fc_sending   <= 1'b0;
        dllp_sending <= 1'b0;
      end
      if (tlp_sending && !tlp_scheduled) begin
        tlp_sending <= 1'b0;
      end

      if (!(dllp_sending || tlp_sending)) begin
        if (nak_scheduled) begin
          nak_sending  <= 1'b1;
          dllp_sending <= 1'b1;
        end
        else if (ack_scheduled) begin
          ack_sending  <= 1'b1;
          dllp_sending <= 1'b1;
        end
        else if (|fc_pending) begin  // update is scheduled
          fc_sending   <= 1'b1;
          fc_sel       <= fc_next_sel;  // select type of update
          fc_send_hdr  <= fc_hdr[fc_next_sel];
          fc_send_data <= fc_data[fc_next_sel];
          dllp_sending <= 1'b1;
        end
        else if (dllp_scheduled) begin  // dllp that is not update
          dllp_sending <= 1'b1;
        end
        else if (tlp_scheduled) begin
          tlp_sending <= 1'b1;
        end
      end
    end
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      credit         <= '0;
      update_type    <= FC_P;
      packet_type    <= DLLP_OTHER;
      dllp_scheduled <= 0;
    end
    else begin
      if (tl_dllp.valid && !tl_fc_update) begin  // packet available but not update type
        credit         <= tl_dllp.cred;
        update_type    <= tl_dllp.update_type;
        packet_type    <= tl_dllp.packet_type;
        dllp_scheduled <= 1'b1;
      end
      else if (dllp_sent) begin
        if (dllp_sending && !ack_sending && !nak_sending && !fc_sending) begin
          dllp_scheduled <= 1'b0;
        end
      end
    end
  end

  // Init credit
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      fc_hdr[FC_P]    <= INIT_PH;  // 0
      fc_data[FC_P]   <= INIT_PD;  // 0
      fc_hdr[FC_NP]   <= INIT_NPH;  // 1
      fc_data[FC_NP]  <= INIT_NPD;  // 1
      fc_hdr[FC_CPL]  <= INIT_CPLH;  // 2
      fc_data[FC_CPL] <= INIT_CPLD;  // 2
      fc_pending      <= 3'b000;
    end
    else if (link_inactive) begin  // the link went down: back to the initial credits
      fc_hdr[FC_P]    <= INIT_PH;  // 0
      fc_data[FC_P]   <= INIT_PD;  // 0
      fc_hdr[FC_NP]   <= INIT_NPH;  // 1
      fc_data[FC_NP]  <= INIT_NPD;  // 1
      fc_hdr[FC_CPL]  <= INIT_CPLH;  // 2
      fc_data[FC_CPL] <= INIT_CPLD;  // 2
      fc_pending      <= 3'b000;
    end
    else begin
      for (int f = 0; f < 3; f = f + 1) begin
        // the TL updates a class: its credits for the next UpdateFC
        if (tl_fc_update && tl_dllp.update_type == fc_class_e'(f)) begin
          fc_hdr[f]     <= tl_dllp.cred.hdr;
          fc_data[f]    <= tl_dllp.cred.data;
          fc_pending[f] <= 1'b1;
        end
        // Update credit requested and no infinite credit was advertised
        else if (updatefc_req && fc_needed[f]) begin
          fc_pending[f] <= 1'b1;
        end
        else if (dllp_sent && fc_sending && fc_sel == fc_class_e'(f)) begin
          fc_pending[f] <= 1'b0;
        end
      end
    end
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      ack_scheduled        <= 1'b0;
      nak_scheduled        <= 1'b0;
      nack_sequence_number <= '0;
    end
    else if (ack_trigger) begin
      ack_scheduled        <= 1'b1;
      nack_sequence_number <= ack_sequence_number;
    end
    else if (nak_trigger) begin
      nak_scheduled        <= 1'b1;
      nack_sequence_number <= nak_sequence_number;
    end
    else if (dllp_sent) begin
      if (ack_sending) begin
        ack_scheduled <= 1'b0;
      end
      else if (nak_sending) begin
        nak_scheduled <= 1'b0;
      end
    end
  end

  logic initfc1_sent;
  logic initfc2_sent;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      dllp_initfc1_sent <= 1'b0;
      dllp_initfc2_sent <= 1'b0;
    end
    else begin
      dllp_initfc1_sent <= initfc1_sent;
      dllp_initfc2_sent <= initfc2_sent;
    end
  end

  pipe_sym_t  dllp_sym;

  // The DLLP to send: the pending UpdateFC, else the one the TL asked for
  fc_hdr_t    send_hdr_credit;
  fc_data_t   send_data_credit;
  fc_class_e  send_update_type;
  dllp_type_e send_packet_type;
  always_comb begin  // if / else, not ?: on enums (Icarus 14, #18, iverilog#1048)
    if (fc_sending) begin
      send_hdr_credit  = fc_send_hdr;
      send_data_credit = fc_send_data;
      send_update_type = fc_sel;
      send_packet_type = DLLP_UPDATEFC;
    end
    else begin
      send_hdr_credit  = credit.hdr;
      send_data_credit = credit.data;
      send_update_type = update_type;
      send_packet_type = packet_type;
    end
  end

  send_dllp u_send_dllp (
      .clk   (clk),
      .reset (reset),

      .virtual_channel (virtual_channel),
      .hdr_credit      (send_hdr_credit),
      .data_credit     (send_data_credit),
      .update_type     (send_update_type),
      .packet_type     (send_packet_type),

      .nack_sequence_number (nack_sequence_number),
      .ack_trigger          (ack_sending),
      .nak_trigger          (nak_sending),

      .packet_avail (dllp_sending),

      .initfc1_en  (initfc1_en),
      .initfc2_en  (initfc2_en),
      .initfc1_req (initfc1_req),
      .initfc2_req (initfc2_req),

      .dllp_initfc1_sent (initfc1_sent),
      .dllp_initfc2_sent (initfc2_sent),
      .dllp_sent         (dllp_sent),
      .tx_sym            (dllp_sym)
  );

  logic release_flag_d;
  logic retransmit_flag_d;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      release_flag_d    <= 1'b0;
      retransmit_flag_d <= 1'b0;
    end
    else begin
      release_flag_d    <= release_flag;
      retransmit_flag_d <= retransmit_flag;
    end
  end

  logic empty;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      retry_buffer_empty <= 1'b1;
    end
    else begin
      retry_buffer_empty <= empty;
    end
  end

  pipe_sym_t tlp_sym;

  seq_num_t  current_seq_num;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      current_seq_num <= 12'b0;
    end
    else if (link_inactive) begin
      current_seq_num <= 12'b0;
    end
    else if (empty && tlp_valid && tlp_first) begin
      current_seq_num <= current_seq_num + 1'b1;
    end
  end

  retry_buffer #(
      .BRAM_ADDR_WIDTH (RETRY_ADDR_WIDTH)
  ) u_retry_buffer (
      .clk   (clk),
      .reset (reset),

      .tlp_valid     (tlp_valid),
      .tlp_first     (tlp_first),
      .tlp_last      (tlp_last),
      .tlp_last_half (tlp_last_half),
      .tlp_in_data   (tlp_data),

      .current_seq_num (current_seq_num),

      .empty (empty),

      .release_flag    (release_flag_d),
      .retransmit_flag (retransmit_flag_d),

      // First word of TLP is sent, stay asserting until the last word is sent
      .tlp_sending   (tlp_sending),
      // TLP is scheduled to be sent, stay asserting until the last word is sent
      .tlp_scheduled (tlp_scheduled),
      .tlp_out       (tlp_sym)
  );

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      tx_sym <= '0;
    end
    else if (ack_sending || nak_sending || dllp_sending || initfc1_en || initfc2_en) begin
      tx_sym <= dllp_sym;
    end
    else if (tlp_sending) begin
      tx_sym <= tlp_sym;
    end
    else begin
      tx_sym <= '0;
    end
  end
endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Jan 10, 2026
// -----------------------------------------------------------------------------
