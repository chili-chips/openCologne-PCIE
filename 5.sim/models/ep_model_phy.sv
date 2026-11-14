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
//   ep_model_phy: the EP model behind our PHY (make IFACE=phy). As top, but
//   with pcie_top replaced by the EP model:
//
//     serial line <-> phy_top <-- pipe_mac --> pipe_mac_adapter <-> EP model
//
//   phy_top is the chip's: Cologne Chip's PIPE logic and the SerDes (here the
//   open-source BFM, phy.f). The EP model is the pcieVHost of EP=model
//   (node 1, usercode/VUserMain1.cpp), with only symbols; pipe_mac_adapter
//   (master in openPCIE) does what a PIPE MAC does with the side-band
//   signals: receiver detection, P0, electrical idle, RxValid.
//
//   The resets are those of clk_rst_gen: rst_pipe_n (PIPE Reset#) released
//   on a free-running clock, the MAC side released on PCLK once phy_rdy is
//   high. The adapter's own PIPE Reset (mac_reset) stays open: in this PHY
//   PIPE Reset# is also the SerDes PLL reset (ccfpga_pipe_top), so PCLK only
//   runs once it is released, and a reset counted on PCLK would never end.
//==========================================================================

`timescale 1ps/1ps

module ep_model_phy
  import pipe_pkg::*;
(
    input  logic rst_n,    // PERST#
    input  logic refclk,   // 100 MHz PCIE REFCLK
    input  logic ser_rxp,
    input  logic ser_rxn,
    output logic ser_txp,
    output logic ser_txn
);

  //------------------------------------------------------------------
  // Resets, as clk_rst_gen
  //------------------------------------------------------------------
  // rst_pipe_n: PERST#, released on refclk (clk_rst_gen: on the board clock)
  bit rst_pipe_meta, rst_pipe_n;

  always_ff @(posedge refclk or negedge rst_n) begin
    if (!rst_n) begin
      rst_pipe_meta <= 1'b0;
      rst_pipe_n    <= 1'b0;
    end
    else begin
      rst_pipe_meta <= 1'b1;
      rst_pipe_n    <= rst_pipe_meta;
    end
  end

  // mac_rst_n: released on PCLK once the SerDes TX is out of reset
  logic phy_rdy;
  logic pclk;
  bit   mac_rst_meta, mac_rst_n;

  always_ff @(posedge pclk or negedge phy_rdy) begin
    if (!phy_rdy) begin
      mac_rst_meta <= 1'b0;
      mac_rst_n    <= 1'b0;
    end
    else begin
      mac_rst_meta <= 1'b1;
      mac_rst_n    <= mac_rst_meta;
    end
  end

  //------------------------------------------------------------------
  // The PHY, as in top
  //------------------------------------------------------------------
  pipe_if pipe_mac ();

  phy_top u_phy_top (
      .clk_ref    (refclk),
      .rst_pipe_n (rst_pipe_n),
      .ser_rxp    (ser_rxp),
      .ser_rxn    (ser_rxn),
      .ser_txp    (ser_txp),
      .ser_txn    (ser_txn),
      .pipe       (pipe_mac),
      .phy_rdy    (phy_rdy)
  );

  //------------------------------------------------------------------
  // The PIPE, MAC side: the adapter's ports, then pipe_mac
  //------------------------------------------------------------------
  logic [           1:0] powerdown;
  logic                  tx_detect_rx;
  logic                  tx_elec_idle;
  logic [DATA_WIDTH-1:0] tx_data;
  logic [DATA_BYTES-1:0] tx_datak;
  logic                  link_up;     // P0 granted: the model's symbols flow

  assign pclk                   = pipe_mac.pclk;
  assign pipe_mac.reset_n       = rst_pipe_n;
  assign pipe_mac.power_down    = power_state_e'(powerdown);
  assign pipe_mac.tx_detect_rx  = tx_detect_rx;
  assign pipe_mac.tx_elec_idle  = tx_elec_idle;
  assign pipe_mac.tx_compliance = '0;
  assign pipe_mac.rx_polarity   = 1'b0;
  assign pipe_mac.tx.data       = tx_data;
  assign pipe_mac.tx.kcode      = tx_datak;

  // the EP model's side: symbols, NOSIG for electrical idle
  logic [DATA_WIDTH-1:0] vh_txdata, vh_rxdata;
  logic [DATA_BYTES-1:0] vh_txdatak, vh_rxdatak;

  pipe_mac_adapter #(
      .LANES        (1),
      .BYTES        (DATA_BYTES)
  ) u_adapter (
      .pclk         (pclk),
      .rst_n        (mac_rst_n),
      .link_up      (link_up),

      .vh_gen2      (1'b0),                 // Gen1 only
      .vh_txdata    (vh_txdata),
      .vh_txdatak   (vh_txdatak),
      .vh_rxdata    (vh_rxdata),
      .vh_rxdatak   (vh_rxdatak),

      .mac_reset    (  /*LINT:OK*/),        // PIPE Reset# is rst_pipe_n, above
      .powerdown    (powerdown),
      .rate         (  /*LINT:OK*/),        // Gen1 only: pipe_if has no Rate
      .tx_detect_rx (tx_detect_rx),
      .tx_elec_idle (tx_elec_idle),
      .tx_data      (tx_data),
      .tx_datak     (tx_datak),

      .phy_status   (pipe_mac.phy_status),
      .rx_status    (pipe_mac.rx_status),
      .rx_valid     (pipe_mac.rx_valid),
      .rx_elec_idle (pipe_mac.rx_elec_idle),
      .rx_data      (pipe_mac.rx.data),
      .rx_datak     (pipe_mac.rx.kcode)
  );

  //------------------------------------------------------------------
  // The EP model: a pcieVHost in EP mode at VProc node 1, as in
  // EPPIPEx1__pcieVHost_DUT; tb.dut.bfm_pcie is its decoder page
  //------------------------------------------------------------------
  PIPEx1__pcieVHost #(
      .NodeNum            (1),
      .EndPoint           (1'b1),
      .DataWidth          (DATA_WIDTH),
      .DllBytes           (DATA_BYTES)
  ) bfm_pcie (
      .pclk               (pclk),
      .nreset             (mac_rst_n),

      .TxData             (vh_txdata),
      .TxDataK            (vh_txdatak),
      .RxData             (vh_rxdata),
      .RxDataK            (vh_rxdatak),

      .pipe_dn_pclk       (),
      .pipe_dn_data       (),
      .pipe_dn_datak      (),
      .pipe_up_pclk       (),
      .pipe_up_data       (),
      .pipe_up_datak      (),

      .dll_clk            (pclk),
      .dll_rx_data        (),
      .dll_rx_tlp_valid   (),
      .dll_rx_tlp_first   (),
      .dll_rx_tlp_last    (),
      .dll_rx_hdr_credit  (),
      .dll_rx_data_credit (),
      .dll_rx_update_type (),
      .dll_rx_packet_type (),
      .dll_rx_dllp_valid  (),
      .dllp_clk           (),
      .dllp_dn_data       (),
      .dllp_dn_valid      (),
      .dllp_up_data       (),
      .dllp_up_valid      (),

      .tx_clk             (),
      .tx_tlp_data        (),
      .tx_tlp_sop         (),
      .tx_tlp_eop         (),
      .tx_tlp_valid       (),
      .tx_peer_data       (),
      .tx_peer_sop        (),
      .tx_peer_eop        (),
      .tx_peer_valid      (),
      .rx_clk             (),
      .rx_tlp_data        (),
      .rx_tlp_sop         (),
      .rx_tlp_eop         (),
      .rx_tlp_valid       (),
      .rx_peer_data       (),
      .rx_peer_sop        (),
      .rx_peer_eop        (),
      .rx_peer_valid      ()
  );

endmodule: ep_model_phy

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Nov 14, 2026
// -----------------------------------------------------------------------------
