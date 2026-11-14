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

module dll_top
  import pipe_pkg::*;
  import dll_pkg::*;
#(
    parameter int NUMBER_OF_VIRTUAL_CHANNELS = 1,
    parameter int RETRY_ADDR_WIDTH           = 9
) (
    input  logic phy_clk,    // Clock from Physical layer
    input  logic phy_reset,  // Async reset from Physical layer

    mac_if.dll   mac,        // to and from the MAC
    dll_if.dll   tl          // to and from the Transaction Layer
);

  // The DLL's link up: set on reaching L0, held through Recovery, cleared
  // when the MAC drops its link up (back to Detect). The MAC also raises
  // link up in PRE_L0; the DLL starts only in L0
  logic phy_linkup;
  always_ff @(posedge phy_clk or posedge phy_reset) begin
    if (phy_reset) begin
      phy_linkup <= 1'b0;
    end
    else begin
      phy_linkup <= mac.link_up & (phy_linkup | (mac.ltssm_state == mac_pkg::L0));
    end
  end

  dl_state_e vc_state[NUMBER_OF_VIRTUAL_CHANNELS];

  generate
    genvar i;
    for (i = 0; i < NUMBER_OF_VIRTUAL_CHANNELS; i = i + 1) begin : g_vc
      virtual_channel #(
          .RETRY_ADDR_WIDTH (RETRY_ADDR_WIDTH)
      ) u_vc (
          .clk                    (phy_clk),
          .reset                  (phy_reset),
          .linkup                 (phy_linkup),
          .virtual_channel_number (i[2:0]),

          .tx_dllp (tl.tx_dllp),

          .rx_sym (mac.rx),

          .tx_tlp       (tl.tx_tlp),
          .tx_tlp_ready (tl.tx_tlp_ready),

          .tx_sym (mac.tx),

          .rx_dllp (tl.rx_dllp),

          .rx_tlp      (tl.rx_tlp),
          .o_fsm_state (vc_state[i])
      );
    end
  endgenerate

  assign tl.dl_state = vc_state[0];

  // TODO: Add arbiter logic for multiple virtual channels

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Jan 10, 2026
// -----------------------------------------------------------------------------
