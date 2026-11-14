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
// Filename     : ccfpga_pipe_tx_demux.sv
// Author       : Philipp Leduc
// Tool         :
// Description  : Demuxes Tx PIPE (8-, 16-, 32-, 64-Bit) across TX SerDes (64-Bit).
//                Also includes Control Symbols (K Data) and Compliance (running disparity).
//                TX PIPE ---> DEMUX ---> TX SERDES
// Commentary   : DATA_BYTES (pipe_pkg) is the Tx PIPE width.
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

module ccfpga_pipe_tx_demux
  import pipe_pkg::*;
(
    input  logic        i_clk,
    input  logic        i_reset,
    input  logic        i_enable,

    input  pipe_data_t  i_data,        // PIPE: data
    input  pipe_flags_t i_kcode,       // PIPE: K symbol
    input  pipe_flags_t i_compliance,  // PIPE: compliance, negative disparity

    output serdes_tx_t  o_tx           // SerDes: symbols, K flags, disparity mode
);

  // The PIPE fills the SerDes word one slice per PCLK, lowest first
  generate
    if (SERDES_SLICES == 1) begin : g_one_slice
      always_ff @(posedge i_clk, posedge i_reset) begin
        if (i_reset == 1'b1) begin
          o_tx <= '0;
        end
        else if (i_enable == 1'b1) begin
          o_tx.data[0]     <= i_data;
          o_tx.kcode[0]    <= i_kcode;
          o_tx.dispmode[0] <= i_compliance;
        end
      end
    end
    else begin : g_slices
      logic [$clog2(SERDES_SLICES)-1:0] phase;  // the slice this PCLK fills

      always_ff @(posedge i_clk, posedge i_reset) begin
        if (i_reset == 1'b1) begin
          phase <= '0;
          o_tx  <= '0;
        end
        else if (i_enable == 1'b1) begin
          phase                <= phase + 1'b1;
          o_tx.data[phase]     <= i_data;
          o_tx.kcode[phase]    <= i_kcode;
          o_tx.dispmode[phase] <= i_compliance;
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
