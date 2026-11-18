// SPDX-FileCopyrightText: 2025-2026 Cologne Chip AG
//
// SPDX-License-Identifier: BSD-3-Clause

// Refined in the NLnet-funded openCologne-PCIE project,
// executed by Chili.CHIPS and Intergalaktik doo

//--------------------------------------------------------------------------
// Description: This module is the top module for the PHY/MAC
// - It instantiates the LTSSM FSM, Rx MAC, Tx counter, Timeout blocks,
// Data Sending modules, Scrambler and Descrambler
//==========================================================================

module ccfpga_mac_top
  import pipe_pkg::*;
  import mac_pkg::*;
#(
    // Detect.Quiet and Detect.Active timeout, in us: 12 ms by the spec. A test
    // bench of two of these MACs may shorten it: both start electrically idle,
    // so neither leaves Detect.Quiet before the timeout.
    parameter int DETECT_TIMEOUT_US = 12000
) (
    input  logic i_reset_n,  // Asynchronous Reset

    pipe_if.mac  pipe,       // PIPE, MAC side (Reset# comes from the parent)
    mac_if.mac   mac         // to and from the DLL, and the link state
);

  // The interface ports, mapped onto the internal names
  // -----------------------------------------------------------------------------------------------
  // Parameters
  // Define cycle time based on data width
  // in ns
  localparam int CYCLE_TIME = 4 * DATA_BYTES;  // 4, 8, 16, 32 for DATA_BYTES 1, 2, 4, 8
  // -----------------------------------------------------------------------------------------------
  // Reset
  logic       reset;
  assign      reset = ~i_reset_n;
  // L0 flags
  logic       l0_enabled;  // L0 state
  // -----------------------------------------------------------------------------------------------
  // Receiver side signals
  logic       s_rx_flag;  // Receiver flag
  logic       s_rx_flag_rst;  // Receiver flag Reset from FSM
  logic       s_rx_rst;  // Receiver flag Reset
  logic       s_rx_os_flag_rst;  // Receiver OS flag Reset
  logic       s_rx_idle_flag_rst;  // Receiver IDLE flag Reset
  logic       s_rx_idle_flag;  // Max count for received IDLE reached
  logic [7:0] link_num;  // Expected link number in Ordered Set
  logic [7:0] lane_num;  // Expected lane number in Ordered Set
  ts_ctrl_t ts_ctrl;  // Expected control
  logic s_link_detected_rst;  // Link Detected Reset from FSM
  logic s_lane_detected_rst;  // Lane Detected Reset from FSM
  logic s_link_detected;  // Link number detected
  logic s_lane_detected;  // Lane number detected
  logic [3:0] rx_max_count;  // Max count for received Ordered Set
  logic ts1_pattern_en;  // Enable TS1 pattern
  logic ts2_pattern_en;  // Enable TS2 pattern
  logic os_valid;  // Received OS is valid
  logic idle_detected;  // IDLE symbol detected
  logic os_rec_cfg_detected;  // Received OS with non-match Link/Lane in Recovery.RcvrCfg
  logic s_rx_os_flag;  // Max count for received Orderes Set reached
  logic s_rx_rec_idle_flag_rst;  // Recovery Idle Rx Reset flag (TS1 with PAD-Lane)
  logic s_rx_rec_idle_flag;  // Recovery Idle Rx flag (TS1 with PAD-Lane)
  // Recovery Rcvrcfg Rx Reset flag (TS1 with non-matched Link/Lane)
  logic s_rx_rec_cfg_flag_rst;
  logic s_rx_rec_cfg_flag;  // Recovery Rcvrcfg Rx flag (TS1 with non-matched Link/Lane)
  // -----------------------------------------------------------------------------------------------
  // Transmitter side signals
  logic s_tx_flag;  // Transmitter flag
  logic s_tx_flag_rst;  // Transmitter flag Reset from FSM
  logic s_tx_os_flag_rst;  // Transmitter flag reset
  logic s_tx_idle_flag_rst;  // Transmitter IDLE flag reset
  logic s_tx_idle_flag;  // Max count for transmitted IDLE reached
  logic [4:0] tx_max_count;  // Max count for transmitter
  logic s_tx_os_flag;  // Max count for transmitter reached
  os_type_e os_type;  // Type of Ordered Set to be sent
  logic s_tx_poll_flag;
  logic s_tx_poll_flag_rst;
  // -----------------------------------------------------------------------------------------------
  // Timeout signals
  logic s_timeout_clk_rst;  // Timeout reset
  logic s_timeout_os_rst;  // Timeout reset
  logic [20:0] clk_max_count;  // Max count for timeout
  logic s_timeout;  // Timeout flag
  logic s_timeout_clk;  // Timeout due to clock
  logic s_timeout_os;  // Timeout due to received OS
  logic s_timeout_clk_en;  // Enable timeout due to clock
  logic s_timeout_os_en;  // Enable timeout due to received OS
  // -----------------------------------------------------------------------------------------------
  // FSM states
  ltssm_state_e s_fsm_state;
  // -----------------------------------------------------------------------------------------------
  // Sending triggers and signals
  logic s_send_idle_trigger;  // Trigger to send IDLE
  logic s_send_os_trigger;  // Trigger to send OS
  logic s_send_data_trigger;  // Trigger to send data
  logic sending_os;  // Sending OS flag
  // -----------------------------------------------------------------------------------------------
  // Transmitted data signals
  pipe_sym_t tx_plain;
  // -----------------------------------------------------------------------------------------------
  // Inversion Detection
  logic inversion_detected;
  // -----------------------------------------------------------------------------------------------
  // Descrambler signals
  pipe_sym_t rx_plain;
  // -----------------------------------------------------------------------------------------------
  // Assignments
  logic idle_state;
  // CONFIG_IDLE or RECOVERY.IDLE
  assign idle_state = s_fsm_state == CONFIG_IDLE | s_fsm_state == RECOVERY_IDLE;
  assign s_rx_os_flag_rst = ~idle_state ? s_rx_rst : 1'b1;  // Rx OS counting when not in IDLE state
  assign s_rx_idle_flag_rst = idle_state ? s_rx_rst : 1'b1;  // Rx IDLE counting when in IDLE state

  // Tx OS counting when not in IDLE state
  assign s_tx_os_flag_rst = ~idle_state ? s_tx_flag_rst : 1'b1;
  // Tx IDLE counting when in IDLE state
  assign s_tx_idle_flag_rst = idle_state ? s_tx_flag_rst : 1'b1;
  always_comb begin
    unique case (s_fsm_state)
      DETECT_QUIET, DETECT_ACTIVE, PRE_DETECT_ACTIVE, PRE_DETECT_QUIET: pipe.power_down = P1;
      default:                                                          pipe.power_down = P0;
    endcase
  end
  assign mac.ltssm_state = s_fsm_state;
  always_comb begin
    unique case (s_fsm_state)
      L0, PRE_L0, RECOVERY_RCVRLOCK, RECOVERY_RCVRCFG, RECOVERY_IDLE,
      PRE_RECOVERY_RCVRLOCK, PRE_RECOVERY_RCVRCFG, PRE_RECOVERY_IDLE:
      mac.link_up = 1'b1;
      default: mac.link_up = 1'b0;
    endcase
  end
  assign s_rx_flag = ((s_rx_os_flag & ~idle_state) | (s_rx_idle_flag & idle_state));  // Rx flag
  assign s_tx_flag = (s_tx_os_flag & ~idle_state) | (s_tx_idle_flag & idle_state);  // Tx flag
  // Rx reset when:
  // - Link number detection in CONFIG_LINKWIDTH_START_LINKNUM state (substate of
  // CONFIG_LINKWIDTH_START, waiting for link number)
  // - Lane number detection in CONFIG_LINKWIDTH_ACCEPT_LANENUM state (substate of
  // CONFIG_LINKWIDTH_ACCEPT, waiting for lane number)
  // - Rx flag reset in other states
  // - Detection and Ordered Sets counting is only enabled when pipe.rx_valid is high
  always_comb begin
    unique case (s_fsm_state)
      CONFIG_LINKWIDTH_START_LINKNUM:  s_rx_rst = s_link_detected_rst | ~pipe.rx_valid;
      CONFIG_LINKWIDTH_ACCEPT_LANENUM: s_rx_rst = s_lane_detected_rst | ~pipe.rx_valid;
      default:                         s_rx_rst = s_rx_flag_rst | ~pipe.rx_valid;
    endcase
  end

  // L0 enabled in L0 state
  //assign l0_enabled   = s_fsm_state == L0 ? 1'b1 : 1'b0;
  assign l0_enabled       = s_send_data_trigger;
  // Invert Rx polarity
  assign pipe.rx_polarity = inversion_detected;
  // -----------------------------------------------------------------------------------------------
  // Count number of received Ordered Sets/IDLE data at each state
  always_comb begin
    unique case (s_fsm_state)
      POLLING_ACTIVE, POLLING_CONFIG, CONFIG_COMPLETE, CONFIG_IDLE, RECOVERY_RCVRLOCK,
      RECOVERY_RCVRCFG, RECOVERY_IDLE:
      rx_max_count = 4'b1000;
      CONFIG_LINKWIDTH_START, CONFIG_LINKWIDTH_ACCEPT, CONFIG_LANENUM_WAIT,
      CONFIG_LANENUM_ACCEPT, L0:
      rx_max_count = 4'b0010;
      CONFIG_LINKWIDTH_START_LINKNUM, CONFIG_LINKWIDTH_ACCEPT_LANENUM: rx_max_count = 4'b0001;
      default: rx_max_count = 4'b1111;
    endcase
  end
  // TS1 Ordered Set pattern enable
  always_comb begin
    unique case (s_fsm_state)
      POLLING_ACTIVE, CONFIG_LINKWIDTH_START, CONFIG_LINKWIDTH_ACCEPT, CONFIG_LANENUM_WAIT,
      CONFIG_LINKWIDTH_START_LINKNUM, CONFIG_LINKWIDTH_ACCEPT_LANENUM, RECOVERY_RCVRLOCK,
      L0:
      ts1_pattern_en = 1'b1;
      default: ts1_pattern_en = 1'b0;
    endcase
  end
  // TS2 Ordered Set pattern enable
  always_comb begin
    unique case (s_fsm_state)
      POLLING_ACTIVE, POLLING_CONFIG, CONFIG_LANENUM_ACCEPT, CONFIG_COMPLETE,
      RECOVERY_RCVRLOCK, RECOVERY_RCVRCFG:
      ts2_pattern_en = 1'b1;
      default: ts2_pattern_en = 1'b0;
    endcase
  end
  // Count number of transmitted Ordered Sets at each state
  always_comb begin
    unique case (s_fsm_state)
      POLLING_CONFIG, CONFIG_COMPLETE, CONFIG_IDLE, RECOVERY_RCVRCFG: tx_max_count = 5'b10000;
      default:                                                        tx_max_count = 5'b11111;
    endcase
  end
  // Type of Ordered Set to be sent at each state/ 0:TS1, 1:TS2
  always_comb begin
    unique case (s_fsm_state)
      POLLING_CONFIG, CONFIG_COMPLETE, RECOVERY_RCVRCFG: os_type = OS_TS2;
      default:                                           os_type = OS_TS1;
    endcase
  end
  // Max count for timeout at each state
  always_comb begin
    unique case (s_fsm_state)
      DETECT_QUIET, DETECT_ACTIVE: clk_max_count = 21'(DETECT_TIMEOUT_US * 1000 / CYCLE_TIME);
      POLLING_ACTIVE, CONFIG_LINKWIDTH_START, RECOVERY_RCVRLOCK, CONFIG_LINKWIDTH_START_LINKNUM:
      clk_max_count = 21'(24 * 1000000 / CYCLE_TIME);
      POLLING_CONFIG, RECOVERY_RCVRCFG: clk_max_count = 21'(48 * 1000000 / CYCLE_TIME);
      default: clk_max_count = 21'(2 * 1000000 / CYCLE_TIME);
    endcase
  end
  // -----------------------------------------------------------------------------------------------
  // Timeout enable and timeout signal
  assign s_timeout_clk_en = s_fsm_state == CONFIG_LANENUM_ACCEPT ? 1'b0 : 1'b1;
  assign s_timeout_os_en  = s_fsm_state == CONFIG_LINKWIDTH_ACCEPT
                          | s_fsm_state == CONFIG_LANENUM_WAIT
                          | s_fsm_state == CONFIG_LANENUM_ACCEPT;
  assign s_timeout = (s_timeout_clk & s_timeout_clk_en) | (s_timeout_os & s_timeout_os_en);
  // -----------------------------------------------------------------------------------------------
  // ----- LTSSM -----
  ccfpga_LTSSM_fsm u_ltssm_fsm (
      .i_reset_n          (i_reset_n),           // Asynchronous Reset
      .i_pclk             (pipe.pclk),           // Parallel Interface Clock
      .i_rx_status        (pipe.rx_status),      // Receiver Status
      .i_timeout          (s_timeout),           // Timeout flag
      .i_rx_flag          (s_rx_flag),           // Rx Flag
      .i_tx_flag          (s_tx_flag),           // Tx Flag
      .i_tx_poll_flag     (s_tx_poll_flag),      // Polling Active Tx Flag
      .i_rx_rec_cfg_flag  (s_rx_rec_cfg_flag),   // Recovery Rcvrcfg Rx Flag
      .i_rx_rec_idle_flag (s_rx_rec_idle_flag),  // Recovery Idle Rx Flag
      .i_rx_elec_idle     (pipe.rx_elec_idle),   // Electrical Idle at Receiver
      .i_link_detected    (s_link_detected),     // Link Detected
      .i_lane_detected    (s_lane_detected),     // Lane Detected

      .o_tx_detect_rx         (pipe.tx_detect_rx),       // Receiver Detection (P1)/Loopback (P0)
      .o_tx_elec_idle         (pipe.tx_elec_idle),       // Electrical Idle
      .o_tx_compliance        (pipe.tx_compliance),      // Compliance Pattern
      .o_send_os_trigger      (s_send_os_trigger),       // Trigger the sending of OS
      .o_send_idle_trigger    (s_send_idle_trigger),     // Trigger the sending of IDLE
      .o_send_data_trigger    (s_send_data_trigger),     // Trigger the sending of data
      .o_fsm_state            (s_fsm_state),             // fsm status
      .o_timeout_clk_rst      (s_timeout_clk_rst),       // Clock Timeout Reset
      .o_timeout_os_rst       (s_timeout_os_rst),        // OS Timeout Reset
      .o_rx_flag_rst          (s_rx_flag_rst),           // Rx Flag Reset
      .o_tx_flag_rst          (s_tx_flag_rst),           // Tx Flag Reset
      .o_tx_poll_flag_rst     (s_tx_poll_flag_rst),      // Polling Active Tx Reset flag
      .o_rx_rec_cfg_flag_rst  (s_rx_rec_cfg_flag_rst),   // Recovery Rcvrcfg Rx Reset flag
      .o_rx_rec_idle_flag_rst (s_rx_rec_idle_flag_rst),  // Recovery Idle Rx Reset flag
      .o_link_detected_rst    (s_link_detected_rst),     // Link Detected Reset
      .o_lane_detected_rst    (s_lane_detected_rst)      // Lane Detected Reset
  );
  // -----------------------------------------------------------------------------------------------
  // ----- Receiver of MAC layer -----
  ccfpga_rx_MAC #(
      .COUNT_WIDTH (4)
  ) u_rx_mac (
      .i_clk       (pipe.pclk),
      .i_reset     (reset),
      .i_fsm_state (s_fsm_state),

      .i_rx_sym (rx_plain),

      .i_rx_os_flag_rst       (s_rx_os_flag_rst),
      .i_rx_idle_flag_rst     (s_rx_idle_flag_rst),
      .i_timeout_os_rst       (s_timeout_os_rst),
      .i_rx_rec_cfg_flag_rst  (s_rx_rec_cfg_flag_rst),
      .i_rx_rec_idle_flag_rst (s_rx_rec_idle_flag_rst),
      .i_ts1_pattern_en       (ts1_pattern_en),
      .i_ts2_pattern_en       (ts2_pattern_en),
      .i_max_count            (rx_max_count),
      .i_l0_enabled           (l0_enabled),

      .o_os_valid            (os_valid),
      .o_inversion_detected  (inversion_detected),
      .o_os_rec_cfg_detected (os_rec_cfg_detected),
      .o_idle_detected       (idle_detected),

      .o_rx_os_flag       (s_rx_os_flag),
      .o_timeout_os       (s_timeout_os),
      .o_rx_idle_flag     (s_rx_idle_flag),
      .o_rx_rec_cfg_flag  (s_rx_rec_cfg_flag),
      .o_rx_rec_idle_flag (s_rx_rec_idle_flag),

      .o_link_num      (link_num),
      .o_lane_num      (lane_num),
      .o_ts_ctrl       (ts_ctrl),
      .o_link_detected (s_link_detected),
      .o_lane_detected (s_lane_detected),

      .o_rx_sym_dll (mac.rx)
  );
  // -----------------------------------------------------------------------------------------------
  // ----- Transmitter of MAC layer -----
  ccfpga_tx_MAC u_tx_mac (
      .i_clk   (pipe.pclk),
      .i_reset (reset),

      .i_tx_sym_dll (mac.tx),

      .i_tx_os_flag_rst   (s_tx_os_flag_rst),
      .i_tx_idle_flag_rst (s_tx_idle_flag_rst),
      .i_tx_poll_flag_rst (s_tx_poll_flag_rst),

      .i_os_valid            (os_valid),
      .i_os_rec_cfg_detected (os_rec_cfg_detected),
      .i_idle_detected       (idle_detected),
      .i_l0_enabled          (l0_enabled),

      .i_send_os_trigger   (s_send_os_trigger),
      .i_send_idle_trigger (s_send_idle_trigger),
      .i_os_type           (os_type),
      .i_max_count         (tx_max_count),

      .i_link_num (link_num),
      .i_lane_num (lane_num),
      .i_ts_ctrl  (ts_ctrl),

      .o_tx_os_flag   (s_tx_os_flag),
      .o_tx_idle_flag (s_tx_idle_flag),
      .o_tx_poll_flag (s_tx_poll_flag),
      .o_sending_os   (sending_os),

      .o_tx_sym (tx_plain)
  );
  // -----------------------------------------------------------------------------------------------
  // ----- Clock count (Timeout) -----
  ccfpga_clk_counter #(
      .BIT_WIDTH (21)
  ) u_timeout_counter (
      .i_clk       (pipe.pclk),
      .i_reset     (s_timeout_clk_rst),  // Asynchronous Reset
      .i_max_count (clk_max_count),      // Max Count
      .o_flag      (s_timeout_clk)       // Output Flag when Count reaches max count
  );
  // -----------------------------------------------------------------------------------------------
  // ----- Scrambler -----
  logic                       scrambler_en;
  logic      [DATA_BYTES-1:0] tx_sym_is_ts;
  pipe_sym_t                  tx_scrambled;

  // Scrambled output data
  always_ff @(posedge pipe.pclk or posedge reset) begin
    if (reset) begin
      pipe.tx <= '0;
    end
    else begin
      pipe.tx <= tx_scrambled;
    end
  end

  // Scrambler instance
  ccfpga_scrambler u_scrambler (
      .i_clk          (pipe.pclk),
      .i_reset        (reset),
      .i_scrambler_en (scrambler_en),
      .i_sym_in       (tx_plain),
      .i_sym_is_ts    (tx_sym_is_ts),

      .o_sym_out (tx_scrambled)
  );

  // ----- Descrambler -----
  logic                       descrambler_en;
  logic      [DATA_BYTES-1:0] rx_sym_is_ts;

  pipe_sym_t                  rx_scrambled;

  // Capture input data
  always_ff @(posedge pipe.pclk or posedge reset) begin
    if (reset) begin
      rx_scrambled <= '0;
    end
    else begin
      rx_scrambled <= pipe.rx;
    end
  end

  // Descrambler instance (for Rx data)
  ccfpga_scrambler u_descrambler (
      .i_clk          (pipe.pclk),
      .i_reset        (reset),
      .i_scrambler_en (descrambler_en),
      .i_sym_in       (rx_scrambled),
      .i_sym_is_ts    (rx_sym_is_ts),

      .o_sym_out (rx_plain)
  );

  // TODO: Question: if we sending nothing, maybe waiting for data from upper layer
  // should the scrambler_en disabled?
  // Scrambler enabled when not directed in control bits and sending data/OS/SKP
  assign scrambler_en = ~ts_ctrl.disable_scrambling;
  // assign scrambler_en = (sending_data | sending_os | sending_skp) &
  // ~ts_ctrl.disable_scrambling;
  // Descrambler enabled when not directed in control bits
  assign descrambler_en = ~ts_ctrl.disable_scrambling;
  // Training sequence indication for scrambler/descrambler
  assign tx_sym_is_ts = sending_os ? {DATA_BYTES{1'b1}} : {DATA_BYTES{1'b0}};
  assign rx_sym_is_ts =
      (s_fsm_state == L0 | s_fsm_state == CONFIG_IDLE | s_fsm_state == PRE_L0) ?
      {DATA_BYTES{1'b0}} : {DATA_BYTES{1'b1}};
  // -----------------------------------------------------------------------------------------------
endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Nov 3, 2026
// -----------------------------------------------------------------------------
