// SPDX-FileCopyrightText: 2025-2026 Cologne Chip AG
//
// SPDX-License-Identifier: BSD-3-Clause

// Refined in the NLnet-funded openCologne-PCIE project,
// executed by Chili.CHIPS and Intergalaktik doo

//----------------------------------------------------------------------------------------
// Description: This module handles the Rx side of PHY/MAC
// - It counts the number of consecutive received Ordered Set sequences, Idle sequences
// - Link and lane defines the expected Link and Lane numbers in the received Ordered Sets
// - Ctrl defines the expected control signal for the received Ordered Sets
// - It handles and forwards the received data to DLL
// - It detects inversion in the received Ordered Sets
// - It handles Rx timeout detection
// - The received data is stored in a shift register for processing
//========================================================================================

module ccfpga_rx_MAC
  import pipe_pkg::*;
  import mac_pkg::*;
#(
    parameter  int COUNT_WIDTH   = 4,
    localparam int PATTERN_WIDTH = OS_W
) (
    input  logic                               i_clk,
    input  logic                               i_reset,
    input  ltssm_state_e                       i_fsm_state,

    input  pipe_sym_t                          i_rx_sym,

    input  logic                               i_rx_os_flag_rst,
    input  logic                               i_rx_idle_flag_rst,
    input  logic                               i_timeout_os_rst,
    input  logic                               i_rx_rec_cfg_flag_rst,
    input  logic                               i_rx_rec_idle_flag_rst,
    input  logic                               i_ts1_pattern_en,
    input  logic                               i_ts2_pattern_en,
    input  logic         [COUNT_WIDTH - 1 : 0] i_max_count,
    input  logic                               i_l0_enabled,

    output logic                               o_os_valid,
    output logic                               o_inversion_detected,
    output logic                               o_os_rec_cfg_detected,
    output logic                               o_idle_detected,
    output logic                               o_rx_os_flag,
    output logic                               o_timeout_os,
    output logic                               o_rx_idle_flag,
    output logic                               o_rx_rec_cfg_flag,
    output logic                               o_rx_rec_idle_flag,
    output logic         [7:0]                 o_link_num,
    output logic         [7:0]                 o_lane_num,
    output ts_ctrl_t                           o_ts_ctrl,
    output logic                               o_link_detected,
    output logic                               o_lane_detected,
    output pipe_sym_t                          o_rx_sym_dll
);


  localparam int NUMBER_OF_STEPS = PATTERN_WIDTH / DATA_WIDTH;

  logic                          com_detected;
  logic      [PATTERN_WIDTH-1:0] data_os;
  pipe_sym_t                     assembled_sym;

  //--------------------------------------------------------------------------------
  ccfpga_data_assembly #(
      .NUMBER_OF_STEPS (NUMBER_OF_STEPS)
  ) u_data_assembly (
      .i_clk            (i_clk),
      .i_reset          (i_reset),
      .i_rx_sym         (i_rx_sym),
      .o_com_detected   (com_detected),
      .o_data_os        (data_os),
      .o_rx_sym_aligned (assembled_sym)
  );
  //--------------------------------------------------------------------------------
  // Instantiation of Rx MAC Ordered Set processing module
  ccfpga_rx_MAC_OS #(
      .COUNT_WIDTH (COUNT_WIDTH)
  ) u_rx_mac_os (
      .i_clk       (i_clk),
      .i_reset     (i_reset),
      .i_fsm_state (i_fsm_state),

      .i_data (data_os),

      .i_rx_os_flag_rst       (i_rx_os_flag_rst),
      .i_timeout_os_rst       (i_timeout_os_rst),
      .i_rx_rec_cfg_flag_rst  (i_rx_rec_cfg_flag_rst),
      .i_rx_rec_idle_flag_rst (i_rx_rec_idle_flag_rst),
      .i_ts1_pattern_en       (i_ts1_pattern_en),
      .i_ts2_pattern_en       (i_ts2_pattern_en),
      .i_com_detected         (com_detected),

      .i_max_count (i_max_count),

      .o_os_valid            (o_os_valid),
      .o_os_rec_cfg_detected (o_os_rec_cfg_detected),
      .o_inversion_detected  (o_inversion_detected),

      .o_link_num      (o_link_num),
      .o_lane_num      (o_lane_num),
      .o_ts_ctrl       (o_ts_ctrl),
      .o_link_detected (o_link_detected),
      .o_lane_detected (o_lane_detected),

      .o_rx_os_flag       (o_rx_os_flag),
      .o_timeout_os       (o_timeout_os),
      .o_rx_rec_cfg_flag  (o_rx_rec_cfg_flag),
      .o_rx_rec_idle_flag (o_rx_rec_idle_flag)
  );
  //--------------------------------------------------------------------------------
  // Instantiation of Rx MAC IDLE processing module
  ccfpga_rx_MAC_IDLE u_rx_mac_idle (
      .i_clk              (i_clk),
      .i_rx_idle_flag_rst (i_rx_idle_flag_rst),
      .i_com_detected     (com_detected),

      .o_idle_detected (o_idle_detected),
      .o_rx_idle_flag  (o_rx_idle_flag)
  );
  //--------------------------------------------------------------------------------
  // Instantiation of Rx MAC data processing module
  ccfpga_rx_MAC_data u_rx_mac_data (
      .i_clk        (i_clk),
      .i_reset      (i_reset),
      .i_l0_enabled (i_l0_enabled),
      .i_rx_sym     (assembled_sym),

      .o_rx_sym_dll (o_rx_sym_dll)
  );
  //--------------------------------------------------------------------------------
endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Nov 3, 2026
// -----------------------------------------------------------------------------
