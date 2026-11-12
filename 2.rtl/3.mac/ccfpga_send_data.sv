// SPDX-FileCopyrightText: 2025-2026 Cologne Chip AG
//
// SPDX-License-Identifier: BSD-3-Clause

// Refined in the NLnet-funded openCologne-PCIE project,
// executed by Chili.CHIPS and Intergalaktik doo

//----------------------------------------------------------------------------
// Description: This module detects valid data from DLL and sends it out
//============================================================================

module ccfpga_send_data
  import pipe_pkg::*;
(
    input logic      i_clk,
    input logic      i_reset,
    input logic      i_l0_enabled,
    input pipe_sym_t i_tx_sym_dll,  // from the DLL

    output pipe_sym_t o_tx_sym,
    output logic      o_sending_data
);

  logic        in_packet;
  logic        in_packet_next;
  pipe_flags_t is_start;  // per symbol: STP or SDP
  pipe_flags_t is_end;  // per symbol: END or EDB
  integer      i;

  for (genvar j = 0; j < DATA_BYTES; j++) begin : g_detect
    assign is_start[j] = i_tx_sym_dll.kcode[j]
                       & (i_tx_sym_dll.data[8*j+:8] == K_STP | i_tx_sym_dll.data[8*j+:8] == K_SDP);
    assign is_end[j]   = i_tx_sym_dll.kcode[j]
                       & (i_tx_sym_dll.data[8*j+:8] == K_END | i_tx_sym_dll.data[8*j+:8] == K_EDB);
  end

  // the last start or end in the word decides
  always_comb begin
    in_packet_next = in_packet;
    for (i = 0; i < DATA_BYTES; i = i + 1) begin
      if (is_start[i]) begin
        in_packet_next = 1'b1;
      end
      else if (is_end[i]) begin
        in_packet_next = 1'b0;
      end
    end
  end

  always_ff @(posedge i_clk or posedge i_reset) begin
    if (i_reset) begin
      o_tx_sym       <= '0;
      in_packet      <= 1'b0;
      o_sending_data <= 1'b0;
    end
    else if (i_l0_enabled && (in_packet || |i_tx_sym_dll.kcode)) begin
      o_tx_sym       <= i_tx_sym_dll;
      in_packet      <= in_packet_next;
      o_sending_data <= 1'b1;
    end
    else begin
      o_tx_sym       <= '0;
      in_packet      <= 1'b0;
      o_sending_data <= 1'b0;
    end
  end
endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Nov 3, 2026
// -----------------------------------------------------------------------------
