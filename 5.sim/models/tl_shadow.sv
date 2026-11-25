// SPDX-FileCopyrightText: 2026 Chili.CHIPS
//
// SPDX-License-Identifier: BSD-3-Clause

//==========================================================================
// openCologne-PCIE * NLnet-sponsored open-source implementation
//--------------------------------------------------------------------------
// Description:
//   tl_shadow: our Transaction Layer (tl_top) beside the EP model (make TL=1,
//   EP=model IFACE=pipe), bound into tb. No MAC or DLL under it: dll_if is
//   driven from the EP model's Data Link taps (openPCIE_BFM's dll_rx_*), the
//   RC -> EP TLPs and DLLPs as its DLL hands them to its own TL: no replay,
//   duplicate or bad TLP. So the TL sees the run's real traffic:
//   enumeration, BAR set-up, the tester's requests.
//
//        g_ep_model.dut.bfm_pcie dll_rx_* --> dll_if (rx_tlp, rx_dllp, dl_state) --> tl_top
//        g_rc.u_rc rx_tlp_* (the EP model's TLPs the RC takes) --+                |
//                                                            +-- compare <----+ tx_tlp
//
//   - dl_state follows the host's flow-control DLLPs: DL_Init on InitFC1,
//     FC2 on InitFC2, DL_Active on InitFC2 for Cpl, an UpdateFC or a TLP.
//   - The TL's TLPs go nowhere. tx_tlp_ready is high in DL_Active and drops
//     for a clock after each TLP, as our DLL's when its retry buffer takes
//     one: the TL waits for that drop before its next TLP. trn_tx is idle,
//     trn_rx always ready: no SOC, so memory requests get no completion.
//   - Checked: each Configuration and I/O completion the TL makes against
//     the EP model's for the same request (Requester ID, Tag), the header
//     field by field. Not the data: the two configuration spaces differ.
//     The TL's Completer ID also against the captured one.
//     A difference is an $error at once. At the end, a completion the EP
//     model made and the TL did not is a FAIL too.
//   - Counted: TLPs in, TLPs to the SOC, completions for memory requests
//     (UR: outside our BAR0, which is smaller than the EP model's BARs).
//
//   The last line of a run: "TL SHADOW: PASS" or "TL SHADOW: FAIL".
//==========================================================================

module tl_shadow
  import pipe_pkg::*;
  import dll_pkg::*;
(
    input logic        clk,                 // PCLK: the taps' dll_clk
    input logic        rst_n,
    // the EP model's Data Link taps: RC -> EP, TLP byte 0 in dll_rx_data[7:0]
    input pipe_data_t  dll_rx_data,
    input logic        dll_rx_tlp_valid,
    input logic        dll_rx_tlp_first,
    input logic        dll_rx_tlp_last,
    input logic [ 7:0] dll_rx_hdr_credit,
    input logic [11:0] dll_rx_data_credit,
    input logic [ 1:0] dll_rx_update_type,
    input logic [ 1:0] dll_rx_packet_type,
    input logic        dll_rx_dllp_valid,
    // u_rc's Transaction taps: the EP model's TLPs the RC takes, one DW a
    // clock, byte 0 in rx_tlp_data[31:24]
    input logic        rx_clk,
    input logic [31:0] rx_tlp_data,
    input logic        rx_tlp_sop,
    input logic        rx_tlp_eop,
    input logic        rx_tlp_valid
);

  // ---- The TL, and the DLL's side of dll_if --------------------------------
  dll_if dll ();
  trn_tx_if trn_tx ();
  trn_rx_if trn_rx ();
  cfg_if cfg ();

  tl_top u_tl (
      .clk    (clk),
      .rst_n  (rst_n),
      .dll    (dll),
      .trn_tx (trn_tx),
      .trn_rx (trn_rx),
      .cfg    (cfg)
  );

  logic fc1, fc2, fc2_cpl, fc_upd;
  assign fc1     = dll_rx_dllp_valid & (dll_rx_packet_type == DLLP_INITFC1);
  assign fc2     = dll_rx_dllp_valid & (dll_rx_packet_type == DLLP_INITFC2);
  assign fc2_cpl = fc2 & (dll_rx_update_type == FC_CPL);
  assign fc_upd  = dll_rx_dllp_valid & (dll_rx_packet_type == DLLP_UPDATEFC);

  dl_state_e dl_state;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dl_state <= DL_INACTIVE;
    end
    else begin
      case (dl_state)
        DL_INACTIVE: if (fc1) dl_state <= DL_INITFC1;
        DL_INITFC1:  if (fc2) dl_state <= DL_INITFC2;
        DL_INITFC2:  if (fc2_cpl | fc_upd | dll_rx_tlp_valid) dl_state <= DL_ACTIVE;
        default:     ;
      endcase
    end
  end

  assign dll.dl_state     = dl_state;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dll.tx_tlp_ready <= 1'b0;
    end
    else begin
      dll.tx_tlp_ready <= (dl_state == DL_ACTIVE) & ~(dll.tx_tlp.valid & dll.tx_tlp.last);
    end
  end
  assign dll.rx_tlp.valid = dll_rx_tlp_valid;
  assign dll.rx_tlp.first = dll_rx_tlp_first;
  assign dll.rx_tlp.last  = dll_rx_tlp_last;
  assign dll.rx_tlp.half  = 1'b0;
  assign dll.rx_tlp.data  = dll_rx_data;
  // as our DLL: every DLLP, Ack and Nak too; fc_credit keeps the FC ones
  assign dll.rx_dllp.valid       = dll_rx_dllp_valid;
  assign dll.rx_dllp.packet_type = dllp_type_e'(dll_rx_packet_type);
  assign dll.rx_dllp.update_type = fc_class_e'(dll_rx_update_type);
  assign dll.rx_dllp.cred.hdr    = dll_rx_hdr_credit;
  assign dll.rx_dllp.cred.data   = dll_rx_data_credit;

  assign trn_tx.dat = '0;
  assign trn_tx.sof = 1'b0;
  assign trn_tx.eof = 1'b0;
  assign trn_tx.vld = 1'b0;
  assign trn_rx.rdy = 1'b1;

  // ---- The check -----------------------------------------------------------
  // A completion's header, the first 3 DW
  typedef struct packed {
    logic [ 2:0] fmt;
    logic [ 4:0] typ;
    logic [ 2:0] tc;
    logic [ 1:0] attr;
    logic [ 9:0] len;
    logic [15:0] cpl_id;
    logic [ 2:0] status;
    logic        bcm;
    logic [11:0] bc;
    logic [15:0] req_id;
    logic [ 7:0] tag;
    logic [ 6:0] la;
  } cpl_t;

  // 12 header bytes, byte 0 in [95:88]
  function automatic cpl_t cpl_of(logic [95:0] h);
    cpl_t c;
    c.fmt    = h[95:93];
    c.typ    = h[92:88];
    c.tc     = h[86:84];
    c.attr   = h[77:76];
    c.len    = h[73:64];
    c.cpl_id = h[63:48];
    c.status = h[47:45];
    c.bcm    = h[44];
    c.bc     = h[43:32];
    c.req_id = h[31:16];
    c.tag    = h[15:8];
    c.la     = h[6:0];
    return c;
  endfunction

  function automatic string cpl_str(cpl_t c);
    return $sformatf("fmt %0d type %02h tc %0d attr %0d len %0d cpl_id %04h status %0d bcm %0d bc %0d req_id %04h tag %02h la %02h",
                     c.fmt, c.typ, c.tc, c.attr, c.len, c.cpl_id, c.status, c.bcm, c.bc, c.req_id, c.tag, c.la);
  endfunction

  // Outstanding requests by {Requester ID, Tag}: Configuration or I/O (the
  // TL completes it itself) or memory, and the Completer ID the TL must
  // give. A new request with the same key replaces the old one: the host
  // reuses a tag only once it has its completion
  typedef struct packed {
    logic        cfg_io;
    logic [15:0] exp_id;
  } req_t;
  req_t pend_tl[logic [23:0]];
  req_t pend_ep[logic [23:0]];
  cpl_t cmp_tl [logic [23:0]];  // a TL completion, waiting for the EP model's
  cpl_t cmp_ep [logic [23:0]];  // and the other way

  // The Completer ID: the Bus, Device and Function the EP captured from the
  // last Type 0 Configuration Write (2.2.6.2), 0 before the first; that
  // write's own Completion carries the new one
  logic [15:0] cap_id;
  logic [23:0] cfg_k;     // a Configuration Request, its target ID still to come
  bit          cfg_wait;
  bit          cfg_wr0;

  int unsigned n_in, n_np, n_cfg, n_soc, n_tl_tlp, n_cmp, n_diff, n_mem_tl, n_nomatch, n_bad_id;
  bit          dbg;  // +tl_shadow_debug: each TLP in and out, and dl_state
  initial dbg = $test$plusargs("tl_shadow_debug");
  always @(dl_state) if (dbg) $display("%t tl_shadow: dl_state %s", $time, dl_state.name());
  always @(posedge clk) begin
    if (dbg && (u_tl.err.malformed || u_tl.err.overflow))
      $display("%t tl_shadow: the TL drops a TLP: malformed %0d overflow %0d", $time, u_tl.err.malformed, u_tl.err.overflow);
  end

  // a completion from the TL (tl = 1) or the EP model
  function automatic void on_cpl(bit tl, cpl_t c);
    logic [23:0] k;
    bit          cfg_io, last;
    int          bytes;
    k = {c.req_id, c.tag};
    if (tl ? !pend_tl.exists(k) : !pend_ep.exists(k)) begin
      if (tl) begin
        n_nomatch++;
        $error("TL shadow: the TL completes no request: %s", cpl_str(c));
      end
      return;
    end
    cfg_io = tl ? pend_tl[k].cfg_io : pend_ep[k].cfg_io;
    if (tl && c.cpl_id != pend_tl[k].exp_id) begin
      n_bad_id++;
      $error("TL shadow: Completer ID %04h, the captured ID is %04h: %s", c.cpl_id, pend_tl[k].exp_id,
             cpl_str(c));
    end
    bytes  = (c.len == 0 ? 1024 : int'(c.len)) * 4 - int'(c.la[1:0]);
    last   = (c.status != 3'd0) || !c.fmt[1] || ((c.bc == 0 ? 4096 : int'(c.bc)) <= bytes);
    if (last) begin
      if (tl) pend_tl.delete(k);
      else pend_ep.delete(k);
    end
    if (!cfg_io) begin
      if (tl) n_mem_tl++;
      return;
    end
    if (tl ? cmp_ep.exists(k) : cmp_tl.exists(k)) begin
      cpl_t o;
      o = tl ? cmp_ep[k] : cmp_tl[k];
      if (tl) cmp_ep.delete(k);
      else cmp_tl.delete(k);
      n_cmp++;
      if (o != c) begin
        n_diff++;
        $error("TL shadow: completions differ\n  TL:       %s\n  EP model: %s",
               cpl_str(tl ? c : o), cpl_str(tl ? o : c));
      end
    end
    else if (tl) begin
      cmp_tl[k] = c;
    end
    else begin
      cmp_ep[k] = c;
    end
  endfunction

  function automatic void add_req(logic [23:0] k, bit cfg_io);
    pend_tl[k] = '{cfg_io: cfg_io, exp_id: cap_id};
    pend_ep[k] = '{cfg_io: cfg_io, exp_id: cap_id};
    n_np++;
    if (cfg_io) n_cfg++;
  endfunction

  // RC -> EP: the requests, from the first beat (bytes 0 to 7); for a
  // Configuration Request also the second (its target ID, bytes 8 and 9)
  always @(posedge clk) begin
    if (!rst_n) begin
      cap_id   = '0;
      cfg_wait = 1'b0;
    end
    else if (dll_rx_tlp_valid && dll_rx_tlp_first) begin
      logic [2:0]  fmt;
      logic [4:0]  typ;
      logic [23:0] k;
      fmt = dll_rx_data[7:5];
      typ = dll_rx_data[4:0];
      k   = {dll_rx_data[39:32], dll_rx_data[47:40], dll_rx_data[55:48]};  // Requester ID, Tag
      n_in++;
      if (dbg) $display("%t tl_shadow: in  fmt %0d type %02h, first DWs %08h %08h", $time, fmt, typ,
                        dll_rx_data[31:0], dll_rx_data[63:32]);
      if (typ[4:1] == 4'b0010) begin  // Cfg0, Cfg1
        cfg_k    = k;
        cfg_wait = 1'b1;
        cfg_wr0  = fmt[1] && !typ[0];
      end
      else if (typ == 5'b00010) begin  // IO
        add_req(k, 1'b1);
      end
      else if (!fmt[1] && typ[4:1] == 4'b0000) begin  // MRd, MRdLk
        add_req(k, 1'b0);
      end
    end
    else if (dll_rx_tlp_valid && cfg_wait) begin
      if (cfg_wr0) cap_id = {dll_rx_data[7:0], dll_rx_data[15:8]};
      add_req(cfg_k, 1'b1);
      cfg_wait = 1'b0;
    end
  end

  // the TL's TLPs, 8 bytes a beat, byte 0 in [7:0]
  logic [95:0] tl_h;
  int          tl_n;
  always @(posedge clk) begin
    if (rst_n && dll.tx_tlp.valid) begin
      if (dll.tx_tlp.first) tl_n = 0;
      for (int j = 0; j < 8; j++) begin
        if (tl_n < 12) begin
          tl_h[95-8*tl_n-:8] = dll.tx_tlp.data[8*j+:8];
          tl_n++;
        end
      end
      if (dll.tx_tlp.last) begin
        n_tl_tlp++;
        if (dbg) $display("%t tl_shadow: out %024h", $time, tl_h);
        if (tl_h[92:89] == 4'b0101) on_cpl(1'b1, cpl_of(tl_h));  // Cpl, CplD, CplLk, CplDLk
      end
    end
  end

  // the EP model's TLPs, a DW a clock
  logic [95:0] ep_h;
  int          ep_n;
  always @(posedge rx_clk) begin
    if (rx_tlp_valid) begin
      if (rx_tlp_sop) ep_n = 0;
      if (ep_n < 12) begin
        ep_h[95-8*ep_n-:32] = rx_tlp_data;
        ep_n += 4;
      end
      if (rx_tlp_eop && ep_h[92:89] == 4'b0101) on_cpl(1'b0, cpl_of(ep_h));
    end
  end

  // to the SOC
  always @(posedge clk) begin
    if (rst_n && trn_rx.vld && trn_rx.rdy && trn_rx.eof) n_soc++;
  end

  final begin
    bit pass;
    pass = (n_cmp != 0) && (n_diff == 0) && (n_nomatch == 0) && (n_bad_id == 0) && (cmp_ep.num() == 0);
    $display("TL shadow: %0d TLPs in (%0d non-posted, %0d Configuration or I/O), %0d to the SOC; %0d TLPs out, %0d completions for memory requests",
             n_in, n_np, n_cfg, n_soc, n_tl_tlp, n_mem_tl);
    $display("TL shadow: %0d completions compared, %0d differ, %0d the TL made for no request, %0d the TL did not make, %0d still to come from the EP model, %0d wrong Completer IDs",
             n_cmp, n_diff, n_nomatch, cmp_ep.num(), cmp_tl.num(), n_bad_id);
    $display("TL SHADOW: %s", pass ? "PASS" : "FAIL");
  end

endmodule : tl_shadow

bind tb tl_shadow u_tl_shadow (
    .clk                (pclk),
    .rst_n              (rst_n),
    .dll_rx_data        (g_ep_model.dut.bfm_pcie.dll_rx_data),
    .dll_rx_tlp_valid   (g_ep_model.dut.bfm_pcie.dll_rx_tlp_valid),
    .dll_rx_tlp_first   (g_ep_model.dut.bfm_pcie.dll_rx_tlp_first),
    .dll_rx_tlp_last    (g_ep_model.dut.bfm_pcie.dll_rx_tlp_last),
    .dll_rx_hdr_credit  (g_ep_model.dut.bfm_pcie.dll_rx_hdr_credit),
    .dll_rx_data_credit (g_ep_model.dut.bfm_pcie.dll_rx_data_credit),
    .dll_rx_update_type (g_ep_model.dut.bfm_pcie.dll_rx_update_type),
    .dll_rx_packet_type (g_ep_model.dut.bfm_pcie.dll_rx_packet_type),
    .dll_rx_dllp_valid  (g_ep_model.dut.bfm_pcie.dll_rx_dllp_valid),
    .rx_clk             (rx_clk),
    .rx_tlp_data        (rx_tlp_data),
    .rx_tlp_sop         (rx_tlp_sop),
    .rx_tlp_eop         (rx_tlp_eop),
    .rx_tlp_valid       (rx_tlp_valid)
);

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Nov 24, 2026
// -----------------------------------------------------------------------------
