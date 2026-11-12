// SPDX-FileCopyrightText: 2025-2026 Cologne Chip AG
//
// SPDX-License-Identifier: BSD-3-Clause

// Refined in the NLnet-funded openCologne-PCIE project,
// executed by Chili.CHIPS and Intergalaktik doo

//----------------------------------------------------------------------------------------
// Description: This module handles the Rx MAC data forwarding to DLL
// - Forwards received data to DLL when STP or SDP is detected
// - Stops forwarding when END is detected
// - No alignment support for now
//========================================================================================

module ccfpga_rx_MAC_data
  import pipe_pkg::*;
  import mac_pkg::*;
(
    input logic      i_clk,         // Clock
    input logic      i_l0_enabled,  // L0 state enable signal
    input pipe_sym_t i_rx_sym,      // Rx data and K flags

    output pipe_sym_t o_rx_sym_dll  // Data and K flags forwarded to DLL
);


  logic [DATA_BYTES - 1 : 0] char_is_start;  // STP or SDP detected in received data
  logic [DATA_BYTES - 1 : 0] char_is_end;  // END detected in received data
  logic                      start_detected;  // STP or SDP detected flag
  logic                      end_detected;  // END detected flag

  logic                      receiving_data;  // Data receiving flag for DLL (needed??)

  // Forwarding data to DLL when STP or SDP detected
  // Stop when END detected
  // No alignment support for now - the whole datapath is forwarded
  always_ff @(posedge i_clk) begin
    if (i_l0_enabled == 1'b0) begin
      receiving_data <= 1'b0;
      o_rx_sym_dll   <= '0;
    end
    else begin
      if (start_detected) begin
        receiving_data     <= 1'b1;
        o_rx_sym_dll.data  <= i_rx_sym.data;
        o_rx_sym_dll.kcode <= char_is_start | char_is_end;
      end
      else if (end_detected) begin
        receiving_data     <= 1'b0;
        o_rx_sym_dll.data  <= i_rx_sym.data;
        o_rx_sym_dll.kcode <= char_is_end;
      end
      else if (receiving_data == 1'b1) begin
        receiving_data     <= 1'b1;
        o_rx_sym_dll.data  <= i_rx_sym.data;
        o_rx_sym_dll.kcode <= {DATA_BYTES{1'b0}};
      end
      else begin
        receiving_data <= 1'b0;
        o_rx_sym_dll   <= '0;
      end
    end
  end

  // Detection of special characters (STP, SDP or END) in all symbol positions
  generate
    genvar j;
    for (j = 0; j < DATA_BYTES; j = j + 1) begin : g_start_detect
      assign char_is_start[j] = i_rx_sym.kcode[j]
                              & (  (i_rx_sym.data[8*j+:8] == K_STP)
                                 | (i_rx_sym.data[8*j+:8] == K_SDP));
      assign char_is_end[j] = i_rx_sym.kcode[j] & (i_rx_sym.data[8*j+:8] == K_END);
    end
  endgenerate

  // Detection flags
  assign start_detected = |char_is_start;
  assign end_detected   = |char_is_end;

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Nov 3, 2026
// -----------------------------------------------------------------------------
