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
//   pcie_core: the soft PCIE stack, everything between the PIPE interface and
//   the SOC, as in the RTL block diagram (0.doc/2.rtl/block-diagram.drawio):
//
//     pipe <-> MAC <-> DLL <-- dll --> TL <-- trn --> trn_bridge <-> s_axis_tx / m_axis_rx
//                                       \--- cfg ---------------------------------> SOC
//
//   - MAC (ccfpga_mac_top, Cologne Chip): the LTSSM trains the link,
//     then sends and receives the ordered sets and scrambled data on PIPE.
//   - DLL (dll_top): sequence numbers and LCRC, Ack/Nak and
//     replay, flow-control DLLPs; it starts once the LTSSM is in L0.
//   - TL (tl_top): flow control, the configuration space, and the TLPs to
//     and from the SOC, on trn_tx_if / trn_rx_if (derived from the TRN bus
//     of the PCIE_2_1 hard block).
//   - trn_bridge (openPCIE): AXI-Stream to and from TRN, and the SOC's TX
//     throttle.
//
//   The data link is up (dll_up, UG477 trn_lnk_up) when the DLL is in
//   DL_Active. core_rst_n, the reset of trn_bridge and the SOC, follows it
//   one PCLK later; a link drop or mac_rst_n asserts it again. The TL runs on
//   mac_rst_n: it resets its parts on DL_Down itself, and takes the link
//   partner's InitFC credit limits in DL_Init (3.2.1).
//==========================================================================

module pcie_core
  import pipe_pkg::*;
  import tl_pkg::*;
  import trn_pkg::*;
  import dll_pkg::*;
(
    input  logic   rst_pipe_n,  // PIPE Reset#
    input  logic   mac_rst_n,   // PCLK: MAC and DLL

    pipe_if.mac    pipe,

    output logic   dll_up,      // PCLK: data link up (DL_Active)
    output logic   core_rst_n,  // PCLK: trn_bridge and the SOC, follows dll_up

    axis_if.slave  s_axis_tx,   // TLPs from the SOC (tuser: tx_tuser_t)
    axis_if.master m_axis_rx,   // TLPs to the SOC   (tuser: rx_tuser_t)

    cfg_if.core    cfg          // status sideband to the SOC
);


  mac_if mac ();
  dll_if dll ();

  trn_tx_if trn_tx ();
  trn_rx_if trn_rx ();

  // The MAC drives PIPE Reset#
  assign pipe.reset_n = rst_pipe_n;

  ccfpga_mac_top u_mac (
      .i_reset_n (mac_rst_n),
      .pipe      (pipe),
      .mac       (mac)
  );

  logic  dll_reset;  // the DLL resets active high
  assign dll_reset = ~mac_rst_n;

  dll_top #(
      .NUMBER_OF_VIRTUAL_CHANNELS (1)
  ) u_dll (
      .phy_clk   (pipe.pclk),
      .phy_reset (dll_reset),
      .mac       (mac),
      .tl        (dll)
  );

  assign dll_up = (dll.dl_state == DL_ACTIVE);

  // core_rst_n: the trn_bridge and SOC reset, follows the data link
  always_ff @(posedge pipe.pclk or negedge mac_rst_n) begin
    if (!mac_rst_n) begin
      core_rst_n <= 1'b0;
    end
    else begin
      core_rst_n <= dll_up;
    end
  end

  tl_top u_tl (
      .clk    (pipe.pclk),
      .rst_n  (mac_rst_n),
      .dll    (dll),
      .trn_tx (trn_tx),
      .trn_rx (trn_rx),
      .cfg    (cfg)
  );

  trn_top u_trn_bridge (
      .s_axis_tx  (s_axis_tx),
      .m_axis_rx  (m_axis_rx),
      .trn_tx     (trn_tx),
      .trn_rx     (trn_rx),
      .clk        (pipe.pclk),
      .core_rst_n (core_rst_n)
  );

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Oct 18, 2026
// -----------------------------------------------------------------------------
