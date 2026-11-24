// SPDX-FileCopyrightText: 2025-2026 Cologne Chip AG
//
// SPDX-License-Identifier: BSD-3-Clause

// Refined in the NLnet-funded openCologne-PCIE project,
// executed by Chili.CHIPS and Intergalaktik doo

//----------------------------------------------------------------------------------------
// Description: Top module for Tx side of PHY/MAC
// - It handles the transmission of Ordered Sets, data, IDLE sequences and SKP sequences
// - It counts the number of transmitted Ordered Sets and IDLE sequences
//========================================================================================

module ccfpga_tx_MAC
  import pipe_pkg::*;
  import mac_pkg::*;
(
    input logic i_clk,   // Clock
    input logic i_reset, // Asynchronous i_reset

    input pipe_sym_t i_tx_sym_dll,  // Data and K flags from DLL

    input logic i_tx_os_flag_rst,    // Transmitter OS flag Reset
    input logic i_tx_idle_flag_rst,  // Transmitter IDLE flag Reset
    input logic i_tx_poll_flag_rst,  // Polling active flag Reset

    input logic i_os_valid,             // Ordered Set valid indication
    // non-matched Link/Lane Ordered Set detected in Recovery Config state
    input logic i_os_rec_cfg_detected,
    input logic i_idle_detected,        // IDLE detected indication
    input logic i_l0_enabled,           // L0 state enabled indication

    input logic           i_send_os_trigger,    // Trigger to send Ordered Set
    input logic           i_send_idle_trigger,  // Trigger to send IDLE
    input os_type_e       i_os_type,            // Type of OS to send
    input logic     [4:0] i_max_count,          // Max count for transmitted Ordered Set

    input logic     [7:0] i_link_num,  // Expected link number in Ordered Set
    input logic     [7:0] i_lane_num,  // Expected lane number in Ordered Set
    input ts_ctrl_t       i_ts_ctrl,   // Expected control

    output logic o_tx_os_flag,    // Max count for transmitted OS reached
    output logic o_tx_idle_flag,  // Max count for transmitted IDLE reached
    output logic o_tx_poll_flag,  // Max count for transmitted polling active reached

    output logic o_sending_os,  // Sending Ordered Set indication

    output pipe_sym_t o_tx_sym  // Data and K flags to be transmitted
);

  logic os_sent;  // Ordered Set sent indication
  logic idle_sent;  // IDLE sent indication
  logic skp_in_queue;  // SKP Ordered Set scheduled in queue
  logic sending_idle;  // Sending IDLE indication

  // Transmitter counter
  ccfpga_tx_count #(
      .COUNT_WIDTH (5)
  ) u_tx_count (
      .i_clk                 (i_clk),
      .i_tx_os_flag_rst      (i_tx_os_flag_rst),
      .i_tx_idle_flag_rst    (i_tx_idle_flag_rst),
      .i_tx_poll_flag_rst    (i_tx_poll_flag_rst),
      .i_os_sent             (os_sent),
      .i_os_valid            (i_os_valid),
      .i_os_rec_cfg_detected (i_os_rec_cfg_detected),
      .i_idle_sent           (idle_sent),
      .i_idle_detected       (i_idle_detected),
      .i_max_count           (i_max_count),

      .o_tx_os_flag   (o_tx_os_flag),
      .o_tx_idle_flag (o_tx_idle_flag),
      .o_tx_poll_flag (o_tx_poll_flag)
  );

  // Sending modules
  // Send OS module
  pipe_sym_t tx_sym_os;

  ccfpga_send_OS u_send_os (
      .i_clk             (i_clk),
      .i_send_os_trigger (i_send_os_trigger),
      .i_reset           (i_reset),
      .i_link_num        (i_link_num),
      .i_lane_num        (i_lane_num),
      .i_ts_ctrl         (i_ts_ctrl),
      .i_os_type         (i_os_type),
      .i_skp_in_queue    (skp_in_queue),

      .o_tx_sym     (tx_sym_os),
      .o_os_sent    (os_sent),
      .o_sending_os (o_sending_os)
  );

  logic sending_data;  // Sending Data indication
  logic data_next;  // ... after the next edge
  logic skp_hold;  // a SKP waits for a data word going out now or next (#6)

  assign skp_hold = sending_data | data_next;
  logic  sending_skp;  // Sending SKP indication

  // Send IDLE module
  pipe_sym_t tx_sym_idle;

  ccfpga_send_IDLE u_send_idle (
      .i_clk               (i_clk),
      .i_send_idle_trigger (i_send_idle_trigger),
      .i_reset             (i_reset),
      .i_skp_in_queue      (skp_in_queue),

      .o_tx_sym       (tx_sym_idle),
      .o_idle_sent    (idle_sent),
      .o_sending_idle (sending_idle)
  );

  // Send Data
  pipe_sym_t tx_sym_data;

  ccfpga_send_data u_send_data (
      .i_clk        (i_clk),
      .i_reset      (i_reset),
      .i_l0_enabled (i_l0_enabled),
      .i_tx_sym_dll (i_tx_sym_dll),

      .o_tx_sym       (tx_sym_data),
      .o_sending_data (sending_data),
      .o_data_next    (data_next)
  );

  // SKP Generator
  pipe_sym_t tx_sym_skp;

  ccfpga_SKP_generator #(
      .SKP_WIDTH (32)
  ) u_skp_generator (
      .i_clk          (i_clk),
      .i_reset        (i_reset),
      .i_sending_data (skp_hold),
      .i_sending_os   (o_sending_os),
      .i_sending_idle (sending_idle),

      .o_tx_sym       (tx_sym_skp),
      .o_skp_in_queue (skp_in_queue),
      .o_sending_skp  (sending_skp)
  );

  // Transmitted data multiplexer: the first source sending wins
  always_ff @(posedge i_clk or posedge i_reset) begin
    if (i_reset) begin
      o_tx_sym <= '0;
    end
    else if (sending_data) begin
      o_tx_sym <= tx_sym_data;
    end
    else if (o_sending_os) begin
      o_tx_sym <= tx_sym_os;
    end
    else if (sending_idle) begin
      o_tx_sym <= tx_sym_idle;
    end
    else if (sending_skp) begin
      o_tx_sym <= tx_sym_skp;
    end
    else begin
      o_tx_sym <= '0;
    end
  end

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Nov 3, 2026
// -----------------------------------------------------------------------------
