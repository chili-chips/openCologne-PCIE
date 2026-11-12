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
// Filename     : ccfpga_pipe_rx_mux.sv
// Author       : Philipp Leduc
// Tool         :
// Description  : Used in PIPE Logic to mux Rx SerDes (64-Bit) to Rx PIPE (8-, 16-, 32-, 64-Bit).
//                Also includes Control Symbols (K Data) and Error Detection Logic (e.g. RxStatus).
//                Module also contains the additional Control Support Signals (CSS).
//                RX SERDES ---> MUX ---> RX PIPE
// Commentary   : DATA_BYTES (pipe_pkg) is the Rx PIPE width. Reset is asynchronous.
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
// 1.01    | Leduc              | 01.08.2021 | changed reset values for s_msb and s_msb_k
// -------------------------------------------------------------------------------------------------
////////////////////////////////////////////////////////////////////////////////////////////////////

module ccfpga_pipe_rx_mux
  import pipe_pkg::*;
(
    input logic i_clk,
    input logic i_reset,
    input logic i_enable,

    input serdes_rx_t i_rx,  // SerDes: symbols and their flags

    output pipe_data_t  o_data,      // PIPE: data
    output pipe_flags_t o_kcode,     // PIPE: K symbol
    output pipe_flags_t o_comma,     // PIPE: comma symbol
    output pipe_flags_t o_disp_err,  // PIPE: disparity error
    output pipe_flags_t o_dec_err,   // PIPE: 8b/10b decode error
    output rx_status_e  o_status     // PIPE: RxStatus
);

  // the slice this PCLK takes
  pipe_data_t  sel_data;
  pipe_flags_t sel_kcode;
  pipe_flags_t sel_comma;
  pipe_flags_t sel_disp_err;
  pipe_flags_t sel_dec_err;

  pipe_data_t  s_data;
  logic        s_disp_err_flag;
  logic        s_dec_err_flag;

  assign s_disp_err_flag = |o_disp_err;
  assign s_dec_err_flag  = |o_dec_err;

  generate
    if (SERDES_SLICES == 1) begin : g_one_slice
      assign sel_data     = i_rx.data[0];
      assign sel_kcode    = i_rx.kcode[0];
      assign sel_comma    = i_rx.comma[0];
      assign sel_disp_err = i_rx.disp_err[0];
      assign sel_dec_err  = i_rx.dec_err[0];
    end
    else begin : g_slices
      logic [$clog2(SERDES_SLICES)-1:0] phase;

      always_ff @(posedge i_clk, posedge i_reset) begin
        if (i_reset == 1'b1) begin
          phase <= '0;
        end
        else if (i_enable == 1'b1) begin
          phase <= phase + 1'b1;
        end
      end

      assign sel_data     = i_rx.data[phase];
      assign sel_kcode    = i_rx.kcode[phase];
      assign sel_comma    = i_rx.comma[phase];
      assign sel_disp_err = i_rx.disp_err[phase];
      assign sel_dec_err  = i_rx.dec_err[phase];
    end
  endgenerate

  always_ff @(posedge i_clk, posedge i_reset) begin
    if (i_reset == 1'b1) begin
      s_data     <= '0;
      o_kcode    <= '0;
      o_comma    <= '0;
      o_disp_err <= '0;
      o_dec_err  <= '0;
    end
    else if (i_enable == 1'b1) begin
      s_data     <= sel_data;
      o_kcode    <= sel_kcode;
      o_comma    <= sel_comma;
      o_disp_err <= sel_disp_err;
      o_dec_err  <= sel_dec_err;
    end
  end

  // RxStatus: a decode error wins over a disparity error
  always_comb begin
    if (s_dec_err_flag == 1'b1) begin
      o_status = DECODE_ERR;
    end
    else if (s_disp_err_flag == 1'b1) begin
      o_status = DISP_ERR;
    end
    else begin
      o_status = RX_OK;
    end
  end

  // a symbol that decoded wrong becomes EDB
  for (genvar i = 0; i < DATA_BYTES; i++) begin : g_edb
    assign o_data[i*8+:8] = o_dec_err[i] ? K_EDB : s_data[i*8+:8];
  end

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Nov 3, 2026
// -----------------------------------------------------------------------------
