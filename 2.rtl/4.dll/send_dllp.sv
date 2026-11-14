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

// Separate sending InitFC logic
module send_dllp
  import pipe_pkg::*;
  import dll_pkg::*;
#(
    localparam int PATTERN_WIDTH = DLLP_W
) (
    input logic clk,
    input logic reset,

    input logic       [2:0] virtual_channel,
    input fc_hdr_t          hdr_credit,
    input fc_data_t         data_credit,
    input fc_class_e        update_type,
    input dllp_type_e       packet_type,

    input seq_num_t nack_sequence_number,  // Sequence number for NAK/ACK DLLP
    // Asserted in the same cycle as packet_avail, deasserted when DLLP is sent
    input logic     ack_trigger,
    input logic     nak_trigger,           //

    input logic packet_avail,  // DLLP available and free to send, deasserted when DLLP is sent

    input logic initfc1_en,   // Sending InitFC1 sequence
    input logic initfc2_en,   // Sending InitFC2 sequence
    input logic initfc1_req,  // Request one InitFC1 set (pulse)
    input logic initfc2_req,  // Request one InitFC2 set (pulse)

    output logic      dllp_initfc1_sent,
    output logic      dllp_initfc2_sent,
    output logic      dllp_sent,
    output pipe_sym_t tx_sym
);


  localparam int NUMBER_OF_STEPS        = PATTERN_WIDTH / DATA_WIDTH - 1;
  // Send all three InitFC at a time
  localparam int INITFC_NUMBER_OF_STEPS = (PATTERN_WIDTH * 3) / DATA_WIDTH - 1;

  dllp_type_byte_t                         dtype;
  dllp_body_t                              body;
  dllp_wire_t                              dllp;
  logic            [  PATTERN_WIDTH/8-1:0] dllp_k;
  logic            [  PATTERN_WIDTH*3-1:0] dllp_initfc1;
  logic            [PATTERN_WIDTH*3/8-1:0] dllp_initfc1_k;
  logic            [  PATTERN_WIDTH*3-1:0] dllp_initfc2;
  logic            [PATTERN_WIDTH*3/8-1:0] dllp_initfc2_k;
  logic            [                 15:0] calc_crc;

  localparam int                       STEP_W           = $clog2(NUMBER_OF_STEPS) + 1;
  localparam int                       INITFC_STEP_W    = $clog2(INITFC_NUMBER_OF_STEPS) + 1;
  localparam logic [       STEP_W-1:0] LAST_STEP        = STEP_W'(NUMBER_OF_STEPS);
  localparam logic [INITFC_STEP_W-1:0] INITFC_LAST_STEP = INITFC_STEP_W'(INITFC_NUMBER_OF_STEPS);
  logic [       STEP_W-1:0] step;
  logic [INITFC_STEP_W-1:0] initfc_step;
  logic                     initfc1_pending;
  logic                     initfc2_pending;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      tx_sym            <= '0;
      step              <= 0;
      initfc_step       <= 0;
      dllp_sent         <= 1'b0;
      dllp_initfc1_sent <= 1'b0;
      dllp_initfc2_sent <= 1'b0;
      initfc1_pending   <= 1'b0;
      initfc2_pending   <= 1'b0;
    end
    else begin
      dllp_sent         <= 1'b0;
      dllp_initfc1_sent <= 1'b0;
      dllp_initfc2_sent <= 1'b0;


      if (dllp_sent) begin
        tx_sym      <= '0;
        step        <= 0;
        initfc_step <= 0;
      end
      else if (packet_avail) begin
        if (step != LAST_STEP) begin
          tx_sym.data  <= dllp[DATA_WIDTH*step+:DATA_WIDTH];
          tx_sym.kcode <= dllp_k[DATA_BYTES*step+:DATA_BYTES];
          step         <= step + 1;
          initfc_step  <= 0;
        end
        else if (step == LAST_STEP) begin
          tx_sym.data  <= dllp[DATA_WIDTH*step+:DATA_WIDTH];
          tx_sym.kcode <= dllp_k[DATA_BYTES*step+:DATA_BYTES];
          dllp_sent    <= 1'b1;
          step         <= 0;
          initfc_step  <= 0;
        end
      end
      else if (initfc1_pending) begin
        if (initfc_step != INITFC_LAST_STEP) begin
          tx_sym.data  <= dllp_initfc1[DATA_WIDTH*initfc_step+:DATA_WIDTH];
          tx_sym.kcode <= dllp_initfc1_k[DATA_BYTES*initfc_step+:DATA_BYTES];
          initfc_step  <= initfc_step + 1;
          step         <= 0;
        end
        else if (initfc_step == INITFC_LAST_STEP) begin
          tx_sym.data       <= dllp_initfc1[DATA_WIDTH*initfc_step+:DATA_WIDTH];
          tx_sym.kcode      <= dllp_initfc1_k[DATA_BYTES*initfc_step+:DATA_BYTES];
          dllp_initfc1_sent <= 1'b1;
          initfc1_pending   <= 1'b0;
          initfc_step       <= 0;
          step              <= 0;
        end
      end
      else if (initfc2_pending) begin
        if (initfc_step != INITFC_LAST_STEP) begin
          tx_sym.data  <= dllp_initfc2[DATA_WIDTH*initfc_step+:DATA_WIDTH];
          tx_sym.kcode <= dllp_initfc2_k[DATA_BYTES*initfc_step+:DATA_BYTES];
          initfc_step  <= initfc_step + 1;
          step         <= 0;
        end
        else if (initfc_step == INITFC_LAST_STEP) begin
          tx_sym.data       <= dllp_initfc2[DATA_WIDTH*initfc_step+:DATA_WIDTH];
          tx_sym.kcode      <= dllp_initfc2_k[DATA_BYTES*initfc_step+:DATA_BYTES];
          dllp_initfc2_sent <= 1'b1;
          initfc2_pending   <= 1'b0;
          initfc_step       <= 0;
          step              <= 0;
        end
      end
      else begin
        tx_sym      <= '0;
        step        <= 0;
        initfc_step <= 0;
      end

      if (!initfc1_en) begin
        initfc1_pending <= 1'b0;
      end
      else if (initfc1_req) begin
        initfc1_pending <= 1'b1;
      end

      if (!initfc2_en) begin
        initfc2_pending <= 1'b0;
      end
      else if (initfc2_req) begin
        initfc2_pending <= 1'b1;
      end
    end
  end

  crc_gen u_crc (
      .crc_en  (1'b1),
      .data_in ({body, dtype}),

      .calc_crc (calc_crc)
  );

  // Ack and Nak: Type 0000_0000 and 0001_0000, the sequence number in bytes
  // 2 and 3; InitFC and UpdateFC: Type, VC, HdrFC and DataFC
  always_comb begin
    dtype = '0;
    body  = '0;
    if (ack_trigger || nak_trigger) begin
      dtype.packet_type       = DLLP_OTHER;
      dtype.update_type.other = DLLP_ACK;
      if (!ack_trigger) begin
        dtype.update_type.other = DLLP_NAK;
      end
      body.acknak.seq_hi = nack_sequence_number[11:8];
      body.acknak.seq_lo = nack_sequence_number[7:0];
    end
    else begin
      dtype.packet_type    = packet_type;
      dtype.update_type.fc = update_type;
      dtype.vc             = virtual_channel;
      body.fc.hdrfc_hi     = hdr_credit[7:2];
      body.fc.hdrfc_lo     = hdr_credit[1:0];
      body.fc.datafc_hi    = data_credit[11:8];
      body.fc.datafc_lo    = data_credit[7:0];
    end
  end
  assign dllp   = {K_END, calc_crc, body, dtype, K_SDP};
  assign dllp_k = DLLP_K;
  // DLLP CRC as crc_gen computes it, for the InitFC DLLPs at elaboration
  function automatic logic [15:0] dllp_crc(input logic [31:0] d);
    integer        i;
    logic   [15:0] c;
    begin
      c = DLLP_CRC_SEED;
      for (i = 0; i < 32; i = i + 1) begin
        c = {c[14:0], 1'b0} ^ ((c[15] ^ d[i]) ? DLLP_CRC_POLY : 16'h0000);
      end
      for (i = 0; i < 8; i = i + 1) begin
        dllp_crc[i]   = ~c[15-i];
        dllp_crc[8+i] = ~c[7-i];
      end
    end
  endfunction

  // An InitFC DLLP (VC0) of type t and class c with credits h/d
  function automatic logic [63:0] initfc(input dllp_type_e t, input fc_class_e c, input fc_hdr_t h,
                                         input fc_data_t d);
    dllp_type_byte_t ty;
    dllp_fc_body_t   b;
    ty                = '0;
    ty.packet_type    = t;
    ty.update_type.fc = c;
    b                 = '0;
    b.hdrfc_hi        = h[7:2];
    b.hdrfc_lo        = h[1:0];
    b.datafc_hi       = d[11:8];
    b.datafc_lo       = d[7:0];
    return {K_END, dllp_crc({b, ty}), b, ty, K_SDP};
  endfunction

  assign dllp_initfc1 = {
    initfc(DLLP_INITFC1, FC_CPL, INIT_CPLH, INIT_CPLD),
    initfc(DLLP_INITFC1, FC_NP, INIT_NPH, INIT_NPD),
    initfc(DLLP_INITFC1, FC_P, INIT_PH, INIT_PD)
  };
  assign dllp_initfc1_k = {3{DLLP_K}};
  assign dllp_initfc2 = {
    initfc(DLLP_INITFC2, FC_CPL, INIT_CPLH, INIT_CPLD),
    initfc(DLLP_INITFC2, FC_NP, INIT_NPH, INIT_NPD),
    initfc(DLLP_INITFC2, FC_P, INIT_PH, INIT_PD)
  };
  assign dllp_initfc2_k = {3{DLLP_K}};

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Jul 11, 2026
// -----------------------------------------------------------------------------
