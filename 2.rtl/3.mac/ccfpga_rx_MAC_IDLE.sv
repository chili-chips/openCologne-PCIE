// SPDX-FileCopyrightText: 2025-2026 Cologne Chip AG
//
// SPDX-License-Identifier: BSD-3-Clause

// Refined in the NLnet-funded openCologne-PCIE project,
// executed by Chili.CHIPS and Intergalaktik doo

//----------------------------------------------------------------------------------------
// Description: This module handles the Rx MAC IDLE detection and counting
// - Counts the number of consecutive IDLE symbols received
// - Generates IDLE detected and count maxed signals
//========================================================================================

module ccfpga_rx_MAC_IDLE
  import pipe_pkg::*;
  import mac_pkg::*;
(
    input  logic i_clk,               // Clock
    input  logic i_rx_idle_flag_rst,  // IDLE count reset flag
    input  logic i_com_detected,      // COM detected signal

    output logic o_idle_detected,     // IDLE detected signal
    output logic o_rx_idle_flag       // IDLE count maxed signal
);

  logic [3:0] rx_count_idle;  // IDLE count

  logic       inc_count_idle;  // IDLE count increment signal
  logic       clear_count_idle;  // IDLE count clear signal

  // IDLE detection signal
  always_ff @(posedge i_clk or posedge i_rx_idle_flag_rst) begin
    if (i_rx_idle_flag_rst) begin
      o_idle_detected <= 1'b0;
    end
    else if ( inc_count_idle ) // Idle pattern detected
            begin
      o_idle_detected <= 1'b1;
    end
    else begin
      o_idle_detected <= 1'b0;
    end
  end

  // IDLE counting/ count_maxed is hold until reset or clear_count
  always_ff @(posedge i_clk or posedge i_rx_idle_flag_rst) begin
    if (i_rx_idle_flag_rst) begin
      rx_count_idle  <= 4'b0;
      o_rx_idle_flag <= 1'b0;
    end
    else if (clear_count_idle) begin
      rx_count_idle  <= 4'b0;
      o_rx_idle_flag <= 1'b0;
    end
    else if (inc_count_idle) begin
      if (rx_count_idle == 4'(IDL_MAX_COUNT)) begin
        rx_count_idle  <= rx_count_idle;
        o_rx_idle_flag <= 1'b1;
      end
      else begin
        rx_count_idle  <= rx_count_idle + 4'(DATA_BYTES);
        o_rx_idle_flag <= 1'b0;
      end
    end
  end

  // IDLE counting signals
  //assign inc_count_idle = ( rx_data_shift[NUMBER_OF_STEPS] == { DATA_WIDTH{1'b0} } );
  assign inc_count_idle   = i_com_detected == 1'b0;
  assign clear_count_idle = !inc_count_idle;

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Nov 3, 2026
// -----------------------------------------------------------------------------
