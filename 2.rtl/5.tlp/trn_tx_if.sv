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

// TLPs from trn_bridge (the SOC) to the TL, in 64-bit beats, header DW0 in
// [63:32]. Derived from the PCIE_2_1 TRN TX bus (UG477), see trn_compat
interface trn_tx_if
  import trn_pkg::*;
();

  trn_dat_t   dat;  // one beat of a TLP

  logic       sof;  // the first beat of a TLP

  logic       eof;  // the last beat of a TLP

  logic       vld;  // a beat is on dat; it moves when vld & rdy

  logic       rdy;  // the TL takes the beat. Low outside DL_Active,
                    // and between TLPs while a largest TLP would
                    // not fit

  trn_words_t free_words;  // beats the TX buffer can still take, of
                           // 2^TRN_TX_ADDR_W - 1 (511). A beat's place frees
                           // when the TL reads it out for the DLL. trn_bridge
                           // pauses the SOC between TLPs while it is below a
                           // largest TLP (TRN_TLP_MAX_BEATS, 18) plus 4

  modport src(output dat, sof, eof, vld, input rdy, free_words);  // trn_bridge
  modport dst(input dat, sof, eof, vld, output rdy, free_words);  // the TL
  modport mon(input dat, sof, eof, vld, rdy, free_words);  // a monitor
endinterface
// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Nov 5, 2026
// -----------------------------------------------------------------------------
