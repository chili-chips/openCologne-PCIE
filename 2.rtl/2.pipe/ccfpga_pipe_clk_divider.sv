// SPDX-FileCopyrightText: 2025-2026 Cologne Chip AG
//
// SPDX-License-Identifier: BSD-3-Clause

// Refined in the NLnet-funded openCologne-PCIE project,
// executed by Chili.CHIPS and Intergalaktik doo

// Clock divider module for CCFPGA
module ccfpga_pipe_clk_divider #(
    parameter int DIVIDER = 2
) (
    input  logic i_clk,    // Input clock
    input  logic i_reset,  // Active high reset
    output logic o_clk     // Divided output clock
);
  generate
    if (DIVIDER == 2) begin : g_div2
      always_ff @(posedge i_clk or posedge i_reset) begin
        if (i_reset) begin
          o_clk <= 1'b0;  // Reset output clock to 0
        end
        else begin
          o_clk <= ~o_clk;  // Toggle output clock every cycle
        end
      end
    end
    else begin : g_div_n
      localparam int COUNTER_WIDTH = $clog2(DIVIDER) - 1;
      logic [COUNTER_WIDTH-1:0] counter;  // Counter for division

      // Always block triggered on the rising edge of i_clk or reset
      always_ff @(posedge i_clk or posedge i_reset) begin
        if (i_reset) begin
          counter <= {COUNTER_WIDTH{1'b0}};  // Reset counter to 0
          o_clk   <= 1'b0;  // Reset output clock to 0
        end
        else begin
          if (counter == {COUNTER_WIDTH{1'b1}}) begin
            o_clk <= ~o_clk;  // Toggle output clock every 2 cycles
          end
          counter <= counter + 1;  // Increment counter
        end
      end
    end
  endgenerate

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Nov 3, 2026
// -----------------------------------------------------------------------------
