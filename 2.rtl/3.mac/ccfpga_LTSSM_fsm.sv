// SPDX-FileCopyrightText: 2025-2026 Cologne Chip AG
//
// SPDX-License-Identifier: BSD-3-Clause

// Refined in the NLnet-funded openCologne-PCIE project,
// executed by Chili.CHIPS and Intergalaktik doo

//----------------------------------------------------------------------------
// Description: This module defines the LTSSM for PCIe
// - It handles the state transitions and based on input flags and conditions
// - Outputs appropriate triggers for OS, IDLE, and data transmission
// - Outputs reset flags for timeouts, Rx/Tx counters, and link/lane detection
//============================================================================

module ccfpga_LTSSM_fsm
  import pipe_pkg::*;
  import mac_pkg::*;
(
    input logic       i_reset_n,          // Asynchronous Reset
    input logic       i_pclk,             // Parallel Interface Clock
    input rx_status_e i_rx_status,        // Receiver Status
    input logic       i_timeout,          // Timeout Flag
    input logic       i_rx_flag,          // Rx Flag
    input logic       i_tx_flag,          // Tx Flag
    // Separate tx/rx flags due to different handling in these states
    input logic       i_tx_poll_flag,     // Polling Active Tx flag
    input logic       i_rx_rec_cfg_flag,  // Recovery Rcvrcfg Rx flag
    input logic       i_rx_rec_idle_flag, // Recovery Idle Rx flag

    input logic i_rx_elec_idle,   // Electrical Idle at Receiver
    input logic i_link_detected,  // Link number Detected
    input logic i_lane_detected,  // Lane number Detected

    output logic o_tx_detect_rx,  // Receiver Detection (P1)/Loopback (P0)
    output logic o_tx_elec_idle,  // Electrical Idle
    output logic [DATA_BYTES-1:0] o_tx_compliance,  // Compliance Pattern
    output logic o_send_os_trigger,  // Trigger the sending of OS
    output logic o_send_idle_trigger,  // Trigger the sending of IDLE
    output logic o_send_data_trigger,  // Trigger the sending of data
    output ltssm_state_e o_fsm_state,  // fsm status
    output logic o_timeout_clk_rst,  // Timeout Reset
    output logic o_timeout_os_rst,  // OS Timeout Reset
    output logic o_rx_flag_rst,  // Rx Flag Reset
    output logic o_tx_flag_rst,  // Tx Flag Reset
    // Separate tx/rx flags due to different handling in these states
    output logic o_tx_poll_flag_rst,  // Polling Active Tx flag Reset
    output logic o_rx_rec_cfg_flag_rst,  // Recovery Rcvrcfg Rx flag Reset
    output logic o_rx_rec_idle_flag_rst,  // Recovery Idle Rx flag Reset

    output logic o_link_detected_rst,  // Link Detected Reset
    output logic o_lane_detected_rst   // Lane Detected Reset
);

  // FSM states: ltssm_state_e in mac_pkg
  ltssm_state_e s_state, s_next_state;

  assign o_fsm_state = s_state;


  //State Register
  always_ff @(posedge i_pclk, negedge i_reset_n) begin
    if (!i_reset_n) begin
      s_state <= DETECT_QUIET;
    end
    else begin
      s_state <= s_next_state;
    end
  end

  //Transition logic
  always_comb begin
    s_next_state = s_state;
    unique case (s_state)
      DETECT_QUIET: begin
        if (i_timeout == 1'b1 | i_rx_elec_idle == 1'b0) begin
          s_next_state = PRE_DETECT_ACTIVE;
        end
        else begin
          s_next_state = DETECT_QUIET;
        end
      end
      PRE_DETECT_ACTIVE: begin
        s_next_state = DETECT_ACTIVE;
      end
      PRE_DETECT_QUIET: begin
        s_next_state = DETECT_QUIET;
      end
      DETECT_ACTIVE: begin
        if (i_rx_status == RX_DETECTED) begin
          s_next_state = POLLING_ACTIVE;
        end
        else if (i_timeout == 1'b1) begin
          s_next_state = PRE_DETECT_QUIET;
        end
        else begin
          s_next_state = DETECT_ACTIVE;
        end
      end
      POLLING_ACTIVE: begin
        if ((i_rx_flag == 1'b1) && (i_tx_poll_flag == 1'b1)) begin
          s_next_state = PRE_POLLING_CONFIG;
        end
        else if (i_timeout == 1'b1) begin
          s_next_state = PRE_DETECT_QUIET;
        end
      end
      PRE_POLLING_CONFIG: begin
        s_next_state = POLLING_CONFIG;
      end
      POLLING_CONFIG: begin
        if ((i_rx_flag == 1'b1) && (i_tx_flag == 1'b1)) begin
          s_next_state = PRE_CONFIG_LINKWIDTH_START;
        end
        else if (i_timeout == 1'b1) begin
          s_next_state = PRE_DETECT_QUIET;
        end
      end
      PRE_CONFIG_LINKWIDTH_START: begin
        s_next_state = CONFIG_LINKWIDTH_START_LINKNUM;
      end
      CONFIG_LINKWIDTH_START_LINKNUM: begin
        if (i_link_detected == 1'b1) begin
          s_next_state = PRE_CONFIG_LINKWIDTH_START_CNT;
        end
        else if (i_timeout == 1'b1) begin
          s_next_state = PRE_DETECT_QUIET;
        end
      end
      PRE_CONFIG_LINKWIDTH_START_CNT: begin
        s_next_state = CONFIG_LINKWIDTH_START;
      end
      CONFIG_LINKWIDTH_START: begin
        if (i_rx_flag == 1'b1) begin
          s_next_state = PRE_CONFIG_LINKWIDTH_ACCEPT;
        end
        else if (i_timeout == 1'b1) begin
          s_next_state = PRE_DETECT_QUIET;
        end
      end
      PRE_CONFIG_LINKWIDTH_ACCEPT: begin
        s_next_state = CONFIG_LINKWIDTH_ACCEPT_LANENUM;
      end
      CONFIG_LINKWIDTH_ACCEPT_LANENUM: begin
        if (i_lane_detected == 1'b1) begin
          s_next_state = PRE_CONFIG_LINKWIDTH_ACCEPT_CNT;
        end
        else if (i_timeout == 1'b1) begin
          s_next_state = PRE_DETECT_QUIET;
        end
      end
      PRE_CONFIG_LINKWIDTH_ACCEPT_CNT: begin
        s_next_state = CONFIG_LINKWIDTH_ACCEPT;
      end
      CONFIG_LINKWIDTH_ACCEPT: begin
        if (i_rx_flag == 1'b1) begin
          s_next_state = PRE_CONFIG_LANENUM_ACCEPT;
        end
        else if (i_timeout == 1'b1) begin
          s_next_state = PRE_DETECT_QUIET;
        end
      end
      PRE_CONFIG_LANENUM_ACCEPT: begin
        s_next_state = CONFIG_LANENUM_ACCEPT;
      end
      CONFIG_LANENUM_WAIT: begin
        if (i_rx_flag == 1'b1) begin
          s_next_state = PRE_CONFIG_LANENUM_ACCEPT;
        end
        else if (i_timeout == 1'b1) begin
          s_next_state = PRE_DETECT_QUIET;
        end
      end
      CONFIG_LANENUM_ACCEPT: begin
        if (i_rx_flag == 1'b1) begin
          s_next_state = PRE_CONFIG_COMPLETE;
        end
        else if (i_timeout == 1'b1) begin
          s_next_state = PRE_DETECT_QUIET;
        end
      end
      PRE_CONFIG_COMPLETE: begin
        s_next_state = CONFIG_COMPLETE;
      end
      CONFIG_COMPLETE: begin
        if ((i_rx_flag == 1'b1) && (i_tx_flag == 1'b1)) begin
          s_next_state = PRE_CONFIG_IDLE;
        end
        else if (i_timeout == 1'b1) begin
          s_next_state = PRE_DETECT_QUIET;
        end
      end
      PRE_CONFIG_IDLE: begin
        s_next_state = CONFIG_IDLE;
      end
      CONFIG_IDLE: begin
        if ((i_rx_flag == 1'b1) && (i_tx_flag == 1'b1)) begin
          s_next_state = PRE_L0;
        end
        else if (i_timeout == 1'b1) begin
          s_next_state = PRE_DETECT_QUIET;
        end
      end
      PRE_L0: begin
        s_next_state = L0;
      end
      L0: begin
        if (i_rx_flag == 1'b1) begin
          s_next_state = PRE_RECOVERY_RCVRLOCK;
        end
      end
      PRE_RECOVERY_RCVRLOCK: begin
        s_next_state = RECOVERY_RCVRLOCK;
      end
      RECOVERY_RCVRLOCK: begin
        if (i_rx_flag == 1'b1) begin
          s_next_state = PRE_RECOVERY_RCVRCFG;
        end
        else if (i_timeout == 1'b1) begin
          s_next_state = PRE_DETECT_QUIET;
        end
      end
      PRE_RECOVERY_RCVRCFG: begin
        s_next_state = RECOVERY_RCVRCFG;
      end
      RECOVERY_RCVRCFG: begin
        if ((i_rx_flag == 1'b1) && (i_tx_flag == 1'b1)) begin
          s_next_state = PRE_RECOVERY_IDLE;
        end
        // Received 2 consecutive TS1 with PAD-Lane
        else if ((i_rx_rec_cfg_flag == 1'b1) && (i_tx_flag == 1'b1)) begin
          s_next_state = PRE_CONFIG_LINKWIDTH_START;
        end
        else if (i_timeout == 1'b1) begin
          s_next_state = PRE_DETECT_QUIET;
        end
      end
      PRE_RECOVERY_IDLE: begin
        s_next_state = RECOVERY_IDLE;
      end
      RECOVERY_IDLE: begin
        if ((i_rx_flag == 1'b1) && (i_tx_flag == 1'b1)) begin
          s_next_state = PRE_L0;
        end
        else if ( i_rx_rec_idle_flag == 1'b1 ) // Received 2 consecutive TS1 with PAD-Lane
               begin
          s_next_state = PRE_CONFIG_LINKWIDTH_START;
        end
        else if (i_timeout == 1'b1) begin
          s_next_state = PRE_DETECT_QUIET;
        end
      end
      default: ;
    endcase
  end

  // Output logic
  always_comb begin
    o_tx_detect_rx         = 1'b0;
    o_tx_elec_idle         = 1'b0;
    o_tx_compliance        = {DATA_BYTES{1'b0}};
    o_timeout_os_rst       = 1'b1;
    o_timeout_clk_rst      = 1'b1;
    o_rx_flag_rst          = 1'b1;
    o_tx_flag_rst          = 1'b1;
    o_tx_poll_flag_rst     = 1'b1;
    o_rx_rec_cfg_flag_rst  = 1'b1;
    o_rx_rec_idle_flag_rst = 1'b1;
    o_send_os_trigger      = 1'b0;
    o_send_idle_trigger    = 1'b0;
    o_send_data_trigger    = 1'b0;
    o_lane_detected_rst    = 1'b1;
    o_link_detected_rst    = 1'b1;
    unique case (s_state)
      DETECT_QUIET: begin
        o_tx_detect_rx    = 1'b0;
        o_tx_elec_idle    = 1'b1;
        o_timeout_clk_rst = 1'b0;  // Start counting 12ms
      end
      PRE_DETECT_ACTIVE: begin
        o_tx_elec_idle = 1'b1;
      end
      PRE_DETECT_QUIET: begin
        o_tx_elec_idle = 1'b1;
      end
      DETECT_ACTIVE: begin
        o_tx_detect_rx    = 1'b1;
        o_tx_elec_idle    = 1'b1;
        o_timeout_clk_rst = 1'b0;  // Start counting 12ms
      end
      POLLING_ACTIVE: begin
        o_send_os_trigger  = 1'b1;
        o_rx_flag_rst      = 1'b0;
        o_tx_poll_flag_rst = 1'b0;
        o_timeout_clk_rst  = 1'b0;  // Start counting 24ms
      end
      PRE_POLLING_CONFIG: begin
        o_send_os_trigger = 1'b1;
      end
      POLLING_CONFIG: begin
        o_send_os_trigger = 1'b1;
        o_rx_flag_rst     = 1'b0;
        o_tx_flag_rst     = 1'b0;
        o_timeout_clk_rst = 1'b0;  // Start counting 48ms
      end
      CONFIG_LINKWIDTH_START_LINKNUM: begin
        o_send_os_trigger   = 1'b1;
        o_link_detected_rst = 1'b0;
        o_timeout_clk_rst   = 1'b0;  // Start counting 24ms
      end
      CONFIG_LINKWIDTH_START: begin
        o_send_os_trigger = 1'b1;
        o_rx_flag_rst     = 1'b0;
        o_timeout_clk_rst = 1'b0;  // Start counting 24ms
      end
      CONFIG_LINKWIDTH_ACCEPT_LANENUM: begin
        o_send_os_trigger   = 1'b1;
        o_lane_detected_rst = 1'b0;
        o_timeout_clk_rst   = 1'b0;  // Start counting 2ms
      end
      CONFIG_LINKWIDTH_ACCEPT: begin
        o_send_os_trigger = 1'b1;
        o_rx_flag_rst     = 1'b0;
        o_timeout_clk_rst = 1'b0;  // Start counting 2ms
        o_timeout_os_rst  = 1'b0;  // Start counting 2 consecutive TS1 with PAD Link and Lane
      end
      CONFIG_LANENUM_WAIT: begin
        o_send_os_trigger = 1'b1;
        o_rx_flag_rst     = 1'b0;
        o_timeout_clk_rst = 1'b0;  // Start counting 2ms
        o_timeout_os_rst  = 1'b0;  // Start counting 2 consecutive TS1 with PAD Link and Lane
      end
      CONFIG_LANENUM_ACCEPT: begin
        o_send_os_trigger = 1'b1;
        o_rx_flag_rst     = 1'b0;
        o_timeout_os_rst  = 1'b0;  // 2 consecutive TS1 with PAD Link and Lane
      end
      CONFIG_COMPLETE: begin
        o_send_os_trigger = 1'b1;
        o_rx_flag_rst     = 1'b0;
        o_tx_flag_rst     = 1'b0;
        o_timeout_clk_rst = 1'b0;  // Start counting 2ms
      end
      CONFIG_IDLE: begin
        o_send_idle_trigger = 1'b1;
        o_rx_flag_rst       = 1'b0;
        o_tx_flag_rst       = 1'b0;
        o_timeout_clk_rst   = 1'b0;  // Start counting 2ms
      end
      L0: begin
        // Normal Operation
        o_send_data_trigger = 1'b1;
        o_rx_flag_rst       = 1'b0;
      end
      RECOVERY_RCVRLOCK: begin
        o_send_os_trigger = 1'b1;
        o_rx_flag_rst     = 1'b0;
        o_timeout_clk_rst = 1'b0;  // Start counting 24ms
      end
      RECOVERY_RCVRCFG: begin
        o_send_os_trigger     = 1'b1;
        o_rx_flag_rst         = 1'b0;
        o_tx_flag_rst         = 1'b0;
        o_rx_rec_cfg_flag_rst = 1'b0;
        o_timeout_clk_rst     = 1'b0;  // Start counting 48ms
      end
      RECOVERY_IDLE: begin
        o_send_idle_trigger    = 1'b1;
        o_rx_flag_rst          = 1'b0;
        o_tx_flag_rst          = 1'b0;
        o_rx_rec_idle_flag_rst = 1'b0;
        o_timeout_clk_rst      = 1'b0;  // Start counting 2ms
      end
      default: ;
    endcase
  end

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Nov 3, 2026
// -----------------------------------------------------------------------------
