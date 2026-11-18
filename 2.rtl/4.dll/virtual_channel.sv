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

module virtual_channel
  import pipe_pkg::*;
  import dll_pkg::*;
#(
    localparam int PATTERN_WIDTH    = DLLP_W,
    parameter  int RETRY_ADDR_WIDTH = 9
) (
    input  logic            clk,
    input  logic            reset,
    input  logic            linkup,
    input  logic      [2:0] virtual_channel_number,
    // Credits data from Transaction Layer
    input  fc_dllp_t        tx_dllp,
    // Received data from Physical Layer
    input  pipe_sym_t       rx_sym,
    // TLP data from Transaction Layer
    input  tlp_beat_t       tx_tlp,
    output logic            tx_tlp_ready,            // Ready if retry buffer is empty
    // Transmitted data to Physical Layer
    output pipe_sym_t       tx_sym,
    // Extracted credits data
    output fc_dllp_t        rx_dllp,
    // Received TLP data to Transaction Layer
    output tlp_beat_t       rx_tlp,
    output dl_state_e       o_fsm_state
);
  // FSM
  logic      initfc1_en;
  logic      initfc2_en;
  dl_state_e fsm_state;
  logic  link_active;
  assign link_active   = (fsm_state == DL_ACTIVE);
  assign o_fsm_state   = fsm_state;
  logic  link_inactive;
  assign link_inactive = (fsm_state == DL_INACTIVE);
  logic  tlp_rx_enable;
  assign tlp_rx_enable = (fsm_state == DL_ACTIVE) | (fsm_state == DL_INITFC2);
  // Tx side
  pipe_sym_t                      tx_sym_c;

  logic                           dllp_initfc1_sent;
  logic                           dllp_initfc2_sent;
  logic                           retry_buffer_empty;

  // Rx side
  logic       [PATTERN_WIDTH-1:0] data_dllp;
  dllp_sub_t                      update_type;
  dllp_type_e                     packet_type;
  fc_hdr_t                        hdrfc;
  fc_data_t                       datafc;
  logic                           crc_valid;
  logic                           sdp_detected;

  pipe_data_t                     rx_data_tl;
  logic                           rx_valid_tl;
  logic                           rx_first_tl;
  logic                           rx_last_tl;

  pipe_data_t                     data_tl;
  logic                           stp_detected;
  logic                           end_detected;
  tlp_seq_t                       sequence_number;
  logic       [             31:0] lcrc;
  logic                           tlp_valid;
  logic                           tlp_half;

  logic                           nak_trigger;
  seq_num_t                       nak_seq_num;
  logic                           ack_trigger;
  seq_num_t                       ack_seq_num;

  logic       [              2:0] initfc1_received_flag;
  logic                           initfc1_seq_received;
  logic       [              2:0] initfc2_received_flag;
  logic                           initfc2_seq_received;

  logic                           ack_received_flag;
  logic                           nak_received_flag;
  seq_num_t                       acknak_seq_num;
  logic       [             11:0] ackd_seq;
  logic                           tlp_released_flag;
  logic                           tlp_retransmit_flag;

  // Parameters
  // Define cycle time based on data width
  // TODO: Look at retry timer again
  localparam int CYCLE_TIME = 4 * DATA_BYTES;  // PCLK period in ns at 2.5 GT/s
  // 34 us and 30 us in PCLK cycles
  localparam logic [13:0] INIT_CYCLE_CNT = 14'(34000 / CYCLE_TIME - 1);
  localparam logic [13:0] UPDATEFC_CYCLE_CNT = 14'(30000 / CYCLE_TIME - 1);
  logic      init_counter_flag;
  logic      updatefc_counter_flag;
  logic      initfc1;
  logic      initfc2;
  dl_state_e fsm_state_d;
  logic  fsm_state_changed;
  assign fsm_state_changed = (fsm_state != fsm_state_d);

  logic  end_lost;
  assign end_lost = 1'b0;  // no source yet; packet_handler also ends a TLP at MAX_TLP_WORDS

  packet_handler u_dllp_assembly (
      .clk      (clk),
      .reset    (reset),
      .rx_sym   (rx_sym),
      .end_lost (end_lost), // tlp_rx_buffer for one TLP is full but no END is detected

      .sdp_detected    (sdp_detected),
      .stp_detected    (stp_detected),
      .end_detected    (end_detected),
      .data_dllp       (data_dllp),
      .data_tl         (data_tl),
      .sequence_number (sequence_number),
      .lcrc            (lcrc),
      .tlp_valid       (tlp_valid),
      .tlp_half        (tlp_half)
  );

  virtual_channel_rx u_vc_rx (
      .clk           (clk),
      .reset         (reset),
      .link_active   (tlp_rx_enable),
      .link_inactive (link_inactive),

      .dllp_data    (data_dllp),
      .sdp_detected (sdp_detected),

      .tlp_data        (data_tl),
      .stp_detected    (stp_detected),
      .end_detected    (end_detected),
      .sequence_number (sequence_number),
      .lcrc            (lcrc),
      .tlp_valid       (tlp_valid),
      .tlp_half        (tlp_half),

      .update_type (update_type),
      .packet_type (packet_type),
      .hdrfc       (hdrfc),
      .datafc      (datafc),
      .crc_valid   (crc_valid),

      .rx_tlp_data  (rx_data_tl),
      .rx_tlp_valid (rx_valid_tl),
      .rx_tlp_first (rx_first_tl),
      .rx_tlp_last  (rx_last_tl),

      .nak_trigger (nak_trigger),
      .nak_seq_num (nak_seq_num),
      .ack_trigger (ack_trigger),
      .ack_seq_num (ack_seq_num)
  );

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      rx_tlp <= '0;
    end
    else begin
      rx_tlp.data  <= rx_data_tl;
      rx_tlp.first <= rx_first_tl;
      rx_tlp.last  <= rx_last_tl;
      rx_tlp.valid <= rx_valid_tl;
      rx_tlp.half  <= 1'b0;
    end
  end

  // Received DLLP data is sent to TLP
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      rx_dllp <= '0;  // not valid, DLLP_OTHER, FC_P, no credits
    end
    else begin
      rx_dllp.valid <= 1'b0;
      if (crc_valid) begin
        rx_dllp.update_type <= update_type.fc;
        rx_dllp.packet_type <= packet_type;
        rx_dllp.valid       <= crc_valid;
        rx_dllp.cred.hdr    <= hdrfc;
        rx_dllp.cred.data   <= datafc;
      end
    end
  end

  // Init sequence handling
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      initfc1_received_flag <= 3'b000;
      initfc2_received_flag <= 3'b000;
    end
    else if (fsm_state == DL_INACTIVE) begin
      initfc1_received_flag <= 3'b000;
      initfc2_received_flag <= 3'b000;
    end
    else if (crc_valid) begin
      if (initfc1_en) begin
        // FC_INIT1 also takes InitFC2: the partner may be a step ahead
        if (packet_type == DLLP_INITFC1 || packet_type == DLLP_INITFC2) begin
          unique case (update_type.fc)
            FC_P:    initfc1_received_flag[0] <= 1'b1;
            FC_NP:   initfc1_received_flag[1] <= 1'b1;
            FC_CPL:  initfc1_received_flag[2] <= 1'b1;
            default: ;
          endcase
        end
      end
      else if (initfc2_en) begin
        if (packet_type == DLLP_INITFC2) begin
          unique case (update_type.fc)
            FC_P:    initfc2_received_flag[0] <= 1'b1;
            FC_NP:   initfc2_received_flag[1] <= 1'b1;
            FC_CPL:  initfc2_received_flag[2] <= 1'b1;
            default: ;
          endcase
        end
      end
    end
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      initfc1_seq_received <= 1'b0;
      initfc2_seq_received <= 1'b0;
    end
    else if (fsm_state == DL_INACTIVE) begin
      initfc1_seq_received <= 1'b0;
      initfc2_seq_received <= 1'b0;
    end
    else begin
      if (&initfc1_received_flag) begin
        initfc1_seq_received <= 1'b1;
      end
      if (&initfc2_received_flag
          || (initfc2_en && (stp_detected || (crc_valid && packet_type == DLLP_UPDATEFC)))) begin
        initfc2_seq_received <= 1'b1;
      end
    end
  end

  // repeat logic for initfc1 and initfc2
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      fsm_state_d <= DL_INACTIVE;
      initfc1     <= 1'b0;
      initfc2     <= 1'b0;
    end
    else begin
      fsm_state_d <= fsm_state;
      initfc1     <= initfc1_en & (fsm_state_changed | init_counter_flag);
      initfc2     <= initfc2_en & (fsm_state_changed | init_counter_flag);
    end
  end

  // Ack and Nak handling
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      ack_received_flag <= 1'b0;
      nak_received_flag <= 1'b0;
      acknak_seq_num    <= 12'b0;
    end
    else if (crc_valid) begin
      ack_received_flag <= 1'b0;
      nak_received_flag <= 1'b0;
      if (packet_type == DLLP_OTHER && update_type.other == DLLP_ACK) begin
        ack_received_flag <= 1'b1;
        acknak_seq_num    <= datafc;
      end
      else if (packet_type == DLLP_OTHER && update_type.other == DLLP_NAK) begin
        nak_received_flag <= 1'b1;
        acknak_seq_num    <= datafc;
      end
    end
    else begin
      ack_received_flag <= 1'b0;
      nak_received_flag <= 1'b0;
      acknak_seq_num    <= 12'b0;
    end
  end

  // Release and retransmit handling
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      ackd_seq            <= 12'hFFF;
      tlp_released_flag   <= 1'b0;
      tlp_retransmit_flag <= 1'b0;
    end
    else if (link_inactive) begin
      ackd_seq            <= 12'hFFF;
      tlp_released_flag   <= 1'b0;
      tlp_retransmit_flag <= 1'b0;
    end
    else if (ack_received_flag) begin
      if ((acknak_seq_num - ackd_seq) != 12'b0 && (acknak_seq_num - ackd_seq) <= SEQ_HALF) begin
        ackd_seq            <= acknak_seq_num;  // Update acknowledged sequence number
        tlp_released_flag   <= 1'b1;
        tlp_retransmit_flag <= 1'b0;
      end
      else begin
        tlp_released_flag   <= 1'b0;
        tlp_retransmit_flag <= 1'b0;
      end
      // TODO: What if wrong ACK is received? Should we ignore it or trigger a NAK?
    end
    else if (nak_received_flag) begin
      tlp_released_flag   <= 1'b0;
      tlp_retransmit_flag <= 1'b1;
    end
    else begin
      tlp_released_flag   <= 1'b0;
      tlp_retransmit_flag <= 1'b0;
    end
  end

  dll_clk_counter #(
      .BIT_WIDTH (14)  // Width of Count Register
  ) u_init_counter (
      .i_clk     (clk),
      .i_reset   (reset),
      .i_clear   (fsm_state_changed),
      .max_count (INIT_CYCLE_CNT),
      .o_flag    (init_counter_flag)
  );

  logic  updatefc_clear;  // the UpdateFC timer runs only while the link is active
  logic  updatefc_req;
  assign updatefc_clear = ~link_active;
  assign updatefc_req   = updatefc_counter_flag & link_active;

  dll_clk_counter #(
      .BIT_WIDTH (14)  // Width of Count Register
  ) u_updatefc_counter (
      .i_clk     (clk),
      .i_reset   (reset),
      .i_clear   (updatefc_clear),
      .max_count (UPDATEFC_CYCLE_CNT),
      .o_flag    (updatefc_counter_flag)
  );

  virtual_channel_tx #(
      .RETRY_ADDR_WIDTH (RETRY_ADDR_WIDTH)
  ) u_vc_tx (
      .clk           (clk),
      .reset         (reset),
      .link_inactive (link_inactive),

      .virtual_channel (virtual_channel_number),
      .tl_dllp         (tx_dllp),
      .updatefc_req    (updatefc_req),

      .initfc1_en    (initfc1_en),
      .initfc2_en    (initfc2_en),
      .initfc1_req   (initfc1),
      .initfc2_req   (initfc2),
      //.tlp_en(tlp_en),
      .tlp_valid     (tx_tlp.valid),
      .tlp_first     (tx_tlp.first),
      .tlp_last      (tx_tlp.last),
      .tlp_last_half (tx_tlp.half),
      .tlp_data      (tx_tlp.data),

      .release_flag    (tlp_released_flag),
      .retransmit_flag (tlp_retransmit_flag),

      .nak_trigger         (nak_trigger),
      .ack_trigger         (ack_trigger),
      .nak_sequence_number (nak_seq_num),
      .ack_sequence_number (ack_seq_num),

      .dllp_initfc1_sent (dllp_initfc1_sent),
      .dllp_initfc2_sent (dllp_initfc2_sent),

      .retry_buffer_empty (retry_buffer_empty),
      //.dllp_sent(dllp_sent),
      //.tlp_sent(tlp_sent),
      .tx_sym             (tx_sym_c)
  );

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      tx_tlp_ready <= 1'b0;
    end
    else begin
      // ready when retry buffer is empty and FSM is in active state
      tx_tlp_ready <= retry_buffer_empty & (fsm_state == DL_ACTIVE);
    end
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      tx_sym <= '0;
    end
    else begin
      tx_sym <= tx_sym_c;
    end
  end

  dll_fsm u_init_fsm (
      .reset             (reset),
      .i_clk             (clk),
      .i_link_up         (linkup),
      .i_initfc1_rx_done (initfc1_seq_received),
      .i_initfc1_tx_done (dllp_initfc1_sent),
      .i_initfc2_rx_done (initfc2_seq_received),
      .i_initfc2_tx_done (dllp_initfc2_sent),

      .o_initfc1_en (initfc1_en),
      .o_initfc2_en (initfc2_en),
      .o_fsm_state  (fsm_state)
  );

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Jan 10, 2026
// -----------------------------------------------------------------------------
