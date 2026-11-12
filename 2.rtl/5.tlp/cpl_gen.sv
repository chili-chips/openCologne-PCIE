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

module cpl_gen
  import tl_pkg::*;
  import dll_pkg::*;
(
    input  logic     clk,
    input  logic     rst_n,
    input  pcie_id_t own_id,
    input  logic     cpl_req,
    input  tl_cpl_t  cpl,
    input  logic     cpl_hold,
    output logic     cpl_ready,
    input  logic     msg_nonfatal,
    input  logic     msg_fatal,
    output tl_src_t  src,
    input  logic     src_ready
);

  typedef enum logic [1:0] {
    IDLE  = 2'd0,
    WORD0 = 2'd1,
    WORD1 = 2'd2
  } state_e;

  state_e    state;
  hdr_dw01_t word0_hdr_dw01;
  hdr_dw23_t word1_hdr_dw23;
  logic      half;
  fc_class_e src_class;
  fc_data_t  src_credits;
  logic      pending_nonfatal;
  logic      pending_fatal;

  logic      pending;
  logic      start_cpl;
  logic      start_msg;

  dw0_t      cpl_dw0;
  dw1_cpl_t  cpl_dw1;
  dw2_cpl_t  cpl_dw2;
  dw0_t      msg_dw0;
  dw1_msg_t  msg_dw1;

  assign pending          = pending_nonfatal | pending_fatal;
  assign start_cpl        = (state == IDLE) & cpl_req;
  assign start_msg        = (state == IDLE) & !cpl_req & !cpl_hold & pending;

  assign cpl_ready        = (state == IDLE) & !cpl_req;
  assign src.valid        = (state == WORD0) | (state == WORD1);
  assign src.first        = (state == WORD0);
  assign src.last         = (state == WORD1);
  assign src.half         = half;
  assign src.fc_class     = src_class;
  assign src.data_credits = src_credits;
  assign src.data         = (state == WORD1) ? word1_hdr_dw23 : word0_hdr_dw01;

  always_comb begin
    cpl_dw0 = '0;
    cpl_dw0.fmt = cpl.with_data ? TLP_FMT_3DW_DATA : TLP_FMT_3DW;
    cpl_dw0.tlp_type = cpl.locked ? TLP_TYPE_CPL_LK : TLP_TYPE_CPL;
    cpl_dw0.tc = cpl.tc;
    cpl_dw0.attr = cpl.attr;
    cpl_dw0.length = cpl.with_data ? 10'd1 : 10'd0;

    cpl_dw1 = '0;
    cpl_dw1.completer_id = own_id;
    cpl_dw1.cpl_status = cpl.status;
    cpl_dw1.byte_count = cpl.byte_count;

    cpl_dw2 = '0;
    cpl_dw2.requester_id = cpl.requester_id;
    cpl_dw2.tag = cpl.tag;
    cpl_dw2.lower_addr = cpl.lower_addr;

    msg_dw0 = '0;
    msg_dw0.fmt = TLP_FMT_4DW;
    msg_dw0.tlp_type = tlp_type_e'({TLP_TYPE_MSG, cpl_req ? cpl.msg_route : MSG_ROUTE_TO_RC});

    msg_dw1 = '0;
    msg_dw1.requester_id = own_id;
    msg_dw1.msg_code = cpl_req ? cpl.msg_code : (pending_fatal ? MSG_ERR_FATAL : MSG_ERR_NONFATAL);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state          <= IDLE;
      word0_hdr_dw01 <= '0;
      word1_hdr_dw23 <= '0;
      half           <= 1'b0;
      src_class      <= FC_CPL;
      src_credits    <= 12'd0;
    end
    else begin
      unique case (state)
        IDLE: begin
          if (start_cpl && !cpl.is_msg) begin
            word0_hdr_dw01.dw1.cpl  <= cpl_dw1;
            word0_hdr_dw01.dw0      <= cpl_dw0;
            word1_hdr_dw23.dw3.data <= cpl.with_data ? dw_byte_swap(cpl.data) : 32'h0000_0000;
            word1_hdr_dw23.dw2.cpl  <= cpl_dw2;
            half                    <= !cpl.with_data;
            src_class               <= FC_CPL;
            src_credits             <= cpl.with_data ? 12'd1 : 12'd0;
            state                   <= WORD0;
          end
          else if (start_cpl || start_msg) begin
            word0_hdr_dw01.dw1.msg <= msg_dw1;
            word0_hdr_dw01.dw0     <= msg_dw0;
            word1_hdr_dw23         <= '0;
            half                   <= 1'b0;
            src_class              <= FC_P;
            src_credits            <= 12'd0;
            state                  <= WORD0;
          end
        end
        WORD0: begin
          if (src_ready) begin
            state <= WORD1;
          end
        end
        WORD1: begin
          if (src_ready) begin
            state <= IDLE;
          end
        end
        default: ;
      endcase
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pending_nonfatal <= 1'b0;
      pending_fatal    <= 1'b0;
    end
    else begin
      if (msg_nonfatal) begin
        pending_nonfatal <= 1'b1;
      end
      else if (start_msg && !pending_fatal) begin
        pending_nonfatal <= 1'b0;
      end
      if (msg_fatal) begin
        pending_fatal <= 1'b1;
      end
      else if (start_msg) begin
        pending_fatal <= 1'b0;
      end
    end
  end

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Oct 21, 2026
// -----------------------------------------------------------------------------
