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
//   clk_rst_gen: the clocks and resets of the EP.
//
//   Clocks:
//   - clk_aon: always on, the board clock (10 MHz on the GateMate EVK), no PLL. Runs
//     the reset sequencing below. The SerDes regfile clock is tied to 0.
//   - PCLK is not made here: the PHY makes it (pipe_if.pclk), and the MAC,
//     DLL, TL, trn_bridge and the SOC all run on it.
//
//   Resets, one per clock domain, each asserted asynchronously and released
//   on its own clock:
//   - perst_por_n: CC_USR_RSTN (end of FPGA configuration) and PERST# from the
//     connector. CC_USR_RSTN replaces the INIT-value flops a Xilinx design
//     needs for a reset after configuration.
//   - rst_pipe_n (clk_aon): perst_por_n, released on clk_aon. PIPE Reset#;
//     the PIPE logic turns it into the SerDes PLL reset (PLL_RESET_I).
//   - mac_rst_n (PCLK): held until the SerDes TX is out of reset (phy_rdy).
//   - core_rst_n is made in pcie_core, from mac_rst_n and the data link (dll_up).
//==========================================================================

module clk_rst_gen (
    input logic clk_brd,  // board oscillator, on a dedicated clock pin
    input logic perst_n,  // PERST# from the connector, active low

    input logic pclk,    // PCLK, from the PHY
    input logic phy_rdy, // PCLK: SerDes TX out of reset

    output logic rst_pipe_n,
    output logic mac_rst_n
);

  logic clk_aon;
  logic usr_rstn;
  logic perst_por_n;

  CC_USR_RSTN u_usr_rstn (.USR_RSTN(usr_rstn));

  // The board clock reaches the fabric through a global buffer (UG1001)
  CC_BUFG u_clk_aon (
      .I(clk_brd),
      .O(clk_aon)
  );

  assign perst_por_n = usr_rstn & perst_n;

  // rst_pipe_n: perst_por_n, released on clk_aon
  logic rst_pipe_meta, rst_pipe_q;

  always_ff @(posedge clk_aon or negedge perst_por_n) begin
    if (!perst_por_n) begin
      rst_pipe_meta <= 1'b0;
      rst_pipe_q    <= 1'b0;
    end
    else begin
      rst_pipe_meta <= 1'b1;
      rst_pipe_q    <= rst_pipe_meta;
    end
  end

  assign rst_pipe_n = rst_pipe_q;

  // mac_rst_n: released on PCLK once the SerDes TX is out of reset
  logic mac_rst_meta, mac_rst_q;

  always_ff @(posedge pclk or negedge phy_rdy) begin
    if (!phy_rdy) begin
      mac_rst_meta <= 1'b0;
      mac_rst_q    <= 1'b0;
    end
    else begin
      mac_rst_meta <= 1'b1;
      mac_rst_q    <= mac_rst_meta;
    end
  end

  assign mac_rst_n = mac_rst_q;

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Oct 18, 2026
// -----------------------------------------------------------------------------
