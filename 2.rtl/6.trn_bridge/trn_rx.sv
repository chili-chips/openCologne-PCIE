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

module trn_rx
  import axis_pkg::*;
  import trn_pkg::*;
(
    axis_if.master m_axis_rx,
    trn_rx_if.dst  trn_rx,     // TLPs from the TL

    input  logic   clk,
    input  logic   core_rst_n
);

  logic     rx_tlast;

  trn_dat_t rx_dat_swapped;
  trn_dat_t rx_dat_prev;

  logic     data_hold;
  logic     data_prev;

  logic     rx_eof_prev;
  logic     rx_vld_prev;

  // a TLP always starts whole: DL_Down resets the TL RX and trn_rx on the
  // same edge, and the TL holds a TLP at its first beat until rdy

  always_ff @(posedge clk or negedge core_rst_n) begin
    if (!core_rst_n) begin
      rx_dat_prev <= '0;
      rx_vld_prev <= 1'b0;
      rx_eof_prev <= 1'b0;
    end
    else begin
      if (trn_rx.rdy) begin
        rx_dat_prev <= rx_dat_swapped;
        rx_vld_prev <= trn_rx.vld;
        rx_eof_prev <= trn_rx.eof;
      end
    end
  end

  assign rx_dat_swapped = trn_dw_swap(trn_rx.dat);

  always_ff @(posedge clk or negedge core_rst_n) begin
    if (!core_rst_n) begin
      m_axis_rx.tdata <= {TRN_DATA_W{1'b0}};
    end
    else begin
      if (!data_hold) begin
        if (data_prev) begin
          m_axis_rx.tdata <= rx_dat_prev;
        end
        else begin
          m_axis_rx.tdata <= rx_dat_swapped;
        end
      end
    end
  end

  assign data_hold = (!m_axis_rx.tready & m_axis_rx.tvalid);

  always_ff @(posedge clk or negedge core_rst_n) begin
    if (!core_rst_n) begin
      data_prev <= 1'b0;
    end
    else begin
      data_prev <= data_hold;
    end
  end

  always_ff @(posedge clk or negedge core_rst_n) begin
    if (!core_rst_n) begin
      m_axis_rx.tvalid <= 1'b0;
      rx_tlast         <= 1'b0;
    end
    else begin
      if (!data_hold) begin
        if (data_prev) begin
          m_axis_rx.tvalid <= rx_vld_prev;
          rx_tlast         <= rx_eof_prev;
        end
        else begin
          m_axis_rx.tvalid <= trn_rx.vld;
          rx_tlast         <= trn_rx.eof;
        end
      end
    end
  end

  assign m_axis_rx.tlast = rx_tlast;

  // the SOC reads tdata, tvalid and tlast only: no tkeep, and no tuser (BAR
  // hit, poisoned, ECRC error) from TRN RX
  assign m_axis_rx.tkeep = KEEP_ALL;
  assign m_axis_rx.tuser = '0;

  always_ff @(posedge clk or negedge core_rst_n) begin
    if (!core_rst_n) begin
      trn_rx.rdy <= 1'b0;
    end
    else begin
      if (m_axis_rx.tvalid) begin
        trn_rx.rdy <= m_axis_rx.tready;
      end
      else begin
        trn_rx.rdy <= 1'b1;
      end
    end
  end

endmodule
// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        May 24, 2024
// -----------------------------------------------------------------------------
