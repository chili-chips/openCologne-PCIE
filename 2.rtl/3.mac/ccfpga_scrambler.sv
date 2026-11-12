// SPDX-FileCopyrightText: 2025-2026 Cologne Chip AG
//
// SPDX-License-Identifier: BSD-3-Clause

// Refined in the NLnet-funded openCologne-PCIE project,
// executed by Chili.CHIPS and Intergalaktik doo

//----------------------------------------------------------------------------------------
// Description: Top module for the parallel scrambler
// - LFSR with polynomial x^16 + x^5 + x^4 +x^3 +1
//========================================================================================

module ccfpga_scrambler
  import pipe_pkg::*;
  import mac_pkg::*;
(
    input logic                           i_clk,
    input logic                           i_reset,
    input logic                           i_scrambler_en,
    input pipe_sym_t                      i_sym_in,
    input logic      [DATA_BYTES - 1 : 0] i_sym_is_ts,

    output pipe_sym_t o_sym_out
);

  localparam int LFSR_WIDTH = 16;

  logic [           DATA_WIDTH - 1 : 0] scrambled_data;
  logic [           DATA_BYTES - 1 : 0] kcode_d;
  logic [                         15:0] first_lfsr;

  logic [           DATA_WIDTH - 1 : 0] scrambled_data_next;
  logic [                         15:0] first_lfsr_next;
  logic [LFSR_WIDTH*DATA_BYTES - 1 : 0] lfsr_vector;
  logic [LFSR_WIDTH*DATA_BYTES - 1 : 0] lfsr_out;
  logic [           DATA_WIDTH - 1 : 0] lfsr_value;

  always_ff @(posedge i_clk or posedge i_reset) begin
    if (i_reset) begin
      first_lfsr     <= SCRAMBLER_SEED;
      scrambled_data <= {DATA_WIDTH{1'b0}};
    end
    else begin
      first_lfsr     <= first_lfsr_next;
      scrambled_data <= scrambled_data_next;
    end
  end

  always_ff @(posedge i_clk or posedge i_reset) begin
    if (i_reset) begin
      kcode_d <= {DATA_BYTES{1'b0}};
    end
    else begin
      kcode_d <= i_sym_in.kcode;
    end
  end

  assign lfsr_vector = {lfsr_out[LFSR_WIDTH*(DATA_BYTES-1)-1 : 0], first_lfsr};

  // Generate scrambler_value for each byte
  genvar i;
  generate
    for (i = 0; i < DATA_BYTES; i = i + 1) begin : g_scrambler
      ccfpga_scrambler_byte u_scrambler_byte (
          .i_data_in      (i_sym_in.data[i*8+:8]),
          .i_data_in_kcode(i_sym_in.kcode[i]),
          .i_scrambler_en (i_scrambler_en),
          .i_lfsr_in      (lfsr_vector[i*LFSR_WIDTH+:LFSR_WIDTH]),
          .o_lfsr_out     (lfsr_out[i*LFSR_WIDTH+:LFSR_WIDTH]),
          .o_data_out     (lfsr_value[i*8+:8])
      );
    end
  endgenerate

  ccfpga_scrambler_data u_scrambler_data (
      .i_data_in      (i_sym_in.data),
      .i_data_in_kcode(i_sym_in.kcode),
      .i_sym_is_ts    (i_sym_is_ts),
      .i_scrambler_en (i_scrambler_en),
      .i_lfsr_value   (lfsr_value),
      .o_data_out     (scrambled_data_next)
  );

  assign o_sym_out.data  = scrambled_data;
  assign first_lfsr_next = lfsr_out[LFSR_WIDTH*DATA_BYTES-1-:LFSR_WIDTH];
  assign o_sym_out.kcode = kcode_d;

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Nov 3, 2026
// -----------------------------------------------------------------------------
