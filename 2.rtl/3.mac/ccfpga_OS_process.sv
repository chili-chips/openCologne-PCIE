// SPDX-FileCopyrightText: 2025-2026 Cologne Chip AG
//
// SPDX-License-Identifier: BSD-3-Clause

// Refined in the NLnet-funded openCologne-PCIE project,
// executed by Chili.CHIPS and Intergalaktik doo

//----------------------------------------------------------------------------------------
// Description: This module processes received Ordered Sets
// - Detects and validates received Ordered Sets (TS1/TS2)
// - Extracts Link number, Lane number and Ctrl field from received Ordered Sets
// - Detects polarity inversion of received Ordered Sets
// - Generates counting signals for received Ordered Sets and timeouts
//========================================================================================

module ccfpga_OS_process
  import pipe_pkg::*;
  import mac_pkg::*;
(
    input logic i_clk,   // Clock
    input logic i_reset, // Asynchronous i_reset

    input ts_os_t i_data,  // Extracted Ordered Set i_data

    input logic i_rx_os_flag_rst,       // Ordered Set i_reset flag
    input logic i_rx_rec_cfg_flag_rst,  // Recovery.RcvrCfg i_reset flag
    input logic i_com_detected,         // COM detection flag
    input logic i_ts1_pattern_en,       // TS1 pattern enable
    input logic i_ts2_pattern_en,       // TS2 pattern enable

    input logic [7:0] i_link_num,            // Expected Link number
    input logic [7:0] i_lane_num,            // Expected Lane number
    input logic       i_detect_inversion_en, // Inversion detection enable

    output logic o_os_valid,             // Ordered Set valid flag
    output logic o_os_detected,          // Ordered Set detection flag
    // Ordered Set with non-matched Link/Lane number in Recovery.RcvrCfg detection flag
    output logic o_os_rec_cfg_detected,
    output logic o_inversion_detected,   // Polarity inversion detection flag

    output logic     [7:0] o_rx_link,  // Detected Link number
    output logic     [7:0] o_rx_lane,  // Detected Lane number
    output ts_ctrl_t       o_rx_ctrl,  // Detected Ctrl field

    output logic o_inc_count_os,         // Increment Ordered Set count
    output logic o_clear_count_os,       // Clear Ordered Set count
    output logic o_inc_count_timeout,    // Increment Timeout count
    output logic o_clear_count_timeout,  // Clear Timeout count
    // Increment TS1 count with non-matched Link/Lane number in Recovery.RcvrCfg
    output logic o_inc_count_rec_cfg,
    // Clear TS1 count with non-matched Link/Lane number in Recovery.RcvrCfg
    output logic o_clear_count_rec_cfg,
    output logic o_inc_count_rec_idle,   // Increment TS1 count with PAD-Lane in Recovery.Idle
    output logic o_clear_count_rec_idle  // Clear TS1 count with PAD-Lane in Recovery.Idle
);

  // Rx flags
  logic rx_valid;  // received Ordered Set is valid
  logic rx_os;  // received i_data is an Ordered Set
  logic rx_os_inv;  // received Ordered Set is inverted
  logic rx_timeout;  // received Ordered Set with PAD-Lane and PAD-Link, used for timeout
  logic rx_rec_cfg;  // received Ordered Set with non-matched Link/Lane, used in Recovery.RcvrCfg
  logic rx_rec_idl;  // received recovery idle Ordered Set with PAD-Lane, used in Recovery.Idle

  // A TS1/TS2 of either polarity, and its Link and Lane as expected
  logic ts1, ts2, ts1_inv, ts2_inv;
  logic link_lane_ok;

  // Processing received Ordered Sets
  // Ordered Set validation
  // o_os_valid = 1 for one clock cycle when an Ordered Set is correctly received
  always_ff @(posedge i_clk or posedge i_rx_os_flag_rst) begin
    if (i_rx_os_flag_rst) begin
      o_os_valid <= 1'b0;
    end
    else begin
      if ((i_com_detected == 1'b1) && rx_valid) begin
        o_os_valid <= 1'b1;
      end
      else begin
        o_os_valid <= 1'b0;
      end
    end
  end

  // Ordered Set received detection
  // Extract Link, Lane and Ctrl from the received Ordered Set
  // o_os_detected = 1 for one clock cycle when an Ordered Set received
  always_ff @(posedge i_clk or posedge i_rx_os_flag_rst) begin
    if (i_rx_os_flag_rst) begin
      o_os_detected <= 1'b0;
      o_rx_link     <= 8'h00;
      o_rx_lane     <= 8'h00;
      o_rx_ctrl     <= '0;
    end
    else begin
      if ((i_com_detected == 1'b1) && rx_os) begin
        o_os_detected <= 1'b1;
        o_rx_link     <= i_data.link;
        o_rx_lane     <= i_data.lane;
        o_rx_ctrl     <= i_data.ctrl;
      end
      else begin
        o_os_detected <= 1'b0;
        o_rx_link     <= 8'h00;
        o_rx_lane     <= 8'h00;
        o_rx_ctrl     <= '0;
      end
    end
  end

  // Ordered Set received with non-matched Link/Lane in Recovery.RcvrCfg
  always_ff @(posedge i_clk or posedge i_rx_rec_cfg_flag_rst) begin
    if (i_rx_rec_cfg_flag_rst) begin
      o_os_rec_cfg_detected <= 1'b0;
    end
    else begin
      if ((i_com_detected == 1'b1) && rx_rec_cfg) begin
        o_os_rec_cfg_detected <= 1'b1;
      end
      else begin
        o_os_rec_cfg_detected <= 1'b0;
      end
    end
  end

  // Polarity inversion detection
  always_ff @(posedge i_clk or posedge i_reset) begin
    if (i_reset) begin
      o_inversion_detected <= 1'b0;
    end
    else if (i_detect_inversion_en) begin
      if ((i_com_detected == 1'b1) && rx_os_inv) begin
        o_inversion_detected <= 1'b1;
      end
    end
  end

  // A TS1/TS2: COM and the 10 identifiers; N_FTS, the i_data rate and Ctrl
  // are not compared
  assign ts1 = (i_data.com == K_COM) & (i_data.id == {10{TS1_ID}});
  assign ts2 = (i_data.com == K_COM) & (i_data.id == {10{TS2_ID}});
  assign ts1_inv = (i_data.com == K_COM) & (i_data.id == {10{TS1_ID_INV}});
  assign ts2_inv = (i_data.com == K_COM) & (i_data.id == {10{TS2_ID_INV}});
  assign link_lane_ok = (i_data.link == i_link_num) & (i_data.lane == i_lane_num);

  // Rx Ordered Set detection signals
  assign rx_os = (i_ts1_pattern_en & ts1) | (i_ts2_pattern_en & ts2);
  assign rx_os_inv = (i_ts1_pattern_en & ts1_inv) | (i_ts2_pattern_en & ts2_inv);
  assign rx_valid = rx_os & link_lane_ok;
  // TS1 with PAD-Lane and PAD-Link, COM not compared
  assign rx_timeout = (i_data.id == {10{TS1_ID}}) & (i_data.lane == K_PAD) & (i_data.link == K_PAD);
  assign rx_rec_cfg = ts1 & ~link_lane_ok;  // TS1 with non-matched Link/Lane
  assign rx_rec_idl = ts1 & (i_data.lane == K_PAD);  // TS1 with PAD-Lane

  // Rx Ordered Set counting signals
  assign o_inc_count_os = (i_com_detected == 1'b1) & rx_valid;
  assign o_clear_count_os = (i_com_detected == 1'b1) & ~rx_valid;
  // Rx Timeout counting signals
  assign o_inc_count_timeout = (i_com_detected == 1'b1) & rx_timeout;
  assign o_clear_count_timeout = (i_com_detected == 1'b1) & ~rx_timeout;
  // Recovery.RcvrCfg counting signals
  assign o_inc_count_rec_cfg = (i_com_detected == 1'b1) & rx_rec_cfg;
  assign o_clear_count_rec_cfg = (i_com_detected == 1'b1) & ~rx_rec_cfg;
  // Recovery.Idle counting signals
  assign o_inc_count_rec_idle = (i_com_detected == 1'b1) & rx_rec_idl;
  assign o_clear_count_rec_idle = (i_com_detected == 1'b1) & ~rx_rec_idl;

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Nov 3, 2026
// -----------------------------------------------------------------------------
