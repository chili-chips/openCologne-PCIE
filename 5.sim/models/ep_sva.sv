// SPDX-FileCopyrightText: 2026 Chili.CHIPS
//
// SPDX-License-Identifier: BSD-3-Clause

//==========================================================================
// openCologne-PCIE * NLnet-sponsored open-source implementation
//--------------------------------------------------------------------------
// Description:
//   ep_sva: simulation-only assertions inside our EP (make EP=rtl, Verilator
//   --assert), bound into pcie_core. Nothing in the design reads them. Each
//   fails at the clock an open issue happens, not when the host's checker
//   later sees its effect, so a run reaches it whatever the timing:
//
//     SKP     in L0, the MAC sends an SKP Ordered Set on the PIPE at least
//             every 1538 + Max_Payload_Size (128) + 28 Symbol Times, 8 a
//             PCLK (4.2.7.1; BA#38)
//     SKP-MUX the SKP word the MAC's SKP generator sends (and took off its
//             queue) reaches the PIPE: no data, OS or IDLE in that cycle,
//             which ccfpga_tx_MAC's output mux puts first (#38)
//     REPLAY  a TLP in the retry buffer is Acked (the buffer empties) or
//             replayed within the REPLAY_TIMER limit: 711 Symbol Times at
//             2.5 GT/s x1 and 128 bytes, +100% (3.5.2.1, Table 3-4), plus
//             the TLP itself; the timer counts in L0 only (#24)
//     FCINIT  when the DLL enters DL_Active, the TL holds the TX credit
//             limits of P, NP and Cpl, taken in DL_Init: the DLL leaves
//             FC_INIT1 only with an InitFC of each type (3.2.1, 3.3.1)
//==========================================================================

module ep_sva (
    input logic pclk,
    input logic rst_n,      // mac_rst_n
    input logic l0,         // the LTSSM in L0
    input logic dl_active,  // the DLL in DL_Active
    input logic [63:0] tx_data,   // PIPE, MAC -> PHY
    input logic [ 7:0] tx_datak,
    input logic skp_gen,    // ccfpga_tx_MAC: the SKP generator's word, and the
    input logic tx_other,   // data, OS or IDLE its output mux puts first
    input logic buf_empty,  // the DLL's retry buffer
    input logic replay,     // the DLL replays the buffer
    input logic [2:0] fc_init  // the TL's TX credit limits of P, NP, Cpl are set
);

  localparam int SKP_MAX    = (1538 + 128 + 28 + 7) / 8;     // PCLK
  localparam int REPLAY_MAX = (2 * 711 + 128 + 28 + 7) / 8;  // PCLK

  // An SKP symbol (K28.0) in the word
  logic skp;
  always_comb begin
    skp = 1'b0;
    for (int b = 0; b < 8; b++) skp |= tx_datak[b] && tx_data[8*b+:8] == 8'h1C;
  end

  a_skp :
  assert property (@(posedge pclk) disable iff (!rst_n || !l0)
      (skp || $rose(l0)) |-> ##[1:SKP_MAX] skp)
  else $error("**** SVA BA#38: no SKP Ordered Set from the EP's MAC on the PIPE for %0d PCLK (%0d Symbol Times) in L0",
              SKP_MAX, 8 * SKP_MAX);

  a_skp_mux :
  assert property (@(posedge pclk) disable iff (!rst_n) skp_gen |-> !tx_other)
  else $error("**** SVA BA#38: the MAC dropped an SKP Ordered Set: data, OS or IDLE in its cycle");

  a_replay :
  assert property (@(posedge pclk) disable iff (!rst_n || !l0 || !dl_active)
      ($fell(buf_empty) || $rose(replay) || ($rose(l0) && !buf_empty)) |->
      ##[1:REPLAY_MAX] (buf_empty || $rose(replay)))
  else $error("**** SVA BA#24: a TLP in the EP's retry buffer neither Acked nor replayed in %0d PCLK in L0",
              REPLAY_MAX);

  a_fc_init :
  assert property (@(posedge pclk) disable iff (!rst_n) $rose(dl_active) |-> &fc_init)
  else $error("**** SVA FCINIT: DL_Active, but the TL has not taken the InitFC credit limits (Cpl, NP, P: %b)",
              fc_init);

endmodule: ep_sva

bind pcie_core ep_sva sva (
    .pclk     (pipe.pclk),
    .rst_n    (mac_rst_n),
    .l0       (mac.ltssm_state == mac_pkg::L0),
    .dl_active(dll.dl_state == DL_ACTIVE),
    .tx_data  (pipe.tx.data),
    .tx_datak (pipe.tx.kcode),
    .skp_gen  (u_mac.u_tx_mac.sending_skp),
    .tx_other (u_mac.u_tx_mac.sending_data || u_mac.u_tx_mac.o_sending_os || u_mac.u_tx_mac.sending_idle),
    .buf_empty(u_dll.g_vc[0].u_vc.retry_buffer_empty),
    .replay   (u_dll.g_vc[0].u_vc.tlp_retransmit_flag),
    .fc_init  ({u_tl.u_fc_credit.tx_fc[2].init, u_tl.u_fc_credit.tx_fc[1].init,
                u_tl.u_fc_credit.tx_fc[0].init})
);
