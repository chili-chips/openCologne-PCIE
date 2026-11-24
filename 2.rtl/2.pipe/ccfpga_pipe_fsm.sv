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
// Filename     : ccfpga_pipe_fsm.sv
// Author       : Philipp Leduc
// Tool         :
// Description  : PIPE FSM to implement behaviour during different Power States.
//                Powerstates P0s and P2 are not supported yet.
// Commentary   : Rx Polarity should only be changed during P0 States.
// Abreviations : [i_] > input (port)
//                [o_] > output (port)
//                [s_] > signal
//                [_n] > low active
//
//
// Changelog:
// -------------------------------------------------------------------------------------------------
// Version | Author             | Date       | Changes
// -------------------------------------------------------------------------------------------------
// 1.0     | Leduc              | 05.06.2021 | released
// -------------------------------------------------------------------------------------------------
////////////////////////////////////////////////////////////////////////////////////////////////////

module ccfpga_pipe_fsm
  import pipe_pkg::*;
(
    input  logic            i_clk,
    input  logic            i_reset,
    output pipe_fsm_state_e o_fsm_state,       // fsm status (CSS)

    input  power_state_e    i_power_down,      // Powerstate
    //input  logic        i_rx_polarity,        // Rx Polarity
    input  logic            i_tx_elec_idle,    // Tx Elec Idle
    input  logic            i_tx_detect_rx,    // Tx Receiver Detection/ Loopmode
    output logic            o_phy_status,
    //output logic        o_rx_elec_idle,
    output rx_status_e      o_rx_status,

    input  logic            i_reset_done,      // Reset Done Indicator (SerDes)
    input  logic            i_rx_detect_done,  // Receiver detection done
    input  logic            i_rx_present,      // Receiver status, 1 if receiver present
    output logic            o_tx_detect_rx,    // Start rceiver detection
    output logic            o_sel_rx_status,
    output logic            o_pcs_loopback,    // Loopback Enable
    output logic            o_tx_elec_idle,

    output logic            o_cnt_reset,       // Reset Clock Counter
    input  logic            i_cnt_flag,        // Flag for Count Indication

    output logic            o_enable_align     // Activate Word Alignment (FSM)
);


  pipe_fsm_state_e s_state, s_next_state;

  logic [3:0] s_transit;

  assign s_transit   = {i_power_down, i_tx_elec_idle, i_tx_detect_rx};
  assign o_fsm_state = s_state;

  // Receiver detection: the SerDes holds DONE from the last detection until
  // a new request reaches it (about 130 ns), so take its rise, not its level
  logic  s_det_done_q, s_det_done_rise;
  assign s_det_done_rise = i_rx_detect_done & ~s_det_done_q;

  // State Register
  always_ff @(posedge i_clk, posedge i_reset) begin
    if (i_reset == 1'b1) begin
      s_state      <= PS_RESET;
      s_det_done_q <= 1'b0;
    end
    else begin
      s_state      <= s_next_state;
      s_det_done_q <= i_rx_detect_done;
    end
  end

  // // Transition Logic
  always_comb begin
    s_next_state = s_state;
    unique case (s_state)
      PS_RESET: begin
        if (i_reset_done == 1'b1) begin
          s_next_state = PS_P1_IDLE;
        end
        else begin
          s_next_state = PS_RESET;
        end
      end
      PS_P1_IDLE: begin
        unique case (s_transit)
          {P0, 1'b1, 1'b0} : s_next_state = PS_P0_PRE_IDLE;
          {P0, 1'b0, 1'b1} : s_next_state = PS_P0_PRE_LOOP;
          {P0, 1'b0, 1'b0} : s_next_state = PS_P0_PRE_NORMAL;
          {P1, 1'b1, 1'b1} : s_next_state = PS_P1_DET_START;
          default:           s_next_state = PS_P1_IDLE;
        endcase
      end
      PS_P0_NORMAL: begin
        unique case (s_transit)
          {P1, 1'b1, 1'b0}, {P1, 1'b1, 1'b1} : s_next_state = PS_P1_SET_IDLE;
          {P0, 1'b1, 1'b0} :                   s_next_state = PS_P0_IDLE;
          {P0, 1'b0, 1'b1} :                   s_next_state = PS_P0_LOOP;
          default:                             s_next_state = PS_P0_NORMAL;
        endcase
      end
      PS_P0_LOOP: begin
        unique case (s_transit)
          {P1, 1'b1, 1'b0}, {P1, 1'b1, 1'b1} : s_next_state = PS_P1_SET_IDLE;
          {P0, 1'b1, 1'b0}, {P0, 1'b1, 1'b1} : s_next_state = PS_P0_IDLE;
          {P0, 1'b0, 1'b0} :                   s_next_state = PS_P0_NORMAL;
          default:                             s_next_state = PS_P0_LOOP;
        endcase
      end
      PS_P0_IDLE: begin
        unique case (s_transit)
          {P1, 1'b1, 1'b0}, {P1, 1'b1, 1'b1} : s_next_state = PS_P1_SET_IDLE;
          {P0, 1'b0, 1'b1} :                   s_next_state = PS_P0_LOOP;
          {P0, 1'b0, 1'b0} :                   s_next_state = PS_P0_NORMAL;
          default:                             s_next_state = PS_P0_IDLE;
        endcase
      end
      PS_P1_DET_START: begin
        if (s_transit[0] == 1'b0) begin
          s_next_state = PS_P1_IDLE;
        end
        else if (s_det_done_rise == 1'b1 && i_rx_present == 1'b1) begin
          s_next_state = PS_P1_DET_GOOD;
        end
        else if (s_det_done_rise == 1'b1 && i_rx_present == 1'b0) begin
          s_next_state = PS_P1_DET_BAD;
        end
        else begin
          s_next_state = PS_P1_DET_START;
        end
      end
      PS_P1_DET_GOOD: begin
        if (s_transit[0] == 1'b0) begin
          s_next_state = PS_P1_IDLE;
        end
        else begin
          s_next_state = PS_P1_DET_WAIT;
        end
      end
      PS_P1_DET_BAD: begin
        if (s_transit[0] == 1'b0) begin
          s_next_state = PS_P1_IDLE;
        end
        else begin
          s_next_state = PS_P1_DET_WAIT;
        end
      end
      PS_P1_DET_WAIT: begin
        if (s_transit[0] == 1'b0) begin
          s_next_state = PS_P1_IDLE;
        end
        else begin
          s_next_state = PS_P1_DET_WAIT;
        end
      end
      PS_P0_PRE_NORMAL: begin
        s_next_state = PS_P0_NORMAL;
      end
      PS_P0_PRE_LOOP: begin
        s_next_state = PS_P0_LOOP;
      end
      PS_P0_PRE_IDLE: begin
        s_next_state = PS_P0_IDLE;
      end
      PS_P1_SET_IDLE: begin
        if (i_cnt_flag == 1'b1) begin
          s_next_state = PS_P1_PRE_IDLE;
        end
        else begin
          s_next_state = PS_P1_SET_IDLE;
        end
      end
      PS_P1_PRE_IDLE: begin
        s_next_state = PS_P1_IDLE;
      end
      default: s_next_state = PS_RESET;
    endcase
  end

  // Output Logic
  always_comb begin
    // o_rx_polarity   = 0;
    o_enable_align  = 1'b0;
    o_cnt_reset     = 1'b1;  // new
    o_tx_elec_idle  = 1'b0;
    o_sel_rx_status = 1'b0;
    o_phy_status    = 1'b0;
    o_rx_status     = RX_OK;
    o_pcs_loopback  = 1'b0;
    o_tx_detect_rx  = 1'b0;
    unique case (s_state)
      PS_RESET: begin
        o_phy_status    = 1'b1;
        o_tx_elec_idle  = 1'b1;
        o_sel_rx_status = 1'b1;
      end
      PS_P1_IDLE: begin
        o_tx_elec_idle  = 1'b1;
        o_sel_rx_status = 1'b1;
      end
      PS_P0_NORMAL: begin
        o_enable_align = 1'b1;
      end
      PS_P0_LOOP: begin
        o_pcs_loopback = 1'b1;
        o_enable_align = 1'b1;
      end
      PS_P0_IDLE: begin
        o_tx_elec_idle = 1'b1;
        o_cnt_reset    = 1'b0;
        o_enable_align = 1'b1;
      end
      PS_P1_DET_START: begin
        o_tx_elec_idle  = 1'b1;
        o_sel_rx_status = 1'b1;
        o_tx_detect_rx  = 1'b1;
      end
      PS_P1_DET_GOOD: begin
        o_tx_elec_idle  = 1'b1;
        o_sel_rx_status = 1'b1;
        o_phy_status    = 1'b1;
        o_rx_status     = RX_DETECTED;
      end
      PS_P1_DET_BAD: begin
        o_tx_elec_idle  = 1'b1;
        o_sel_rx_status = 1'b1;
        o_phy_status    = 1'b1;
      end
      PS_P1_DET_WAIT: begin
        o_tx_elec_idle  = 1'b1;
        o_sel_rx_status = 1'b1;
        //o_phy_status      = 1'b1;
        //o_rx_status       = RX_DETECTED;
      end
      PS_P0_PRE_NORMAL: begin
        o_phy_status = 1'b1;
      end
      PS_P0_PRE_LOOP: begin
        o_phy_status   = 1'b1;
        o_pcs_loopback = 1'b1;
      end
      PS_P0_PRE_IDLE: begin
        o_cnt_reset    = 1'b0;
        o_phy_status   = 1'b1;
        o_tx_elec_idle = 1'b1;
      end
      PS_P1_SET_IDLE: begin
        o_cnt_reset    = 1'b0;
        o_tx_elec_idle = 1'b1;
      end
      PS_P1_PRE_IDLE: begin
        o_phy_status    = 1'b1;
        o_sel_rx_status = 1'b1;
        o_tx_elec_idle  = 1'b1;
      end
      default: ;
    endcase
  end

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Nov 3, 2026
// -----------------------------------------------------------------------------
