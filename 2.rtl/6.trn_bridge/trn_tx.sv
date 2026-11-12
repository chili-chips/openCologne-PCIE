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

module trn_tx
  import trn_pkg::*;
(
    axis_if.slave s_axis_tx,
    trn_tx_if.src trn_tx,     // TLPs to the TL

    input logic clk,
    input logic core_rst_n
);


  logic [TRN_DATA_W-1:0] beat_tdata;
  logic                  beat_tvalid;
  logic                  beat_tlast;

  logic                  trn_pkt_started;
  logic                  beat_rdy;

  logic                  axi_beat_live;
  assign axi_beat_live = s_axis_tx.tvalid & s_axis_tx.tready;

  assign trn_tx.dat    = trn_dw_swap(beat_tdata);

  assign trn_tx.sof    = beat_tvalid & !trn_pkt_started;

  always_ff @(posedge clk or negedge core_rst_n) begin
    if (!core_rst_n) begin
      trn_pkt_started <= 1'b0;
    end
    else begin
      if (trn_tx.sof && trn_tx.vld && trn_tx.rdy && !trn_tx.eof) begin
        trn_pkt_started <= 1'b1;
      end
      else if (trn_pkt_started && trn_tx.eof && trn_tx.vld) begin
        trn_pkt_started <= 1'b0;
      end
    end
  end

  assign trn_tx.eof = beat_tlast;

  // s_axis_tx.tkeep and tuser are not read: the TL takes the length from
  // the header and supports no TX qualifier (see trn_compat)
  always_ff @(posedge clk or negedge core_rst_n) begin
    if (!core_rst_n) begin
      beat_tdata  <= {TRN_DATA_W{1'b0}};
      beat_tvalid <= 1'b0;
      beat_tlast  <= 1'b0;
      beat_rdy    <= 1'b0;
    end
    else begin
      beat_tdata  <= s_axis_tx.tdata;
      beat_tvalid <= s_axis_tx.tvalid;
      beat_tlast  <= s_axis_tx.tlast;
      beat_rdy    <= axi_beat_live;
    end
  end

  assign trn_tx.vld = beat_rdy;

endmodule
// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        May 24, 2024
// -----------------------------------------------------------------------------
