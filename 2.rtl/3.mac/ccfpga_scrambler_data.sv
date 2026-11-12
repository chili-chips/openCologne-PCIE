// SPDX-FileCopyrightText: 2025-2026 Cologne Chip AG
//
// SPDX-License-Identifier: BSD-3-Clause

// Refined in the NLnet-funded openCologne-PCIE project,
// executed by Chili.CHIPS and Intergalaktik doo

//----------------------------------------------------------------------------------------
// Description: This module calculates the scrambled data
//========================================================================================

module ccfpga_scrambler_data
  import pipe_pkg::*;
(
    input  logic [DATA_WIDTH - 1 : 0] i_data_in,
    input  logic [DATA_BYTES - 1 : 0] i_data_in_kcode,
    input  logic [DATA_BYTES - 1 : 0] i_sym_is_ts,
    input  logic                      i_scrambler_en,
    input  logic [DATA_WIDTH - 1 : 0] i_lfsr_value,
    output logic [DATA_WIDTH - 1 : 0] o_data_out
);

  logic [DATA_WIDTH-1:0] scrambled_data;
  logic [DATA_BYTES-1:0] scrambler_enabled;

  genvar i;
  generate
    for (i = 0; i < DATA_BYTES; i = i + 1) begin : g_data_scramble
      // Scramble if not a character in training sequence or K character
      // and scrambler is enabled
      assign scrambler_enabled[i] = ~(i_sym_is_ts[i] | i_data_in_kcode[i] | ~(i_scrambler_en));
      // Scrambling with XOR operation
      assign scrambled_data[8*i +: 8] = i_data_in[8*i +: 8]
                                      ^ (i_lfsr_value[8*i +: 8] & {8{scrambler_enabled[i]}});
    end
  endgenerate

  assign o_data_out = scrambled_data;
endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Nov 3, 2026
// -----------------------------------------------------------------------------
