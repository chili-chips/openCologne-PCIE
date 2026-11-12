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

// WaveCrux view of the DLL's PHY-side streams.
//
// Presents the 64-bit stream in both directions under the names the
// WaveCrux PCIe decoders (wcx-pcie, ferrite.pcie_pipe_w64 / pcie_dll_w64)
// auto-bind to: TxPclk/TxData/TxDataK (DLL -> PHY) and
// RxPclk/RxData/RxDataK (PHY -> DLL). In WaveCrux, Ctrl+Shift+D on
// tb_dll_wavecrux.wavecrux binds all inputs; the prefix drop-down picks
// Tx or Rx.
//
// RxDataK is rebuilt here: the testbench loops phy_tx_data and
// phy_tx_data_k back to the DLL's phy_rx_data and phy_rx_data_k through
// one register, so RxDataK is phy_tx_data_k through the same register.
// Not valid while the testbench drives external_data.
//
// Attached with `bind`, so the testbench itself carries no view code.
// Compile this file after tb_dll_wavecrux.sv (Verilator; Icarus does not
// support bind). Build with Verilator -O0, or these copies become trace
// aliases that WaveCrux's signal pickers hide.

module dll_wavecrux_view
  import pipe_pkg::*;
(
    input  wire                  phy_clk,
    input  wire                  phy_reset,
    input  pipe_data_t  phy_tx_data,
    input  pipe_flags_t phy_tx_data_k,
    input  pipe_data_t  phy_rx_data
);

    // Only read by the waveform dump
    /* verilator lint_off UNUSEDSIGNAL */
    wire                  pclk    = phy_clk;
    wire                  TxPclk  = phy_clk;  // per-prefix copies: auto-bind looks
    wire                  RxPclk  = phy_clk;  // for <prefix>pclk, not a shared pclk
    pipe_data_t  TxData  = phy_tx_data;
    pipe_flags_t TxDataK = phy_tx_data_k;
    pipe_data_t  RxData  = phy_rx_data;
    pipe_flags_t RxDataK;
    /* verilator lint_on UNUSEDSIGNAL */

    always @(posedge phy_clk or posedge phy_reset) begin
        if (phy_reset) begin
            RxDataK <= {DATA_BYTES{1'b0}};
        end else begin
            RxDataK <= phy_tx_data_k;
        end
    end

endmodule

bind tb_dll_wavecrux dll_wavecrux_view wavecrux (
    .phy_clk      (phy_clk),
    .phy_reset    (phy_reset),
    .phy_tx_data  (phy_tx_data),
    .phy_tx_data_k(phy_tx_data_k),
    .phy_rx_data  (phy_rx_data)
);

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Oct 8, 2026
// -----------------------------------------------------------------------------
