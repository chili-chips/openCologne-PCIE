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

`timescale 1ns/100fs

module pcie_stack
  import pipe_pkg::*;
#(
   parameter PATTERN_WIDTH     = 128,
   parameter DETECT_TIMEOUT_US = 12000  // the MAC's Detect timeout (12 ms by the spec)
   )
   (
   input  logic                   clk_ref,
   input  logic                   clk_aon,
   input  logic                   clk_cfg,
   input  logic                   reset_n,

   output logic                   o_pclk,
   output logic                   o_link_up,
   output logic             [4:0] o_ltssm_state,
   output logic                   o_serdes_ready,
   output logic                   o_rx_valid,
   output pipe_flags_t o_rx_disp_err,
   output pipe_flags_t o_rx_dec_err,
   output logic                   o_tx_buf_err,

   input  pipe_data_t  tl_tx_data,
   input  logic                   tl_tx_tlp_valid,
   input  logic                   tl_tx_tlp_first,
   input  logic                   tl_tx_tlp_last,
   input  logic                   tl_tx_tlp_last_half,
   output logic                   tl_tx_tlp_ready,
   input  logic             [7:0] tl_tx_hdr_credit,
   input  logic            [11:0] tl_tx_data_credit,
   input  logic             [1:0] tl_tx_update_type,
   input  logic             [1:0] tl_tx_packet_type,
   input  logic                   tl_tx_dllp_valid,

   output pipe_data_t  tl_rx_data,
   output logic                   tl_rx_tlp_valid,
   output logic                   tl_rx_tlp_first,
   output logic                   tl_rx_tlp_last,
   output logic             [7:0] tl_rx_hdr_credit,
   output logic            [11:0] tl_rx_data_credit,
   output logic             [1:0] tl_rx_update_type,
   output logic             [1:0] tl_rx_packet_type,
   output logic                   tl_rx_dllp_valid,

   input  logic                   RX_SERIO_P,
   input  logic                   RX_SERIO_N,
   output logic                   TX_SERIO_P,
   output logic                   TX_SERIO_N
   );

   logic   [7:0] rst_pipe_cnt;
   logic        pipe_reset_n;
   assign pipe_reset_n = (rst_pipe_cnt == 8'hFF);

   always @(posedge clk_aon or negedge reset_n) begin
      if (!reset_n)
         rst_pipe_cnt <= 8'd0;
      else if (!pipe_reset_n)
         rst_pipe_cnt <= rst_pipe_cnt + 8'd1;
   end

   logic   [1:0] mac_rst_sync;
   logic        mac_reset_n;
   assign mac_reset_n = mac_rst_sync[1];

   always @(posedge o_pclk or negedge o_serdes_ready) begin
      if (!o_serdes_ready)
         mac_rst_sync <= 2'b00;
      else
         mac_rst_sync <= {mac_rst_sync[0], 1'b1};
   end

   logic                  phy_rx_valid;
   logic                  phy_status;
   logic            [2:0] phy_rx_status;
   logic                  phy_rx_elec_idle;
   pipe_data_t  phy_rx_data;
   pipe_flags_t phy_rx_datak;

   logic            [1:0] mac_power_down;
   logic                  mac_tx_detect_rx;
   logic                  mac_tx_elec_idle;
   pipe_flags_t mac_tx_compliance;
   logic                  mac_rx_polarity;
   pipe_data_t  mac_tx_data;
   pipe_flags_t mac_tx_datak;
   pipe_data_t  mac_rx_data;
   pipe_flags_t mac_rx_datak;

   pipe_data_t  dll_tx_data;
   pipe_flags_t dll_tx_datak;

   assign o_rx_valid     = phy_rx_valid;
   assign o_ltssm_state = mac.s_fsm_state;

pipe_if pipe ();
mac_if mac2dll ();
dll_if dll2tl ();
assign pipe.reset_n = pipe_reset_n;


   dll_top #(
      .NUMBER_OF_VIRTUAL_CHANNELS ( 1          )
   ) dll (
      .phy_clk           ( o_pclk            ),
      .phy_reset         ( !mac_reset_n      ),
      .mac (mac2dll),
      .tl (dll2tl)

);
   assign dll2tl.tx_tlp.data = tl_tx_data;
   assign dll2tl.tx_tlp.valid = tl_tx_tlp_valid;
   assign dll2tl.tx_tlp.first = tl_tx_tlp_first;
   assign dll2tl.tx_tlp.last = tl_tx_tlp_last;
   assign dll2tl.tx_tlp.half = tl_tx_tlp_last_half;
   assign tl_tx_tlp_ready = dll2tl.tx_tlp_ready;
   assign dll2tl.tx_dllp = {tl_tx_dllp_valid, dll_pkg::dllp_type_e'(tl_tx_packet_type),
                            dll_pkg::fc_class_e'(tl_tx_update_type), tl_tx_hdr_credit, tl_tx_data_credit};
   assign dll_tx_data = mac2dll.tx.data;
   assign dll_tx_datak = mac2dll.tx.kcode;
   assign tl_rx_data = dll2tl.rx_tlp.data;
   assign tl_rx_tlp_valid = dll2tl.rx_tlp.valid;
   assign tl_rx_tlp_first = dll2tl.rx_tlp.first;
   assign tl_rx_tlp_last = dll2tl.rx_tlp.last;
   assign tl_rx_hdr_credit = dll2tl.rx_dllp.cred.hdr;
   assign tl_rx_data_credit = dll2tl.rx_dllp.cred.data;
   assign tl_rx_update_type = dll2tl.rx_dllp.update_type;
   assign tl_rx_packet_type = dll2tl.rx_dllp.packet_type;
   assign tl_rx_dllp_valid = dll2tl.rx_dllp.valid;

   ccfpga_mac_top #(
      .DETECT_TIMEOUT_US ( DETECT_TIMEOUT_US )
   ) mac (
      .i_reset_n      ( mac_reset_n       ),
      .pipe (pipe),
      .mac (mac2dll)

   );
   assign mac_power_down = pipe.power_down;
   assign mac_tx_detect_rx = pipe.tx_detect_rx;
   assign mac_tx_elec_idle = pipe.tx_elec_idle;
   assign mac_tx_compliance = pipe.tx_compliance;
   assign mac_rx_polarity = pipe.rx_polarity;
   assign mac_tx_data = pipe.tx.data;
   assign mac_tx_datak = pipe.tx.kcode;
   assign mac_rx_data = mac2dll.rx.data;
   assign mac_rx_datak = mac2dll.rx.kcode;
   assign o_link_up = mac2dll.link_up;

   phy_model phy (
      .clk_ref           ( clk_ref           ),
      .clk_aon           ( clk_aon           ),
      .clk_cfg           ( clk_cfg           ),
      .reset_n           ( reset_n           ),

      .pipe (pipe),

.o_fsm_state_pipe  (                   ),
      .o_fsm_state_align (                   ),
      .o_rx_comma     (                   ),
      .o_rx_disp_err   ( o_rx_disp_err   ),
      .o_rx_dec_err    ( o_rx_dec_err    ),
      .o_tx_buf_err      ( o_tx_buf_err      ),
      .o_rx_buf_err      (                   ),
      .o_serdes_ready    ( o_serdes_ready    ),

      .RX_SERIO_P        ( RX_SERIO_P        ),
      .RX_SERIO_N        ( RX_SERIO_N        ),
      .TX_SERIO_P        ( TX_SERIO_P        ),
      .TX_SERIO_N        ( TX_SERIO_N        )
   );
   assign o_pclk = pipe.pclk;
   assign phy_rx_valid = pipe.rx_valid;
   assign phy_status = pipe.phy_status;
   assign phy_rx_elec_idle = pipe.rx_elec_idle;
   assign phy_rx_status = pipe.rx_status;
   assign phy_rx_data = pipe.rx.data;
   assign phy_rx_datak = pipe.rx.kcode;

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Oct 13, 2026
// -----------------------------------------------------------------------------
