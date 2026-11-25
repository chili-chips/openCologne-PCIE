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

module soc_top
  import tl_pkg::*;
  import axis_pkg::*;
  import edubos5_pkg::*;
  import csr_pkg::*;
(
    input  logic   clk,
    input  logic   resetn,

    axis_if.master s_axis_tx,  // TLPs to the PCIE stack
    axis_if.slave  m_axis_rx,  // TLPs from the PCIE stack

    cfg_if.soc     cfg,        // status sideband from the PCIE core

    output logic   fw_pass     // the firmware has reported PASS, for an LED
);

  mem_if mem ();  // CPU memory bus

  logic        ram_ready;
  logic [31:0] ram_rdata;

  logic [31:0] tx_packet_counter;

  // CPU address: bit 28 picks the PCIe CSR (0x3000_0000) or the RAM; nc_byte
  // are byte lanes, which the word bus carries in wstrb
  typedef struct packed {
    logic [2:0]  nc_region;  // [31:29]
    logic        bridge;     // [28]
    logic [14:0] nc_mid;     // [27:13]
    logic [10:0] word;       // [12:2]
    logic [1:0]  nc_byte;    // [1:0]
  } soc_addr_t;

  soc_addr_t addr;
  assign addr = mem.addr;

  // -------------------------------------------------------------------------
  // The CPU -- two interchangeable implementations
  //
  //   default             : the eduBOS5 RTL core (CPU.eduBOS5, a copy from
  //                         openPCIE), 3-stage pipeline, register file in
  //                         block RAM, executing firmware.hex out of the RAM
  //                         below; `define SOC_EDUBOS5_2STG for 2-stage.
  //   `define SOC_CPU_VPROC : the VProc virtual processor, so that a native
  //                         C/C++ program or the rv32 ISS drives the very
  //                         same bus. Co-simulation only -- see 5.sim.
  //
  // Nothing else in the SOC changes: the address decode, the CSR and the PCIe
  // stack see an identical memory interface either way.
  //
  // `define SOC_CSR_RD_COMB (experimental): the CSR answers in the request
  // cycle, without its output register.
  // -------------------------------------------------------------------------

  // KEEPME: the CPU's retired-instruction stream (RVFI). Nothing in the
  // design reads it: it is for WaveCrux's RISC-V decoder and RVFI Commit
  // Inspector, through tb.cpu_view in 5.sim, and for formal checks.
  // eduBOS5 drives it with RISCV_FORMAL defined (simulation and formal
  // only); otherwise, and under VProc, it reads 0: a native program has no
  // instructions, and the rv32 ISS does not report them to the HDL.
  rvfi_if rvfi ();  // KEEPME

`ifdef SOC_CSR_RD_COMB
  localparam bit CSR_RD_FLOP = 1'b0;
`else
  localparam bit CSR_RD_FLOP = 1'b1;
`endif
`ifdef SOC_CPU_VPROC
  soc_cpu_vproc #(
      .NODE (4'd0)
  ) cpu (
      .clk       (clk),
      .resetn    (resetn),
      .mem_valid (mem.valid),
      .mem_ready (mem.ready),
      .mem_addr  (mem.addr),
      .mem_wdata (mem.wdata),
      .mem_wstrb (mem.wstrb),
      .mem_rdata (mem.rdata)
  );

  // KEEPME: no retired-instruction stream here, rvfi reads 0
  assign rvfi.rvfi_valid     = '0;
  assign rvfi.rvfi_order     = '0;
  assign rvfi.rvfi_insn      = '0;
  assign rvfi.rvfi_trap      = '0;
  assign rvfi.rvfi_halt      = '0;
  assign rvfi.rvfi_intr      = '0;
  assign rvfi.rvfi_mode      = '0;
  assign rvfi.rvfi_ixl       = '0;
  assign rvfi.rvfi_rs1_addr  = '0;
  assign rvfi.rvfi_rs2_addr  = '0;
  assign rvfi.rvfi_rs1_rdata = '0;
  assign rvfi.rvfi_rs2_rdata = '0;
  assign rvfi.rvfi_rd_addr   = '0;
  assign rvfi.rvfi_rd_wdata  = '0;
  assign rvfi.rvfi_pc_rdata  = '0;
  assign rvfi.rvfi_pc_wdata  = '0;
  assign rvfi.rvfi_mem_addr  = '0;
  assign rvfi.rvfi_mem_rmask = '0;
  assign rvfi.rvfi_mem_wmask = '0;
  assign rvfi.rvfi_mem_rdata = '0;
  assign rvfi.rvfi_mem_wdata = '0;
`else
  // eduBOS5 is Harvard: it fetches through a second, read-only port of the RAM
  // (below), which answers in one cycle as eduBOS5 expects; its data bus is the
  // memory interface. Its stores are one-cycle requests that do not wait for
  // ready, so the ready a store gets back, one cycle later, must not reach it:
  // eduBOS5 would take it for the data of a load that follows. Only the ready
  // of a load still waiting for its data goes through.
  cpu_pc_t        imem_addr;
  logic    [18:0] NC_imem_addr_hi;  // the RAM decodes [12:2]
  logic    [31:0] imem_rdat;
  logic           load_wait;
  logic           edubos5_rdy;

  // NC_imem_addr_hi is here only for lint; without it, Verilator reports
  //   %Warning-UNUSEDSIGNAL: Bits of signal are not used: 'imem_addr'[31:13]
  assign NC_imem_addr_hi = imem_addr[31:13];

  always_ff @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      load_wait <= 1'b0;
    end
    else begin
      load_wait <= mem.valid & (mem.wstrb == '0) & ~mem.ready;
    end
  end

  generate
    if (CSR_RD_FLOP == 1'b1) begin : g_rdy_flop
      assign edubos5_rdy = mem.ready & load_wait;
    end
    else begin : g_rdy_comb
      // the CSR answers in the load's request cycle, the RAM one cycle later
      assign edubos5_rdy = mem.ready & (load_wait | mem.valid & mem.wstrb == '0);
    end
  endgenerate

  // GateMate has no LUT RAM: the 3-stage core, whose register file reads on a
  // clock and so maps to block RAM. SOC_EDUBOS5_2STG: the 2-stage core, its
  // register file in flip-flops (the build before 2026-11-24)
`ifdef SOC_EDUBOS5_2STG
  localparam int EDUBOS5_WAIT4REGS = 0;     // 2-stage pipeline
  localparam bit EDUBOS5_RF_SYNC   = 1'b0;  // register file read asynchronously
`else
  localparam int EDUBOS5_WAIT4REGS = 1;     // 3-stage pipeline
  localparam bit EDUBOS5_RF_SYNC   = 1'b1;  // register file in block RAM
`endif

  edubos5 #(
      .EN_WAIT4REGS (EDUBOS5_WAIT4REGS),
      .RF_SYNC_READ (EDUBOS5_RF_SYNC)
  ) cpu (
      .clk           (clk),
      .arst_n        (resetn),
`ifdef RISCV_FORMAL
      .rvfi_valid     (rvfi.rvfi_valid),      // KEEPME
      .rvfi_order     (rvfi.rvfi_order),      // KEEPME
      .rvfi_insn      (rvfi.rvfi_insn),       // KEEPME
      .rvfi_trap      (rvfi.rvfi_trap),       // KEEPME
      .rvfi_halt      (rvfi.rvfi_halt),       // KEEPME
      .rvfi_intr      (rvfi.rvfi_intr),       // KEEPME
      .rvfi_mode      (rvfi.rvfi_mode),       // KEEPME
      .rvfi_ixl       (rvfi.rvfi_ixl),        // KEEPME
      .rvfi_rs1_addr  (rvfi.rvfi_rs1_addr),   // KEEPME
      .rvfi_rs2_addr  (rvfi.rvfi_rs2_addr),   // KEEPME
      .rvfi_rs1_rdata (rvfi.rvfi_rs1_rdata),  // KEEPME
      .rvfi_rs2_rdata (rvfi.rvfi_rs2_rdata),  // KEEPME
      .rvfi_rd_addr   (rvfi.rvfi_rd_addr),    // KEEPME
      .rvfi_rd_wdata  (rvfi.rvfi_rd_wdata),   // KEEPME
      .rvfi_pc_rdata  (rvfi.rvfi_pc_rdata),   // KEEPME
      .rvfi_pc_wdata  (rvfi.rvfi_pc_wdata),   // KEEPME
      .rvfi_mem_addr  (rvfi.rvfi_mem_addr),   // KEEPME
      .rvfi_mem_rmask (rvfi.rvfi_mem_rmask),  // KEEPME
      .rvfi_mem_wmask (rvfi.rvfi_mem_wmask),  // KEEPME
      .rvfi_mem_rdata (rvfi.rvfi_mem_rdata),  // KEEPME
      .rvfi_mem_wdata (rvfi.rvfi_mem_wdata),  // KEEPME
`endif
      .imem_addr     (imem_addr),
      .imem_rdat     (imem_rdat),
      .imem_rdy      (1'b1),
      .imem_vld      (  /*LINT:OK*/),        // the RAM read port needs no request
      .dmem_addr     (mem.addr),
      .dmem_we       (mem.wstrb),
      .dmem_strobe   (  /*LINT:OK*/),        // dmem_vld is the request
      .dmem_wdat     (mem.wdata),
      .dmem_rdat     (mem.rdata),
      .dmem_rdy      (edubos5_rdy),
      .dmem_vld      (mem.valid)
  );

`ifndef RISCV_FORMAL
  // KEEPME: eduBOS5 built without its RVFI outputs, rvfi reads 0
  assign rvfi.rvfi_valid     = '0;
  assign rvfi.rvfi_order     = '0;
  assign rvfi.rvfi_insn      = '0;
  assign rvfi.rvfi_trap      = '0;
  assign rvfi.rvfi_halt      = '0;
  assign rvfi.rvfi_intr      = '0;
  assign rvfi.rvfi_mode      = '0;
  assign rvfi.rvfi_ixl       = '0;
  assign rvfi.rvfi_rs1_addr  = '0;
  assign rvfi.rvfi_rs2_addr  = '0;
  assign rvfi.rvfi_rs1_rdata = '0;
  assign rvfi.rvfi_rs2_rdata = '0;
  assign rvfi.rvfi_rd_addr   = '0;
  assign rvfi.rvfi_rd_wdata  = '0;
  assign rvfi.rvfi_pc_rdata  = '0;
  assign rvfi.rvfi_pc_wdata  = '0;
  assign rvfi.rvfi_mem_addr  = '0;
  assign rvfi.rvfi_mem_rmask = '0;
  assign rvfi.rvfi_mem_wmask = '0;
  assign rvfi.rvfi_mem_rdata = '0;
  assign rvfi.rvfi_mem_wdata = '0;
`endif
`endif

  logic [31:0] ram[2048];
  initial begin
    $readmemh("firmware.hex", ram);
  end

`ifndef SOC_CPU_VPROC
  // eduBOS5's instruction port: read-only, one cycle
  always_ff @(posedge clk) begin
    imem_rdat <= ram[imem_addr[12:2]];
  end
`endif

  always_ff @(posedge clk) begin
    if (mem.valid && !addr.bridge) begin
      if (mem.wstrb == '0) begin
        ram_rdata <= ram[addr.word];
      end
      else begin
        if (mem.wstrb[0]) begin
          ram[addr.word][7:0] <= mem.wdata[7:0];
        end
        if (mem.wstrb[1]) begin
          ram[addr.word][15:8] <= mem.wdata[15:8];
        end
        if (mem.wstrb[2]) begin
          ram[addr.word][23:16] <= mem.wdata[23:16];
        end
        if (mem.wstrb[3]) begin
          ram[addr.word][31:24] <= mem.wdata[31:24];
        end
      end
    end
  end

  // the RAM answers every access, load or store, one clock later
  always_ff @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      ram_ready <= 1'b0;
    end
    else begin
      ram_ready <= mem.valid & ~addr.bridge;
    end
  end

  // -------------------------------------------------------------------------
  // PCIe CSR, generated by PeakRDL out of 4.build/csr_build/csr.rdl
  // (module "csr", wrapped by soc_csr.sv). The register map is the address
  // table at the top of csr.rdl.
  // -------------------------------------------------------------------------
  logic [31:0] bridge_rdat;
  logic        bridge_rdy;

  logic [31:0] tx_header1;
  logic [31:0] tx_header2;
  logic [31:0] tx_data;

  typedef enum logic [1:0] {
    IDLE         = 2'd0,
    SEND_CYCLE_1 = 2'd1,
    SEND_CYCLE_2 = 2'd2,
    SEND_REST    = 2'd3   // beats from the 3rd on, out of tx_payload
  } tx_state_e;
  tx_state_e tx_state;

  typedef enum logic [1:0] {
    RX_HDR0 = 2'd0,  // next beat: header DW0/DW1
    RX_HDR2 = 2'd1,  // next beat: DW2 and the payload DW (or DW3)
    RX_REST = 2'd2   // later beats: taken and dropped
  } rx_phase_e;
  rx_phase_e rx_phase;

  // PeakRDL-generated CSR ports (u_soc_csr below)
  csr__in_t  csr_in;
  csr__out_t csr_out;

  dw0_t      tx_dw0;

  assign tx_dw0 = csr_out.tx.header0.hdr.value;

  //=========================================================================
  // PeakRDL-generated CSR
  //
  // The register storage, the read mux and the bus handshake live in the
  // generated block. What stays here is the logic that the registers
  // drive and that drives them back: the Tx FSM and the Rx capture.
  //=========================================================================

  soc_csr #(
      .RD_FLOP (CSR_RD_FLOP)
  ) u_soc_csr (
      .clk    (clk),
      .resetn (resetn),

      .sel  (addr.bridge),
      .mem  (mem),
      .rdat (bridge_rdat),
      .rdy  (bridge_rdy),

      .csr_in  (csr_in),
      .csr_out (csr_out)
  );

  // ---- Tx: the CPU-written registers feed the FSM -------------------------
  // Writing tx.data is what launches a transfer, hence "swmod" -- the strobe
  // PeakRDL raises on the cycle software modifies that field.
  logic tx_start;

  assign tx_header1 = csr_out.tx.header1.hdr.value;
  assign tx_header2 = csr_out.tx.header2.hdr.value;
  assign tx_data    = csr_out.tx.data.payload.value;
  assign tx_start   = csr_out.tx.data.payload.swmod;

  // A TLP is a stream of DWORDs: DW0..DW2 from tx.header0..2, DW3 from
  // tx.data, DW 3+i from tx_payload entry i. Two DWORDs a beat: beat k from 2
  // on carries DW 2k (entry 2k-3) and DW 2k+1 (entry 2k-2). tx_payload is two
  // banks, odd and even entries, so that both DWORDs of a beat are read in one
  // clock, a cycle ahead (tx_ra) as the RAMs have a registered read.
  localparam int PAYLOAD_DW = 64;  // csr.rdl: tx_payload, rx_payload entries

  logic     [31:0] tx_pl_even_q;
  logic     [31:0] tx_pl_odd_q;
  tlp_dws_t        tx_dws;  // DWORDs in the TLP
  logic     [ 9:0] tx_beats;  // beats in the TLP
  logic     [ 9:0] tx_nb;  // next beat to load, from 2 on
  logic     [ 9:0] tx_ra;  // beat whose two DWORDs are read from the banks
  logic            tx_take;
  logic            tx_load;
  tlp_dws_t        tx_dws_c;
  logic     [ 4:0] tx_pl_widx;

  // Fmt[0]: 4-DW header; Fmt[1]: with data, Length DWORDs (0: 1024)
  assign tx_dws_c   = tlp_body_dw(tx_dw0);  // the SOC sends no digest

  assign tx_take    = s_axis_tx.tvalid & s_axis_tx.tready;
  assign tx_load    = tx_take & (tx_state inside {SEND_CYCLE_2, SEND_REST}) & (tx_nb < tx_beats);
  assign tx_ra      = tx_load ? tx_nb + 10'd1 : tx_nb;
  assign tx_pl_widx = csr_out.tx_payload.addr[7:3];

  // the two banks: even entries 0, 2, 4 ..., odd entries 1, 3, 5 ...
  logic [31:0] tx_pl_even[PAYLOAD_DW/2];
  logic [31:0] tx_pl_odd [PAYLOAD_DW/2];

  always_ff @(posedge clk) begin
    if (csr_out.tx_payload.req && csr_out.tx_payload.req_is_wr) begin
      if (csr_out.tx_payload.addr[2]) begin
        tx_pl_odd[tx_pl_widx] <= csr_out.tx_payload.wr_data;
      end
      else begin
        tx_pl_even[tx_pl_widx] <= csr_out.tx_payload.wr_data;
      end
    end
    tx_pl_odd_q  <= tx_pl_odd[5'(tx_ra-10'd2)];
    tx_pl_even_q <= tx_pl_even[5'(tx_ra-10'd1)];
  end

  assign csr_in.tx_payload.wr_ack  = csr_out.tx_payload.req & csr_out.tx_payload.req_is_wr;
  assign csr_in.tx_payload.rd_ack  = 1'b0;  // write-only
  assign csr_in.tx_payload.rd_data = '0;

  always_ff @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      tx_state          <= IDLE;
      s_axis_tx.tvalid  <= 1'b0;
      s_axis_tx.tdata   <= '0;
      s_axis_tx.tkeep   <= '0;
      s_axis_tx.tlast   <= 1'b0;
      tx_packet_counter <= '0;
      tx_dws            <= '0;
      tx_beats          <= '0;
      tx_nb             <= 10'd2;
    end
    else begin
      if (tx_start) begin
        tx_state          <= SEND_CYCLE_1;
        tx_packet_counter <= tx_packet_counter + 32'd1;
        tx_dws            <= tx_dws_c;
        tx_beats          <= 10'((tx_dws_c + 12'd1) >> 1);
        tx_nb             <= 10'd2;
      end

      unique case (tx_state)
        IDLE: begin
          s_axis_tx.tvalid <= 1'b0;
        end
        SEND_CYCLE_1: begin
          if (s_axis_tx.tvalid && s_axis_tx.tready) begin
            s_axis_tx.tdata <= hdr_dw23_t'{dw3: tx_data, dw2: tx_header2};
            s_axis_tx.tkeep <= (tx_dws > 12'd3) ? KEEP_ALL : KEEP_LO;  // DW2, DW3 if any
            s_axis_tx.tlast <= (tx_beats == 10'd2);
            tx_state        <= SEND_CYCLE_2;
          end
          else begin
            s_axis_tx.tdata  <= hdr_dw01_t'{dw1: tx_header1, dw0: tx_dw0};
            s_axis_tx.tkeep  <= KEEP_ALL;
            s_axis_tx.tvalid <= 1'b1;
            s_axis_tx.tlast  <= 1'b0;
          end
        end
        SEND_CYCLE_2, SEND_REST: begin
          if (tx_load) begin
            s_axis_tx.tdata <= {tx_pl_even_q, tx_pl_odd_q};
            s_axis_tx.tkeep <= (12'({tx_nb, 1'b1}) < tx_dws) ? KEEP_ALL : KEEP_LO;  // DW 2k, 2k+1
            s_axis_tx.tlast <= (tx_nb == tx_beats - 10'd1);
            tx_nb           <= tx_nb + 10'd1;
            tx_state        <= SEND_REST;
          end
          else if (tx_take) begin
            s_axis_tx.tvalid <= 1'b0;
            s_axis_tx.tlast  <= 1'b0;
            tx_state         <= IDLE;
          end
        end
        default: ;
      endcase
    end
  end

`ifndef SYNTHESIS
  // The firmware's contract: at most Max_Payload_Size (128 bytes, 32 DWORDs)
  // of payload. The hardware does not check it: a longer TLP goes out as its
  // header says (the host sees a Malformed TLP), and past 61 DWORDs the
  // tx_payload index wraps
  // verilog_format: off
  a_tx_max_payload :
  assert property (@(posedge clk)  // tx_start is a CSR write strobe: never in reset
      tx_start |-> !tlp_has_data(tx_dw0) || (tlp_length_dw(tx_dw0) <= 11'd32))
  else begin
    $error("SOC_TX_CHECK: payload of %0d DWORDs, over Max_Payload_Size (32)",
           tlp_length_dw(tx_dw0));
  end
  // verilog_format: on
`endif

  // ---- Rx: a TLP written into the CSR as-is -------------------------------
  // 1st beat carries header DW0/DW1, the 2nd one DW2 and DW3 (the 1st payload
  // DWORD, or DW3 of a 4-DW header), beat k from 2 on DW 2k and DW 2k+1.
  // From DW3 on, DW 3+i goes into rx_payload entry i, two banks as in Tx;
  // DWORDs past the last entry are dropped. rx.valid is set at the end of the
  // TLP and holds the link off until the firmware clears it.
  logic        rx_valid;
  logic        rx_beat;
  logic        rx_dw0;
  logic        rx_dw2;
  logic        rx_rest;
  logic [ 9:0] rx_k;  // beat k - 2 while in RX_REST

  logic [31:0] rx_pl_even_q;
  logic [31:0] rx_pl_odd_q;
  logic        rx_pl_odd_sel;
  logic        rx_pl_rd;
  logic        rx_pl_ack;
  logic [ 4:0] rx_pl_ridx;

  // an RX beat by what it carries: the payload pair goes to the two banks
  typedef struct packed {
    logic [31:0] even;  // [63:32] DW 2k+1: an even rx_payload entry
    logic [31:0] odd;   // [31:0] DW 2k: an odd rx_payload entry
  } rx_pl_pair_t;

  typedef union packed {
    hdr_dw01_t   dw01;  // [63:0] beat 0
    hdr_dw23_t   dw23;  // [63:0] beat 1
    rx_pl_pair_t pl;    // [63:0] beat k, from 2 on
  } rx_beat_t;

  rx_beat_t rx_data;
  assign rx_data  = m_axis_rx.tdata;

  assign rx_valid = csr_out.rx.valid.valid.value;
  assign rx_beat  = m_axis_rx.tvalid & m_axis_rx.tready;
  assign rx_dw0   = rx_beat & (rx_phase == RX_HDR0);
  assign rx_dw2   = rx_beat & (rx_phase == RX_HDR2);
  assign rx_rest  = rx_beat & (rx_phase == RX_REST);

  always_ff @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      rx_phase <= RX_HDR0;
    end
    else if (rx_beat && m_axis_rx.tlast) begin
      rx_phase <= RX_HDR0;
    end
    else if (rx_dw0) begin
      rx_phase <= RX_HDR2;
    end
    else if (rx_dw2) begin
      rx_phase <= RX_REST;
    end
  end

  always_ff @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      rx_k <= '0;
    end
    else if (rx_dw2) begin
      rx_k <= '0;
    end
    else if (rx_rest && (rx_k != '1)) begin
      rx_k <= rx_k + 10'd1;
    end
  end

  assign rx_pl_rd   = csr_out.rx_payload.req & ~csr_out.rx_payload.req_is_wr;
  assign rx_pl_ridx = csr_out.rx_payload.addr[7:3];

  // the two banks: even entries 0, 2, 4 ..., odd entries 1, 3, 5 ...
  logic [31:0] rx_pl_even[PAYLOAD_DW/2];
  logic [31:0] rx_pl_odd [PAYLOAD_DW/2];

  always_ff @(posedge clk) begin
    if (rx_dw2) begin
      rx_pl_even[0] <= rx_data.dw23.dw3.data;
    end
    else if (rx_rest && (rx_k < 10'(PAYLOAD_DW / 2 - 1))) begin
      rx_pl_even[5'(rx_k+10'd1)] <= rx_data.pl.even;
    end
    if (rx_rest && (rx_k < 10'(PAYLOAD_DW / 2))) begin
      rx_pl_odd[5'(rx_k)] <= rx_data.pl.odd;
    end
    rx_pl_even_q <= rx_pl_even[rx_pl_ridx];
    rx_pl_odd_q  <= rx_pl_odd[rx_pl_ridx];
  end

  // the bank select of the read: a select, reset
  always_ff @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      rx_pl_odd_sel <= 1'b0;
    end
    else begin
      rx_pl_odd_sel <= csr_out.rx_payload.addr[2];
    end
  end

  always_ff @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      rx_pl_ack <= 1'b0;
    end
    else begin
      rx_pl_ack <= rx_pl_rd;
    end
  end

  assign csr_in.rx_payload.rd_ack             = rx_pl_ack;
  assign csr_in.rx_payload.rd_data            = rx_pl_odd_sel ? rx_pl_odd_q : rx_pl_even_q;
  assign csr_in.rx_payload.wr_ack             = 1'b0;  // read-only

  assign csr_in.rx.header0.hdr.we             = rx_dw0;
  assign csr_in.rx.header0.hdr.next           = rx_data.dw01.dw0;
  assign csr_in.rx.header1.hdr.we             = rx_dw0;
  assign csr_in.rx.header1.hdr.next           = rx_data.dw01.dw1;
  assign csr_in.rx.header2.hdr.we             = rx_dw2;
  assign csr_in.rx.header2.hdr.next           = rx_data.dw23.dw2;
  assign csr_in.rx.data.payload.we            = rx_dw2;
  assign csr_in.rx.data.payload.next          = rx_data.dw23.dw3.data;
  assign csr_in.rx.valid.valid.hwset          = rx_beat & m_axis_rx.tlast;

  // ---- Status: straight from the PCIe core, no shadow registers ----------
  assign csr_in.status.err.msg_err_fatal.next = cfg.msg_err_fatal;

  assign csr_in.status.phy.tx_state.next      = tx_state;
  assign csr_in.status.phy.tx_buf_avail.next  = cfg.tx_buf_avail;
  assign csr_in.status.cfg_id.id.next         = cfg.id;

  // ---- Firmware result: the marker the firmware writes when it stops ------
  // The PASS compare drives an LED.
  localparam logic [31:0] FW_RESULT_PASS = 32'h0000_FACE;

  logic [31:0] fw_result;

  assign fw_result        = csr_out.status.result.marker.value;
  assign fw_pass          = (fw_result == FW_RESULT_PASS);

  assign m_axis_rx.tready = ~rx_valid;

  // Per-packet transmit qualifiers (tx_tuser_t, UG477 table 2-9), none
  // of which this design uses. Left undriven they are X in simulation, and
  // the core would discard every TLP.
  assign s_axis_tx.tuser  = '0;

  assign mem.rdata        = addr.bridge ? bridge_rdat : ram_rdata;

  assign mem.ready        = ram_ready | bridge_rdy;

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        April 2025
// -----------------------------------------------------------------------------
