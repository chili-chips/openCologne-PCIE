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
//   dll_pkg: the constants and types of the Data Link Layer, shared by its
//   modules, dll_if and the Transaction Layer (tl_pkg imports it).
//==========================================================================

package dll_pkg;

  import pipe_pkg::*;  // pipe_data_t


  // A framed DLLP: SDP, 4 bytes, 16-bit CRC, END
  localparam int DLLP_W     = 64;
  localparam int DLLP_CRC_W = 16;
  localparam int LCRC_W     = 32;  // a TLP's LCRC

  // Data Link Control and Management State Machine (DLCMSM)
  typedef enum logic [2:0] {
    DL_INACTIVE = 3'd0,
    DL_INITFC1  = 3'd1,
    DL_INITFC2  = 3'd2,
    DL_ACTIVE   = 3'd3
  } dl_state_e;

  // DLLP Type[7:6]: the flow-control DLLPs, and the rest
  typedef enum logic [1:0] {
    DLLP_OTHER    = 2'd0,  // Ack, Nak, PM, vendor: Type[5:4] tells them apart
    DLLP_INITFC1  = 2'd1,
    DLLP_UPDATEFC = 2'd2,
    DLLP_INITFC2  = 2'd3
  } dllp_type_e;

  // Flow-control credits: header and data, as in InitFC and UpdateFC
  typedef logic [7:0] fc_hdr_t;
  typedef logic [11:0] fc_data_t;

  // A TLP beat between the TL and the DLL: one word and its place in the TLP
  typedef struct packed {
    logic       valid;  // [67]
    logic       first;  // [66]
    logic       last;   // [65]
    logic       half;   // [64]   last word is one DW (TX). Unused: RX always 0, TL never reads it
    pipe_data_t data;   // [63:0]
  } tlp_beat_t;

  // A TLP's sequence number (12 bits)
  typedef logic [11:0] seq_num_t;

  // Half the sequence number space: a number is ahead of another when their
  // distance mod 4096 is 1 .. SEQ_HALF (PCIe 2.1 3.5.2.1)
  localparam seq_num_t        SEQ_HALF      = 12'd2048;

  // Half the credit counter spaces: the limit checks of PCIe 2.1 2.6.1
  localparam fc_hdr_t         FC_HDR_HALF   = 8'd128;
  localparam fc_data_t        FC_DATA_HALF  = 12'd2048;

  // DLLP CRC: x^16 + x^12 + x^3 + x + 1, seed all ones (PCIe 2.1 3.5.2.2)
  localparam logic     [15:0] DLLP_CRC_POLY = 16'h100B;
  localparam logic     [15:0] DLLP_CRC_SEED = 16'hFFFF;

  // The K flags of a DLLP's 8 symbols: SDP first, END last
  localparam logic     [ 7:0] DLLP_K        = 8'b1000_0001;

  // The LCRC in wire byte order: its byte 0, lcrc[31:24], in [7:0]
  function automatic logic [31:0] lcrc_wire(input logic [31:0] lcrc);
    return {lcrc[7:0], lcrc[15:8], lcrc[23:16], lcrc[31:24]};
  endfunction

  // The sequence number field of a TLP, as received: 4 reserved bits, then
  // the number. The LCRC covers the reserved bits too (PCIe 2.1 3.5.2.1)
  typedef struct packed {
    logic [3:0] rsvd;  // [15:12]
    seq_num_t   num;   // [11:0]
  } tlp_seq_t;

  // A TLP on the wire starts with STP and its sequence number, byte 0 (STP)
  // first; the sequence number is MSB first, so it comes in two parts
  typedef struct packed {
    logic [7:0] seq_lo;  // [23:16] byte 2: sequence number [7:0]
    logic [3:0] rsvd;    // [15:12] byte 1
    logic [3:0] seq_hi;  // [11:8] byte 1: sequence number [11:8]
    logic [7:0] stp;     // [7:0]  byte 0: STP
  } tlp_prefix_t;

  localparam int       TLP_PREFIX_BYTES = $bits(tlp_prefix_t) / 8;

  // The credits InitFC1 and InitFC2 advertise: the TL's receive buffers, used by
  // the DLL (InitFC) and the TL (flow control); 0 = infinite
  localparam fc_hdr_t  INIT_PH          = 8'd8;
  localparam fc_data_t INIT_PD          = 12'd32;

  localparam fc_hdr_t  INIT_NPH         = 8'd8;
  localparam fc_data_t INIT_NPD         = 12'd8;

  localparam fc_hdr_t  INIT_CPLH        = 8'd0;
  localparam fc_data_t INIT_CPLD        = 12'd0;

  // Flow-control credit class
  typedef enum logic [1:0] {
    FC_P    = 2'd0,
    FC_NP   = 2'd1,
    FC_CPL  = 2'd2,
    FC_RSVD = 2'd3   // reserved: not a credit class
  } fc_class_e;

  // The other DLLPs: Type bits [5:4] when packet_type is DLLP_OTHER
  typedef enum logic [1:0] {
    DLLP_ACK    = 2'd0,  // 0000_0000
    DLLP_NAK    = 2'd1,  // 0001_0000
    DLLP_PM     = 2'd2,  // 0010_0xxx
    DLLP_VENDOR = 2'd3   // 0011_0000
  } dllp_other_e;

  // Type bits [5:4]: the credit class of an FC DLLP, or which other DLLP
  typedef union packed {
    fc_class_e   fc;     // [1:0]
    dllp_other_e other;  // [1:0]
  } dllp_sub_t;

  // Credits, as InitFC and UpdateFC carry them
  typedef struct packed {
    fc_hdr_t  hdr;   // [19:12]
    fc_data_t data;  // [11:0]
  } fc_cred_t;

  // A flow-control DLLP between the DLL and the TL
  typedef struct packed {
    logic       valid;        // [24]
    dllp_type_e packet_type;  // [23:22]
    fc_class_e  update_type;  // [21:20]
    fc_cred_t   cred;         // [19:0]
  } fc_dllp_t;

  // A DLLP on the wire, as the 8 symbols the MAC moves: byte 0 (Type) first.
  // Bytes go out byte 0 first but a field is MSB first within its bytes, so
  // HdrFC, DataFC and the Ack/Nak sequence number come in two parts
  typedef struct packed {
    dllp_type_e packet_type;  // [7:6]
    dllp_sub_t  update_type;  // [5:4]
    logic       rsvd0;        // [3]
    logic [2:0] vc;           // [2:0]
  } dllp_type_byte_t;

  typedef struct packed {
    logic [7:0] datafc_lo;  // [23:16] byte 3: DataFC[7:0]
    logic [1:0] hdrfc_lo;   // [15:14] byte 2: HdrFC[1:0]
    logic [1:0] rsvd1;      // [13:12]
    logic [3:0] datafc_hi;  // [11:8] byte 2: DataFC[11:8]
    logic [1:0] rsvd0;      // [7:6]
    logic [5:0] hdrfc_hi;   // [5:0]  byte 1: HdrFC[7:2]
  } dllp_fc_body_t;

  typedef struct packed {
    logic [7:0] seq_lo;  // [23:16] byte 3: sequence number [7:0]
    logic [3:0] rsvd1;   // [15:12]
    logic [3:0] seq_hi;  // [11:8] byte 2: sequence number [11:8]
    logic [7:0] rsvd0;   // [7:0]  byte 1
  } dllp_acknak_body_t;

  typedef union packed {
    dllp_fc_body_t     fc;      // [23:0] InitFC, UpdateFC
    dllp_acknak_body_t acknak;  // [23:0] Ack, Nak
  } dllp_body_t;

  typedef struct packed {
    logic [7:0]      end_k;  // [63:56] END
    logic [15:0]     crc;    // [55:40]
    dllp_body_t      body;   // [39:16] bytes 1..3
    dllp_type_byte_t dtype;  // [15:8] byte 0
    logic [7:0]      sdp;    // [7:0]  SDP
  } dllp_wire_t;

endpackage

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Nov 3, 2026
// -----------------------------------------------------------------------------
