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
//   Top-level test bench: the host, RCPIPEx1__pcieVHost at VProc node 2
//   running openPCIE's Artix-7 RC model, drives the DUT at its PIPE
//   interface (IFACE=serial: on the serial line): the EP RTL + firmware, or
//   the EP model EPPIPEx1__pcieVHost_DUT (node 1).
//
//   Every setting is a parameter (the Makefile sets them per simulator); no
//   macros. The DUT and the host sit in generate blocks, one per setting;
//   each make mode compiles only the modules of its own blocks:
//
//     g_ep_rtl_serial  EP=rtl IFACE=serial  top (our PHY and EP)
//     g_ep_rtl         EP=rtl               phy_vproc_rc + pcie_top
//     g_ep_phy         IFACE=phy            ep_model_phy (the EP model behind our PHY)
//     g_ep_serial      IFACE=serial         PcieVhostSerial (the EP model)
//     g_ep_model       (default)            EPPIPEx1__pcieVHost_DUT
//     g_rc_serial      IFACE=serial, phy    the host on the serial line
//     g_rc             IFACE=pipe           the host at the PIPE
//
//   As Verilator resolves a dotted reference even in a block not taken, the
//   references into modules only some modes compile (top, pcie_top,
//   ep_model_phy) are in models/tb_glue_<block>.sv, bound into tb by the
//   mode that compiles them: the SerDes pins of top, and the waveform dumps
//==========================================================================

// No `timescale: 1ns/10ps from the simulator command line (Makefile); every
// delay carries its unit. The periods below are in ps: a delay is
// #(x * 1ns / 1000.0), as 1ps rounds to 0 at 10 ps precision.

// PPM: on the serial line with our PHY (IFACE=phy, EP=rtl IFACE=serial), the
// EP's REFCLK so many ppm off the host's clocks (make PPM; + faster), as
// boards with their own reference clocks (SRNS). RX_RETIME: the host's
// receiver for a partner on its own clock (make RETIME, default 1). POL_DN:
// the host -> EP pair with P and N swapped (make POL=1), so the EP's MAC
// must invert its lane in Polling (4.2.4.4); with our PHY on the line
module tb #(
   parameter      RUN_SIM_US     = 10000,
                  PIPE_DATAWIDTH = 64,
   parameter real PPM            = 0.0,
   parameter int  RX_RETIME      = 1,
   parameter bit  POL_DN         = 1'b0,
   parameter bit  EP_RTL         = 1'b0,  // make EP=rtl: our EP RTL + firmware
   parameter bit  IFACE_SERIAL   = 1'b0,  // make IFACE=serial or phy: the host on the serial line
   parameter bit  IFACE_PHY      = 1'b0,  // make IFACE=phy: the EP model behind our PHY
   parameter bit  DUMP           = 1'b0   // make DUMP=1: the FST waveform
)();

  // Our PHY under the host: EP=rtl IFACE=serial (top), IFACE=phy (the EP model)
  localparam bit GM_PHY = IFACE_PHY || (EP_RTL && IFACE_SERIAL);

//--------------------------------------------------------------
// Clock and reset generation
//--------------------------------------------------------------

  // Generate clocks and run sim for the specified amount of time
  localparam  HALF_CLK_P_PERIOD_PS      = 2_500; // 200MHz, reset timing
  localparam  HALF_PCIE_PERIOD_PS       = 2_000; // 250MHz (GEN1): the symbol clock
  localparam  HALF_PIPE_PERIOD_PS       = HALF_PCIE_PERIOD_PS*PIPE_DATAWIDTH/8;
  localparam  RST_CYLES                 = 10;

  // The host's VProc node: openPCIE's Artix-7 RC model, its VUserMain2.cpp
  localparam  HOST_NODE                 = 2;

  logic       clk_p;
  wire        clk_n;
  logic       rst_n;
  bit         pclk;

  initial begin
    clk_p      = 1'b0;
    //clk_n      = 1'b0;
    rst_n      = 1'b0;
    pclk       = 1'b0;
  end

  // One clock: PCLK. Each model makes its symbol clock from it
  // (vip/openPCIE_BFM/2.rtl/PIPEx1__pcieVHost.sv)

  initial begin
    fork
      // released with a nonblocking assignment: 25 ns is a symbol clock edge,
      // and the models' reset registers then see it after that edge, on every
      // simulator
      begin : board_rst_n
        #(HALF_CLK_P_PERIOD_PS*RST_CYLES * 1ns / 1000.0)
          rst_n <= 1'b1;
      end

      forever begin: clk_p_gen
        #(HALF_CLK_P_PERIOD_PS * 1ns / 1000.0)
          clk_p  = ~clk_p;
      end

      forever begin: pipe_clock_gen
        #(HALF_PIPE_PERIOD_PS * 1ns / 1000.0)
          pclk = ~pclk;
      end

      begin: run_sim
        #(RUN_SIM_US * 1us);
          $fatal(1, "time limit of %0d us: no RC MODEL RESULT", RUN_SIM_US);
      end
    join
  end

  assign clk_n = ~clk_p;


//--------------------------------------------------------------
// DUT
//--------------------------------------------------------------

  logic [PIPE_DATAWIDTH-1:0]           downdata;
  logic [PIPE_DATAWIDTH/8-1:0]         downdatak;
  logic [PIPE_DATAWIDTH-1:0]           updata;
  logic [PIPE_DATAWIDTH/8-1:0]         updatak;

  // down = RC -> EP, up = EP -> RC. Electrical idle is NOSIG (K flag, 0xFF) per
  // symbol on the data, on Verilator and Icarus alike: no side-band

//--------------------------------------------------------------
// DUT: the EP, at its PIPE interface. Either the EP RTL + firmware
// (make EP=rtl): pcie_top, with the host in the phy_top socket
// (phy_vproc_rc), or the EP model EPPIPEx1__pcieVHost_DUT, a pcieVHost in EP
// mode (make EP=model). On the serial line (IFACE=serial: the GateMate PHY with EP=rtl;
// with EP=model, the EP model is upstream's PcieVhostSerial), the host too
//--------------------------------------------------------------

  // The serial line (IFACE_SERIAL): its clocks run only then
  localparam  HALF_SER_PERIOD_PS        = 100;    // 5 GHz: the host divides it to 2.5 GHz at Gen1
  localparam  HALF_PCIE2_PERIOD_PS      = 1_000;  // 500 MHz: the host divides it to 250 MHz at Gen1

  logic       serclk;
  logic       pcieclk2;
  logic       ser_dn;
  logic       ser_up;

  initial begin
    serclk = 1'b0;
    if (IFACE_SERIAL) begin
      forever begin
        #(HALF_SER_PERIOD_PS * 1ns / 1000.0) serclk = ~serclk;
      end
    end
  end

  initial begin
    pcieclk2 = 1'b0;
    if (IFACE_SERIAL) begin
      forever begin
        #(HALF_PCIE2_PERIOD_PS * 1ns / 1000.0) pcieclk2 = ~pcieclk2;
      end
    end
  end

  // The EP RTL's board clock and outputs (EP_RTL)
  localparam  HALF_BRD_PERIOD_PS        = 50_000; // 10 MHz board clock

  logic       clk_brd;
  logic       link_up;
  logic       fw_pass;

  initial begin
    clk_brd = 1'b0;
    if (EP_RTL) begin
      forever begin
        #(HALF_BRD_PERIOD_PS * 1ns / 1000.0) clk_brd = ~clk_brd;
      end
    end
  end

  // Our PHY's REFCLK and its receive pair (GM_PHY)
  localparam  HALF_REF_PERIOD_PS        = 5_000;  // 100 MHz PCIE REFCLK

  logic       refclk;
  logic       ser_up_n;

  // Edge k at k half periods from time 0: each edge rounds to the time
  // precision on its own, so a PPM offset builds up at any precision
  initial begin : _refclk
    longint k;
    real    half_ns;
    half_ns = (HALF_REF_PERIOD_PS / 1000.0) / (1.0 + PPM * 1.0e-6);
    refclk  = 1'b0;
    if (GM_PHY) begin
      for (k = 1; ; k++) begin
        /* verilator lint_off ZERODLY */  // never 0: k grows each edge
        #((k * half_ns) * 1ns - $realtime);
        /* verilator lint_on ZERODLY */
        refclk = ~refclk;
      end
    end
  end : _refclk

  // The host's electrical idle is a constant 0 on ser_dn; the GateMate RX takes
  // idle from P = N. So N follows P once the line has stayed constant longer
  // than any 8b/10b run (5 bits): 12 serclk periods, 6 UI at Gen1, 12 at Gen2.
  // The first change ends it at once
  bit         ser_dn_q;
  int         ser_dn_same;
  logic       ser_dn_idle;

  // in reset the host is idle: the line constant 0
  always_ff @(posedge serclk or negedge rst_n) begin
    if (!rst_n) begin
      ser_dn_q    <= 1'b0;
      ser_dn_same <= 12;
    end
    else begin
      ser_dn_q    <= ser_dn;
      ser_dn_same <= (ser_dn != ser_dn_q) ? 0 : ((ser_dn_same < 12) ? ser_dn_same + 1 : 12);
    end
  end

  assign ser_dn_idle = (ser_dn_same == 12) && (ser_dn == ser_dn_q);

  // the pair at the EP's pins, P and N swapped with POL_DN (idle: P = N either way)
  logic       ser_dn_p, ser_dn_n;
  assign ser_dn_p = POL_DN ? (ser_dn_idle ? ser_dn : ~ser_dn) : ser_dn;
  assign ser_dn_n = POL_DN ? ser_dn : (ser_dn_idle ? ser_dn : ~ser_dn);

// FST waveform, for WaveCrux and GTKWave (make DUMP=1 run): in each DUT
// block, g_dump (models/tb_glue_<block>.sv for three of them). The signals of this level, i.e. the PIPE link both ways, its
// clocks and reset, and the host's ports (u_rc), the decoder page. With
// EP=rtl, the EP's decoder pages instead of the EP model's: its layer
// boundaries (pcie_core.wavecrux, models/ep_wavecrux_view.sv) and the SOC
// CPU's retired instructions (soc_top.cpu_view), in a file of their own

  if (EP_RTL && IFACE_SERIAL) begin : g_ep_rtl_serial
    top dut
    (
      .clk_brd                           (clk_brd),
      .perst_n                           (rst_n),
      .clkreq_n                          (),
      .link_up                           (link_up),
      .fw_pass                           (fw_pass)
    );

    // the SerDes pins (not ports of top) and the dump: models/tb_glue_ep_rtl_serial.sv

    always @(link_up) $display("%t tb: dll_up = %b", $time, link_up);
    always @(fw_pass) $display("%t tb: fw_pass = %b", $time, fw_pass);
  end : g_ep_rtl_serial

  else if (EP_RTL) begin : g_ep_rtl
    logic       phy_rdy;

    pipe_if pipe_mac ();

    phy_vproc_rc #(
      .DATA_BYTES                        (PIPE_DATAWIDTH/8)
    ) u_phy
    (
      .pclk                              (pclk),
      .rst_n                             (rst_n),
      .pipe                              (pipe_mac),
      .phy_rdy                           (phy_rdy),
      .host_txdata                       (downdata),
      .host_txdatak                      (downdatak),
      .host_rxdata                       (updata),
      .host_rxdatak                      (updatak)
    );

    pcie_top dut
    (
      .clk_brd                           (clk_brd),
      .perst_n                           (rst_n),
      .pipe_mac                          (pipe_mac),
      .phy_rdy                           (phy_rdy),
      .rst_pipe_n                        (),
      .dll_up                            (link_up),
      .fw_pass                           (fw_pass)
    );

    always @(link_up) $display("%t tb: dll_up = %b", $time, link_up);
    always @(fw_pass) $display("%t tb: fw_pass = %b", $time, fw_pass);

    // the dump: models/tb_glue_ep_rtl.sv
  end : g_ep_rtl

  else if (IFACE_PHY) begin : g_ep_phy
    // the EP model behind our PHY: phy_top, Cologne Chip's PIPE logic and the
    // SerDes BFM, the EP model on its PIPE (models/ep_model_phy.sv)
    ep_model_phy dut
    (
      .rst_n                             (rst_n),
      .refclk                            (refclk),
      .ser_rxp                           (ser_dn_p),
      .ser_rxn                           (ser_dn_n),
      .ser_txp                           (ser_up),
      .ser_txn                           (ser_up_n)
    );

    // the dump: models/tb_glue_ep_phy.sv
  end : g_ep_phy

  else if (IFACE_SERIAL) begin : g_ep_serial
    PcieVhostSerial #(
      .LinkWidth                         (1),
      .NodeNum                           (1),
      .EndPoint                          (1),
      .Gen2Clk                           (1)
    ) dut
    (
      .Clk                               (pcieclk2),
      .SerClk                            (serclk),
      .notReset                          (rst_n),
      .ClkOut                            (),
      .SerClkOut                         (),
      .LinkIn0                           (ser_dn),
      .LinkIn1                           (1'b0),
      .LinkIn2                           (1'b0),
      .LinkIn3                           (1'b0),
      .LinkIn4                           (1'b0),
      .LinkIn5                           (1'b0),
      .LinkIn6                           (1'b0),
      .LinkIn7                           (1'b0),
      .LinkIn8                           (1'b0),
      .LinkIn9                           (1'b0),
      .LinkIn10                          (1'b0),
      .LinkIn11                          (1'b0),
      .LinkIn12                          (1'b0),
      .LinkIn13                          (1'b0),
      .LinkIn14                          (1'b0),
      .LinkIn15                          (1'b0),
      .LinkOut0                          (ser_up),
      .LinkOut1                          (),
      .LinkOut2                          (),
      .LinkOut3                          (),
      .LinkOut4                          (),
      .LinkOut5                          (),
      .LinkOut6                          (),
      .LinkOut7                          (),
      .LinkOut8                          (),
      .LinkOut9                          (),
      .LinkOut10                         (),
      .LinkOut11                         (),
      .LinkOut12                         (),
      .LinkOut13                         (),
      .LinkOut14                         (),
      .LinkOut15                         ()
    );

    if (DUMP) begin : g_dump
      initial begin
        $dumpfile("tb_serial.fst");
        $dumpvars(1, tb);
        $dumpvars(1, tb.g_rc_serial.u_rc);
        $dumpvars(1, dut);
      end
    end : g_dump
  end : g_ep_serial

  else begin : g_ep_model
    EPPIPEx1__pcieVHost_DUT #(
      .DataWidth                         (PIPE_DATAWIDTH)
    ) dut
    (
      .rst_n                             (rst_n),
      .pclk                              (pclk),

      // PCIE PIPE data
      .txdata                            (updata),
      .txdatak                           (updatak),
      .rxdata                            (downdata),
      .rxdatak                           (downdatak)
    );

    if (DUMP) begin : g_dump
      initial begin
        $dumpfile("tb.fst");
        $dumpvars(1, tb);
        $dumpvars(1, tb.g_rc.u_rc);
        $dumpvars(1, dut.bfm_pcie);
      end
    end : g_dump
  end : g_ep_model

//--------------------------------------------------------------
// Host: RCPIPEx1__pcieVHost, a pcieVHost in RC mode at VProc node HOST_NODE. Its
// ports are the RC's decoder page of the dump (tb.g_rc.u_rc): the link at the
// PIPE, Data Link and Transaction layers, under the names WaveCrux
// auto-binds. The EP model has the same, as it sees the link
// (tb.g_ep_model.dut.bfm_pcie)
//--------------------------------------------------------------

  // Data Link: RC -> EP TLPs as sent, on pclk (the EP model's taps,
  // tb.g_ep_model.dut.bfm_pcie, have them as its DLL hands them to its TL).
  // And Transaction: the EP's TLPs the RC takes, on rx_clk; make TL=1 checks
  // its shadow TL's completions against them (models/tl_shadow.sv)
  logic [PIPE_DATAWIDTH-1:0]           dll_rx_data;
  logic                                dll_rx_tlp_valid;
  logic                                dll_rx_tlp_first;
  logic                                dll_rx_tlp_last;
  logic                                rx_clk;
  logic [              31:0]           rx_tlp_data;
  logic                                rx_tlp_sop;
  logic                                rx_tlp_eop;
  logic                                rx_tlp_valid;

  if (IFACE_SERIAL) begin : g_rc_serial
    PcieVhostSerial #(
      .LinkWidth                         (1),
      .NodeNum                           (HOST_NODE),
      .EndPoint                          (0),
      .Gen2Clk                           (1),
      .RX_RETIME                         (RX_RETIME)
    ) u_rc
    (
      .Clk                               (pcieclk2),
      .SerClk                            (serclk),
      .notReset                          (rst_n),
      .ClkOut                            (),
      .SerClkOut                         (),
      .LinkIn0                           (ser_up),
      .LinkIn1                           (1'b0),
      .LinkIn2                           (1'b0),
      .LinkIn3                           (1'b0),
      .LinkIn4                           (1'b0),
      .LinkIn5                           (1'b0),
      .LinkIn6                           (1'b0),
      .LinkIn7                           (1'b0),
      .LinkIn8                           (1'b0),
      .LinkIn9                           (1'b0),
      .LinkIn10                          (1'b0),
      .LinkIn11                          (1'b0),
      .LinkIn12                          (1'b0),
      .LinkIn13                          (1'b0),
      .LinkIn14                          (1'b0),
      .LinkIn15                          (1'b0),
      .LinkOut0                          (ser_dn),
      .LinkOut1                          (),
      .LinkOut2                          (),
      .LinkOut3                          (),
      .LinkOut4                          (),
      .LinkOut5                          (),
      .LinkOut6                          (),
      .LinkOut7                          (),
      .LinkOut8                          (),
      .LinkOut9                          (),
      .LinkOut10                         (),
      .LinkOut11                         (),
      .LinkOut12                         (),
      .LinkOut13                         (),
      .LinkOut14                         (),
      .LinkOut15                         ()
    );
  end : g_rc_serial

  else begin : g_rc
    RCPIPEx1__pcieVHost #(
      .NodeNum                           (HOST_NODE),
      .DataWidth                         (PIPE_DATAWIDTH),
      .DllBytes                          (PIPE_DATAWIDTH/8)
    ) u_rc
    (
      .pclk                              (pclk),
      .nreset                            (rst_n),

      // PIPE: the link, and its copies by direction for the decoders
      .TxData                            (downdata),
      .TxDataK                           (downdatak),
      .RxData                            (updata),
      .RxDataK                           (updatak),
      .pipe_dn_pclk                      (),
      .pipe_dn_data                      (),
      .pipe_dn_datak                     (),
      .pipe_up_pclk                      (),
      .pipe_up_data                      (),
      .pipe_up_datak                     (),

      // Data Link
      .dll_clk                           (pclk),
      .dll_rx_data                       (dll_rx_data),
      .dll_rx_tlp_valid                  (dll_rx_tlp_valid),
      .dll_rx_tlp_first                  (dll_rx_tlp_first),
      .dll_rx_tlp_last                   (dll_rx_tlp_last),
      .dll_rx_hdr_credit                 (),
      .dll_rx_data_credit                (),
      .dll_rx_update_type                (),
      .dll_rx_packet_type                (),
      .dll_rx_dllp_valid                 (),
      .dllp_clk                          (),
      .dllp_dn_data                      (),
      .dllp_dn_valid                     (),
      .dllp_up_data                      (),
      .dllp_up_valid                     (),

      // Transaction: for waveform decoders, read from the dump; rx_* also for
      // make TL=1
      .tx_clk                            (),
      .tx_tlp_data                       (),
      .tx_tlp_sop                        (),
      .tx_tlp_eop                        (),
      .tx_tlp_valid                      (),
      .tx_peer_data                      (),
      .tx_peer_sop                       (),
      .tx_peer_eop                       (),
      .tx_peer_valid                     (),
      .rx_clk                            (rx_clk),
      .rx_tlp_data                       (rx_tlp_data),
      .rx_tlp_sop                        (rx_tlp_sop),
      .rx_tlp_eop                        (rx_tlp_eop),
      .rx_tlp_valid                      (rx_tlp_valid),
      .rx_peer_data                      (),
      .rx_peer_sop                       (),
      .rx_peer_eop                       (),
      .rx_peer_valid                     ()
    );
  end : g_rc

// Top level fatal task, which can be called from anywhere in verilog code.
// via the `fatal definition in pciedispheader.svh. Any data logging, error
// message displays etc., on a fatal, should be placed in here.
task Fatal;
begin
    $fatal(1, "pcieVHost fatal: the RC model's FAIL, or a bad VProc access");
end
endtask

  // The serial line by direction, under the name the wcx-pcie serial-line
  // decoders bind (line): RC -> EP and EP -> RC (IFACE_SERIAL)
  logic       ser_dn_line;
  logic       ser_up_line;

  assign ser_dn_line = ser_dn;
  assign ser_up_line = ser_up;

endmodule: tb

/*
------------------------------------------------------------------------------
Version History:
------------------------------------------------------------------------------
 2025/08/19 SS: initial creation
 2026/11/24    : macros (EP_RTL, IFACE_SERIAL, IFACE_PHY, DUMP) made parameters

*/

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        April 2025
// -----------------------------------------------------------------------------
