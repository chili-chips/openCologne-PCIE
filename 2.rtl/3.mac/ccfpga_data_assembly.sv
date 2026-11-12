// SPDX-FileCopyrightText: 2025-2026 Cologne Chip AG
//
// SPDX-License-Identifier: BSD-3-Clause

// Refined in the NLnet-funded openCologne-PCIE project,
// executed by Chili.CHIPS and Intergalaktik doo

//----------------------------------------------------------------------------------------
// Description: This module assembles the received data bytes into patterns
// - COM detected, start assembling the Ordered Set
// - New COM arrival before completing the Ordered Set resets the assembly
// - Completion of Ordered Set assembly resets the assembly
// - Forward the last received data to DLL
//========================================================================================

module ccfpga_data_assembly
  import pipe_pkg::*;
  import mac_pkg::*;
#(
    localparam int PATTERN_WIDTH   = OS_W,
    parameter  int NUMBER_OF_STEPS = 2
) (
    input  logic                          i_clk,            // Clock
    input  logic                          i_reset,          // Asynchronous i_reset
    input  pipe_sym_t                     i_rx_sym,         // Received symbols and K flags
    output logic                          o_com_detected,   // COM detected flag
    output logic      [PATTERN_WIDTH-1:0] o_data_os,        // Extracted Ordered Set data
    output pipe_sym_t                     o_rx_sym_aligned  // Data and K flags forwarded to DLL
);

  // K characters

  // Shift registers to store received data for Ordered Set assembly
  pipe_sym_t rx_shift[NUMBER_OF_STEPS+1];
  integer    i;

  always_ff @(posedge i_clk) begin
    rx_shift[0] <= i_rx_sym;
    for (i = 1; i < NUMBER_OF_STEPS + 1; i = i + 1) begin
      rx_shift[i] <= rx_shift[i-1];
    end
  end

  // Note: this design is a bit overkilled as the current SerDes setup aligns the COM
  // to the first or the fifth byte for 64 bit data width and always to the first byte for 32 bit or
  // narrower.
  // However, this design can handle any COM position and is more robust to potential future changes
  // in SerDes alignment.

  localparam int WIN_BYTES = (NUMBER_OF_STEPS + 1) * DATA_BYTES;

  logic [WIN_BYTES*8-1:0] win;  //  flatten out the received window
  logic [  WIN_BYTES-1:0] win_k;

  genvar w;
  generate
    for (w = 0; w < NUMBER_OF_STEPS + 1; w = w + 1) begin : g_window
      assign win[w*DATA_WIDTH+:DATA_WIDTH]   = rx_shift[NUMBER_OF_STEPS-w].data;
      assign win_k[w*DATA_BYTES+:DATA_BYTES] = rx_shift[NUMBER_OF_STEPS-w].kcode;
    end
  endgenerate

  logic                       com_found;
  logic                       skp_found;
  logic   [PATTERN_WIDTH-1:0] os_found;
  integer                     p;

  always_comb begin
    com_found = 1'b0;
    skp_found = 1'b0;
    os_found  = {PATTERN_WIDTH{1'b0}};
    for (p = DATA_BYTES - 1; p >= 0; p = p - 1) begin
      if (win[8*p+:8] == K_COM && win_k[p]) begin
        com_found = 1'b1;
        skp_found = (win[8*(p+1)+:8] == K_SKP) & win_k[p+1];
        os_found  = win[8*p+:PATTERN_WIDTH];
      end
    end
  end

  always_ff @(posedge i_clk or posedge i_reset) begin
    if (i_reset) begin
      o_rx_sym_aligned <= '0;
      o_com_detected   <= 1'b0;
      o_data_os        <= {PATTERN_WIDTH{1'b0}};
    end
    else begin
      o_rx_sym_aligned <= rx_shift[NUMBER_OF_STEPS];
      if (com_found && !skp_found) begin
        o_com_detected <= 1'b1;
        o_data_os      <= os_found;
      end
      else begin
        o_com_detected <= 1'b0;
        o_data_os      <= {PATTERN_WIDTH{1'b0}};
      end
    end
  end

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Nov 3, 2026
// -----------------------------------------------------------------------------
