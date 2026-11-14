// SPDX-FileCopyrightText: 2025-2026 Cologne Chip AG
//
// SPDX-License-Identifier: BSD-3-Clause

// Refined in the NLnet-funded openCologne-PCIE project,
// executed by Chili.CHIPS and Intergalaktik doo

//-----------------------------------------------------------------------------
// Description: Count the number of transmitted sequences after receiving one
// sequence (IDLE or Ordered Set)
// - Polling Active does not require receiving a sequence to start counting
//=============================================================================

module ccfpga_tx_count
  import pipe_pkg::*;
#(
    parameter int COUNT_WIDTH = 5,
    parameter int IDLE_WIDTH  = 8
) (
    input  logic                       i_clk,
    input  logic                       i_tx_os_flag_rst,
    input  logic                       i_tx_idle_flag_rst,
    input  logic                       i_tx_poll_flag_rst,

    input  logic                       i_os_sent,
    input  logic                       i_os_valid,
    input  logic                       i_os_rec_cfg_detected,
    input  logic                       i_idle_sent,
    input  logic                       i_idle_detected,
    input  logic [COUNT_WIDTH - 1 : 0] i_max_count,

    output logic                       o_tx_os_flag,
    output logic                       o_tx_idle_flag,
    output logic                       o_tx_poll_flag
);

  localparam logic [COUNT_WIDTH-1:0] IDLE_MAX_COUNT = COUNT_WIDTH'(16);
  localparam logic [10:0] POLLING_ACTIVE_MAX_COUNT = 11'd1024;
  localparam logic [COUNT_WIDTH-1:0] NUMBER_OF_STEPS = COUNT_WIDTH'(DATA_WIDTH / IDLE_WIDTH);

  logic [COUNT_WIDTH - 1 : 0] tx_count_os;
  logic [COUNT_WIDTH - 1 : 0] tx_count_idle;
  logic [               10:0] polling_active_tx_count;
  logic                       os_count_enabled;
  logic                       idle_count_enabled;

  // Pattern counting
  always_ff @(posedge i_clk or posedge i_tx_os_flag_rst) begin
    if (i_tx_os_flag_rst) begin
      tx_count_os <= {COUNT_WIDTH{1'b0}};
    end
    else if (os_count_enabled == 1'b1) begin
      if (tx_count_os == i_max_count) begin
        tx_count_os <= tx_count_os;
      end
      else if (i_os_sent) begin
        tx_count_os <= tx_count_os + 1'b1;
      end
    end
  end

  // IDLE counting
  always_ff @(posedge i_clk or posedge i_tx_idle_flag_rst) begin
    if (i_tx_idle_flag_rst) begin
      tx_count_idle <= {COUNT_WIDTH{1'b0}};
    end
    else if (idle_count_enabled == 1'b1) begin
      if (tx_count_idle == IDLE_MAX_COUNT) begin
        tx_count_idle <= tx_count_idle;
      end
      else if (i_idle_sent) begin
        tx_count_idle <= tx_count_idle + NUMBER_OF_STEPS;
      end
    end
  end

  // Polling Active counting
  always_ff @(posedge i_clk or posedge i_tx_poll_flag_rst) begin
    if (i_tx_poll_flag_rst) begin
      polling_active_tx_count <= '0;
    end
    else begin
      if (polling_active_tx_count == POLLING_ACTIVE_MAX_COUNT) begin
        polling_active_tx_count <= polling_active_tx_count;
      end
      else if (i_os_sent) begin
        polling_active_tx_count <= polling_active_tx_count + 1'b1;
      end
    end
  end

  // Enable counting after an Ordered Set is detected
  always_ff @(posedge i_clk or posedge i_tx_os_flag_rst) begin
    if (i_tx_os_flag_rst) begin
      os_count_enabled <= 1'b0;
    end
    else if (i_os_valid || i_os_rec_cfg_detected) begin
      os_count_enabled <= 1'b1;
    end
  end

  // Enable IDLE counting after an IDLE is detected
  always_ff @(posedge i_clk or posedge i_tx_idle_flag_rst) begin
    if (i_tx_idle_flag_rst) begin
      idle_count_enabled <= 1'b0;
    end
    else if (i_idle_detected) begin
      idle_count_enabled <= 1'b1;
    end
  end

  assign o_tx_os_flag   = tx_count_os == i_max_count;
  assign o_tx_idle_flag = tx_count_idle == IDLE_MAX_COUNT;
  assign o_tx_poll_flag = polling_active_tx_count == POLLING_ACTIVE_MAX_COUNT;

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Nov 3, 2026
// -----------------------------------------------------------------------------
