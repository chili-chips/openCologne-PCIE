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
//   mac_pkg: the constants and types of the MAC, shared with mac_if, the DLL
//   and the core: symbols, ordered sets, the spec counts and the LTSSM states
//   (named, so a waveform viewer shows them).
//==========================================================================

package mac_pkg;


  // TS1/TS2 identifiers (symbols 6 to 15), and as seen with inverted polarity
  typedef enum logic [7:0] {
    TS1_ID     = 8'h4A,  // D10.2
    TS2_ID     = 8'h45,  // D5.2
    TS1_ID_INV = 8'hB5,  // D10.2, inverted polarity
    TS2_ID_INV = 8'hBA   // D5.2, inverted polarity
  } ts_id_e;

  // TS1/TS2 symbol 5: Training Control (spec Table 4-2, 4-3)
  typedef struct packed {
    logic [2:0] rsvd;                // [7:5]
    logic       compliance_receive;  // [4]   TS1 only
    logic       disable_scrambling;  // [3]
    logic       loopback;            // [2]
    logic       disable_link;        // [1]
    logic       hot_reset;           // [0]
  } ts_ctrl_t;

  // A TS1/TS2 ordered set, symbol 0 (COM) in the low byte
  typedef struct packed {
    logic [9:0][7:0] id;     // [127:48] symbols 6 to 15: TS1_ID or TS2_ID
    ts_ctrl_t        ctrl;   // [47:40] symbol 5
    logic [7:0]      rate;   // [39:32] symbol 4: data rate identifier
    logic [7:0]      n_fts;  // [31:24] symbol 3
    logic [7:0]      lane;   // [23:16] symbol 2: Lane number
    logic [7:0]      link;   // [15:8]  symbol 1: Link number
    logic [7:0]      com;    // [7:0]   symbol 0: COM
  } ts_os_t;

  localparam logic [7:0] TS_RATE_2G5 = 8'h02;  // data rate identifier: 2.5 GT/s

  localparam int OS_W = 128;  // a TS1/TS2 ordered set: 16 symbols
  localparam int SKP_INTERVAL = 1180;  // symbol times between SKP ordered sets (4.2.7)

  // Consecutive ordered sets the receiver waits for
  localparam int IDL_MAX_COUNT = 8;
  localparam int TIMEOUT_MAX_COUNT = 2;
  localparam int REC_CFG_MAX_COUNT = 8;
  localparam int REC_IDLE_MAX_COUNT = 2;

  typedef enum logic [4:0] {
    DETECT_QUIET                    = 5'd0,
    DETECT_ACTIVE                   = 5'd1,
    POLLING_ACTIVE                  = 5'd2,
    POLLING_CONFIG                  = 5'd3,
    CONFIG_LINKWIDTH_START          = 5'd4,
    CONFIG_LINKWIDTH_ACCEPT         = 5'd5,
    CONFIG_LANENUM_WAIT             = 5'd6,   // not used for x1 Lane
    CONFIG_LANENUM_ACCEPT           = 5'd7,
    CONFIG_COMPLETE                 = 5'd8,
    CONFIG_IDLE                     = 5'd9,
    L0                              = 5'd10,
    RECOVERY_RCVRLOCK               = 5'd11,
    PRE_CONFIG_LINKWIDTH_START      = 5'd12,
    PRE_CONFIG_LINKWIDTH_ACCEPT     = 5'd13,
    PRE_CONFIG_LANENUM_WAIT         = 5'd14,  // not used for x1 Lane
    PRE_CONFIG_LANENUM_ACCEPT       = 5'd15,
    PRE_CONFIG_COMPLETE             = 5'd16,
    PRE_CONFIG_IDLE                 = 5'd17,
    CONFIG_LINKWIDTH_START_LINKNUM  = 5'd18,
    CONFIG_LINKWIDTH_ACCEPT_LANENUM = 5'd19,
    RECOVERY_RCVRCFG                = 5'd20,
    RECOVERY_IDLE                   = 5'd21,
    PRE_L0                          = 5'd22,
    PRE_RECOVERY_RCVRLOCK           = 5'd23,
    PRE_RECOVERY_RCVRCFG            = 5'd24,
    PRE_RECOVERY_IDLE               = 5'd25,
    PRE_DETECT_ACTIVE               = 5'd26,
    PRE_DETECT_QUIET                = 5'd27,
    PRE_POLLING_CONFIG              = 5'd28,
    PRE_CONFIG_LINKWIDTH_START_CNT  = 5'd29,
    PRE_CONFIG_LINKWIDTH_ACCEPT_CNT = 5'd30
  } ltssm_state_e;

  // Scrambler LFSR: x^16 + x^5 + x^4 + x^3 + 1, seed all ones (PCIe 2.1 4.2.3)
  localparam logic [15:0] SCRAMBLER_POLY = 16'h0039;
  localparam logic [15:0] SCRAMBLER_SEED = 16'hFFFF;

  // The training sequence send_OS sends
  typedef enum logic {
    OS_TS1 = 1'b0,
    OS_TS2 = 1'b1
  } os_type_e;

endpackage

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Nov 3, 2026
// -----------------------------------------------------------------------------
