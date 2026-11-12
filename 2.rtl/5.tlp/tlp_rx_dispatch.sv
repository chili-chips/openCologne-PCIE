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

module tlp_rx_dispatch
  import tl_pkg::*;
  import trn_pkg::*;
  import dll_pkg::*;
#(
    parameter int BAR0_SIZE_BITS = 12
) (
    input  logic               clk,
    input  logic               rst_n,
    input  tl_qrd_t            p_rd,
    output logic               p_pop,
    input  tl_qrd_t            np_rd,
    input  logic               np_ready,
    output logic               np_pop,
    output tl_app_rx_t         app_rx,
    input  logic               app_rx_ready,
    input  logic               memory_enable,
    input  logic        [31:0] bar0_base,
    output tl_cfg_acc_t        cfg_acc,
    input  logic        [31:0] cfg_rdata,
    output tl_id_t             id,
    output tl_sspl_t           sspl,
    input  logic               cpl_ready,
    output logic               cpl_hold,
    output logic               cpl_req,
    output tl_cpl_t            cpl,
    output fc_rel_t            rel,
    output logic               ev_ur,
    output logic               ev_poisoned
);

  typedef enum logic [2:0] {
    A_APP     = 3'd0,
    A_CFG_RD  = 3'd1,
    A_CFG_WR  = 3'd2,
    A_UR_CPL  = 3'd3,
    A_UR_DROP = 3'd4,
    A_DROP    = 3'd5,
    A_PME     = 3'd6,
    A_SSPL    = 3'd7
  } action_e;

  typedef enum logic {
    IDLE,
    XFER
  } state_e;

  localparam logic [31:0] BAR0_MASK = ~((32'd1 << BAR0_SIZE_BITS) - 32'd1);

  function automatic logic bar0_hit(input hdr_dw23_t addr_hdr_dw23, input logic four_dw,
                                    input logic mem_en, input logic [31:0] base);
    logic [31:0] addr_lo;
    addr_lo = four_dw ? addr_hdr_dw23.dw3.addr_lo : addr_hdr_dw23.dw2.addr_lo;
    return mem_en
         & (!four_dw | (addr_hdr_dw23.dw2.addr_hi == '0))
         & (((addr_lo ^ base) & BAR0_MASK) == 32'h0000_0000);
  endfunction

  function automatic action_e msg_action(input logic [7:0] code, input logic with_data,
                                         input logic poisoned);
    action_e act;
    if (!with_data && code == MSG_PME_TURN_OFF) begin
      act = A_PME;
    end
    else if (with_data && code == MSG_SET_SLOT_POWER) begin
      act = poisoned ? A_UR_DROP : A_SSPL;
    end
    else if (code == MSG_VENDOR_TYPE1 || code == MSG_UNLOCK || code == MSG_PM_ASPM_NAK ||
             (code >= MSG_IGNORED_FIRST && code <= MSG_IGNORED_LAST)) begin
      act = A_DROP;
    end
    else begin
      act = A_UR_DROP;
    end
    return act;
  endfunction

  function automatic action_e tlp_action(input tlp_kind_e kind, input logic poisoned,
                                         input logic bar_hit, input logic func0,
                                         input logic [7:0] code);
    action_e act;
    act = A_UR_CPL;
    unique0 case (kind)
      K_MRD:    act = bar_hit ? A_APP : A_UR_CPL;
      K_MWR:    act = (bar_hit & !poisoned) ? A_APP : A_UR_DROP;
      K_CFGRD0: act = func0 ? A_CFG_RD : A_UR_CPL;
      K_CFGWR0: act = (func0 & !poisoned) ? A_CFG_WR : A_UR_CPL;
      K_MSG:    act = msg_action(code, 1'b0, poisoned);
      K_MSGD:   act = msg_action(code, 1'b1, poisoned);
      K_CPL:    act = A_APP;
      K_CPLD:   act = A_APP;
    endcase
    return act;
  endfunction

  function automatic logic needs_cpl(input action_e act);
    return (act == A_CFG_RD) | (act == A_CFG_WR) | (act == A_UR_CPL) | (act == A_PME);
  endfunction

  function automatic logic action_ready(input action_e act, input logic app_ready,
                                        input logic gen_ready);
    logic ready;
    ready = 1'b1;
    if (act == A_APP) begin
      ready = app_ready;
    end
    else if (needs_cpl(act)) begin
      ready = gen_ready;
    end
    return ready;
  endfunction

  function automatic logic [1:0] be_first_on(input logic [3:0] be);
    logic [1:0] pos;
    pos = 2'd3;
    unique casez (be)
      4'b???1:          pos = 2'd0;
      4'b??10:          pos = 2'd1;
      4'b?100:          pos = 2'd2;
      4'b1000, 4'b0000: pos = 2'd3;
      default:          ;
    endcase
    return pos;
  endfunction

  function automatic logic [1:0] be_last_on(input logic [3:0] be);
    logic [1:0] pos;
    pos = 2'd3;
    unique casez (be)
      4'b1???:          pos = 2'd0;
      4'b01??:          pos = 2'd1;
      4'b001?:          pos = 2'd2;
      4'b0001, 4'b0000: pos = 2'd3;
      default:          ;
    endcase
    return pos;
  endfunction

  hdr_dw01_t                    p_hdr_dw01;
  hdr_dw23_t                    p_hdr_dw23;
  hdr_dw01_t                    np_hdr_dw01;
  hdr_dw23_t                    np_hdr_dw23;

  tlp_kind_e                    p_kind;
  logic                         p_poisoned;
  action_e                      p_act;
  tlp_kind_e                    np_kind;
  logic                         np_poisoned;
  action_e                      np_act;

  state_e                       state;
  logic                         np_go;
  logic                         p_go;

  logic                         sel_np;
  action_e                      act;
  hdr_dw01_t                    cur_hdr_dw01;
  hdr_dw23_t                    cur_hdr_dw23;
  tlp_kind_e                    kind_r;
  fc_class_e                    class_r;
  logic        [          11:0] credits_r;
  logic                         poisoned_r;
  logic                         hdr_4dw_r;


  logic                         cur_valid;
  logic                         cur_last;
  logic        [TRN_DATA_W-1:0] cur_data;
  logic                         to_app;
  logic                         take;
  logic                         finish;

  logic        [          10:0] h_length_dw;
  logic        [           4:0] h_addr_6_2;
  logic        [           1:0] fbe_lo;
  logic        [           1:0] fbe_hi;
  logic        [           1:0] lbe_hi;
  logic        [          11:0] mrd_bytes;
  logic        [           6:0] mrd_lower;
  logic        [          11:0] atomic_bytes;
  hdr_dw23_t                    cur_data_dw23;
  dw_bytes_t                    sspl_dw4;

  logic                         cfg_write;
  logic                         id_capture;

  logic                         cpl_is_msg;
  logic                         cpl_with_data;
  cpl_status_e                  cpl_status;
  logic        [          11:0] cpl_byte_count;
  logic        [           6:0] cpl_lower_addr;
  logic        [          31:0] cpl_data;

  assign p_hdr_dw01 = p_rd.head.data;
  assign p_hdr_dw23 = p_rd.next;
  assign np_hdr_dw01 = np_rd.head.data;
  assign np_hdr_dw23 = np_rd.next;

  assign p_kind = tlp_kind(p_hdr_dw01.dw0);
  assign p_poisoned = p_hdr_dw01.dw0.ep & tlp_has_data(p_hdr_dw01.dw0);
  assign p_act = tlp_action(
      p_kind,
      p_poisoned,
      bar0_hit(
          p_hdr_dw23, tlp_4dw(p_hdr_dw01.dw0), memory_enable, bar0_base
      ),
      p_hdr_dw23.dw2.cfg.id.func == 3'd0,
      p_hdr_dw01.dw1.msg.msg_code
  );

  assign np_kind = tlp_kind(np_hdr_dw01.dw0);
  assign np_poisoned = np_hdr_dw01.dw0.ep & tlp_has_data(np_hdr_dw01.dw0);
  assign np_act = tlp_action(
      np_kind,
      np_poisoned,
      bar0_hit(
          np_hdr_dw23, tlp_4dw(np_hdr_dw01.dw0), memory_enable, bar0_base
      ),
      np_hdr_dw23.dw2.cfg.id.func == 3'd0,
      8'h00
  );

  assign np_go = (state == IDLE)
               & np_rd.avail
               & np_ready
               & action_ready(np_act, app_rx_ready, cpl_ready);
  assign p_go = (state == IDLE)
              & !np_go
              & p_rd.avail
              & action_ready(p_act, app_rx_ready, cpl_ready);

  assign cur_valid = sel_np ? np_rd.valid : p_rd.valid;
  assign cur_last = sel_np ? np_rd.head.last : p_rd.head.last;
  assign cur_data = sel_np ? np_rd.head.data : p_rd.head.data;
  assign to_app = (state == XFER) & (act == A_APP) & cur_valid;
  assign take = (state == XFER) & cur_valid & ((act != A_APP) | app_rx_ready);
  assign finish = take & cur_last;

  assign p_pop = take & !sel_np;
  assign np_pop = take & sel_np;

  assign app_rx.valid = to_app;
  assign app_rx.last = to_app & cur_last;
  assign app_rx.data = cur_data;

  assign cpl_hold = (state == XFER) & needs_cpl(act);


  assign h_length_dw = tlp_length_dw(cur_hdr_dw01.dw0);
  assign h_addr_6_2 = hdr_4dw_r ? cur_hdr_dw23.dw3.addr_lo.addr[4:0] :
                                cur_hdr_dw23.dw2.addr_lo.addr[4:0];

  assign cpl.is_msg = cpl_is_msg;
  assign cpl.with_data = cpl_with_data;
  assign cpl.locked = (kind_r == K_MRDLK);
  assign cpl.tc = cur_hdr_dw01.dw0.tc;
  assign cpl.attr = cur_hdr_dw01.dw0.attr;
  assign cpl.requester_id = cur_hdr_dw01.dw1.req.requester_id;
  assign cpl.tag = cur_hdr_dw01.dw1.req.tag;
  assign cpl.status = cpl_status;
  assign cpl.byte_count = cpl_byte_count;
  assign cpl.lower_addr = cpl_lower_addr;
  assign cpl.data = cpl_data;
  assign cpl.msg_code = MSG_PME_TO_ACK;
  assign cpl.msg_route = MSG_ROUTE_GATHER;

  assign cfg_acc.write = cfg_write;
  assign cfg_acc.regnum = cfg_reg_e'({cur_hdr_dw23.dw2.cfg.ext_reg, cur_hdr_dw23.dw2.cfg.reg_num});
  assign cfg_acc.be = cur_hdr_dw01.dw1.req.first_be;
  assign cfg_acc.wdata = dw_byte_swap(cur_hdr_dw23.dw3.data);
  assign id.capture = id_capture;
  assign id.bus = cur_hdr_dw23.dw2.cfg.id.bus;
  assign id.device = cur_hdr_dw23.dw2.cfg.id.device;

  assign fbe_lo = be_first_on(cur_hdr_dw01.dw1.req.first_be);
  assign fbe_hi = be_last_on(cur_hdr_dw01.dw1.req.first_be);
  assign lbe_hi = be_last_on(cur_hdr_dw01.dw1.req.last_be);

  assign mrd_bytes = (h_length_dw == 11'd1) ?
      ((cur_hdr_dw01.dw1.req.first_be == 4'b0000) ? 12'd1 : 12'd4 - 12'(fbe_lo) - 12'(fbe_hi)) :
      12'({h_length_dw, 2'b00} - 13'(fbe_lo) - 13'(lbe_hi));
  assign mrd_lower = {h_addr_6_2, (cur_hdr_dw01.dw1.req.first_be == 4'b0000) ? 2'd0 : fbe_lo};

  assign atomic_bytes = (cur_hdr_dw01.dw0.tlp_type == TLP_TYPE_CAS) ? {h_length_dw, 1'b0} :
      12'({h_length_dw, 2'b00});

  assign cur_data_dw23 = cur_data;
  assign sspl_dw4 = dw_byte_swap(hdr_4dw_r ? cur_data_dw23.dw2 : cur_hdr_dw23.dw3);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state        <= IDLE;
      sel_np       <= 1'b0;
      act          <= A_DROP;
      cur_hdr_dw01 <= '0;
      cur_hdr_dw23 <= '0;
      kind_r       <= K_UNKNOWN;
      class_r      <= FC_P;
      credits_r    <= 12'd0;
      poisoned_r   <= 1'b0;
      hdr_4dw_r    <= 1'b0;
    end
    else begin
      unique case (state)
        IDLE: begin
          if (np_go) begin
            sel_np       <= 1'b1;
            act          <= np_act;
            cur_hdr_dw01 <= np_hdr_dw01;
            cur_hdr_dw23 <= np_hdr_dw23;
            kind_r       <= np_kind;
            class_r      <= tlp_class(np_kind);
            credits_r    <= tlp_data_credits(np_hdr_dw01.dw0);
            poisoned_r   <= np_poisoned;
            hdr_4dw_r    <= tlp_4dw(np_hdr_dw01.dw0);
            state        <= XFER;
          end
          else if (p_go) begin
            sel_np       <= 1'b0;
            act          <= p_act;
            cur_hdr_dw01 <= p_hdr_dw01;
            cur_hdr_dw23 <= p_hdr_dw23;
            kind_r       <= p_kind;
            class_r      <= tlp_class(p_kind);
            credits_r    <= tlp_data_credits(p_hdr_dw01.dw0);
            poisoned_r   <= p_poisoned;
            hdr_4dw_r    <= tlp_4dw(p_hdr_dw01.dw0);
            state        <= XFER;
          end
        end
        XFER: begin
          if (finish) begin
            state <= IDLE;
          end
        end
        default: ;
      endcase
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cfg_write      <= 1'b0;
      id_capture     <= 1'b0;
      sspl.capture   <= 1'b0;
      sspl.scale     <= 2'b00;
      sspl.value     <= 8'h00;
      cpl_req        <= 1'b0;
      cpl_is_msg     <= 1'b0;
      cpl_with_data  <= 1'b0;
      cpl_status     <= CPL_SC;
      cpl_byte_count <= 12'd0;
      cpl_lower_addr <= 7'd0;
      cpl_data       <= 32'd0;
      rel            <= '0;
      ev_ur          <= 1'b0;
      ev_poisoned    <= 1'b0;
    end
    else begin
      cfg_write    <= 1'b0;
      id_capture   <= np_go & (np_kind == K_CFGWR0) & (np_hdr_dw23.dw2.cfg.id.func == 3'd0);
      sspl.capture <= 1'b0;
      cpl_req      <= 1'b0;
      rel.valid    <= 1'b0;
      ev_ur        <= 1'b0;
      ev_poisoned  <= 1'b0;
      if (finish) begin
        rel.valid    <= (class_r != FC_CPL);
        rel.fc_class <= class_r;
        rel.data     <= credits_r;
        ev_poisoned  <= poisoned_r;
        ev_ur        <= (act == A_UR_DROP);
        unique0 case (act)
          A_CFG_RD: begin
            cpl_req        <= 1'b1;
            cpl_is_msg     <= 1'b0;
            cpl_with_data  <= 1'b1;
            cpl_status     <= CPL_SC;
            cpl_byte_count <= 12'd4;
            cpl_lower_addr <= 7'd0;
            cpl_data       <= cfg_rdata;
          end
          A_CFG_WR: begin
            cfg_write      <= 1'b1;
            cpl_req        <= 1'b1;
            cpl_is_msg     <= 1'b0;
            cpl_with_data  <= 1'b0;
            cpl_status     <= CPL_SC;
            cpl_byte_count <= 12'd4;
            cpl_lower_addr <= 7'd0;
          end
          A_UR_CPL: begin
            cpl_req       <= 1'b1;
            cpl_is_msg    <= 1'b0;
            cpl_with_data <= 1'b0;
            cpl_status    <= CPL_UR;
            if (kind_r == K_MRD || kind_r == K_MRDLK) begin
              cpl_byte_count <= mrd_bytes;
              cpl_lower_addr <= mrd_lower;
            end
            else if (kind_r == K_ATOMIC) begin
              cpl_byte_count <= atomic_bytes;
              cpl_lower_addr <= 7'd0;
            end
            else begin
              cpl_byte_count <= 12'd4;
              cpl_lower_addr <= 7'd0;
            end
          end
          A_PME: begin
            cpl_req       <= 1'b1;
            cpl_is_msg    <= 1'b1;
            cpl_with_data <= 1'b0;
          end
          A_SSPL: begin
            sspl.capture <= 1'b1;
            sspl.value   <= sspl_dw4[0];
            sspl.scale   <= sspl_dw4[1][1:0];
          end
        endcase
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
