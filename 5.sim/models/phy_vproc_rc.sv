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
//   It is the PHY side of pipe_if for our MAC, PCLK from the test bench: a
//   wrapper of models/pipe_phy_core.sv (master in openPCIE), which gives the
//   PIPE handshakes (PhyStatus, receiver detection) and electrical idle both
//   ways (NOSIG on the host's data).
//==========================================================================

`timescale 1ps/1ps

module phy_vproc_rc #(
    parameter int DATA_BYTES = 8
) (
    input  logic                    pclk,
    input  logic                    rst_n,
           pipe_if.phy              pipe,
    output logic                    phy_rdy,
    input  logic [DATA_BYTES*8-1:0] host_txdata,
    input  logic [  DATA_BYTES-1:0] host_txdatak,
    output logic [DATA_BYTES*8-1:0] host_rxdata,
    output logic [  DATA_BYTES-1:0] host_rxdatak
);
  assign pipe.pclk = pclk;

  pipe_phy_core #(
      .LANES        (1),
      .BYTES        (DATA_BYTES),
      .RDY_LAT      (15),
      .RCVRDET_LAT  (4)     // 128 ns: the SerDes BFM detects in 120 ns
  ) u_core (
      .pclk         (pclk),
      .rst_n        (rst_n),
      .phy_rdy      (phy_rdy),

      .mac_reset    (!pipe.reset_n),
      .powerdown    (pipe.power_down),
      .rate         (1'b0),               // Gen1 only
      .tx_detect_rx (pipe.tx_detect_rx),
      .tx_elec_idle (pipe.tx_elec_idle),
      .tx_data      (pipe.tx.data),
      .tx_datak     (pipe.tx.kcode),

      .phy_status   (pipe.phy_status),
      .rx_status    (pipe.rx_status),
      .rx_valid     (pipe.rx_valid),
      .rx_elec_idle (pipe.rx_elec_idle),
      .rx_data      (pipe.rx.data),
      .rx_datak     (pipe.rx.kcode),

      .rcvr_present (1'b1),
      .host_rxdata  (host_rxdata),
      .host_rxdatak (host_rxdatak),
      .host_txdata  (host_txdata),
      .host_txdatak (host_txdatak)
  );
endmodule: phy_vproc_rc

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Oct 21, 2026
// -----------------------------------------------------------------------------
