// SPDX-FileCopyrightText: 2025-2026 Cologne Chip AG
//
// SPDX-License-Identifier: BSD-3-Clause

// Refined in the NLnet-funded openCologne-PCIE project,
// executed by Chili.CHIPS and Intergalaktik doo

//----------------------------------------------------------------------------------------
// Description: Top module for Rx MAC Ordered Set processing
// - Instantiates OS Process modules
// - Count logic for Ordered Sets, Timeout
// - Sets expected Link, Lane and Ctrl
//========================================================================================

module ccfpga_rx_MAC_OS
  import pipe_pkg::*;
  import mac_pkg::*;
#(
    localparam int PATTERN_WIDTH = OS_W,
    parameter  int COUNT_WIDTH   = 4
) (
    input logic         i_clk,       // Clock
    input logic         i_reset,     // Asynchronous i_reset
    input ltssm_state_e i_fsm_state, // FSM current state

    input logic [PATTERN_WIDTH-1:0] i_data,  // Received i_data bytes

    input logic i_rx_os_flag_rst,        // Ordered Set i_reset flag
    input logic i_timeout_os_rst,        // Timeout i_reset flag
    input logic i_rx_rec_cfg_flag_rst,   // Recovery.RcvrCfg i_reset flag
    input logic i_rx_rec_idle_flag_rst,  // Recovery.Idle i_reset flag
    input logic i_ts1_pattern_en,        // TS1 pattern enable
    input logic i_ts2_pattern_en,        // TS2 pattern enable
    input logic i_com_detected,          // COM detected flag

    input logic [COUNT_WIDTH-1:0] i_max_count,  // Maximum count for Ordered Set counting

    output logic o_os_valid,             // Ordered Set valid flag
    // Ordered Set with non-matched Link/Lane number in Recovery.RcvrCfg detection flag
    output logic o_os_rec_cfg_detected,
    output logic o_inversion_detected,   // Polarity inversion detection flag

    output logic     [7:0] o_link_num,       // Expected Link number
    output logic     [7:0] o_lane_num,       // Expected Lane number
    output ts_ctrl_t       o_ts_ctrl,        // Expected Ctrl field
    output logic           o_link_detected,  // Link number detected flag
    output logic           o_lane_detected,  // Lane number detected flag

    output logic o_rx_os_flag,       // Ordered Set count maxed flag
    output logic o_timeout_os,       // Timeout flag
    output logic o_rx_rec_cfg_flag,  // Recovery.RcvrCfg count maxed
    output logic o_rx_rec_idle_flag  // Recovery.Idle count maxed
);


  logic     [7:0] rx_link;  // Detected Link number
  logic     [7:0] rx_lane;  // Detected Lane number
  ts_ctrl_t       rx_ctrl;  // Detected Ctrl field

  logic           inc_count_os;  // Increment Ordered Set count
  logic           clear_count_os;  // Clear Ordered Set count
  logic           inc_count_timeout;  // Increment Timeout count
  logic           clear_count_timeout;  // Clear Timeout count
  // Increment TS1 count with non-matched Link/Lane number in Recovery.RcvrCfg
  logic           inc_count_rec_cfg;
  // Clear TS1 count with non-matched Link/Lane number in Recovery.RcvrCfg
  logic           clear_count_rec_cfg;
  logic           inc_count_rec_idle;  // Increment TS1 count with PAD-Lane in Recovery.Idle
  logic           clear_count_rec_idle;  // Clear TS1 count with PAD-Lane in Recovery.Idle

  logic           detect_inversion_en;
  assign detect_inversion_en = i_fsm_state == POLLING_ACTIVE;  // Enable in POLLING_ACTIVE

  logic                   os_detected;  // an Ordered Set is received (one clock)
  logic [COUNT_WIDTH-1:0] rx_count_os;  // Ordered Set count
  logic [            1:0] rx_count_timeout;  // Ordered Set count for timeout
  logic [            3:0] rx_count_rec_cfg;  // Ordered Set count for Recovery config
  logic [            1:0] rx_count_rec_idle;  // Ordered Set count for Recovery idle

  ccfpga_OS_process u_os_process (
      .i_clk  (i_clk),
      .i_reset(i_reset),

      .i_data(i_data),

      .i_rx_os_flag_rst     (i_rx_os_flag_rst),
      .i_rx_rec_cfg_flag_rst(i_rx_rec_cfg_flag_rst),
      .i_com_detected       (i_com_detected),
      .i_ts1_pattern_en     (i_ts1_pattern_en),
      .i_ts2_pattern_en     (i_ts2_pattern_en),
      .i_link_num           (o_link_num),
      .i_lane_num           (o_lane_num),
      .i_detect_inversion_en(detect_inversion_en),

      .o_os_valid           (o_os_valid),
      .o_os_detected        (os_detected),
      .o_os_rec_cfg_detected(o_os_rec_cfg_detected),
      .o_inversion_detected (o_inversion_detected),

      .o_rx_link(rx_link),
      .o_rx_lane(rx_lane),
      .o_rx_ctrl(rx_ctrl),

      .o_inc_count_os        (inc_count_os),
      .o_clear_count_os      (clear_count_os),
      .o_inc_count_timeout   (inc_count_timeout),
      .o_clear_count_timeout (clear_count_timeout),
      .o_inc_count_rec_cfg   (inc_count_rec_cfg),
      .o_clear_count_rec_cfg (clear_count_rec_cfg),
      .o_inc_count_rec_idle  (inc_count_rec_idle),
      .o_clear_count_rec_idle(clear_count_rec_idle)
  );

  // Counting logic
  // inc_count = 1 if correctly received
  // clear_count = 1 if incorrectly received
  // Ordered Set Pattern counting/ count_maxed is hold until i_reset or clear_count
  always_ff @(posedge i_clk or posedge i_rx_os_flag_rst) begin
    if (i_rx_os_flag_rst) begin
      rx_count_os  <= {COUNT_WIDTH{1'b0}};
      o_rx_os_flag <= 1'b0;
    end
    else if (rx_count_os == i_max_count) begin
      rx_count_os  <= rx_count_os;
      o_rx_os_flag <= 1'b1;
    end
    else if (clear_count_os) begin
      rx_count_os  <= {COUNT_WIDTH{1'b0}};
      o_rx_os_flag <= 1'b0;
    end
    else if (inc_count_os) begin
      rx_count_os  <= rx_count_os + 1'b1;
      o_rx_os_flag <= 1'b0;
    end
  end

  // Ordered Set Timeout counting/ count_maxed is hold until i_reset or clear_count
  // Receives Ordered Sets with PAD-Link/Lane can lead to timeout in some states
  always_ff @(posedge i_clk or posedge i_timeout_os_rst) begin
    if (i_timeout_os_rst) begin
      rx_count_timeout <= 2'b00;
      o_timeout_os     <= 1'b0;
    end
    else if (rx_count_timeout == 2'(TIMEOUT_MAX_COUNT)) begin
      rx_count_timeout <= rx_count_timeout;
      o_timeout_os     <= 1'b1;
    end
    else if (clear_count_timeout) begin
      rx_count_timeout <= 2'b00;
      o_timeout_os     <= 1'b0;
    end
    else if (inc_count_timeout) begin
      rx_count_timeout <= rx_count_timeout + 1'b1;
      o_timeout_os     <= 1'b0;
    end
  end

  // TS1 with non-matched Link/Lane in Recovery.RcvrCfg counting
  // count_maxed is hold until i_reset or clear_count
  always_ff @(posedge i_clk or posedge i_rx_rec_cfg_flag_rst) begin
    if (i_rx_rec_cfg_flag_rst) begin
      rx_count_rec_cfg  <= 4'b0;
      o_rx_rec_cfg_flag <= 1'b0;
    end
    else if (rx_count_rec_cfg == 4'(REC_CFG_MAX_COUNT)) begin
      rx_count_rec_cfg  <= rx_count_rec_cfg;
      o_rx_rec_cfg_flag <= 1'b1;
    end
    else if (clear_count_rec_cfg) begin
      rx_count_rec_cfg  <= 4'b0;
      o_rx_rec_cfg_flag <= 1'b0;
    end
    else if (inc_count_rec_cfg) begin
      rx_count_rec_cfg  <= rx_count_rec_cfg + 1'b1;
      o_rx_rec_cfg_flag <= 1'b0;
    end
  end

  // TS1 with PAD-Lane in Recovery.Idle counting
  // count_maxed is hold until i_reset or clear_count
  always_ff @(posedge i_clk or posedge i_rx_rec_idle_flag_rst) begin
    if (i_rx_rec_idle_flag_rst) begin
      rx_count_rec_idle  <= 2'b0;
      o_rx_rec_idle_flag <= 1'b0;
    end
    else if (rx_count_rec_idle == 2'(REC_IDLE_MAX_COUNT)) begin
      rx_count_rec_idle  <= rx_count_rec_idle;
      o_rx_rec_idle_flag <= 1'b1;
    end
    else if (clear_count_rec_idle) begin
      rx_count_rec_idle  <= 2'b0;
      o_rx_rec_idle_flag <= 1'b0;
    end
    else if (inc_count_rec_idle) begin
      rx_count_rec_idle  <= rx_count_rec_idle + 1'b1;
      o_rx_rec_idle_flag <= 1'b0;
    end
  end

  // Set detected Link/Lane number and control bits based on received Ordered Sets
  always_ff @(posedge i_clk or posedge i_reset) begin
    if (i_reset) begin
      o_link_num      <= K_PAD;
      o_lane_num      <= K_PAD;
      o_ts_ctrl       <= '0;
      o_link_detected <= 1'b0;
      o_lane_detected <= 1'b0;
    end
    else if (i_fsm_state == CONFIG_LINKWIDTH_START_LINKNUM) begin
      if (os_detected == 1'b1 && rx_link != K_PAD) begin
        o_link_num      <= rx_link;
        o_lane_num      <= K_PAD;
        o_ts_ctrl       <= '0;
        o_link_detected <= 1'b1;
        o_lane_detected <= 1'b0;
      end
    end
    else if (i_fsm_state == CONFIG_LINKWIDTH_ACCEPT_LANENUM) begin
      if (os_detected == 1'b1 && rx_lane != K_PAD && rx_link == o_link_num) begin
        o_lane_num      <= rx_lane;
        o_ts_ctrl       <= '0;
        o_link_detected <= 1'b1;
        o_lane_detected <= 1'b1;
      end
    end
    else if (i_fsm_state == CONFIG_COMPLETE) begin
      o_ts_ctrl <= rx_ctrl;
    end
    else if (i_fsm_state == DETECT_QUIET) begin
      o_link_num      <= K_PAD;
      o_lane_num      <= K_PAD;
      o_ts_ctrl       <= '0;
      o_link_detected <= 1'b0;
      o_lane_detected <= 1'b0;
    end
  end

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Nov 3, 2026
// -----------------------------------------------------------------------------
