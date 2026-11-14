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

module trn_top (
    axis_if.slave  s_axis_tx,
    axis_if.master m_axis_rx,

    trn_tx_if.src  trn_tx,     // TLPs to the TL
    trn_rx_if.dst  trn_rx,     // TLPs from the TL

    input  logic   clk,
    input  logic   core_rst_n
);

  trn_rx u_trn_rx (
      .m_axis_rx  (m_axis_rx),
      .trn_rx     (trn_rx),
      .clk        (clk),
      .core_rst_n (core_rst_n)
  );


  trn_tx u_trn_tx (
      .s_axis_tx  (s_axis_tx),
      .trn_tx     (trn_tx),
      .clk        (clk),
      .core_rst_n (core_rst_n)
  );

  trn_tx_throttle u_trn_tx_throttle (
      .s_axis_tx_tvalid (s_axis_tx.tvalid),
      .s_axis_tx_tlast  (s_axis_tx.tlast),
      .s_axis_tx_tready (s_axis_tx.tready),
      .trn_tx           (trn_tx),
      .clk              (clk),
      .core_rst_n       (core_rst_n)
  );

endmodule
// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        May 24, 2024
// -----------------------------------------------------------------------------
