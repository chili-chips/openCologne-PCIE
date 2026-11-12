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
//   phy_top: the PHY, everything below the PIPE interface. Two parts:
//
//   - ccfpga_pipe_top (Cologne Chip, 2.pipe): the soft PIPE
//     adaptation layer. It turns PIPE into the SerDes data path, makes PCLK,
//     and runs the SerDes reset and comma-alignment FSMs.
//   - the SerDes, one ccfpga_serdes instance; the file list picks the
//     module: ccfpga_serdes.SYNTH.sv for the chip (the CC_SERDES hard macro
//     behind the BFM's ports), ccfpga_serdes.BFM.sv (our opensource BFM) or
//     the vendor's model for simulation. Parameters set it up, as on the
//     chip: SerDes and PLL on from reset, no regfile writes.
//
//   On the chip CC_SERDES has its own serial pins and reference clock, so
//   clk_ref and ser_* go unused there; in simulation they are the model's.
//==========================================================================

module phy_top
  import pipe_pkg::*;
(
    input  logic clk_ref,     // 100 MHz PCIE REFCLK, the model's reference
    input  logic rst_pipe_n,  // PIPE Reset#, released on clk_aon
    input  logic ser_rxp,
    input  logic ser_rxn,
    output logic ser_txp,
    output logic ser_txn,

    pipe_if.phy pipe,

    output logic phy_rdy  // high once the SerDes TX is out of reset
);

  // SerDes settings, shared by both SerDes: as in Cologne Chip's
  // ccfpga_pipe_wrapper.sv (gatemate-pipe), a 64-bit datapath, the PLL clock at the word rate
  // (31.25 MHz at 2.5 Gb/s) and the comma aligned on a 32-bit word
  localparam logic [5:0] PLL_FCNTRL         = 6'h3A;
  localparam logic [5:0] PLL_MAIN_DIVSEL    = {1'b0, 2'd3, 1'b0, 2'd3};
  localparam logic [1:0] PLL_OUT_DIVSEL     = 2'd1;
  localparam logic [1:0] RX_DATAPATH_SEL    = 2'd3;
  localparam logic [1:0] TX_DATAPATH_SEL    = 2'd3;
  localparam logic [9:0] ALIGN_MCOMMA_VALUE = 10'b1010000011;
  localparam logic [9:0] ALIGN_PCOMMA_VALUE = 10'b0101111100;
  localparam logic [9:0] ALIGN_COMMA_ENABLE = 10'b1111111111;
  localparam logic [1:0] ALIGN_COMMA_WORD   = 2'd3;

  logic clk_core_pll, clk_core_rx_rec;
  logic pll_reset;
  logic tx_reset, tx_pcs_reset, tx_pma_reset;
  logic rx_reset, rx_pcs_reset, rx_pma_reset, rx_cdr_reset, rx_eqa_reset;
  logic tx_powerdown_n, rx_powerdown_n;
  logic [2:0] loopback;
  logic [2:0] tx_prbs_sel, rx_prbs_sel;
  logic tx_prbs_force_err, rx_prbs_cnt_reset;
  logic rx_buf_reset;
  logic tx_buf_err, rx_buf_err;
  serdes_tx_t serdes_tx;  // PIPE -> SerDes: symbols, K flags, disparity mode
  serdes_rx_t serdes_rx;  // SerDes -> PIPE: symbols and their flags
  serdes_flags_t tx_char_dispval, tx_8b10b_bypass;
  logic tx_8b10b_en, tx_polarity, tx_elec_idle, tx_detect_rx;
  serdes_flags_t rx_8b10b_bypass;
  logic rx_8b10b_en, rx_polarity, rx_slide, rx_comma_detect_en;
  logic rx_mcomma_align, rx_pcomma_align, rx_ei_detect_en, rx_elec_idle;
  logic rx_byte_is_aligned;
  logic rx_detect_done, rx_present;
  logic tx_reset_done;

  assign phy_rdy = tx_reset_done;  // CC_SERDES TX_RESET_DONE_O

  // The SerDes TX and RX core clock, from the PIPE logic: the PLL clock,
  // the word rate, also PCLK
  logic tx_clk;

  // The SerDes. Its TX and RX core clocks are the PIPE logic's tx_clk.
  // TODO: validate PLL_REF_SEL(1'b1) (LVDS reference, as in the board-tested
  //       SerDes loopback) and the clocking in general when the board
  //       schematics are published.
  // TODO: add TX de-emphasis (PCIe 2.5 GT/s: -3.5 dB, spec 4.3.3), e.g.
  //       TX_BRANCH_EN_POST = TX_SEL_POST = 13 for about -3.6 dB (DS1001
  //       eq. 2.10-2.12); validate on the board. Today: none, full swing.
  logic reset_core_pll_n;  // the model's PLL-locked reset for its cores

  ccfpga_serdes #(
      .PLL_FCNTRL        (PLL_FCNTRL),
      .PLL_MAIN_DIVSEL   (PLL_MAIN_DIVSEL),
      .PLL_OUT_DIVSEL    (PLL_OUT_DIVSEL),
      .RX_DATAPATH_SEL   (RX_DATAPATH_SEL),
      .TX_DATAPATH_SEL   (TX_DATAPATH_SEL),
      .ALIGN_MCOMMA_VALUE(ALIGN_MCOMMA_VALUE),
      .ALIGN_PCOMMA_VALUE(ALIGN_PCOMMA_VALUE),
      .ALIGN_COMMA_ENABLE(ALIGN_COMMA_ENABLE),
      .ALIGN_COMMA_WORD  (ALIGN_COMMA_WORD),
      .PLL_SET_OP_LOCK   (1'b0),
      .PLL_EN_ADPLL_CTRL (1'b1),
      .PLL_CONFIG_SEL    (1'b1),
      .RX_EI_BIAS        (4'h4),                // RX electrical-idle detector on (RxElecIdle), as
                                                // DS1001 and the BFM; CC_SERDES defaults to 0
      .SERDES_ENABLE     (1'b1)
  ) u_serdes (
      .clk_ref_i           (clk_ref),
      .clk_reg_i           (1'b0),                // no regfile access: parameters set the registers
      .clk_cfg_i           (1'b0),
      .clk_core_tx_i       (tx_clk),
      .clk_core_rx_i       (tx_clk),
      .clk_core_rx_o       (clk_core_rx_rec),
      .reset_n_i           (rst_pipe_n),
      .reset_reg_n_i       (rst_pipe_n),
      .reset_core_tx_n_i   (reset_core_pll_n),
      .reset_core_rx_n_i   (reset_core_pll_n),
      .testmode_i          (1'b0),
      .scan_enable_i       (1'b0),
      .scan_in_i           (7'h0),
      .scan_out_o          (  /*LINT:OK*/),
      .loopback_i          (loopback),
      .pll_reset_i         (pll_reset),
      .clk_core_pll_o      (clk_core_pll),
      .reset_core_pll_n_o  (reset_core_pll_n),
      .refclk_sel_o        (  /*LINT:OK*/),
      .refclk_rterm_o      (  /*LINT:OK*/),
      .RX_SERIO_P_B        (ser_rxp),
      .RX_SERIO_N_B        (ser_rxn),
      .TX_SERIO_P_B        (ser_txp),
      .TX_SERIO_N_B        (ser_txn),
      .regfile_we_i        (1'b0),
      .regfile_en_i        (1'b0),
      .regfile_addr_i      (8'h0),
      .regfile_mask_i      (16'h0),
      .regfile_di_i        (16'h0),
      .regfile_do_o        (  /*LINT:OK*/),
      .regfile_rdy_o       (  /*LINT:OK*/),
      .cfg_en_i            (1'b0),
      .reset_cfg_i         (1'b0),
      .cfgfile_di_i        (16'h0),
      .cfgfile_valid_i     (1'b0),
      .cfgfile_addr_i      (8'h0),
      .tx_reset_i          (tx_reset),
      .tx_pcs_reset_i      (tx_pcs_reset),
      .tx_pma_reset_i      (tx_pma_reset),
      .tx_elec_idle_i      (tx_elec_idle),
      .tx_detect_rx_i      (tx_detect_rx),
      .tx_prbs_sel_i       (tx_prbs_sel),
      .tx_prbs_force_err_i (tx_prbs_force_err),
      .tx_powerdown_n_i    (tx_powerdown_n),
      .tx_data_i           (serdes_tx.data),
      .tx_char_is_k_i      (serdes_tx.kcode),
      .tx_polarity_i       (tx_polarity),
      .tx_8b10b_en_i       (tx_8b10b_en),
      .tx_8b10b_bypass_i   (tx_8b10b_bypass),
      .tx_char_dispmode_i  (serdes_tx.dispmode),
      .tx_char_dispval_i   (tx_char_dispval),
      .tx_buf_err_o        (tx_buf_err),
      .tx_resetdone_o      (tx_reset_done),
      .rx_detect_done_o    (rx_detect_done),
      .rx_present_o        (rx_present),
      .TERM_SERIO_O        (  /*LINT:OK*/),
      .rx_reset_i          (rx_reset),
      .rx_pma_reset_i      (rx_pma_reset),
      .rx_eqa_reset_i      (rx_eqa_reset),
      .rx_cdr_reset_i      (rx_cdr_reset),
      .rx_pcs_reset_i      (rx_pcs_reset),
      .rx_buf_reset_i      (rx_buf_reset),
      .rx_prbs_sel_i       (rx_prbs_sel),
      .rx_prbs_cnt_reset_i (rx_prbs_cnt_reset),
      .rx_powerdown_n_i    (rx_powerdown_n),
      .rx_en_ei_detector_i (rx_ei_detect_en),
      .rx_comma_detect_en_i(rx_comma_detect_en),
      .rx_slide_i          (rx_slide),
      .rx_polarity_i       (rx_polarity),
      .rx_8b10b_en_i       (rx_8b10b_en),
      .rx_8b10b_bypass_i   (rx_8b10b_bypass),
      .rx_mcomma_align_i   (rx_mcomma_align),
      .rx_pcomma_align_i   (rx_pcomma_align),
      .rx_prbs_err_o       (  /*LINT:OK*/),
      .rx_data_o           (serdes_rx.data),
      .rx_char_is_k_o      (serdes_rx.kcode),
      .rx_char_is_comma_o  (serdes_rx.comma),
      .rx_disp_err_o       (serdes_rx.disp_err),
      .rx_not_in_table_o   (serdes_rx.dec_err),
      .rx_buf_err_o        (rx_buf_err),
      .rx_byte_is_aligned_o(rx_byte_is_aligned),
      .rx_byte_realign_o   (  /*LINT:OK*/),
      .rx_resetdone_o      (  /*LINT:OK*/),
      .rx_ei_en_o          (rx_elec_idle)
  );

  ccfpga_pipe_top u_pipe_logic (
      .pipe                (pipe),
      .o_tx_clk            (tx_clk),
      .o_clk_core_tx       (  /*LINT:OK*/),
      .o_clk_core_rx       (  /*LINT:OK*/),
      .o_tx_buf_err        (  /*LINT:OK*/),
      .o_clk_core_rx_rec   (  /*LINT:OK*/),
      .i_rx_buf_reset      (1'b0),
      .o_rx_buf_err        (  /*LINT:OK*/),
      .o_fsm_state_pipe    (  /*LINT:OK*/),
      .o_fsm_state_align   (  /*LINT:OK*/),
      .o_rx_comma          (  /*LINT:OK*/),
      .o_rx_disp_err       (  /*LINT:OK*/),
      .o_rx_dec_err        (  /*LINT:OK*/),
      .i_clk_core_pll      (clk_core_pll),
      .i_clk_core_rx_rec   (clk_core_rx_rec),
      .o_pll_reset         (pll_reset),
      .o_tx_reset          (tx_reset),
      .i_tx_reset_done     (tx_reset_done),
      .o_rx_reset          (rx_reset),
      .o_tx_pcs_reset      (tx_pcs_reset),
      .o_tx_pma_reset      (tx_pma_reset),
      .o_rx_pcs_reset      (rx_pcs_reset),
      .o_rx_pma_reset      (rx_pma_reset),
      .o_rx_cdr_reset      (rx_cdr_reset),
      .o_rx_eqa_reset      (rx_eqa_reset),
      .o_tx_powerdown_n    (tx_powerdown_n),
      .o_rx_powerdown_n    (rx_powerdown_n),
      .o_loopback          (loopback),
      .o_rx_prbs_sel       (rx_prbs_sel),
      .o_rx_prbs_cnt_reset (rx_prbs_cnt_reset),
      .o_tx_prbs_sel       (tx_prbs_sel),
      .o_tx_prbs_force_err (tx_prbs_force_err),
      .o_rx_buf_reset      (rx_buf_reset),
      .i_rx_buf_err        (rx_buf_err),
      .i_tx_buf_err        (tx_buf_err),
      .o_tx                (serdes_tx),
      .o_tx_char_dispval   (tx_char_dispval),
      .o_tx_8b10b_en       (tx_8b10b_en),
      .o_tx_8b10b_bypass   (tx_8b10b_bypass),
      .o_tx_polarity       (tx_polarity),
      .o_tx_elec_idle      (tx_elec_idle),
      .o_tx_detect_rx      (tx_detect_rx),
      .i_rx_detect_done    (rx_detect_done),
      .i_rx_present        (rx_present),
      .i_rx                (serdes_rx),
      .o_rx_8b10b_en       (rx_8b10b_en),
      .o_rx_8b10b_bypass   (rx_8b10b_bypass),
      .i_rx_byte_is_aligned(rx_byte_is_aligned),
      .o_rx_mcomma_align   (rx_mcomma_align),
      .o_rx_pcomma_align   (rx_pcomma_align),
      .o_rx_comma_detect_en(rx_comma_detect_en),
      .o_rx_slide          (rx_slide),
      .o_rx_polarity       (rx_polarity),
      .o_rx_ei_detect_en   (rx_ei_detect_en),
      .i_rx_elec_idle      (rx_elec_idle)
  );

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Oct 18, 2026
// -----------------------------------------------------------------------------
