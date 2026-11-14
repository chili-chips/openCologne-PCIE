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

// trn_compat: the TRN interface of the PCIE_2_1 hard block in EP mode
// (UG477, 64-bit, signals active high) on the TL's trn_tx_if / trn_rx_if,
// for user logic written for TRN. Our RTL does not use it: trn_bridge
// connects to the interfaces; the TL test bench goes through it.
//
// Rebuilt here: trn_rsof (an in-packet register, as UG477 Appendix G does
// for AXI4-Stream), trn_rrem and trn_rbar_hit (from the TLP header),
// trn_tbuf_av (the largest TLPs that fit in free_words), trn_lnk_up.
//
// Not supported:
//   - requester / DMA: no tags, Completion Timeout or Unexpected Completion
//     check; the user's requests pass through, their completions come back
//     unchecked;
//   - TX: trn_tsrc_dsc (discontinue), trn_terrfwd (poisoned TLPs), trn_tstr
//     (streaming), trn_tecrc_gen (ECRC); trn_trem is not needed (the TL
//     takes the length from the header). trn_terr_drop, trn_tcfg_req and
//     trn_tcfg_gnt are not ports;
//   - RX: trn_rerrfwd is 0 (a poisoned completion reaches the user
//     unflagged), trn_recrc_err is 0 (no ECRC), trn_rsrc_dsc is 0 (DL_Down
//     resets the user side with the TL's RX side); trn_rnp_ok, trn_rnp_req
//     and trn_rfcp_ret (non-posted throttle) are not ports;
//   - trn_fc_* (credit status) and trn_tdllp_* (user DLLPs) are not ports;
//   - only BAR0 and memory space: trn_rbar_hit is BAR0 for a request, 0 for
//     a completion.
module trn_compat
  import trn_pkg::*;
  import tl_pkg::*;
(
           trn_tx_if.src       trn_tx,         // to the TL
           trn_rx_if.dst       trn_rx,         // from the TL

    input  trn_dat_t           trn_td,
    input  logic               trn_tsof,
    input  logic               trn_teof,
    input  logic               trn_tsrc_rdy,
    output logic               trn_tdst_rdy,
    output logic         [5:0] trn_tbuf_av,
    input  logic               trn_trem,       // not read
    input  logic               trn_tsrc_dsc,   // not supported
    input  logic               trn_terrfwd,    // not supported
    input  logic               trn_tstr,       // not supported
    input  logic               trn_tecrc_gen,  // not supported

    output trn_dat_t           trn_rd,
    output logic               trn_rrem,       // 0: the last beat holds one DW
    output logic               trn_rsof,
    output logic               trn_reof,
    output logic               trn_rsrc_rdy,
    input  logic               trn_rdst_rdy,
    output logic               trn_rsrc_dsc,   // 0
    output logic               trn_rerrfwd,    // 0
    output logic               trn_recrc_err,  // 0
    output bar_hit_t           trn_rbar_hit,

    output logic               trn_lnk_up,
    input  logic               dll_up,         // pcie_core: the data link is up

    input  logic               clk,
    input  logic               rst_n           // core_rst_n: follows dll_up
);

  logic      rx_mid;  // a TLP on TRN RX: first beat taken, eof not yet

  dw0_t      rx_hdr0;  // its header DW0

  dw0_t      rx_beat_dw0;  // DW0 of the beat on trn_rd: TRN holds it in [63:32]

  dw0_t      rx_dw0;  // header DW0 of the TLP on trn_rd

  tlp_kind_e rx_kind;

  // TX: as it is; trn_tbuf_av counts the largest TLPs that fit
  assign trn_tx.dat   = trn_td;
  assign trn_tx.sof   = trn_tsof;
  assign trn_tx.eof   = trn_teof;
  assign trn_tx.vld   = trn_tsrc_rdy;
  assign trn_tdst_rdy = trn_tx.rdy;
  assign trn_tbuf_av  = trn_tlps_fit(trn_tx.free_words);

  // RX: trn_rsof, trn_rrem and trn_rbar_hit from the header
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rx_mid  <= 1'b0;
      rx_hdr0 <= '0;
    end
    else if (trn_rx.vld && trn_rx.rdy) begin
      rx_mid <= !trn_rx.eof;
      if (!rx_mid) begin
        rx_hdr0 <= rx_dw0;
      end
    end
  end

  assign rx_beat_dw0      = dw0_t'(trn_rx.dat[63:32]);
  assign rx_dw0           = rx_mid ? rx_hdr0 : rx_beat_dw0;
  assign rx_kind          = tlp_kind(rx_dw0);

  assign trn_rd           = trn_rx.dat;
  assign trn_rsof         = !rx_mid;
  assign trn_reof         = trn_rx.eof;
  assign trn_rrem         = !(trn_rx.eof & tlp_last_half(rx_dw0));
  assign trn_rsrc_rdy     = trn_rx.vld;
  assign trn_rx.rdy       = trn_rdst_rdy;
  assign trn_rsrc_dsc     = 1'b0;
  assign trn_rerrfwd      = 1'b0;
  assign trn_recrc_err    = 1'b0;
  assign trn_rbar_hit.rom = 1'b0;
  assign trn_rbar_hit.bar = ((rx_kind == K_CPL) | (rx_kind == K_CPLD)) ? 6'b000000 : 6'b000001;

  assign trn_lnk_up       = dll_up;

endmodule
// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Nov 5, 2026
// -----------------------------------------------------------------------------
