// SPDX-FileCopyrightText: 2025-2026 Cologne Chip AG
//
// SPDX-License-Identifier: BSD-3-Clause

// Refined in the NLnet-funded openCologne-PCIE project,
// executed by Chili.CHIPS and Intergalaktik doo

//----------------------------------------------------------------------------------
// Description: This is a generic clock counter module
// - Count up at each clock cycle until reaching a target count value
// - Reset enabled zeros out the count
// - Flag output is set when the target count value is reached and hold until reset
//==================================================================================

module ccfpga_clk_counter #(
    parameter int BIT_WIDTH = 21  // Width of Count Register
) (
    input  logic                 i_clk,
    input  logic                 i_reset,      // Asynchronous Reset
    input  logic [BIT_WIDTH-1:0] i_max_count,  // Max Count
    output logic                 o_flag        // Output Flag when Count reaches max count
);

  logic [BIT_WIDTH-1:0] s_count;

  always_ff @(posedge i_clk, posedge i_reset) begin
    if (i_reset == 1'b1) begin
      o_flag  <= 1'b0;
      s_count <= {BIT_WIDTH{1'b0}};
    end
    else begin
      if (s_count >= i_max_count - 1) begin
        o_flag <= 1'b1;
      end
      else begin
        o_flag  <= 1'b0;
        s_count <= s_count + 1'b1;
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
