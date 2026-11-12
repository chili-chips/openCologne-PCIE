// SPDX-FileCopyrightText: 2025-2026 Cologne Chip AG
//
// SPDX-License-Identifier: BSD-3-Clause

// Refined in the NLnet-funded openCologne-PCIE project,
// executed by Chili.CHIPS and Intergalaktik doo

////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Interessengruppe fuer Mikroelektronik und Eingebettete Systeme (IMES)
// Fachhochschule Dortmund
//
// Development in cooperation with Cologne Chip AG
//
// Filename     : ccfpga_pipe_top.sv
// Author       : Philipp Leduc
// Tool         :
// Description  : PIPE Interface Logic for SerDes Block of Gatemate FPGA.
// Commentary   : Development according to PIPE Specification Version 2.0 by Intel.
//                DATA_BYTES (pipe_pkg): 1 (8-Bit), 2 (16-Bit), 4 (32-Bit) or 8 (64-Bit).
//                Use of the PIPE Interface requires specific Config-Fields to be set (see Doc).
//                Tx Compliance:
//                The use of the Tx Comliance Port differs from the description in the intel spec.
//                Port width is equal to number of bytes, which can be set individually. In case of
//                16-Bit PIPE Interface the Tx Compliance port has a width of 2-Bit. The upper Bit
//                can be tied to Zero and the lower Bit can be used as stated in the intel spec.
//
// Abreviations : [i_] > input (port)
//                [o_] > output (port)
//                [s_] > signal
//                [_n] > low active
//
// Changelog:
// -------------------------------------------------------------------------------------------------
// Version | Author             | Date       | Changes
// -------------------------------------------------------------------------------------------------
// 1.0     | Leduc              | 05.06.2021 | released
// -------------------------------------------------------------------------------------------------
// 1.1     | Leduc              | 12.07.2021 | Connected PIPE FSM to Core Clock.
// -------------------------------------------------------------------------------------------------
////////////////////////////////////////////////////////////////////////////////////////////////////

module ccfpga_pipe_top
  import pipe_pkg::*;
(
    // -------------- PIPE INTERFACE PORTS -----------------
    pipe_if.phy pipe,  // PIPE, PHY side: commands and TX data in, status, RX data and PCLK out

    // External
    output logic o_tx_clk,  // Tx Clock (user side)

    // -------------- CSS INTERFACE PORTS ------------------

    output logic            o_tx_buf_err,       // Tx Buffer Error
    output logic            o_clk_core_rx_rec,  // Rx Recovered Clock
    input  logic            i_rx_buf_reset,     // Rx Buffer Reset
    output logic            o_rx_buf_err,       // Rx Buffer Error
    output pipe_fsm_state_e o_fsm_state_pipe,   // State of PIPE FSM
    output align_state_e    o_fsm_state_align,  // State of Align FSM

    output logic [DATA_BYTES-1:0] o_rx_comma,     // Rx Byte Comma Indication
    output logic [DATA_BYTES-1:0] o_rx_disp_err,  // Rx Byte Disparity Error Indication
    output logic [DATA_BYTES-1:0] o_rx_dec_err,   // Rx Byte Decode Error Indication

    // -------------- CCAG SERDES PORTS --------------------
    // info: port directions seen from PIPE interface side

    // Clock
    input  logic i_clk_core_pll,     // ADPLL
    input  logic i_clk_core_rx_rec,  // Recovered Clock from Rx
    output logic o_clk_core_tx,      // Transmitter (Tx)
    output logic o_clk_core_rx,      // Receiver (Rx)

    // Reset
    output logic o_pll_reset,      // ADPLL
    output logic o_tx_reset,       // Tx Reset
    input  logic i_tx_reset_done,  // Tx Reset Status
    // Rx Reset; its status is not read: the PIPE waits on TX reset done only
    output logic o_rx_reset,

    output logic o_tx_pcs_reset,  // Tx PCS Reset
    output logic o_tx_pma_reset,  // Tx PMA Reset

    output logic o_rx_pcs_reset,  // Rx PCS Reset
    output logic o_rx_pma_reset,  // Rx PMA Reset
    output logic o_rx_cdr_reset,  // Rx CDR Reset
    output logic o_rx_eqa_reset,  // Rx DFE Reset

    // Power Control
    output logic o_tx_powerdown_n,  // Tx Power Control
    output logic o_rx_powerdown_n,  // Rx Power Control

    // Loopback and PRBS
    output logic [2:0] o_loopback,           // Loopback Control
    output logic [2:0] o_rx_prbs_sel,        // Rx PRBS Checker Mode
    output logic       o_rx_prbs_cnt_reset,  // Rx PRBS Error Counter Reset
    output logic [2:0] o_tx_prbs_sel,        // Tx PRBS Generator Mode
    output logic       o_tx_prbs_force_err,  // Tx PRBS Error Injection

    // Buffer
    output logic o_rx_buf_reset,  // Rx Buffer Reset
    input  logic i_rx_buf_err,    // Rx Buffer Error (Over- or Underflow)
    input  logic i_tx_buf_err,    // Tx Buffer Error (Over- or Underflow)

    // Tx-Datapath
    output serdes_tx_t    o_tx,               // Tx symbols, K flags, disparity enable
    output serdes_flags_t o_tx_char_dispval,  // Tx Disparity Values (0:neg, 1:pos)
    output logic          o_tx_8b10b_en,      // Tx 8b/10b Decoder Enable
    output serdes_flags_t o_tx_8b10b_bypass,  // Tx 8b/10b Decoder Bypass per Bit

    output logic o_tx_polarity,  // Tx Polarity Control

    output logic o_tx_elec_idle,  // Tx Electrical Idle Control

    output logic o_tx_detect_rx,    // Tx Receiver Detection Control
    input  logic i_rx_detect_done,  // Tx Receiver Detection Status
    input  logic i_rx_present,      // Tx Receiver Detection Response (1: Present)

    // Rx-Datapath
    input  serdes_rx_t    i_rx,              // Rx symbols and their flags
    output logic          o_rx_8b10b_en,     // Rx 8b/10b Decoder Enable
    output serdes_flags_t o_rx_8b10b_bypass, // Rx 8b/10b Decoder Bypass per Bit

    input  logic i_rx_byte_is_aligned,  // Rx Byte Alignment Status (Not used atm.)
    output logic o_rx_mcomma_align,     // Rx Byte Alignment Control COM (neg. CRD)
    output logic o_rx_pcomma_align,     // Rx Byte Alignment Control COM (pos. CRD)
    output logic o_rx_comma_detect_en,  // Rx Byte Alignment Enable
    output logic o_rx_slide,            // Rx Manual Comma Slide

    output logic o_rx_polarity,  // Rx Polarity Control

    output logic o_rx_ei_detect_en,  // Rx Electrical Idle Detection Enable
    input  logic i_rx_elec_idle      // Rx Electrical Idle Detection Response
);


  logic       s_reset;
  logic       s_clk;
  logic       s_tx_clk;
  logic       s_sel_rx_status;  // Mux Select Signal for RxStatus
  rx_status_e s_rx_status_dp;  // RxStatus Signal from Rx Datapath
  rx_status_e s_rx_status_fsm;  // RxStatus Signal from FSM (Rx Detection)
  logic       s_loopback_fsm;
  logic       s_rx_val_from_fsm;
  logic       s_reset_done;
  logic       s_tx_idle_cnt_rst;
  logic       s_tx_idle_cnt_flag;
  logic       s_enable_align;
  logic       s_align_cnt_rst;
  logic       s_align_cnt_flag;

  // Parameters for Word Alignment Counter

  localparam int CNT_BITWIDTH_ALIGN = (DATA_BYTES == 2) ? 32'd6 : 32'd4;
  localparam int CNT_NUMBER_ALIGN   = (DATA_BYTES == 2) ? 32'd38 : 32'd7;

  // Parameters for Tx Idle Counter

  localparam int CNT_BITWIDTH_TX    = (DATA_BYTES == 2) ? 32'd4 : 32'd3;
  localparam int CNT_NUMBER_TX      = (DATA_BYTES == 2) ? 32'd9 : 32'd2;

  // Clock divider of the narrower PIPE
  localparam int DIVIDER            = 32'd2;

  // Constant Port Value Assignments

  assign o_tx_reset           = 1'b0;
  assign o_tx_pcs_reset       = 1'b0;
  assign o_tx_pma_reset       = 1'b0;

  assign o_rx_reset           = 1'b0;
  assign o_rx_pcs_reset       = 1'b0;
  assign o_rx_pma_reset       = 1'b0;
  assign o_rx_cdr_reset       = 1'b0;
  assign o_rx_eqa_reset       = 1'b0;

  assign o_tx_8b10b_bypass    = 8'b0000_0000;
  assign o_rx_8b10b_bypass    = 8'b0000_0000;
  assign o_tx_8b10b_en        = 1'b1;
  assign o_rx_8b10b_en        = 1'b1;

  assign o_tx_prbs_sel        = 3'b000;
  assign o_tx_prbs_force_err  = 1'b0;
  assign o_rx_prbs_sel        = 3'b000;
  assign o_rx_prbs_cnt_reset  = 1'b0;

  assign o_rx_slide           = 1'b0;
  assign o_rx_comma_detect_en = 1'b1;

  assign o_tx_polarity        = 1'b0;

  assign o_tx_powerdown_n     = 1'b1;
  assign o_rx_powerdown_n     = 1'b1;

  assign o_rx_ei_detect_en    = 1'h0;  // old: 1'b1;

  assign o_tx_char_dispval    = 8'b0000_0000;

  // Clock
  assign pipe.pclk            = s_clk;
  assign o_tx_clk             = s_tx_clk;

  assign o_clk_core_tx        = i_clk_core_pll;
  assign o_clk_core_rx        = i_clk_core_pll;
  assign o_clk_core_rx_rec    = i_clk_core_rx_rec;

  // Reset Logic
  assign s_reset              = ~pipe.reset_n;
  assign o_pll_reset          = s_reset;

  // RxStatus Mux
  always_comb begin
    if (s_sel_rx_status) begin
      pipe.rx_status = s_rx_status_fsm;
    end
    else begin
      pipe.rx_status = s_rx_status_dp;
    end
  end

  // Loopback
  assign o_loopback[0]     = 1'b0;
  assign o_loopback[1]     = s_loopback_fsm;
  assign o_loopback[2]     = s_loopback_fsm;

  // Rx Valid
  assign pipe.rx_valid     = s_rx_val_from_fsm & i_rx_byte_is_aligned;

  // Rx Electrical Idle
  assign pipe.rx_elec_idle = i_rx_elec_idle;

  // Buffer Support Signals
  assign o_tx_buf_err      = i_tx_buf_err;
  assign o_rx_buf_reset    = i_rx_buf_reset;
  assign o_rx_buf_err      = i_rx_buf_err;

  // Rx Polarity
  assign o_rx_polarity     = pipe.rx_polarity;  // Setting not FSM related atm.

  // FSM PIPE
  ccfpga_pipe_fsm u_pipe_fsm (
      .i_clk           (s_clk),
      .i_reset         (s_reset),
      .o_fsm_state     (o_fsm_state_pipe),
      .i_power_down    (pipe.power_down),
      .i_tx_elec_idle  (pipe.tx_elec_idle),
      .i_tx_detect_rx  (pipe.tx_detect_rx),
      .o_phy_status    (pipe.phy_status),
      .o_rx_status     (s_rx_status_fsm),
      .i_reset_done    (s_reset_done),
      .i_rx_detect_done(i_rx_detect_done),
      .i_rx_present    (i_rx_present),
      .o_tx_detect_rx  (o_tx_detect_rx),
      .o_sel_rx_status (s_sel_rx_status),
      .o_pcs_loopback  (s_loopback_fsm),
      .o_tx_elec_idle  (o_tx_elec_idle),
      .o_cnt_reset     (s_tx_idle_cnt_rst),
      .i_cnt_flag      (s_tx_idle_cnt_flag),
      .o_enable_align  (s_enable_align)       // Activate Word Alignment (FSM)
  );

  // Clock Counter for Tx Idle
  ccfpga_pipe_clk_counter #(
      .BIT_WIDTH(CNT_BITWIDTH_TX),
      .CLK_NUMB (CNT_NUMBER_TX)
  ) u_tx_idle_count (
      .i_clk  (s_clk),
      .i_reset(s_tx_idle_cnt_rst),
      .o_flag (s_tx_idle_cnt_flag)
  );

  // FSM Word Alignment
  ccfpga_pipe_fsm_word_align u_word_align (
      .i_clk               (s_clk),
      .i_reset             (s_reset),
      .i_enable            (s_enable_align),
      .o_fsm_state         (o_fsm_state_align),
      .o_rx_valid          (s_rx_val_from_fsm),
      .o_cnt_reset         (s_align_cnt_rst),
      .i_cnt_flag          (s_align_cnt_flag),
      .o_mcomma_align      (o_rx_mcomma_align),
      .o_pcomma_align      (o_rx_pcomma_align),
      .i_rx_byte_is_aligned(i_rx_byte_is_aligned)
  );

  // Clock Counter for Alignment
  ccfpga_pipe_clk_counter #(
      .BIT_WIDTH(CNT_BITWIDTH_ALIGN),
      .CLK_NUMB (CNT_NUMBER_ALIGN)
  ) u_word_align_count (
      .i_clk  (s_clk),
      .i_reset(s_align_cnt_rst),
      .o_flag (s_align_cnt_flag)
  );

  // Tx clock: the SerDes word clock (64 bits, 80 on the line)
  generate
    // 64-Bit PIPE: PLL_CLK_O is the word clock (PLL_FCNTRL = 6'h3A)
    if (DATA_BYTES == 8) begin : g_pclk_64
      assign s_tx_clk = i_clk_core_pll;
    end
    // narrower PIPE: PLL_CLK_O is twice the word clock (PLL_FCNTRL = 6'h1A)
    else begin : g_pclk_narrow
      ccfpga_pipe_clk_divider #(
          .DIVIDER(DIVIDER)
      ) u_clk_div (
          .i_clk  (i_clk_core_pll),
          .i_reset(s_reset),
          .o_clk  (s_tx_clk)
      );
    end
  endgenerate

  generate
    if (DATA_BYTES == 8) begin : g_64  // 64-Bit PIPE

      // Clock
      assign s_clk         = s_tx_clk;

      // Reset Logic (excludes PLL)
      //assign s_reset_done = i_rx_reset_done & i_tx_reset_done;
      assign s_reset_done  = i_tx_reset_done;

      // Tx Datapath
      assign o_tx.data     = pipe.tx.data;
      assign o_tx.kcode    = pipe.tx.kcode;

      // Disparity (Enable and Value)
      assign o_tx.dispmode = pipe.tx_compliance;

      // Rx Datapath
      // a symbol that decoded wrong becomes EDB
      for (genvar i = 0; i < DATA_BYTES; i++) begin : g_edb
        assign pipe.rx.data[i*8+:8] = i_rx.dec_err[0][i] ? K_EDB : i_rx.data[0][i*8+:8];
      end

      assign pipe.rx.kcode = i_rx.kcode;
      assign o_rx_comma    = i_rx.comma;
      assign o_rx_disp_err = i_rx.disp_err;
      assign o_rx_dec_err  = i_rx.dec_err;

      always_comb begin
        if (|i_rx.dec_err) begin
          s_rx_status_dp = DECODE_ERR;
        end
        else if (|i_rx.disp_err) begin
          s_rx_status_dp = DISP_ERR;
        end
        else begin
          s_rx_status_dp = RX_OK;
        end
      end

    end

    else begin : g_narrow  // 32-Bit PIPE

      // Disparity mode: from the demux (o_tx.dispmode)

      // Reset Logic
      assign s_reset_done = i_tx_reset_done;

      assign s_clk        = i_clk_core_pll;

      // Tx Datapath Demuliplexer
      ccfpga_pipe_tx_demux u_tx_demux (
          .i_clk       (s_clk),
          .i_reset     (s_reset),
          .i_enable    (1'b1),
          .i_data      (pipe.tx.data),        // PIPE
          .i_kcode     (pipe.tx.kcode),       // PIPE
          .i_compliance(pipe.tx_compliance),  // PIPE
          .o_tx        (o_tx)                 // SerDes
      );

      // Rx Datapath Muliplexer
      ccfpga_pipe_rx_mux u_rx_mux (
          .i_clk     (s_clk),
          .i_reset   (s_reset),
          .i_enable  (1'b1),
          .i_rx      (i_rx),           // SerDes
          .o_data    (pipe.rx.data),   // PIPE
          .o_kcode   (pipe.rx.kcode),  // PIPE
          .o_comma   (o_rx_comma),     // PIPE
          .o_disp_err(o_rx_disp_err),  // PIPE
          .o_dec_err (o_rx_dec_err),   // PIPE
          .o_status  (s_rx_status_dp)  // PIPE
      );
    end

  endgenerate

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Nov 3, 2026
// -----------------------------------------------------------------------------
