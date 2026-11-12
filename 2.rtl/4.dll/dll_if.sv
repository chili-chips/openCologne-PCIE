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
//   dll_if: between the Data Link Layer (dll_top) and the
//   Transaction Layer, on PCLK. Two kinds of traffic cross it:
//
//   - TLPs, in DATA_BYTES-wide beats with first/last flags, and a flag for a
//     last beat that holds only one DW (tx_tlp_last_half). The DLL adds the
//     sequence number and LCRC on the way out and keeps each TLP in its
//     retry buffer until the link partner acknowledges it (tx_tlp_ready low
//     while the buffer is full); on the way in it checks and strips them.
//   - Flow-control credits, as DLLP fields: the TL tells the DLL which
//     InitFC/UpdateFC to send, and the DLL hands over the ones it receives.
//     A TLP may only be sent when the receiver has advertised room for it.
//
//   dl_state is the DLL's state for VC0: DL_Inactive, DL_Init (FC1, FC2),
//   DL_Active. TLPs flow only in DL_Active.
//==========================================================================

interface dll_if;
  import pipe_pkg::*;
  import dll_pkg::*;

  // TL -> DLL: TLPs
  tlp_beat_t tx_tlp;
  logic      tx_tlp_ready;  // DLL -> TL: the retry buffer has room

  fc_dllp_t  tx_dllp;  // TL -> DLL: the flow-control DLLP to send

  // DLL -> TL: TLPs
  tlp_beat_t rx_tlp;

  fc_dllp_t  rx_dllp;  // DLL -> TL: a flow-control DLLP received

  dl_state_e dl_state;  // DLL -> TL

  modport dll(
      input tx_tlp,
      input tx_dllp,
      output tx_tlp_ready, rx_tlp,
      output rx_dllp,
      output dl_state
  );
  modport tl(
      output tx_tlp,
      output tx_dllp,
      input tx_tlp_ready, rx_tlp,
      input rx_dllp,
      input dl_state
  );
endinterface

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Oct 18, 2026
// -----------------------------------------------------------------------------
