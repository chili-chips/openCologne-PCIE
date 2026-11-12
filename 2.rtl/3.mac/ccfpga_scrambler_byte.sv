// SPDX-FileCopyrightText: 2025-2026 Cologne Chip AG
//
// SPDX-License-Identifier: BSD-3-Clause

// Refined in the NLnet-funded openCologne-PCIE project,
// executed by Chili.CHIPS and Intergalaktik doo

//----------------------------------------------------------------------------------------
// Description: This module calculates and advances the LFSR for scrambler operation
//========================================================================================

module ccfpga_scrambler_byte
  import pipe_pkg::*;
  import mac_pkg::*;
(
    input  logic [ 7:0] i_data_in,
    input  logic        i_data_in_kcode,
    input  logic        i_scrambler_en,
    input  logic [15:0] i_lfsr_in,
    output logic [15:0] o_lfsr_out,
    output logic [ 7:0] o_data_out
);

  logic [7:0] data_c;


  always_comb begin
    data_c = 8'h00;  // used only where the LFSR advances: no latch
    if (i_data_in == K_COM && i_data_in_kcode) begin  // Initialize LFSR on COM
      o_lfsr_out = SCRAMBLER_SEED;
    end
    // no advancement of LFSR for SKP
    else if ((i_data_in == K_SKP && i_data_in_kcode) || !i_scrambler_en) begin
      o_lfsr_out = i_lfsr_in;
    end
    else begin  // Advance the LFSR one step per data bit, bit 0 first
      // (x^16 + x^5 + x^4 + x^3 + 1); its top bit is the scramble bit,
      // XORed with i_data_in in another block
      o_lfsr_out = i_lfsr_in;
      for (int i = 0; i < 8; i++) begin
        data_c[i]  = o_lfsr_out[15];
        o_lfsr_out = {o_lfsr_out[14:0], 1'b0} ^ (o_lfsr_out[15] ? SCRAMBLER_POLY : 16'h0000);
      end
    end
  end

  assign o_data_out = data_c;

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Nov 3, 2026
// -----------------------------------------------------------------------------
