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
//   tl_top: the Transaction Layer. The TL sits
//   between the DLL (dll_if) and trn_bridge. Its user interface is derived
//   from that of the AMD PCIE_2_1 hard block in EP mode (UG477): TLPs on
//   trn_tx_if / trn_rx_if (the TRN bus, cut to what we use; trn_compat maps
//   it back), and the cfg sideband. trn_bridge, as on openPCIE, turns them
//   into the two AXI-Stream streams of the SOC. Its job:
//
//   - flow control: send UpdateFC credits to the DLL, and hold a
//     TLP back until the link partner has advertised room for it;
//   - the configuration space: answer Configuration Requests itself (Vendor
//     and Device ID, BAR0, the capability list), and capture the bus, device
//     and function number the host assigns (cfg);
//   - the rest: hand Memory Requests to the SOC on TRN RX, and send its
//     Completions from TRN TX. A TX TLP waits in a buffer of
//     2^TRN_TX_ADDR_W - 1 beats until it can go; trn_tx.free_words is its
//     free space, and trn_bridge throttles the SOC on it, as on PCIE_2_1
//     with tbuf_av. A TLP the TL has begun to take is taken whole, and
//     trn_tx.rdy drops between TLPs while a largest TLP would not fit.
//     DL_Down resets the TL's RX side, trn_bridge and the SOC on the same
//     edge, so no TLP is cut short on TRN RX.
//==========================================================================

module tl_top
  import tl_pkg::*;
  import trn_pkg::*;
  import dll_pkg::*;
#(
    parameter logic  [15:0] VENDOR_ID        = PCIE_VENDOR_ID,
    parameter logic  [15:0] DEVICE_ID        = PCIE_DEVICE_ID,
    parameter logic  [ 7:0] REVISION_ID      = 8'h00,
    parameter logic  [23:0] CLASS_CODE       = 24'hFF0000,
    parameter logic  [15:0] SUBSYS_VENDOR_ID = PCIE_SUBSYS_VENDOR_ID,
    parameter logic  [15:0] SUBSYS_ID        = PCIE_SUBSYS_ID,
    parameter int           BAR0_SIZE_BITS   = 12,
    parameter int           P_ADDR_W         = 7,
    parameter int           NP_ADDR_W        = 6,
    parameter aspm_e        ASPM_SUPPORT     = ASPM_L0S,
    parameter logic  [ 2:0] L0S_EXIT_LATENCY = 3'd7,
    parameter logic  [ 2:0] L1_EXIT_LATENCY  = 3'd7,
    // 64 ns, below our L0s exit latency: hosts that check it keep ASPM L0s off (no L0s in the MAC)
    parameter logic  [ 2:0] L0S_ACCEPT_LAT   = 3'd0,
    parameter logic  [ 2:0] L1_ACCEPT_LAT    = 3'd7,
    parameter logic         SLOT_CLOCK       = 1'b1
) (
    input  logic         clk,     // PCLK
    input  logic         rst_n,   // mac_rst_n: the TL resets its parts on DL_Down

           dll_if.tl     dll,

           trn_tx_if.dst trn_tx,  // TLPs from trn_bridge
           trn_rx_if.src trn_rx,  // TLPs to trn_bridge

           cfg_if.core   cfg      // status sideband to the SOC
);


  logic               dl_up;
  logic               dl_inactive;

  tl_beat_t           rx;
  tl_beat_t           tx;

  tl_qwr_t            app_q_wr;
  tl_qrd_t            app_q_rd;
  trn_words_t         app_q_free;
  trn_words_t         app_q_free_next;
  logic               app_q_mid;
  logic               app_q_mid_next;
  logic               tx_room;
  tl_beat_t           app_tx;
  logic               app_tx_ready;
  logic               app_tx_mid;
  tl_app_rx_t         app_rx;

  tl_qwr_t            p_wr;
  tl_qwr_t            np_wr;
  logic               p_full;
  logic               np_full;
  logic               p_commit;
  logic               np_commit;
  logic               p_pop;
  logic               np_pop;
  tl_qrd_t            p_rd;
  tl_qrd_t            np_rd;
  logic               p_done;
  logic               np_done;
  logic               np_ready;

  fc_cred_t           p_alloc;
  fc_cred_t           np_alloc;
  fc_rel_t            rx_rel;
  fc_rel_t            dp_rel;
  fc_rel_t            consume;
  fc_tx_t      [ 2:0] tx_fc;
  tl_err_t            err;
  tl_cfg_acc_t        cfg_acc;
  logic        [31:0] cfg_rdata;
  tl_id_t             id;
  tl_sspl_t           sspl;
  tl_cfg_t            tl_cfg;
  logic               msg_nonfatal;
  logic               msg_fatal;

  logic               cpl_ready;
  logic               cpl_hold;
  logic               cpl_req;
  tl_cpl_t            cpl;
  tl_src_t            int_src;
  logic               int_ready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dl_up       <= 1'b0;
      dl_inactive <= 1'b1;
      trn_tx.rdy  <= 1'b0;
    end
    else begin
      dl_up       <= (dll.dl_state == DL_INITFC2) | (dll.dl_state == DL_ACTIVE);
      dl_inactive <= (dll.dl_state == DL_INACTIVE);
      trn_tx.rdy  <= (dll.dl_state == DL_ACTIVE) & tx_room;
    end
  end

  assign rx.valid           = dll.rx_tlp.valid;
  assign rx.first           = dll.rx_tlp.first;
  assign rx.last            = dll.rx_tlp.last;
  assign rx.data            = wire_byte_swap(dll.rx_tlp.data);

  assign dll.tx_tlp.data    = wire_byte_swap(tx.data);
  assign dll.tx_tlp.valid   = tx.valid;
  assign dll.tx_tlp.first   = tx.first;
  assign dll.tx_tlp.last    = tx.last;

  assign app_q_wr.en        = trn_tx.vld & trn_tx.rdy;
  assign app_q_wr.drop      = 1'b0;
  assign app_q_wr.word.last = trn_tx.eof;
  assign app_q_wr.word.data = trn_dw_swap(trn_tx.dat);

  // room for a whole TLP at its first beat: free after this clock's write,
  // without the beats the queue reads out (an underestimate, never over)
  assign app_q_mid_next     = app_q_wr.en ? !trn_tx.eof : app_q_mid;
  assign app_q_free_next    = app_q_free - trn_words_t'(app_q_wr.en);
  assign tx_room            = app_q_mid_next | (app_q_free_next >= trn_words_t'(TRN_TLP_MAX_BEATS));

  always_ff @(posedge clk or negedge dl_up) begin
    if (!dl_up) begin
      app_q_mid <= 1'b0;
    end
    else begin
      app_q_mid <= app_q_mid_next;
    end
  end

  assign trn_tx.free_words = app_q_free;

  always_ff @(posedge clk or negedge dl_up) begin
    if (!dl_up) begin
      app_tx_mid <= 1'b0;
    end
    else if (app_tx.valid && app_tx_ready) begin
      app_tx_mid <= !app_tx.last;
    end
  end

  assign app_tx.valid      = app_tx_mid ? app_q_rd.valid : app_q_rd.avail;
  assign app_tx.first      = !app_tx_mid;
  assign app_tx.last       = app_q_rd.head.last;
  assign app_tx.data       = app_q_rd.head.data;

  assign trn_rx.dat        = trn_dw_swap(app_rx.data);
  assign trn_rx.eof        = app_rx.last;
  assign trn_rx.vld        = app_rx.valid;

  assign cfg.msg_err_fatal = 1'b0;
  assign cfg.tx_buf_avail  = trn_tlps_fit(trn_tx.free_words);
  assign cfg.id.bus        = tl_cfg.bus_number;
  assign cfg.id.device     = tl_cfg.device_number;
  assign cfg.id.func       = 3'd0;

  tlp_rx_handler u_rx_handler (
      .clk              (clk),
      .rst_n            (dl_up),
      .rx               (rx),
      .max_payload_size (tl_cfg.max_payload_size),
      .p_alloc          (p_alloc),
      .np_alloc         (np_alloc),
      .p_wr             (p_wr),
      .p_full           (p_full),
      .np_wr            (np_wr),
      .np_full          (np_full),
      .rel              (rx_rel),
      .err_malformed    (err.malformed),
      .err_overflow     (err.overflow)
  );

  tlp_queue #(
      .ADDR_W (P_ADDR_W)
  ) u_p_queue (
      .clk     (clk),
      .rst_n   (dl_up),
      .wr      (p_wr),
      .wr_full (p_full),
      .free    (  /*LINT:OK*/),
      .commit  (p_commit),
      .pop     (p_pop),
      .rd      (p_rd),
      .done    (p_done)
  );

  tlp_queue #(
      .ADDR_W (NP_ADDR_W)
  ) u_np_queue (
      .clk     (clk),
      .rst_n   (dl_up),
      .wr      (np_wr),
      .wr_full (np_full),
      .free    (  /*LINT:OK*/),
      .commit  (np_commit),
      .pop     (np_pop),
      .rd      (np_rd),
      .done    (np_done)
  );

  tlp_queue #(
      .ADDR_W (TRN_TX_ADDR_W)
  ) u_app_queue (
      .clk     (clk),
      .rst_n   (dl_up),
      .wr      (app_q_wr),
      .wr_full (  /*LINT:OK*/),
      .free    (app_q_free),
      .commit  (  /*LINT:OK*/),
      .pop     (app_tx_ready),
      .rd      (app_q_rd),
      .done    (  /*LINT:OK*/)
  );

  tlp_order u_order (
      .clk       (clk),
      .rst_n     (dl_up),
      .p_commit  (p_commit),
      .p_done    (p_done),
      .np_commit (np_commit),
      .np_done   (np_done),
      .np_ready  (np_ready)
  );

  tlp_rx_dispatch #(
      .BAR0_SIZE_BITS (BAR0_SIZE_BITS)
  ) u_rx_dispatch (
      .clk           (clk),
      .rst_n         (dl_up),
      .p_rd          (p_rd),
      .p_pop         (p_pop),
      .np_rd         (np_rd),
      .np_ready      (np_ready),
      .np_pop        (np_pop),
      .app_rx        (app_rx),
      .app_rx_ready  (trn_rx.rdy),
      .memory_enable (tl_cfg.memory_enable),
      .bar0_base     (tl_cfg.bar0_base),
      .cfg_acc       (cfg_acc),
      .cfg_rdata     (cfg_rdata),
      .id            (id),
      .sspl          (sspl),
      .cpl_ready     (cpl_ready),
      .cpl_hold      (cpl_hold),
      .cpl_req       (cpl_req),
      .cpl           (cpl),
      .rel           (dp_rel),
      .ev_ur         (err.ur),
      .ev_poisoned   (err.poisoned)
  );

  config_space #(
      .VENDOR_ID        (VENDOR_ID),
      .DEVICE_ID        (DEVICE_ID),
      .REVISION_ID      (REVISION_ID),
      .CLASS_CODE       (CLASS_CODE),
      .SUBSYS_VENDOR_ID (SUBSYS_VENDOR_ID),
      .SUBSYS_ID        (SUBSYS_ID),
      .BAR0_SIZE_BITS   (BAR0_SIZE_BITS),
      .ASPM_SUPPORT     (ASPM_SUPPORT),
      .L0S_EXIT_LATENCY (L0S_EXIT_LATENCY),
      .L1_EXIT_LATENCY  (L1_EXIT_LATENCY),
      .L0S_ACCEPT_LAT   (L0S_ACCEPT_LAT),
      .L1_ACCEPT_LAT    (L1_ACCEPT_LAT),
      .SLOT_CLOCK       (SLOT_CLOCK)
  ) u_cfg_space (
      .clk          (clk),
      .rst_n        (dl_up),
      .acc          (cfg_acc),
      .rdata        (cfg_rdata),
      .id           (id),
      .sspl         (sspl),
      .err          (err),
      .msg_nonfatal (msg_nonfatal),
      .msg_fatal    (msg_fatal),
      .cfg          (tl_cfg)
  );

  cpl_gen u_cpl_gen (
      .clk          (clk),
      .rst_n        (dl_up),
      .own_id       (cfg.id),
      .cpl_req      (cpl_req),
      .cpl          (cpl),
      .cpl_hold     (cpl_hold),
      .cpl_ready    (cpl_ready),
      .msg_nonfatal (msg_nonfatal),
      .msg_fatal    (msg_fatal),
      .src          (int_src),
      .src_ready    (int_ready)
  );

  fc_credit u_fc_credit (
      .clk         (clk),
      .rst_n       (rst_n),
      .rx_rst_n    (dl_up),
      .dl_inactive (dl_inactive),
      .rx_dllp     (dll.rx_dllp),
      .tx_fc       (tx_fc),
      .consume     (consume),
      .p_alloc     (p_alloc),
      .np_alloc    (np_alloc),
      .rel_a       (rx_rel),
      .rel_b       (dp_rel),
      .tx_dllp     (dll.tx_dllp)
  );

  tlp_tx_arbiter u_tx_arbiter (
      .clk               (clk),
      .rst_n             (dl_up),
      .int_src           (int_src),
      .int_ready         (int_ready),
      .app_tx            (app_tx),
      .app_tx_ready      (app_tx_ready),
      .bus_master_enable (tl_cfg.bus_master_enable),
      .tx_fc             (tx_fc),
      .consume           (consume),
      .tx                (tx),
      .tx_half           (dll.tx_tlp.half),
      .tx_ready          (dll.tx_tlp_ready)
  );

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Oct 18, 2026
// -----------------------------------------------------------------------------
