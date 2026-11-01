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
//--------------------------------------------------------------------------
// Description:
//   phy_vproc_rc: the phy_top socket with IFACE=pipe, the host at the PIPE.
//   It is the PHY side of pipe_if for our MAC: PCLK from the test bench, the
//   host's PIPE data in and out, electrical idle both ways (NOSIG, the K flag
//   and 0xFF, per symbol on the host's data), and receiver detection: while the MAC asks for it
//   (tx_detect_rx), RxStatus reports a receiver present (3'b011).
//==========================================================================

`timescale 1ps/1ps

`include "pciexpress_header.v"

module phy_vproc_rc #(
    parameter int DATA_BYTES = 8
) (
    input  logic                    pclk,
    input  logic                    rst_n,
           pipe_if.phy              pipe,
    output logic                    phy_rdy_n,
    input  logic [DATA_BYTES*8-1:0] host_txdata,
    input  logic [  DATA_BYTES-1:0] host_txdatak,
    output logic [DATA_BYTES*8-1:0] host_rxdata,
    output logic [  DATA_BYTES-1:0] host_rxdatak
);
  logic [3:0] rdy_cnt;

  // Electrical idle is NOSIG (the K flag and 0xFF: no 8b/10b code) per symbol
  // on the host's data, on every simulator. The MAC gets 0 under RxElecIdle;
  // the host gets NOSIG under the MAC's TxElecIdle, never the data the MAC
  // leaves there. RxValid and RxElecIdle are per word: a word only partly
  // NOSIG (idle entry after an EIOS, exit before a TS) is valid, its idle
  // bytes D0.0, which the MAC ignores there, as on a line settling
  localparam logic [8:0] NOSIG_SYM = {1'b1, `NOSIG};   // {K, byte}
  logic [  DATA_BYTES-1:0] host_idle;
  logic [DATA_BYTES*8-1:0] rx_data;
  logic [  DATA_BYTES-1:0] rx_datak;

  always_comb begin
    for (int b = 0; b < DATA_BYTES; b++) begin
      host_idle[b]        = ({host_txdatak[b], host_txdata[8*b +: 8]} == NOSIG_SYM);
      rx_data [8*b +: 8]  = host_idle[b] ? 8'h00 : host_txdata[8*b +: 8];
      rx_datak[b]         = host_idle[b] ? 1'b0  : host_txdatak[b];
    end
  end

  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      rdy_cnt <= '0;
    end
    else if (rdy_cnt != 4'hF) begin
      rdy_cnt <= rdy_cnt + 4'd1;
    end
  end

  assign phy_rdy_n         = (rdy_cnt != 4'hF);

  assign pipe.pclk         = pclk;
  assign pipe.rx_data      = rx_data;
  assign pipe.rx_datak     = rx_datak;
  assign pipe.rx_elec_idle = &host_idle;
  assign pipe.rx_valid     = !(&host_idle);

  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      pipe.phy_status <= 1'b1;
      pipe.rx_status  <= 3'b000;
    end
    else begin
      pipe.phy_status <= !pipe.reset_n || pipe.tx_detect_rx;
      pipe.rx_status  <= pipe.tx_detect_rx ? 3'b011 : 3'b000;
    end
  end

  assign host_rxdata  = pipe.tx_elec_idle ? {DATA_BYTES{NOSIG_SYM[7:0]}} : pipe.tx_data;
  assign host_rxdatak = pipe.tx_elec_idle ? {DATA_BYTES{NOSIG_SYM[8]}}   : pipe.tx_datak;
endmodule: phy_vproc_rc

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Oct 21, 2026
// -----------------------------------------------------------------------------
