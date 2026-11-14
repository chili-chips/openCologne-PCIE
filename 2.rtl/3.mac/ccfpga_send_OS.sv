// SPDX-FileCopyrightText: 2025-2026 Cologne Chip AG
//
// SPDX-License-Identifier: BSD-3-Clause

// Refined in the NLnet-funded openCologne-PCIE project,
// executed by Chili.CHIPS and Intergalaktik doo

//----------------------------------------------------------------------------
// Description: This module sends 128-bit Ordered Set, which will be
// transmitted through multiple cycles depending on the DATA_WIDTH
// - os_sent flag is set at the end for one cycle
//============================================================================

module ccfpga_send_OS
  import pipe_pkg::*;
  import mac_pkg::*;
(
    input  logic            i_clk,
    input  logic            i_send_os_trigger,
    input  logic            i_reset,

    input  logic      [7:0] i_link_num,
    input  logic      [7:0] i_lane_num,
    input  ts_ctrl_t        i_ts_ctrl,
    input  os_type_e        i_os_type,
    input  logic            i_skp_in_queue,

    output pipe_sym_t       o_tx_sym,
    output logic            o_os_sent,
    output logic            o_sending_os
);

  localparam int PATTERN_WIDTH   = OS_W;
  localparam int PATTERN_BYTES   = PATTERN_WIDTH / 8;
  localparam int NUMBER_OF_STEPS = PATTERN_WIDTH / DATA_WIDTH - 1;


  ts_os_t                         pattern;
  logic   [PATTERN_BYTES - 1 : 0] pattern_k;
  logic                           pad_link;
  logic                           pad_lane;

  // A SKP is queued: set at the end of an OS, cleared when the queue drains;
  // no new OS starts while it is set
  logic                           skp_yield;
  localparam int                STEP_W    = $clog2(NUMBER_OF_STEPS) + 1;
  localparam logic [STEP_W-1:0] LAST_STEP = STEP_W'(NUMBER_OF_STEPS);
  logic   [           STEP_W-1:0] step;
  ts_os_t                         held_pattern;
  logic   [PATTERN_BYTES - 1 : 0] held_pattern_k;

  ts_os_t                         cur_pattern;
  assign                        cur_pattern   = (step == 0) ? pattern : held_pattern;
  logic [PATTERN_BYTES - 1 : 0] cur_pattern_k;
  assign                        cur_pattern_k = (step == 0) ? pattern_k : held_pattern_k;

  always_ff @(posedge i_clk or posedge i_reset) begin
    if (i_reset) begin
      o_tx_sym       <= '0;
      o_os_sent      <= 1'b0;
      step           <= 0;
      o_sending_os   <= 1'b0;
      skp_yield      <= 1'b0;
      held_pattern   <= '0;
      held_pattern_k <= {PATTERN_BYTES{1'b0}};
    end
    else if ((i_send_os_trigger == 1'b1 && skp_yield == 1'b0) || step != 0) begin
      if (step == 0) begin
        held_pattern   <= pattern;
        held_pattern_k <= pattern_k;
      end
      if (step != LAST_STEP) begin
        o_tx_sym.data  <= cur_pattern[DATA_WIDTH*step+:DATA_WIDTH];
        o_tx_sym.kcode <= cur_pattern_k[DATA_BYTES*step+:DATA_BYTES];
        o_os_sent      <= 1'b0;
        o_sending_os   <= 1'b1;
        step           <= step + 1;
        skp_yield      <= skp_yield;
      end
      else begin
        o_tx_sym.data  <= cur_pattern[DATA_WIDTH*step+:DATA_WIDTH];
        o_tx_sym.kcode <= cur_pattern_k[DATA_BYTES*step+:DATA_BYTES];
        o_os_sent      <= 1'b1;
        o_sending_os   <= 1'b1;
        step           <= 0;
        if (i_skp_in_queue == 1'b1) begin
          skp_yield <= 1'b1;
        end
        else begin
          skp_yield <= skp_yield;
        end
      end
    end
    else begin
      o_tx_sym     <= '0;
      o_os_sent    <= 1'b0;
      o_sending_os <= 1'b0;
      step         <= 0;
      if (i_skp_in_queue == 1'b0) begin
        skp_yield <= 1'b0;
      end
      else begin
        skp_yield <= skp_yield;
      end
    end
  end

  always_comb begin
    pattern.id = {10{TS1_ID}};
    if (i_os_type == OS_TS2) begin
      pattern.id = {10{TS2_ID}};
    end
    pattern.ctrl  = i_ts_ctrl;
    pattern.rate  = TS_RATE_2G5;
    pattern.n_fts = 8'h00;
    pattern.lane  = i_lane_num;
    pattern.link  = i_link_num;
    pattern.com   = K_COM;
  end
  assign pad_link  = i_link_num == K_PAD;
  assign pad_lane  = i_lane_num == K_PAD;
  assign pattern_k = {{13'b0}, pad_lane, pad_link, 1'b1};

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Nov 3, 2026
// -----------------------------------------------------------------------------
