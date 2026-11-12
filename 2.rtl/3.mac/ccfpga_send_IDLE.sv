// SPDX-FileCopyrightText: 2025-2026 Cologne Chip AG
//
// SPDX-License-Identifier: BSD-3-Clause

// Refined in the NLnet-funded openCologne-PCIE project,
// executed by Chili.CHIPS and Intergalaktik doo

//-----------------------------------------------------------------------------
// Description: This module sends IDLE characters when triggered (IDLE = 8'h00)
//=============================================================================

module ccfpga_send_IDLE
  import pipe_pkg::*;
(
    input logic i_clk,
    input logic i_send_idle_trigger,
    input logic i_reset,
    input logic i_skp_in_queue,

    output pipe_sym_t o_tx_sym,
    output logic      o_idle_sent,
    output logic      o_sending_idle
);

  logic skp_yield;

  always_ff @(posedge i_clk or posedge i_reset) begin
    if (i_reset) begin
      o_tx_sym       <= '0;
      o_idle_sent    <= 1'b0;
      skp_yield      <= 1'b0;
      o_sending_idle <= 1'b0;
    end
    else if (i_send_idle_trigger && skp_yield == 1'b0) begin
      o_tx_sym       <= '0;
      o_idle_sent    <= 1'b1;
      o_sending_idle <= 1'b1;
      if (i_skp_in_queue == 1'b1) begin
        skp_yield <= 1'b1;
      end
      else begin
        skp_yield <= skp_yield;
      end
    end
    else begin
      o_tx_sym       <= '0;
      o_idle_sent    <= 1'b0;
      o_sending_idle <= 1'b0;
      if (i_skp_in_queue == 1'b0) begin
        skp_yield <= 1'b0;
      end
      else begin
        skp_yield <= skp_yield;
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
