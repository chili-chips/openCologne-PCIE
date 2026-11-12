`timescale 1ns/100fs

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
//   phy_model: test-bench model of one link partner's PHY, all below the
//   PIPE interface. The Cologne Chip soft wrapper (ccfpga_pipe_top,
//   2.pipe) turns PIPE into the SerDes data path, the SerDes model
//   (ccfpga_serdes: the open BFM or the vendor model) serializes it, and a
//   small FSM brings the SerDes up through its config and regfile ports:
//   SerDes enable, then the PLL. Used by pcie_stack.sv in this DLL-over-PHY
//   flow. The synthesizable phy_top will be this with CC_SERDES in place of
//   the model.
//==========================================================================

module phy_model
  import pipe_pkg::*;
(
   input  logic                   clk_ref,
   input  logic                   clk_aon,
   input  logic                   clk_cfg,
   input  logic                   reset_n,

   pipe_if.phy pipe, // PIPE, PHY side

   output pipe_fsm_state_e o_fsm_state_pipe,
   output align_state_e o_fsm_state_align,
   output pipe_flags_t o_rx_comma,
   output pipe_flags_t o_rx_disp_err,
   output pipe_flags_t o_rx_dec_err,
   output logic                   o_tx_buf_err,
   output logic                   o_rx_buf_err,
   output logic                   o_serdes_ready,

   input  logic                   RX_SERIO_P,
   input  logic                   RX_SERIO_N,
   output logic                   TX_SERIO_P,
   output logic                   TX_SERIO_N
   );

   localparam  [5:0] PLL_FCNTRL         = (DATA_BYTES == 8) ? 6'h3A : 6'h1A;
   localparam  [5:0] PLL_MAIN_DIVSEL    = {1'b0,2'b11,1'b0,2'b11};
   localparam  [1:0] PLL_OUT_DIVSEL     = 2'b01;
   localparam  [1:0] RX_DATAPATH_SEL    = 3;
   localparam  [1:0] TX_DATAPATH_SEL    = 3;
   localparam  [9:0] ALIGN_MCOMMA_VALUE = 10'b1010000011;
   localparam  [9:0] ALIGN_PCOMMA_VALUE = 10'b0101111100;
   localparam  [9:0] ALIGN_COMMA_ENABLE = 10'b1111111111;
   localparam  [1:0] ALIGN_COMMA_WORD   = 2'b11;

   logic        clk_core_pll, clk_core_rx_rec, tx_clk;
   logic        reset_core_pll_n;
   logic        pll_reset;
   logic        tx_reset, tx_pcs_reset, tx_pma_reset;
   logic        rx_reset, rx_pcs_reset, rx_pma_reset, rx_cdr_reset, rx_eqa_reset;
   logic        tx_powerdown_n, rx_powerdown_n;
   logic  [2:0] loopback;
   logic  [2:0] tx_prbs_sel, rx_prbs_sel;
   logic        tx_prbs_force_err, rx_prbs_cnt_reset;
   logic        rx_buf_reset;
   logic        tx_buf_err, rx_buf_err;
   logic [63:0] tx_data, rx_data;
   logic  [7:0] tx_char_is_k, tx_char_dispmode, tx_char_dispval, tx_8b10b_bypass;
   logic        tx_8b10b_en, tx_polarity, tx_elec_idle, tx_detect_rx;
   logic  [7:0] rx_char_is_k, rx_char_is_comma, rx_disp_err, rx_not_in_table;
   logic  [7:0] rx_8b10b_bypass;
   logic        rx_8b10b_en, rx_polarity, rx_slide, rx_comma_detect_en;
   logic        rx_mcomma_align, rx_pcomma_align, rx_ei_detect_en, rx_elec_idle;
   logic        rx_byte_is_aligned, rx_byte_realign;
   logic        rx_detect_done, rx_present;
   logic        tx_reset_done, rx_resetdone;
   logic [15:0] regfile_do;
   logic        regfile_rdy;
   logic        tx_buf_err_pipe, rx_buf_err_pipe;

   assign o_tx_buf_err   = tx_buf_err;
   assign o_rx_buf_err   = rx_buf_err;
   assign o_serdes_ready = tx_reset_done;

   logic        regfile_we, regfile_en;
   logic  [7:0] regfile_addr;
   logic [15:0] regfile_mask, regfile_di;
   logic        cfg_en, reset_cfg, cfgfile_valid;
   logic [15:0] cfgfile_di;
   logic  [7:0] cfgfile_addr;

   logic  [3:0] cfg_state;
   logic  [7:0] cfg_wait;

   localparam [3:0] CFG_IDLE   = 4'd0,
                    CFG_EN0    = 4'd1,
                    CFG_EN1    = 4'd2,
                    CFG_EN2    = 4'd3,
                    CFG_EN3    = 4'd4,
                    CFG_PLL0   = 4'd5,
                    CFG_PLL1   = 4'd6,
                    CFG_PLL2   = 4'd7,
                    CFG_PLL3   = 4'd8,
                    CFG_DONE   = 4'd9;

   always @(posedge clk_aon or negedge reset_n) begin
      if (!reset_n) begin
         regfile_we    <= 1'b0;  regfile_en    <= 1'b0;
         regfile_addr  <= 8'h0;  regfile_mask  <= 16'h0;  regfile_di <= 16'h0;
         cfg_en        <= 1'b0;  cfgfile_valid <= 1'b0;
         cfgfile_di    <= 16'h0; cfgfile_addr  <= 8'h0;
         reset_cfg     <= 1'b0;
         cfg_state     <= CFG_IDLE;
         cfg_wait      <= 8'd0;
      end
      else begin
         regfile_en    <= 1'b0;
         regfile_we    <= 1'b0;
         cfgfile_valid <= 1'b0;

         case (cfg_state)
           CFG_IDLE : begin
              if (cfg_wait == 8'd40) begin cfg_state <= CFG_EN0; cfg_wait <= 8'd0; end
              else cfg_wait <= cfg_wait + 8'd1;
           end

           CFG_EN0 : begin
              cfg_en <= 1'b1;
              if (cfg_wait == 8'd4) begin cfg_state <= CFG_EN1; cfg_wait <= 8'd0; end
              else cfg_wait <= cfg_wait + 8'd1;
           end
           CFG_EN1 : begin
              cfgfile_valid <= 1'b1;
              cfgfile_addr  <= 8'h5C;
              cfgfile_di    <= 16'h0001;
              cfg_state     <= CFG_EN2;
           end
           CFG_EN2 : begin
              cfgfile_addr <= 8'h0;
              cfgfile_di   <= 16'h0;
              if (cfg_wait == 8'd4) begin cfg_state <= CFG_EN3; cfg_wait <= 8'd0; end
              else cfg_wait <= cfg_wait + 8'd1;
           end
           CFG_EN3 : begin
              cfg_en    <= 1'b0;
              cfg_state <= CFG_PLL0;
           end

           CFG_PLL0 : begin
              regfile_en   <= 1'b1;
              regfile_we   <= 1'b1;
              regfile_addr <= 8'h50;
              regfile_di   <= 16'h0002;
              regfile_mask <= 16'h0007;
              cfg_state    <= CFG_PLL1;
              cfg_wait     <= 8'd0;
           end
           CFG_PLL1 : begin
              regfile_addr <= 8'h0; regfile_di <= 16'h0; regfile_mask <= 16'h0;
              if (cfg_wait == 8'd40) begin cfg_state <= CFG_PLL2; cfg_wait <= 8'd0; end
              else cfg_wait <= cfg_wait + 8'd1;
           end

           CFG_PLL2 : begin
              regfile_en   <= 1'b1;
              regfile_we   <= 1'b1;
              regfile_addr <= 8'h50;
              regfile_di   <= 16'h0003;
              regfile_mask <= 16'h0003;
              cfg_state    <= CFG_PLL3;
              cfg_wait     <= 8'd0;
           end
           CFG_PLL3 : begin
              regfile_addr <= 8'h0; regfile_di <= 16'h0; regfile_mask <= 16'h0;
              if (cfg_wait == 8'd40) begin cfg_state <= CFG_DONE; cfg_wait <= 8'd0; end
              else cfg_wait <= cfg_wait + 8'd1;
           end

           default : cfg_state <= CFG_DONE;
         endcase
      end
   end

   // the PIPE takes the SerDes symbols as structs; the BFM keeps flat ports

   serdes_tx_t pipe_tx;

   serdes_rx_t pipe_rx;

   assign tx_data          = pipe_tx.data;

   assign tx_char_is_k     = pipe_tx.kcode;

   assign tx_char_dispmode = pipe_tx.dispmode;

   assign pipe_rx.data     = rx_data;

   assign pipe_rx.kcode    = rx_char_is_k;

   assign pipe_rx.comma    = rx_char_is_comma;

   assign pipe_rx.disp_err = rx_disp_err;

   assign pipe_rx.dec_err  = rx_not_in_table;


   ccfpga_pipe_top u_pipe_logic (
      .pipe (pipe),
      .o_tx_clk             ( tx_clk             ),
      .o_tx_buf_err         ( tx_buf_err_pipe    ),
      .o_clk_core_rx_rec    (                    ),
      .i_rx_buf_reset       ( 1'b0               ),
      .o_rx_buf_err         ( rx_buf_err_pipe    ),
      .o_fsm_state_pipe     ( o_fsm_state_pipe   ),
      .o_fsm_state_align    ( o_fsm_state_align  ),
      .o_rx_comma           ( o_rx_comma         ),
      .o_rx_disp_err        ( o_rx_disp_err      ),
      .o_rx_dec_err         ( o_rx_dec_err       ),
      .i_clk_core_pll       ( clk_core_pll       ),
      .i_clk_core_rx_rec    ( clk_core_rx_rec    ),
      .o_clk_core_tx        (                    ),
      .o_clk_core_rx        (                    ),
      .o_pll_reset          ( pll_reset          ),
      .o_tx_reset           ( tx_reset           ),
      .i_tx_reset_done      ( tx_reset_done      ),
      .o_rx_reset           ( rx_reset           ),
      .o_tx_pcs_reset       ( tx_pcs_reset       ),
      .o_tx_pma_reset       ( tx_pma_reset       ),
      .o_rx_pcs_reset       ( rx_pcs_reset       ),
      .o_rx_pma_reset       ( rx_pma_reset       ),
      .o_rx_cdr_reset       ( rx_cdr_reset       ),
      .o_rx_eqa_reset       ( rx_eqa_reset       ),
      .o_tx_powerdown_n     ( tx_powerdown_n     ),
      .o_rx_powerdown_n     ( rx_powerdown_n     ),
      .o_loopback           ( loopback           ),
      .o_rx_prbs_sel        ( rx_prbs_sel        ),
      .o_rx_prbs_cnt_reset  ( rx_prbs_cnt_reset  ),
      .o_tx_prbs_sel        ( tx_prbs_sel        ),
      .o_tx_prbs_force_err  ( tx_prbs_force_err  ),
      .o_rx_buf_reset       ( rx_buf_reset       ),
      .i_rx_buf_err         ( rx_buf_err         ),
      .i_tx_buf_err         ( tx_buf_err         ),
      .o_tx                 ( pipe_tx            ),
      .o_tx_char_dispval    ( tx_char_dispval    ),
      .o_tx_8b10b_en        ( tx_8b10b_en        ),
      .o_tx_8b10b_bypass    ( tx_8b10b_bypass    ),
      .o_tx_polarity        ( tx_polarity        ),
      .o_tx_elec_idle       ( tx_elec_idle       ),
      .o_tx_detect_rx       ( tx_detect_rx       ),
      .i_rx_detect_done     ( rx_detect_done     ),
      .i_rx_present         ( rx_present         ),
      .i_rx                 ( pipe_rx            ),
      .o_rx_8b10b_en        ( rx_8b10b_en        ),
      .o_rx_8b10b_bypass    ( rx_8b10b_bypass    ),
      .i_rx_byte_is_aligned ( rx_byte_is_aligned ),
      .o_rx_mcomma_align    ( rx_mcomma_align    ),
      .o_rx_pcomma_align    ( rx_pcomma_align    ),
      .o_rx_comma_detect_en ( rx_comma_detect_en ),
      .o_rx_slide           ( rx_slide           ),
      .o_rx_polarity        ( rx_polarity        ),
      .o_rx_ei_detect_en    ( rx_ei_detect_en    ),
      .i_rx_elec_idle       ( rx_elec_idle       )
   );

   ccfpga_serdes #(
      .PLL_FCNTRL           ( PLL_FCNTRL           ),
      .PLL_MAIN_DIVSEL      ( PLL_MAIN_DIVSEL      ),
      .PLL_OUT_DIVSEL       ( PLL_OUT_DIVSEL       ),
      .RX_DATAPATH_SEL      ( RX_DATAPATH_SEL      ),
      .TX_DATAPATH_SEL      ( TX_DATAPATH_SEL      ),
      .ALIGN_MCOMMA_VALUE   ( ALIGN_MCOMMA_VALUE   ),
      .ALIGN_PCOMMA_VALUE   ( ALIGN_PCOMMA_VALUE   ),
      .ALIGN_COMMA_ENABLE   ( ALIGN_COMMA_ENABLE   ),
      .ALIGN_COMMA_WORD     ( ALIGN_COMMA_WORD     ),
      .PLL_SET_OP_LOCK      ( 1'h0                 )
   ) u_serdes (
      .clk_ref_i            ( clk_ref            ),
      .clk_reg_i            ( clk_aon            ),
      .clk_cfg_i            ( clk_cfg            ),
      .clk_core_tx_i        ( tx_clk             ),
      .clk_core_rx_i        ( tx_clk             ),
      .clk_core_rx_o        ( clk_core_rx_rec    ),
      .reset_n_i            ( reset_n            ),
      .reset_reg_n_i        ( reset_n            ),
      .reset_core_tx_n_i    ( reset_core_pll_n   ),
      .reset_core_rx_n_i    ( reset_core_pll_n   ),
      .testmode_i           ( 1'b0               ),
      .scan_enable_i        ( 1'b0               ),
      .scan_in_i            ( 7'h0               ),
      .scan_out_o           (                    ),
      .loopback_i           ( loopback           ),
      .pll_reset_i          ( pll_reset          ),
      .clk_core_pll_o       ( clk_core_pll       ),
      .reset_core_pll_n_o   ( reset_core_pll_n   ),
      .refclk_sel_o         (                    ),
      .refclk_rterm_o       (                    ),
      .RX_SERIO_P_B         ( RX_SERIO_P         ),
      .RX_SERIO_N_B         ( RX_SERIO_N         ),
      .TX_SERIO_P_B         ( TX_SERIO_P         ),
      .TX_SERIO_N_B         ( TX_SERIO_N         ),
      .regfile_we_i         ( regfile_we         ),
      .regfile_en_i         ( regfile_en         ),
      .regfile_addr_i       ( regfile_addr       ),
      .regfile_mask_i       ( regfile_mask       ),
      .regfile_di_i         ( regfile_di         ),
      .regfile_do_o         ( regfile_do         ),
      .regfile_rdy_o        ( regfile_rdy        ),
      .cfg_en_i             ( cfg_en             ),
      .reset_cfg_i          ( reset_cfg          ),
      .cfgfile_di_i         ( cfgfile_di         ),
      .cfgfile_valid_i      ( cfgfile_valid      ),
      .cfgfile_addr_i       ( cfgfile_addr       ),
      .tx_reset_i           ( tx_reset           ),
      .tx_pcs_reset_i       ( tx_pcs_reset       ),
      .tx_pma_reset_i       ( tx_pma_reset       ),
      .tx_elec_idle_i       ( tx_elec_idle       ),
      .tx_detect_rx_i       ( tx_detect_rx       ),
      .tx_prbs_sel_i        ( tx_prbs_sel        ),
      .tx_prbs_force_err_i  ( tx_prbs_force_err  ),
      .tx_powerdown_n_i     ( tx_powerdown_n     ),
      .tx_data_i            ( tx_data            ),
      .tx_char_is_k_i       ( tx_char_is_k       ),
      .tx_polarity_i        ( tx_polarity        ),
      .tx_8b10b_en_i        ( tx_8b10b_en        ),
      .tx_8b10b_bypass_i    ( tx_8b10b_bypass    ),
      .tx_char_dispmode_i   ( tx_char_dispmode   ),
      .tx_char_dispval_i    ( tx_char_dispval    ),
      .tx_buf_err_o         ( tx_buf_err         ),
      .tx_resetdone_o       ( tx_reset_done      ),
      .rx_detect_done_o     ( rx_detect_done     ),
      .rx_present_o         ( rx_present         ),
      .TERM_SERIO_O         (                    ),
      .rx_reset_i           ( rx_reset           ),
      .rx_pma_reset_i       ( rx_pma_reset       ),
      .rx_eqa_reset_i       ( rx_eqa_reset       ),
      .rx_cdr_reset_i       ( rx_cdr_reset       ),
      .rx_pcs_reset_i       ( rx_pcs_reset       ),
      .rx_buf_reset_i       ( rx_buf_reset       ),
      .rx_prbs_sel_i        ( rx_prbs_sel        ),
      .rx_prbs_cnt_reset_i  ( rx_prbs_cnt_reset  ),
      .rx_powerdown_n_i     ( rx_powerdown_n     ),
      .rx_en_ei_detector_i  ( rx_ei_detect_en    ),
      .rx_comma_detect_en_i ( rx_comma_detect_en ),
      .rx_slide_i           ( rx_slide           ),
      .rx_polarity_i        ( rx_polarity        ),
      .rx_8b10b_en_i        ( rx_8b10b_en        ),
      .rx_8b10b_bypass_i    ( rx_8b10b_bypass    ),
      .rx_mcomma_align_i    ( rx_mcomma_align    ),
      .rx_pcomma_align_i    ( rx_pcomma_align    ),
      .rx_prbs_err_o        (                    ),
      .rx_data_o            ( rx_data            ),
      .rx_char_is_k_o       ( rx_char_is_k       ),
      .rx_char_is_comma_o   ( rx_char_is_comma   ),
      .rx_not_in_table_o    ( rx_not_in_table    ),
      .rx_disp_err_o        ( rx_disp_err        ),
      .rx_buf_err_o         ( rx_buf_err         ),
      .rx_byte_is_aligned_o ( rx_byte_is_aligned ),
      .rx_byte_realign_o    ( rx_byte_realign    ),
      .rx_resetdone_o       ( rx_resetdone       ),
      .rx_ei_en_o           ( rx_elec_idle       )
   );

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        April 2025
// -----------------------------------------------------------------------------
