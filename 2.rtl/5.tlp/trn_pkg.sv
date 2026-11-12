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

// TRN (the transaction interface of the AMD PCIE_2_1 hard macro, UG477 in
// 0.doc/2.rtl) between the TL and trn_bridge: its widths and its DW order.
// TRN carries header DW0 in [63:32]; the TL and AXI-Stream carry it in [31:0].

package trn_pkg;

  // TRN / AXI-Stream widths of this design: declared and sized here, used
  // everywhere else (interface instances and modules)
  localparam int TRN_DATA_W = 64;

  // one beat on trn_tx_if / trn_rx_if
  typedef logic [TRN_DATA_W-1:0] trn_dat_t;

  // TX buffer of the TL: 2^TRN_TX_ADDR_W - 1 beats (511). A beat and its
  // last flag, 65 bits, take one 40K block RAM in SDP mode (512 x 80) at any
  // depth up to 512, so 9 costs no more than a shallower buffer
  localparam int TRN_TX_ADDR_W     = 9;

  // the largest TLP, in beats: a 4-DW header and a 128-byte payload
  // (Max_Payload_Size), 18 beats, 144 bytes
  localparam int TRN_TLP_MAX_BEATS = (4 + 128 / 4) * 32 / TRN_DATA_W;

  // free beats in the TX buffer, 0 to 2^TRN_TX_ADDR_W - 1
  typedef logic [TRN_TX_ADDR_W-1:0] trn_words_t;

  // the largest TLPs that fit in free_words: UG477 tbuf_av, and the SOC's
  // csr.status.phy.tx_buf_avail. 6 bits, as tbuf_av: TRN_TX_ADDR_W up to 10
  function automatic logic [5:0] trn_tlps_fit(input trn_words_t free_words);
    return 6'(free_words / trn_words_t'(TRN_TLP_MAX_BEATS));
  endfunction

  // BAR hit (UG477 rx_bar_hit): a bit per BAR, and the expansion ROM
  typedef struct packed {
    logic       rom;  // [6]
    logic [5:0] bar;  // [5:0] BAR0..5
  } bar_hit_t;

  // TRN <-> TL / AXI-Stream: the two DWs of a word change places
  function automatic trn_dat_t trn_dw_swap(input trn_dat_t d);
    return {d[31:0], d[63:32]};
  endfunction

endpackage

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        April 2025
// -----------------------------------------------------------------------------
