// SPDX-FileCopyrightText: 2025-2026 Cologne Chip AG
//
// SPDX-License-Identifier: BSD-3-Clause

// Refined in the NLnet-funded openCologne-PCIE project,
// executed by Chili.CHIPS and Intergalaktik doo

//------------------------------------------------------------------------------
// Description: This module generates SKP OS for compensating the clock mismatch
// - SKP OS needs to be sent between 1180 to 1538 symbol times
//==============================================================================

module ccfpga_SKP_generator
  import pipe_pkg::*;
  import mac_pkg::*;
#(
    parameter int SKP_WIDTH = 32
) (
    input  logic      i_clk,
    input  logic      i_reset,
    input  logic      i_sending_data,
    input  logic      i_sending_os,
    input  logic      i_sending_idle,

    output pipe_sym_t o_tx_sym,
    output logic      o_skp_in_queue,
    output logic      o_sending_skp
);

  localparam int COUNT_MAX = (SKP_INTERVAL - 1) / DATA_BYTES + 1;
  localparam int COUNT_WIDTH = $clog2(COUNT_MAX) + 1;
  localparam logic [COUNT_WIDTH-1:0] COUNT_MIN = COUNT_WIDTH'(COUNT_MAX);
  localparam logic [3:0] SKP_PER_WORD = 4'(DATA_WIDTH / SKP_WIDTH);  // SKP OSs in one word

  logic [            3:0] number_of_queued_skp;
  logic [COUNT_WIDTH-1:0] s_count;

  logic                   skp_count_inc;
  logic                   skp_send_enable;

  logic [ 31:0] skp_os;
  assign        skp_os = {K_SKP, K_SKP, K_SKP, K_COM};  // SKP Ordered Set

  always_ff @(posedge i_clk or posedge i_reset) begin
    if (i_reset) begin
      s_count <= {COUNT_WIDTH{1'b0}};
    end
    else begin
      if (s_count == COUNT_MIN) begin
        s_count <= 0;
      end
      else begin
        s_count <= s_count + 1'b1;
      end
    end
  end

  generate
    if (DATA_WIDTH == 64) begin : g_64
      always_ff @(posedge i_clk or posedge i_reset) begin
        if (i_reset) begin
          o_tx_sym             <= '0;
          o_sending_skp        <= 1'b0;
          number_of_queued_skp <= 4'b0;
        end
        else if (skp_send_enable) begin
          if (number_of_queued_skp >= SKP_PER_WORD) begin
            // Send 2 SKP OSs at once if more than 1 are queued
            // Subtract only 1 SKP from the queue as one is added
            o_tx_sym.data  <= {skp_os, skp_os};
            o_tx_sym.kcode <= {DATA_BYTES{1'b1}};
            o_sending_skp  <= 1'b1;
            if (skp_count_inc) begin
              number_of_queued_skp <= number_of_queued_skp - 1'b1;
            end
            else begin
              number_of_queued_skp <= number_of_queued_skp - SKP_PER_WORD;
            end
          end
          else if (number_of_queued_skp == 1) begin
            // Send 2 SKP OSs at once if one SKP is queued and one is added
            if (skp_count_inc) begin
              o_tx_sym.data  <= {skp_os, skp_os};
              o_tx_sym.kcode <= {DATA_BYTES{1'b1}};
            end
            else begin
              o_tx_sym.data  <= {32'h00000000, skp_os};
              o_tx_sym.kcode <= 8'b00001111;
            end
            o_sending_skp        <= 1'b1;
            number_of_queued_skp <= 4'b0;
          end
          else if (number_of_queued_skp == 0 && skp_count_inc) begin
            // Send 1 SKP OS with IDLE data
            o_tx_sym.data        <= {32'h00000000, skp_os};
            o_tx_sym.kcode       <= 8'b00001111;
            o_sending_skp        <= 1'b1;
            number_of_queued_skp <= 4'b0;
          end
          else begin
            // No SKP OS to send
            o_tx_sym             <= '0;
            o_sending_skp        <= 1'b0;
            number_of_queued_skp <= 4'b0;
          end
        end
        else if (skp_count_inc) begin
          o_tx_sym             <= '0;
          o_sending_skp        <= 1'b0;
          number_of_queued_skp <= number_of_queued_skp + 1'b1;
        end
        else begin
          o_tx_sym             <= '0;
          o_sending_skp        <= 1'b0;
          number_of_queued_skp <= number_of_queued_skp;
        end
      end
    end
    else begin : g_narrow
      localparam int NUMBER_OF_STEP = SKP_WIDTH / DATA_WIDTH;
      logic [$clog2(NUMBER_OF_STEP):0] step_count;

      always_ff @(posedge i_clk or posedge i_reset) begin
        if (i_reset) begin
          o_tx_sym             <= '0;
          o_sending_skp        <= 1'b0;
          number_of_queued_skp <= 4'b0;
          step_count           <= 0;
        end
        else if (skp_send_enable) begin
          if (step_count < (NUMBER_OF_STEP - 1)) begin
            o_tx_sym.data  <= skp_os[step_count*DATA_WIDTH+:DATA_WIDTH];
            o_tx_sym.kcode <= {DATA_BYTES{1'b1}};
            o_sending_skp  <= 1'b1;
            if (skp_count_inc) begin
              number_of_queued_skp <= number_of_queued_skp + 1'b1;
            end
            else begin
              number_of_queued_skp <= number_of_queued_skp;
            end
            step_count <= step_count + 1'b1;
          end
          else if (step_count == (NUMBER_OF_STEP - 1)) begin
            o_tx_sym.data  <= skp_os[step_count*DATA_WIDTH+:DATA_WIDTH];
            o_tx_sym.kcode <= {DATA_BYTES{1'b1}};
            o_sending_skp  <= 1'b1;
            if (skp_count_inc) begin
              number_of_queued_skp <= number_of_queued_skp;
            end
            else begin
              number_of_queued_skp <= number_of_queued_skp - 1'b1;
            end
            step_count <= 0;
          end
        end
        else begin
          o_tx_sym             <= '0;
          o_sending_skp        <= 1'b0;
          number_of_queued_skp <= number_of_queued_skp;
          step_count           <= 0;
        end
      end
    end
  endgenerate

  assign skp_count_inc = s_count == COUNT_MIN;
  assign skp_send_enable = ((number_of_queued_skp != 4'b0) | skp_count_inc)
                         & !i_sending_data
                         & !i_sending_os
                         & !i_sending_idle;
  assign o_skp_in_queue = (number_of_queued_skp != 4'b0);

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Nov 3, 2026
// -----------------------------------------------------------------------------
