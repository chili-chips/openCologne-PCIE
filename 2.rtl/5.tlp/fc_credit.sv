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

module fc_credit
  import tl_pkg::*;
  import dll_pkg::*;
(
    input  logic           clk,
    input  logic           rst_n,
    input  logic           rx_rst_n,
    input  logic           dl_inactive,
    input  fc_dllp_t       rx_dllp,
    output fc_tx_t   [2:0] tx_fc,
    input  fc_rel_t        consume,
    output fc_cred_t       p_alloc,
    output fc_cred_t       np_alloc,
    input  fc_rel_t        rel_a,
    input  fc_rel_t        rel_b,
    output fc_dllp_t       tx_dllp
);

  localparam logic P_FINITE  = (INIT_PH != 8'd0) | (INIT_PD != 12'd0);
  localparam logic NP_FINITE = (INIT_NPH != 8'd0) | (INIT_NPD != 12'd0);

  logic           fc_dllp;
  logic           fc_init;
  logic           fc_update;

  logic           rel_a_p;
  logic           rel_a_np;
  logic           rel_b_p;
  logic           rel_b_np;
  fc_cred_t       p_inc;
  fc_cred_t       np_inc;
  logic     [1:0] update_pending;
  logic           send_p;
  logic           send_np;

  assign fc_dllp = rx_dllp.valid
                 & (rx_dllp.packet_type != DLLP_OTHER)
                 & (rx_dllp.update_type != FC_RSVD);
  assign fc_init = (rx_dllp.packet_type == DLLP_INITFC1) | (rx_dllp.packet_type == DLLP_INITFC2);
  assign fc_update = (rx_dllp.packet_type == DLLP_UPDATEFC);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_fc <= '0;
    end
    else if (dl_inactive) begin
      tx_fc <= '0;
    end
    else begin
      if (fc_dllp && fc_init && !tx_fc[rx_dllp.update_type].init) begin
        tx_fc[rx_dllp.update_type].limit    <= rx_dllp.cred;
        tx_fc[rx_dllp.update_type].inf_hdr  <= (rx_dllp.cred.hdr == 8'd0);
        tx_fc[rx_dllp.update_type].inf_data <= (rx_dllp.cred.data == 12'd0);
        tx_fc[rx_dllp.update_type].init     <= 1'b1;
      end
      else if (fc_dllp && fc_update && tx_fc[rx_dllp.update_type].init) begin
        if (!tx_fc[rx_dllp.update_type].inf_hdr) begin
          tx_fc[rx_dllp.update_type].limit.hdr <= rx_dllp.cred.hdr;
        end
        if (!tx_fc[rx_dllp.update_type].inf_data) begin
          tx_fc[rx_dllp.update_type].limit.data <= rx_dllp.cred.data;
        end
      end
      if (consume.valid) begin
        tx_fc[consume.fc_class].consumed.hdr <= tx_fc[consume.fc_class].consumed.hdr + 8'd1;
        tx_fc[consume.fc_class].consumed.data <= tx_fc[consume.fc_class].consumed.data +
            consume.data;
      end
    end
  end

  assign rel_a_p     = rel_a.valid & (rel_a.fc_class == FC_P);
  assign rel_a_np    = rel_a.valid & (rel_a.fc_class == FC_NP);
  assign rel_b_p     = rel_b.valid & (rel_b.fc_class == FC_P);
  assign rel_b_np    = rel_b.valid & (rel_b.fc_class == FC_NP);

  assign p_inc.hdr   = {7'd0, rel_a_p} + {7'd0, rel_b_p};
  assign p_inc.data  = (rel_a_p ? rel_a.data : 12'd0) + (rel_b_p ? rel_b.data : 12'd0);
  assign np_inc.hdr  = {7'd0, rel_a_np} + {7'd0, rel_b_np};
  assign np_inc.data = (rel_a_np ? rel_a.data : 12'd0) + (rel_b_np ? rel_b.data : 12'd0);

  always_ff @(posedge clk or negedge rx_rst_n) begin
    if (!rx_rst_n) begin
      p_alloc.hdr   <= INIT_PH;
      p_alloc.data  <= INIT_PD;
      np_alloc.hdr  <= INIT_NPH;
      np_alloc.data <= INIT_NPD;
    end
    else begin
      if (INIT_PH != 8'd0) begin
        p_alloc.hdr <= p_alloc.hdr + p_inc.hdr;
      end
      if (INIT_PD != 12'd0) begin
        p_alloc.data <= p_alloc.data + p_inc.data;
      end
      if (INIT_NPH != 8'd0) begin
        np_alloc.hdr <= np_alloc.hdr + np_inc.hdr;
      end
      if (INIT_NPD != 12'd0) begin
        np_alloc.data <= np_alloc.data + np_inc.data;
      end
    end
  end

  assign send_p  = update_pending[0];
  assign send_np = !update_pending[0] & update_pending[1];

  always_ff @(posedge clk or negedge rx_rst_n) begin
    if (!rx_rst_n) begin
      update_pending      <= 2'b00;
      tx_dllp.valid       <= 1'b0;
      tx_dllp.packet_type <= DLLP_UPDATEFC;
      tx_dllp.update_type <= FC_P;
      tx_dllp.cred        <= '0;
    end
    else begin
      tx_dllp.valid <= 1'b0;
      if (send_p) begin
        tx_dllp.valid       <= 1'b1;
        tx_dllp.packet_type <= DLLP_UPDATEFC;
        tx_dllp.update_type <= FC_P;
        tx_dllp.cred.hdr    <= (INIT_PH == 8'd0) ? 8'd0 : p_alloc.hdr;
        tx_dllp.cred.data   <= (INIT_PD == 12'd0) ? 12'd0 : p_alloc.data;
      end
      else if (send_np) begin
        tx_dllp.valid       <= 1'b1;
        tx_dllp.packet_type <= DLLP_UPDATEFC;
        tx_dllp.update_type <= FC_NP;
        tx_dllp.cred.hdr    <= (INIT_NPH == 8'd0) ? 8'd0 : np_alloc.hdr;
        tx_dllp.cred.data   <= (INIT_NPD == 12'd0) ? 12'd0 : np_alloc.data;
      end
      update_pending[0] <= (update_pending[0] & !send_p) | (P_FINITE & (rel_a_p | rel_b_p));
      update_pending[1] <= (update_pending[1] & !send_np) | (NP_FINITE & (rel_a_np | rel_b_np));
    end
  end

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Oct 21, 2026
// -----------------------------------------------------------------------------
