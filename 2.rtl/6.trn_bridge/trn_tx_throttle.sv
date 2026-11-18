// SPDX-FileCopyrightText: 2026 Chili.CHIPS
//
// SPDX-License-Identifier: BSD-3-Clause

//==========================================================================
// openPCIE * NLnet-sponsored open-source implementation
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
//--------------------------------------------------------------------------

module trn_tx_throttle
  import trn_pkg::*;
(
    input  logic  s_axis_tx_tvalid,  // the SOC's AXIS TX handshake
    input  logic  s_axis_tx_tlast,
    output logic  s_axis_tx_tready,  // low while paused
    trn_tx_if.src trn_tx,            // rdy, free_words

    input  logic  clk,
    input  logic  core_rst_n
);

  // pause between TLPs while a largest TLP might not fit: TRN_TLP_MAX_BEATS,
  // and the beats of the TLP before that are still on their way to the TX
  // buffer (s_axis_tx, trn_tx's beat register, the TL's write: 2, and 2 more
  // of margin)
  localparam trn_words_t FREE_MIN = trn_words_t'(TRN_TLP_MAX_BEATS + 4);

  logic rdy_pause;

  logic free_low_pause;
  logic free_low_trig;

  logic any_trig;
  logic any_pause;

  logic tready_mux;

  typedef enum logic {
    IDLE  = 1'd0,
    PAUSE = 1'd1
  } state_e;
  state_e cur_state;
  state_e next_state;

  logic   axi_pkt_started;
  logic   axi_busy;
  logic   axi_pkt_ending;
  logic   axi_paused;
  logic   axi_pause_ok;

  // out of reset, wait for the TL's first rdy
  always_ff @(posedge clk or negedge core_rst_n) begin
    if (!core_rst_n) begin
      rdy_pause <= 1'b1;
    end
    else begin
      if (trn_tx.rdy) begin
        rdy_pause <= 1'b0;
      end
    end
  end

  assign free_low_trig = (trn_tx.free_words < FREE_MIN);

  always_ff @(posedge clk or negedge core_rst_n) begin
    if (!core_rst_n) begin
      free_low_pause <= 1'b0;
    end
    else begin
      free_low_pause <= free_low_trig;
    end
  end

  always_ff @(posedge clk or negedge core_rst_n) begin
    if (!core_rst_n) begin
      axi_pkt_started <= 1'b0;
    end
    else begin
      if (s_axis_tx_tvalid && s_axis_tx_tlast) begin
        axi_pkt_started <= 1'b0;
      end
      else if (s_axis_tx_tready && s_axis_tx_tvalid) begin
        axi_pkt_started <= 1'b1;
      end
    end
  end

  assign axi_busy       = s_axis_tx_tvalid | axi_pkt_started;
  assign axi_pkt_ending = s_axis_tx_tvalid & s_axis_tx_tlast;
  assign axi_paused     = ~s_axis_tx_tready;
  assign axi_pause_ok   = ~axi_busy | axi_pkt_ending | axi_paused;

  assign any_trig       = free_low_trig;

  assign any_pause      = free_low_pause | rdy_pause;

  always_comb begin
    tready_mux = 1'b0;
    next_state = PAUSE;
    unique case (cur_state)
      IDLE: begin
        if (any_pause && axi_pause_ok) begin
          tready_mux = 1'b0;
          next_state = PAUSE;
        end
        else begin
          tready_mux = !(axi_pause_ok & any_trig);
          next_state = IDLE;
        end
      end

      PAUSE: begin
        if (!any_pause) begin
          tready_mux = !any_trig;
          next_state = IDLE;
        end
        else begin
          tready_mux = 1'b0;
          next_state = PAUSE;
        end
      end
      default: ;
    endcase
  end

  always_ff @(posedge clk or negedge core_rst_n) begin
    if (!core_rst_n) begin
      cur_state        <= PAUSE;

      s_axis_tx_tready <= 1'b0;
    end
    else begin
      cur_state        <= next_state;

      s_axis_tx_tready <= tready_mux;
    end
  end

endmodule
// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        May 24, 2024
// -----------------------------------------------------------------------------
