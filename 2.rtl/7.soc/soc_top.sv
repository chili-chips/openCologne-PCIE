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

  // GateMate block RAM has no read-first mode, so a read that meets a write
  // of the same word reads X here, as it does in the RAM: Yosys then needs
  // no read-first logic, and simulation matches the hardware (4.build/
  // README.md, "Block RAM without read-first"). The data port is write,
  // else read; the instruction port meets a store only if the firmware
  // overwrote the instruction it fetches, which it does not (a_ram_rw).
  logic [3:0] ram_wr;  // the byte lanes a store writes

  assign ram_wr = {4{mem.valid & ~addr.bridge}} & mem.wstrb;

  logic [31:0] ram[2048];
  initial begin
    $readmemh("firmware.hex", ram);
  end

`ifndef SOC_CPU_VPROC
  // eduBOS5's instruction port: read-only, one cycle
  always_ff @(posedge clk) begin
    for (int b = 0; b < 4; b++) begin  // a byte that meets its store reads X
      imem_rdat[8*b+:8] <= (ram_wr[b] & (addr.word == imem_addr[12:2])) ? 'x :
          ram[imem_addr[12:2]][8*b+:8];
    end
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

`ifndef SYNTHESIS
`ifndef SOC_CPU_VPROC
  always @(posedge clk) begin : a_ram_rw
    if (resetn && mem.valid && !addr.bridge && (mem.wstrb != '0) &&
        (addr.word == imem_addr[12:2])) begin
      $error("soc_top: a store to word %0d meets its instruction fetch", addr.word);
    end
  end
`endif
`endif

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

  typedef enum logic [1:0] {
    IDLE = 2'd0,
    PREP = 2'd1,  // beat 0 is out of the banks: decode DW0, load beat 0
    SEND = 2'd2   // beats out, one per take
  } tx_state_e;
  tx_state_e tx_state;

  // PeakRDL-generated CSR ports (u_soc_csr below)
  csr__in_t  csr_in;
  csr__out_t csr_out;

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

  // ---- Tx: the TLP the firmware wrote into tx_payload ---------------------
  // Entry i of tx_payload is DW i, header first. Writing tx.send launches the
  // transfer (an external register: its write strobe, nothing stored). Beat k
  // carries DW 2k (low half) and DW 2k+1. tx_payload is two banks, even and
  // odd entries, so that both DWORDs of a beat are read in one clock; the
  // read is registered, so beat tx_ra is read a clock ahead.
  localparam int PAYLOAD_DW = 64;  // csr.rdl: tx_payload, rx_payload entries

  logic            tx_start;
  logic     [31:0] tx_pl_even_q;  // DW 2k of beat tx_ra, a clock later
  logic     [31:0] tx_pl_odd_q;  // DW 2k+1
  tlp_dws_t        tx_dws;  // DWORDs in the TLP
  tlp_dws_t        tx_dws_now;  // the same, from DW0 itself in PREP
  logic     [ 5:0] tx_beats;  // beats in the TLP, at most 18 (a_tx_max_payload)
  logic     [ 5:0] tx_beats_now;
  logic     [ 5:0] tx_nb;  // next beat to load
  logic     [ 4:0] tx_ra;  // beat whose two DWORDs are read from the banks
  logic            tx_take;
  logic            tx_adv;  // load beat tx_nb
  logic     [ 4:0] tx_pl_widx;
  logic            tx_pl_we;

  assign tx_start = csr_out.tx.send.req & csr_out.tx.send.req_is_wr;  // no storage

  assign csr_in.tx.send.wr_ack = tx_start;

  // Fmt[0]: 4-DW header; Fmt[1]: with data, Length DWORDs (0: 1024)
  assign tx_dws_now = (tx_state == PREP) ? tlp_body_dw(tx_pl_even_q) : tx_dws;  // no digest
  assign tx_beats_now = (tx_state == PREP) ? 6'((tx_dws_now + 12'd1) >> 1) : tx_beats;

  assign tx_take = s_axis_tx.tvalid & s_axis_tx.tready;
  assign tx_adv = (tx_state == PREP) | ((tx_state == SEND) & tx_take & (tx_nb < tx_beats));
  assign tx_ra = 5'(tx_adv ? tx_nb + 6'd1 : tx_nb);
  assign tx_pl_widx = csr_out.tx_payload.addr[7:3];
  assign tx_pl_we = csr_out.tx_payload.req & csr_out.tx_payload.req_is_wr;

  // the two banks: even entries 0, 2, 4 ..., odd entries 1, 3, 5 ...
  logic [31:0] tx_pl_even[PAYLOAD_DW/2];
  logic [31:0] tx_pl_odd [PAYLOAD_DW/2];

  // Write, else read, so each bank maps to block RAM with no read-first
  // logic (4.build/README.md, "Block RAM without read-first"). The firmware
  // writes tx_payload only while the Tx FSM is idle, so no read is lost
  always_ff @(posedge clk) begin
    if (tx_pl_we && csr_out.tx_payload.addr[2]) begin
      tx_pl_odd[tx_pl_widx] <= csr_out.tx_payload.wr_data;
    end
    else begin
      tx_pl_odd_q <= tx_pl_odd[tx_ra];
    end
  end

  always_ff @(posedge clk) begin
    if (tx_pl_we && !csr_out.tx_payload.addr[2]) begin
      tx_pl_even[tx_pl_widx] <= csr_out.tx_payload.wr_data;
    end
    else begin
      tx_pl_even_q <= tx_pl_even[tx_ra];
    end
  end

  assign csr_in.tx_payload.wr_ack  = tx_pl_we;
  assign csr_in.tx_payload.rd_ack  = 1'b0;  // write-only
  assign csr_in.tx_payload.rd_data = '0;

  // IDLE reads beat 0 (tx_nb 0), so it is out of the banks in PREP, a clock
  // after the tx.send write (the CPU bus does one access a clock)
  always_ff @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      tx_state         <= IDLE;
      s_axis_tx.tvalid <= 1'b0;
      s_axis_tx.tdata  <= '0;
      s_axis_tx.tkeep  <= '0;
      s_axis_tx.tlast  <= 1'b0;
      tx_dws           <= '0;
      tx_beats         <= '0;
      tx_nb            <= '0;
    end
    else begin
      if (tx_adv) begin
        s_axis_tx.tdata  <= {tx_pl_odd_q, tx_pl_even_q};
        s_axis_tx.tkeep  <= (12'({tx_nb, 1'b1}) < tx_dws_now) ? KEEP_ALL : KEEP_LO;  // DW 2k+1?
        s_axis_tx.tlast  <= (tx_nb == tx_beats_now - 6'd1);
        s_axis_tx.tvalid <= 1'b1;
        tx_nb            <= tx_nb + 6'd1;
      end

      unique case (tx_state)
        IDLE: begin
          if (tx_start) begin
            tx_state <= PREP;
          end
        end
        PREP: begin
          tx_dws   <= tx_dws_now;
          tx_beats <= tx_beats_now;
          tx_state <= SEND;
        end
        SEND: begin
          if (tx_take && (tx_nb == tx_beats)) begin  // the last beat is taken
            s_axis_tx.tvalid <= 1'b0;
            s_axis_tx.tlast  <= 1'b0;
            tx_nb            <= '0;
            tx_state         <= IDLE;
          end
        end
        default: tx_state <= IDLE;
      endcase
    end
  end

`ifndef SYNTHESIS
  // The firmware's contract: at most Max_Payload_Size (128 bytes, 32 DWORDs)
  // of payload. The hardware does not check it: a longer TLP goes out as its
  // header says (the host sees a Malformed TLP), and past 64 DWORDs the
  // tx_payload index wraps. A clocked check, not an assert property, which
  // Icarus does not support (iverilog#120)
  always @(posedge clk) begin : a_tx_max_payload
    if (resetn && (tx_state == PREP) && tlp_has_data(
            tx_pl_even_q
        ) && (tlp_length_dw(
            tx_pl_even_q
        ) > 11'd32)) begin
      $error("SOC_TX_CHECK: payload of %0d DWORDs, over Max_Payload_Size (32)", tlp_length_dw(
             tx_pl_even_q));
    end
  end
`endif

  // ---- Rx: a TLP written into rx_payload as-is ----------------------------
  // Beat k carries DW 2k (low half) and DW 2k+1, so entry i of rx_payload is
  // DW i, header first. One true-dual-port RAM of 32-bit entries takes a
  // beat in one clock: DW 2k on port A, DW 2k+1 on port B. The firmware reads
  // one DWORD on port A, so there is no bank mux on the read. DWORDs past the
  // last entry are dropped. rx.valid is set at the end of the TLP and holds
  // the link off until the firmware clears it.
  localparam int RX_BEATS = PAYLOAD_DW / 2;  // beats the RAM holds

  logic        rx_valid;
  logic        rx_beat;
  logic        rx_we;
  logic [ 5:0] rx_k;  // beat k of the TLP, held at RX_BEATS past the last

  logic [31:0] rx_pl_q;
  logic        rx_pl_rd;
  logic        rx_pl_ack;
  logic [ 5:0] rx_pl_aaddr;  // port A: the beat's DW 2k, or the firmware's read

  // an RX beat: DW 2k in the low half, an even entry; DW 2k+1, an odd one
  typedef struct packed {
    logic [31:0] odd;   // [63:32] DW 2k+1
    logic [31:0] even;  // [31:0] DW 2k
  } rx_pl_pair_t;

  rx_pl_pair_t rx_data;
  assign rx_data  = m_axis_rx.tdata;

  assign rx_valid = csr_out.rx.valid.valid.value;
  assign rx_beat  = m_axis_rx.tvalid & m_axis_rx.tready;
  assign rx_we    = rx_beat & (rx_k < 6'(RX_BEATS));

  always_ff @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      rx_k <= '0;
    end
    else if (rx_beat && m_axis_rx.tlast) begin
      rx_k <= '0;
    end
    else if (rx_we) begin
      rx_k <= rx_k + 6'd1;
    end
  end

  assign rx_pl_rd    = csr_out.rx_payload.req & ~csr_out.rx_payload.req_is_wr;
  assign rx_pl_aaddr = rx_we ? {5'(rx_k), 1'b0} : csr_out.rx_payload.addr[7:2];

  logic [31:0] rx_pl[PAYLOAD_DW];

  // Port A: write, else read. The firmware reads only while rx.valid holds
  // the link off, so no read meets a write, and Yosys sees the two ports
  // never collide
  always_ff @(posedge clk) begin
    if (rx_we) begin
      rx_pl[rx_pl_aaddr] <= rx_data.even;
    end
    else begin
      rx_pl_q <= rx_pl[rx_pl_aaddr];
    end
  end

  // Port B: DW 2k+1 of the beat
  always_ff @(posedge clk) begin
    if (rx_we) begin
      rx_pl[{5'(rx_k), 1'b1}] <= rx_data.odd;
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

  assign csr_in.rx_payload.rd_ack       = rx_pl_ack;
  assign csr_in.rx_payload.rd_data      = rx_pl_q;
  assign csr_in.rx_payload.wr_ack       = 1'b0;  // read-only

  assign csr_in.rx.valid.valid.hwset    = rx_beat & m_axis_rx.tlast;

  // ---- Status: straight from the PCIe core, no shadow registers ----------
  assign csr_in.status.phy.tx_busy.next = (tx_state != IDLE);
  assign csr_in.status.cfg_id.id.next   = cfg.id;

  // ---- Firmware result: the marker the firmware writes when it stops ------
  // Only whether it is PASS is kept, for the LED
  localparam logic [31:0] FW_RESULT_PASS = 32'h0000_FACE;

  logic fw_result_wr;

  assign fw_result_wr                = csr_out.status.result.req & csr_out.status.result.req_is_wr;
  assign csr_in.status.result.wr_ack = fw_result_wr;

  always_ff @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      fw_pass <= 1'b0;
    end
    else if (fw_result_wr) begin
      fw_pass <= (csr_out.status.result.wr_data.marker == FW_RESULT_PASS);
    end
  end

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
