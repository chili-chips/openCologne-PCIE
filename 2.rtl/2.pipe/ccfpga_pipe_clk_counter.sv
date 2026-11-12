// SPDX-FileCopyrightText: 2025-2026 Cologne Chip AG
//
// SPDX-License-Identifier: BSD-3-Clause

// Refined in the NLnet-funded openCologne-PCIE project,
// executed by Chili.CHIPS and Intergalaktik doo

////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Interessengruppe fuer Mikroelektronik und Eingebettete Systeme (IMES)
// Fachhochschule Dortmund
//
// Development in cooperation with Cologne Chip AG
//
// Filename     : ccfpga_pipe_clk_counter.sv
// Author       : Philipp Leduc
// Tool         :
// Description  : Simple parametized Clock Counter to implement the wait time between SerDes Byte
//                Lock and RxDataValid on PIPE Interface.
// Commentary   : Always check if CLK_NUMB matches necessary BIT_WIDTH.
// Abreviations : [i_] > input (port)
//                [o_] > output (port)
//                [s_] > signal
//                [_n] > low active
//
//
// Changelog:
// -------------------------------------------------------------------------------------------------
// Version | Author             | Date       | Changes
// -------------------------------------------------------------------------------------------------
// 1.0     | Leduc              | 05.06.2021 | released
// -------------------------------------------------------------------------------------------------
////////////////////////////////////////////////////////////////////////////////////////////////////

module ccfpga_pipe_clk_counter #(
    parameter int BIT_WIDTH = 4,  // Width of Count Register
    parameter int CLK_NUMB  = 10  // Target Count Value to set Flag
) (
    input  logic i_clk,
    input  logic i_reset,  // Asynchronous Reset
    output logic o_flag
);

  logic [BIT_WIDTH-1:0] s_count;

  always_ff @(posedge i_clk, posedge i_reset) begin
    if (i_reset == 1'b1) begin
      o_flag  <= 1'b0;
      s_count <= {BIT_WIDTH{1'b0}};
    end
    else begin
      if (s_count >= BIT_WIDTH'(CLK_NUMB - 1)) begin
        o_flag <= 1'b1;
        // s_count <= {BIT_WIDTH{1'b0}};
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
