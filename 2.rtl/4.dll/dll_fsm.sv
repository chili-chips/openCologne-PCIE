// SPDX-FileCopyrightText: 2026 Chili.CHIPS
//
// SPDX-License-Identifier: BSD-3-Clause

//==========================================================================
// openCologne-PCIE * NLnet-sponsored open-source implementation
//--------------------------------------------------------------------------
//                   Copyright (C) 2026 Chili.CHIPS
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions
// are met:
//
// 1. Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright
// notice, this list of conditions and the following disclaimer in the
// documentation and/or other materials provided with the distribution.
//
// 3. Neither the name of the copyright holder nor the names of its
// contributors may be used to endorse or promote products derived
// from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
// IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
// TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
// PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
//              https://opensource.org/license/bsd-3-clause
//==========================================================================

module dll_fsm
  import pipe_pkg::*;
  import dll_pkg::*;
(
    input logic reset,              // Asynchronous Reset
    input logic i_clk,              // Parallel Interface Clock
    input logic i_link_up,          // Link Up Status
    input logic i_initfc1_rx_done,  // Receive InitFC1 for all 3 types
    input logic i_initfc1_tx_done,  // Transmit InitFC1 for all 3 types
    input logic i_initfc2_rx_done,  // Receive InitFC2 for all 3 types
    input logic i_initfc2_tx_done,  // Transmit InitFC2 for all 3 types

    output logic      o_initfc1_en,  // Enable InitFC1 Transmission
    output logic      o_initfc2_en,  // Enable InitFC2 Transmission
    output dl_state_e o_fsm_state    // Current FSM State
);

  logic s_initfc1_sent;
  logic s_initfc2_sent;
  logic initfc1_tx_done;
  assign initfc1_tx_done = s_initfc1_sent | i_initfc1_tx_done;
  logic initfc2_tx_done;
  assign initfc2_tx_done = s_initfc2_sent | i_initfc2_tx_done;

  dl_state_e s_state, s_next_state;

  assign o_fsm_state = s_state;

  //State Register
  always_ff @(posedge i_clk, posedge reset) begin
    if (reset) begin
      s_state <= DL_INACTIVE;
    end
    else begin
      s_state <= s_next_state;
    end
  end

  always_ff @(posedge i_clk, posedge reset) begin
    if (reset) begin
      s_initfc1_sent <= 1'b0;
      s_initfc2_sent <= 1'b0;
    end
    else begin
      if (s_state != DL_INITFC1) begin
        s_initfc1_sent <= 1'b0;
      end
      else if (i_initfc1_tx_done == 1'b1) begin
        s_initfc1_sent <= 1'b1;
      end

      if (s_state != DL_INITFC2) begin
        s_initfc2_sent <= 1'b0;
      end
      else if (i_initfc2_tx_done == 1'b1) begin
        s_initfc2_sent <= 1'b1;
      end
    end
  end

  //Transition logic
  always_comb begin
    s_next_state = s_state;
    unique case (s_state)
      DL_INACTIVE: begin
        if (i_link_up == 1'b1) begin
          s_next_state = DL_INITFC1;
        end
        else begin
          s_next_state = DL_INACTIVE;
        end
      end
      DL_INITFC1: begin
        if (i_initfc1_rx_done == 1'b1 && initfc1_tx_done == 1'b1) begin
          s_next_state = DL_INITFC2;
        end
        else if (i_link_up == 1'b0) begin
          s_next_state = DL_INACTIVE;
        end
        else begin
          s_next_state = DL_INITFC1;
        end
      end
      DL_INITFC2: begin
        if (i_initfc2_rx_done == 1'b1 && initfc2_tx_done == 1'b1) begin
          s_next_state = DL_ACTIVE;
        end
        else if (i_link_up == 1'b0) begin
          s_next_state = DL_INACTIVE;
        end
        else begin
          s_next_state = DL_INITFC2;
        end
      end
      DL_ACTIVE: begin
        if (i_link_up == 1'b0) begin
          s_next_state = DL_INACTIVE;
        end
        else begin
          s_next_state = DL_ACTIVE;
        end
      end
      default: ;
    endcase
  end

  // Output logic
  always_comb begin
    o_initfc1_en = 1'b0;
    o_initfc2_en = 1'b0;
    unique case (s_state)
      DL_INACTIVE: begin
        o_initfc1_en = 1'b0;
        o_initfc2_en = 1'b0;
      end
      DL_INITFC1: begin
        o_initfc1_en = 1'b1;
        o_initfc2_en = 1'b0;
      end
      DL_INITFC2: begin
        o_initfc1_en = 1'b0;
        o_initfc2_en = 1'b1;
      end
      DL_ACTIVE: begin
        o_initfc1_en = 1'b0;
        o_initfc2_en = 1'b0;
      end
      default: ;
    endcase
  end

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Jan 10, 2026
// -----------------------------------------------------------------------------
