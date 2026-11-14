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
// Filename     : ccfpga_pipe_fsm_word_align.sv
// Author       : Philipp Leduc
// Tool         :
// Description  : FSM to implement Word Aligment and generate RxValid.
// Commentary   :
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

module ccfpga_pipe_fsm_word_align
  import pipe_pkg::*;
(
    input  logic         i_clk,
    input  logic         i_reset,
    input  logic         i_enable,

    output align_state_e o_fsm_state,          // fsm status (CSS)
    output logic         o_rx_valid,

    output logic         o_cnt_reset,          // Reset Clock Counter
    input  logic         i_cnt_flag,           // Flag for Count Indication

    output logic         o_mcomma_align,       // Byte Lock negative disparity
    output logic         o_pcomma_align,       // Byte Lock positive disparity
    input  logic         i_rx_byte_is_aligned  // Byte lock established
);


  align_state_e s_state, s_next_state;

  logic s_set_rx_valid;
  logic s_rx_valid;

  assign o_fsm_state = s_state;

  // State Register
  always_ff @(posedge i_clk, posedge i_reset) begin
    if (i_reset == 1'b1) begin
      s_state <= WA_WAIT;
    end
    else begin
      s_state <= s_next_state;
    end
  end

  // Transition Logic
  always_comb begin
    s_next_state = s_state;
    unique case (s_state)
      WA_WAIT: begin
        if (i_enable == 1'b1 && i_rx_byte_is_aligned == 1'b0) begin
          s_next_state = WA_ALIGN_START;
        end
        else begin
          s_next_state = WA_WAIT;
        end
      end
      WA_ALIGN_START: begin
        if (i_rx_byte_is_aligned == 1'b1) begin
          s_next_state = WA_COUNT_START;
        end
        else begin
          s_next_state = WA_ALIGN_START;
        end
      end
      WA_COUNT_START: begin
        if (i_cnt_flag == 1'b1) begin
          s_next_state = WA_RX_VALID;
        end
        else begin
          s_next_state = WA_COUNT_START;
        end
      end
      WA_RX_VALID: begin
        s_next_state = WA_WAIT;
      end
      default: ;
    endcase
  end

  // Output Logic
  always_comb begin
    o_cnt_reset    = 1'b1;
    o_mcomma_align = 1'b0;
    o_pcomma_align = 1'b0;
    s_rx_valid     = 1'b0;
    s_set_rx_valid = 1'b0;
    unique case (s_state)
      WA_WAIT: begin
        // NONE
      end
      WA_ALIGN_START: begin
        s_set_rx_valid = 1'b1;
        o_mcomma_align = 1'b1;
        o_pcomma_align = 1'b1;
      end
      WA_COUNT_START: begin
        o_cnt_reset = 1'b0;
      end
      WA_RX_VALID: begin
        s_rx_valid     = 1'b1;
        s_set_rx_valid = 1'b1;
      end
      default: ;
    endcase
  end

  // DFF Rx Valid
  always_ff @(posedge i_clk, posedge i_reset) begin
    if (i_reset == 1'b1) begin
      o_rx_valid <= 1'b0;
    end
    else if (s_set_rx_valid == 1'b1) begin
      o_rx_valid <= s_rx_valid;
    end
  end

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Nov 3, 2026
// -----------------------------------------------------------------------------
