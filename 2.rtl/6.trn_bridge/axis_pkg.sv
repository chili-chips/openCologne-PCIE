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

// AXI-Stream sideband of the SOC <-> pcie_core streams (axis_if tuser), as
// the AMD PCIE_2_1 AXI interface defines it (UG477 tables 2-9, 2-10).

package axis_pkg;

  import trn_pkg::*;  // bar_hit_t

  // tkeep of a 64-bit beat: both DWs, or only DW0 in [31:0]
  localparam logic [7:0] KEEP_ALL = 8'hFF;
  localparam logic [7:0] KEEP_LO  = 8'h0F;

  // s_axis_tx_tuser (UG477 table 2-9)
  typedef struct packed {
    logic src_dsc;   // [3]   source discontinue
    logic str;       // [2]   streamed
    logic err_fwd;   // [1]   error forward (poison)
    logic ecrc_gen;  // [0]   generate ECRC: ignored, the TL has no ECRC
  } tx_tuser_t;

  // m_axis_rx_tuser on the 64-bit interface (UG477 table 2-10); bits [21:10]
  // (is_sof, is_eof) exist on the 128-bit interface only -- on 64 bits the
  // end of a packet is tlast. trn_rx drives it 0: the SOC does not read it
  typedef struct packed {
    logic     rsvd;      // [9]
    bar_hit_t bar_hit;   // [8:2]
    logic     err_fwd;   // [1]
    logic     ecrc_err;  // [0]
  } rx_tuser_t;

endpackage

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        April 2025
// -----------------------------------------------------------------------------
