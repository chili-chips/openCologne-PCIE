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
//==========================================================================

`timescale 1ps/1ps

module tb #(
   parameter RUN_SIM_US     = 10000,
             PIPE_DATAWIDTH = 64   
   
)();

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
  // (models/PIPEx1__pcieVHost.sv)

  initial begin
    fork
      // released with a nonblocking assignment: 25 ns is a symbol clock edge,
      // and the models' reset registers then see it after that edge, on every
      // simulator
      begin : board_rst_n
        #(HALF_CLK_P_PERIOD_PS*RST_CYLES)
          rst_n <= 1'b1;
      end

      forever begin: clk_p_gen
        #(HALF_CLK_P_PERIOD_PS)
          clk_p  = ~clk_p;
      end

      forever begin: pipe_clock_gen
        #(HALF_PIPE_PERIOD_PS)
          pclk = ~pclk;
      end

      begin: run_sim
        #(RUN_SIM_US * 64'd1_000_000);  // in ps, the timescale unit
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

`ifdef IFACE_SERIAL
  localparam  HALF_SER_PERIOD_PS        = 100;    // 5 GHz: the host divides it to 2.5 GHz at Gen1
  localparam  HALF_PCIE2_PERIOD_PS      = 1_000;  // 500 MHz: the host divides it to 250 MHz at Gen1

  logic       serclk;
  logic       pcieclk2;
  logic       ser_dn;
  logic       ser_up;

  initial begin
    serclk = 1'b0;
    forever begin
      #(HALF_SER_PERIOD_PS) serclk = ~serclk;
    end
  end

  initial begin
    pcieclk2 = 1'b0;
    forever begin
      #(HALF_PCIE2_PERIOD_PS) pcieclk2 = ~pcieclk2;
    end
  end
`endif

`ifdef EP_RTL
  localparam  HALF_BRD_PERIOD_PS        = 50_000; // 10 MHz board clock

  logic       clk_brd;
  logic       link_up;
  logic       fw_pass;

  initial begin
    clk_brd = 1'b0;
    forever begin
      #(HALF_BRD_PERIOD_PS) clk_brd = ~clk_brd;
    end
  end

`ifdef IFACE_SERIAL
  localparam  HALF_REF_PERIOD_PS        = 5_000;  // 100 MHz PCIE REFCLK

  logic       refclk;
  logic       ser_up_n;

  initial begin
    refclk = 1'b0;
    forever begin
      #(HALF_REF_PERIOD_PS) refclk = ~refclk;
    end
  end

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

  top dut
  (
    .clk_brd                           (clk_brd),
    .perst_n                           (rst_n),
    .link_up                           (link_up),
    .fw_pass                           (fw_pass)
  );

  // the SerDes pins are not ports of top (no GateMate netlist reaches them):
  // its nets, by hierarchy
  assign dut.refclk  = refclk;
  assign dut.ser_rxp = ser_dn;
  assign dut.ser_rxn = ser_dn_idle ? ser_dn : ~ser_dn;
  assign ser_up      = dut.ser_txp;
  assign ser_up_n    = dut.ser_txn;
`else
  logic       phy_rdy;

  pipe_if #(.DATA_BYTES(PIPE_DATAWIDTH/8)) pipe_mac ();

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
`endif

  always @(link_up) $display("%t tb: dll_up = %b", $time, link_up);
  always @(fw_pass) $display("%t tb: fw_pass = %b", $time, fw_pass);
`elsif IFACE_SERIAL
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
`else
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
`endif

//--------------------------------------------------------------
// Host: RCPIPEx1__pcieVHost, a pcieVHost in RC mode at VProc node HOST_NODE. Its
// ports are the RC's decoder page of the dump (tb.u_rc): the link at the
// PIPE, Data Link and Transaction layers, under the names WaveCrux
// auto-binds. The EP model has the same, as it sees the link
// (tb.dut.bfm_pcie)
//--------------------------------------------------------------

  // Data Link: RC -> EP TLPs as a DLL hands them to its TL, on pclk; for a
  // TL under test without the MAC and DLL below it (nothing reads them yet)
  logic [PIPE_DATAWIDTH-1:0]           dll_rx_data;
  logic                                dll_rx_tlp_valid;
  logic                                dll_rx_tlp_first;
  logic                                dll_rx_tlp_last;

`ifdef IFACE_SERIAL
  PcieVhostSerial #(
    .LinkWidth                         (1),
    .NodeNum                           (HOST_NODE),
    .EndPoint                          (0),
    .Gen2Clk                           (1)
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
`else
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

    // Transaction: for waveform decoders, read from the dump
    .tx_clk                            (),
    .tx_tlp_data                       (),
    .tx_tlp_sop                        (),
    .tx_tlp_eop                        (),
    .tx_tlp_valid                      (),
    .tx_peer_data                      (),
    .tx_peer_sop                       (),
    .tx_peer_eop                       (),
    .tx_peer_valid                     (),
    .rx_clk                            (),
    .rx_tlp_data                       (),
    .rx_tlp_sop                        (),
    .rx_tlp_eop                        (),
    .rx_tlp_valid                      (),
    .rx_peer_data                      (),
    .rx_peer_sop                       (),
    .rx_peer_eop                       (),
    .rx_peer_valid                     ()
  );
`endif

// Top level fatal task, which can be called from anywhere in verilog code.
// via the `fatal definition in pciedispheader.v. Any data logging, error
// message displays etc., on a fatal, should be placed in here.
task Fatal;
begin
    $fatal(1, "pcieVHost fatal: the RC model's FAIL, or a bad VProc access");
end
endtask

`ifdef IFACE_SERIAL
  // The serial line by direction, under the name the wcx-pcie serial-line
  // decoders bind (line): RC -> EP and EP -> RC
  logic       ser_dn_line;
  logic       ser_up_line;

  assign ser_dn_line = ser_dn;
  assign ser_up_line = ser_up;
`endif

// FST waveform, for WaveCrux and GTKWave (make DUMP=1 run): the signals of
// this level, i.e. the PIPE link both ways, its clocks and reset, and the
// host's ports (u_rc), the decoder page. With EP=rtl, the EP's decoder
// pages instead of the EP model's: its layer boundaries (pcie_core.wavecrux,
// models/ep_wavecrux_view.sv) and the SOC CPU's retired instructions
// (riscv_pcie_soc.cpu_view), in a file of their own
`ifdef DUMP
initial begin
`ifdef EP_RTL
`ifdef IFACE_SERIAL
    $dumpfile("tb_rtl_serial.fst");
`else
    $dumpfile("tb_rtl.fst");
`endif
`elsif IFACE_SERIAL
    $dumpfile("tb_serial.fst");
`else
    $dumpfile("tb.fst");
`endif
    $dumpvars(1, tb);
    $dumpvars(1, tb.u_rc);
`ifdef EP_RTL
`ifdef IFACE_SERIAL
    $dumpvars(2, tb.dut.u_pcie_top.u_core.wavecrux);
    $dumpvars(1, tb.dut.u_pcie_top.u_soc.cpu_view);
`else
    $dumpvars(2, tb.dut.u_core.wavecrux);
    $dumpvars(1, tb.dut.u_soc.cpu_view);
`endif
`elsif IFACE_SERIAL
    $dumpvars(1, tb.dut);
`else
    $dumpvars(1, tb.dut.bfm_pcie);
`endif
end
`endif

endmodule: tb

/*
------------------------------------------------------------------------------
Version History:
------------------------------------------------------------------------------
 2025/08/19 SS: initial creation

*/

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        April 2025
// -----------------------------------------------------------------------------
