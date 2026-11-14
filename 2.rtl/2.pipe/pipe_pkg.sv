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
//   pipe_pkg: the datapath width, the PIPE and SerDes word types, the K
//   codes, and the coded fields of the PIPE (pipe_if), named, so a waveform
//   viewer shows them: the PowerDown states and the RxStatus codes.
//==========================================================================

package pipe_pkg;

  // The datapath: DATA_BYTES symbols per PCLK, for every layer from the PIPE
  // up. 8 (64-bit) is the build and the only width tested; the PIPE also
  // takes 4, 2 and 1 (32, 16, 8 bits): placeholders for later, not built
  localparam int DATA_BYTES = 8;
  localparam int DATA_WIDTH = DATA_BYTES * 8;

  // verilog_format: off  (Verible does not align typedefs)
  typedef logic [DATA_WIDTH-1:0] pipe_data_t;   // a PCLK word
  typedef logic [DATA_BYTES-1:0] pipe_flags_t;  // one bit per symbol: K, comma, errors
  // verilog_format: on

  // A PCLK word with its K flags
  typedef struct packed {
    pipe_data_t  data;   // [71:8]
    pipe_flags_t kcode;  // [7:0]  per symbol: 1 = K (control) symbol
  } pipe_sym_t;
  // verilog_format: off

  // The SerDes word, fixed by the CC_SERDES ports: 64 data bits, one flag per
  // symbol, as SERDES_SLICES PCLK words: 1 (64-bit PIPE), 2, 4 or 8
  localparam int SERDES_SLICES = 8 / DATA_BYTES;

  typedef logic [SERDES_SLICES-1:0][DATA_WIDTH-1:0] serdes_data_t;
  typedef logic [SERDES_SLICES-1:0][DATA_BYTES-1:0] serdes_flags_t;
  // verilog_format: on

  // The SerDes receive word: the symbols and, per symbol, the decoder's flags
  typedef struct packed {
    serdes_data_t  data;      // [95:32]
    serdes_flags_t kcode;     // [31:24] K symbol
    serdes_flags_t comma;     // [23:16] comma symbol
    serdes_flags_t disp_err;  // [15:8] disparity error
    serdes_flags_t dec_err;   // [7:0]  8b/10b decode error (not in table)
  } serdes_rx_t;

  // The SerDes transmit word: the symbols, per symbol K and disparity mode
  typedef struct packed {
    serdes_data_t  data;      // [79:16]
    serdes_flags_t kcode;     // [15:8] K symbol
    serdes_flags_t dispmode;  // [7:0]  disparity mode
  } serdes_tx_t;
  // verilog_format: off
  // verilog_format: on

  // PowerDown[1:0]; we use P0 and P1
  typedef enum logic [1:0] {
    P0  = 2'd0,
    P0S = 2'd1,
    P1  = 2'd2,
    P2  = 2'd3
  } power_state_e;

  // 8b/10b control symbols (K codes), PCIe Base 2.1 table 4-1
  // The K symbols by their 8b/10b name Kx.y: y in bits [7:5], x in [4:0]
  localparam logic [7:0] K28_0 = {3'd0, 5'd28};
  localparam logic [7:0] K28_1 = {3'd1, 5'd28};
  localparam logic [7:0] K28_2 = {3'd2, 5'd28};
  localparam logic [7:0] K28_3 = {3'd3, 5'd28};
  localparam logic [7:0] K28_5 = {3'd5, 5'd28};
  localparam logic [7:0] K23_7 = {3'd7, 5'd23};
  localparam logic [7:0] K27_7 = {3'd7, 5'd27};
  localparam logic [7:0] K29_7 = {3'd7, 5'd29};
  localparam logic [7:0] K30_7 = {3'd7, 5'd30};

  typedef enum logic [7:0] {
    K_SKP = K28_0,  // SKiP, 8'h1C
    K_FTS = K28_1,  // Fast Training Sequence, 8'h3C
    K_SDP = K28_2,  // Start of DLLP, 8'h5C
    K_IDL = K28_3,  // electrical IDLe, 8'h7C
    K_COM = K28_5,  // COMma, 8'hBC
    K_PAD = K23_7,  // PAD, 8'hF7
    K_STP = K27_7,  // Start of TLP, 8'hFB
    K_END = K29_7,  // END, 8'hFD
    K_EDB = K30_7   // EnD-Bad (nullified TLP), 8'hFE
  } k_symbol_e;

  // RxStatus[2:0]; our PHY reports RX_OK, RX_DETECTED,
  // DECODE_ERR and DISP_ERR (2.pipe/README.md)
  typedef enum logic [2:0] {
    RX_OK        = 3'd0,  // P1: receiver not detected
    SKP_ADDED    = 3'd1,
    SKP_REMOVED  = 3'd2,
    RX_DETECTED  = 3'd3,
    DECODE_ERR   = 3'd4,  // 8b/10b decode error, maybe also disparity
    EB_OVERFLOW  = 3'd5,
    EB_UNDERFLOW = 3'd6,
    DISP_ERR     = 3'd7
  } rx_status_e;

  // State of the PIPE FSM (ccfpga_pipe_fsm)
  typedef enum logic [3:0] {
    PS_RESET         = 4'd0,
    PS_P0_NORMAL     = 4'd1,
    PS_P0_LOOP       = 4'd2,
    PS_P0_IDLE       = 4'd3,
    PS_P1_IDLE       = 4'd4,
    PS_P1_DET_START  = 4'd5,
    PS_P1_DET_GOOD   = 4'd6,
    PS_P1_DET_BAD    = 4'd7,
    PS_P1_DET_WAIT   = 4'd8,
    PS_P0_PRE_NORMAL = 4'd9,   // Used for PhyStatus Generation
    PS_P0_PRE_LOOP   = 4'd10,  // Used for PhyStatus Generation
    PS_P0_PRE_IDLE   = 4'd11,  // Used for PhyStatus Generation
    PS_P1_SET_IDLE   = 4'd12,  // Used to wait for Tx Idle
    PS_P1_PRE_IDLE   = 4'd13   // Used for Phystatus Generation
  } pipe_fsm_state_e;

  // State of the word-align FSM (ccfpga_pipe_fsm_word_align)
  typedef enum logic [1:0] {
    WA_WAIT        = 2'd0,
    WA_ALIGN_START = 2'd1,
    WA_COUNT_START = 2'd2,
    WA_RX_VALID    = 2'd3
  } align_state_e;

endpackage

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Nov 3, 2026
// -----------------------------------------------------------------------------
