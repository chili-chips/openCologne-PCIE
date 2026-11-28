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

module tlp_rx_handler
  import tl_pkg::*;
  import dll_pkg::*;
(
    input  logic       clk,
    input  logic       rst_n,
    input  tl_beat_t   rx,
    input  pcie_size_e max_payload_size,
    input  fc_cred_t   p_alloc,
    input  fc_cred_t   np_alloc,
    output tl_qwr_t    p_wr,
    input  logic       p_full,
    output tl_qwr_t    np_wr,
    input  logic       np_full,
    output fc_rel_t    rel,
    output logic       err_malformed,
    output logic       err_overflow
);

  typedef enum logic {
    IDLE,
    RECEIVE
  } state_e;

  hdr_dw01_t   rx_hdr_dw01;

  tlp_kind_e   d_kind;
  tlp_dw_cnt_t d_length_dw;

  tlp_dw_cnt_t mps_dw;
  logic        d_cfg_io;
  logic        d_cfg_io_hdr_bad;
  logic        d_bad_cfg_io;
  logic        d_bad_mps;
  logic        d_bad_msg;

  // a TLP, from its first word on: what the rest of it is checked against
  typedef struct packed {
    logic       known;       // [26]
    fc_class_e  fc_class;    // [25:24]
    tlp_words_t words;       // [23:13] the TLP length in words
    logic       static_bad;  // [12]   a header check failed
    fc_data_t   need_data;   // [11:0] its data credits
  } rx_ctx_t;

  state_e     state;
  rx_ctx_t    d_ctx;  // from the first word's header
  tl_beat_t   rxq;  // the word, a clock later
  rx_ctx_t    d_ctx_q;  // its decode, with it
  rx_ctx_t    ctx_r;  // held for the rest of the TLP
  rx_ctx_t    cur;
  tlp_words_t words_seen_r;
  logic       full_r;

  fc_cred_t   p_recv;
  fc_cred_t   np_recv;

  logic       first_word;
  logic       in_tlp;
  logic       cur_np;
  tlp_words_t cur_seen;
  logic       cur_qfull;

  logic       write;
  logic       last_word;
  logic       full_now;

  fc_cred_t   alloc;
  fc_cred_t   recv;
  fc_cred_t   recv_new;
  logic       past_alloc;
  logic       credit_ovf;

  logic       overflow;
  logic       malformed;
  logic       accept;
  logic       counted;
  logic       drop;

  assign rx_hdr_dw01     = rx.data;

  assign d_kind          = tlp_kind(rx_hdr_dw01.dw0);
  assign d_length_dw     = tlp_length_dw(rx_hdr_dw01.dw0);

  assign d_ctx.known     = d_kind != K_UNKNOWN;
  assign d_ctx.fc_class  = tlp_class(d_kind);
  assign d_ctx.words     = tlp_words(rx_hdr_dw01.dw0);
  assign d_ctx.need_data = tlp_data_credits(rx_hdr_dw01.dw0);

  always_comb begin
    mps_dw = 11'd1024;
    unique0 case (max_payload_size)
      SZ_128B:  mps_dw = 11'd32;
      SZ_256B:  mps_dw = 11'd64;
      SZ_512B:  mps_dw = 11'd128;
      SZ_1024B: mps_dw = 11'd256;
      SZ_2048B: mps_dw = 11'd512;
    endcase
  end

  assign d_cfg_io = (d_kind == K_CFGRD0)
                  | (d_kind == K_CFGWR0)
                  | (d_kind == K_CFGRD1)
                  | (d_kind == K_CFGWR1)
                  | (d_kind == K_IORD)
                  | (d_kind == K_IOWR);

  // a Cfg or I/O request must have TC 0, no attributes, Length 1, Last BE 0
  assign d_cfg_io_hdr_bad = (rx_hdr_dw01.dw0.tc          != 3'd0)
                          | (rx_hdr_dw01.dw0.attr        != 2'd0)
                          | (rx_hdr_dw01.dw0.length      != 10'd1)
                          | (rx_hdr_dw01.dw1.req.last_be != 4'd0);
  assign d_bad_cfg_io = d_cfg_io & d_cfg_io_hdr_bad;
  assign d_bad_mps = tlp_has_data(rx_hdr_dw01.dw0) & (d_kind != K_ATOMIC) & (d_length_dw > mps_dw);
  assign d_bad_msg = (d_kind == K_MSGD)
                   & (rx_hdr_dw01.dw1.msg.msg_code == MSG_SET_SLOT_POWER)
                   & (rx_hdr_dw01.dw0.tc != 3'd0);
  assign d_ctx.static_bad = d_bad_cfg_io | d_bad_mps | d_bad_msg;

  // One register stage in front: the word and its header decode go into
  // flops together, so the credit check, the accept/drop decision and the
  // queue controls below start from flops, not from the decode (the TL's
  // deepest logic, 18 to 21 LUT levels, 2026-11-27)
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rxq     <= '0;
      d_ctx_q <= '0;
    end
    else begin
      rxq <= rx;
      if (rx.valid && rx.first) begin
        d_ctx_q <= d_ctx;
      end
    end
  end

  assign first_word = rxq.valid & rxq.first;
  assign in_tlp = first_word | (state == RECEIVE);
  assign cur = first_word ? d_ctx_q : ctx_r;
  assign cur_np = (cur.fc_class == FC_NP);
  assign cur_seen = first_word ? 11'd1 : words_seen_r + 11'd1;
  assign cur_qfull = cur_np ? np_full : p_full;

  assign write = rxq.valid & in_tlp & cur.known;
  assign last_word = rxq.valid & rxq.last & in_tlp;
  assign full_now = full_r | (write & cur_qfull);

  assign alloc = cur_np ? np_alloc : p_alloc;
  assign recv = cur_np ? np_recv : p_recv;
  assign recv_new.hdr = recv.hdr + 8'd1;
  assign recv_new.data = recv.data + cur.need_data;
  // received past the advertised limit: the distance wraps past half the counter
  assign past_alloc = ((alloc.hdr - recv_new.hdr)   >= FC_HDR_HALF)
                    | ((alloc.data - recv_new.data) >= FC_DATA_HALF);
  assign credit_ovf = (cur.fc_class != FC_CPL) & past_alloc;

  assign overflow = credit_ovf | full_now;
  assign malformed = ~cur.known | (cur_seen != cur.words) | cur.static_bad;
  assign accept = last_word & cur.known & ~overflow & ~malformed;
  assign counted = last_word & cur.known & ~overflow & (cur.fc_class != FC_CPL);
  assign drop = last_word & ~accept;

  assign p_wr.en = write & ~cur_np;
  assign p_wr.drop = drop & ~cur_np;
  assign p_wr.word.last = rxq.last;
  assign p_wr.word.data = rxq.data;

  assign np_wr.en = write & cur_np;
  assign np_wr.drop = drop & cur_np;
  assign np_wr.word.last = rxq.last;
  assign np_wr.word.data = rxq.data;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state        <= IDLE;
      ctx_r        <= '0;
      words_seen_r <= 11'd0;
      full_r       <= 1'b0;
    end
    else if (rxq.valid && in_tlp) begin
      ctx_r        <= cur;
      words_seen_r <= cur_seen;
      full_r       <= full_now & ~rxq.last;
      state        <= rxq.last ? IDLE : RECEIVE;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      p_recv  <= '0;
      np_recv <= '0;
    end
    else if (counted) begin
      if (cur_np) begin
        np_recv <= recv_new;
      end
      else begin
        p_recv <= recv_new;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rel           <= '0;
      err_malformed <= 1'b0;
      err_overflow  <= 1'b0;
    end
    else begin
      rel.valid     <= counted & malformed;
      rel.fc_class  <= cur.fc_class;
      rel.data      <= cur.need_data;
      err_malformed <= last_word & malformed & ~(cur.known & overflow);
      err_overflow  <= last_word & cur.known & overflow;
    end
  end

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Oct 21, 2026
// -----------------------------------------------------------------------------
