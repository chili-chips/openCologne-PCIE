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

  // Plain always, not always_ff, for every RAM port here: ram is also
  // written by $readmemh, and an always_ff variable may have no other writer
  // (IEEE 1800 9.2.2.4; VCS rejects it). One process per port, as block RAM
  // inference expects.
`ifndef SOC_CPU_VPROC
  // eduBOS5's instruction port: read-only, one cycle
  always @(posedge clk) begin
    for (int b = 0; b < 4; b++) begin  // a byte that meets its store reads X
      imem_rdat[8*b+:8] <= (ram_wr[b] & (addr.word == imem_addr[12:2])) ? 'x :
          ram[imem_addr[12:2]][8*b+:8];
    end
  end
`endif

  // the data port
  always @(posedge clk) begin
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
    if (mem.valid && !addr.bridge && (mem.wstrb != '0) && (addr.word == imem_addr[12:2])) begin
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

  // PeakRDL-generated CSR ports (u_soc_csr below)
  csr__in_t  csr_in;
  csr__out_t csr_out;

  //=========================================================================
  // PeakRDL-generated CSR
  //
  // The register storage, the read mux and the bus handshake live in the
  // generated block. What stays here is the logic that the registers
  // drive and that drives them back: the Tx side and the Rx ring.
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

  // ---- Tx: a batch of TLPs the firmware wrote into tx_payload -------------
  // The firmware writes TLPs back to back from entry 0, header first (entry
  // i is DW i of the batch), then their number into tx.send, whose write
  // starts the FSM (an external register: its write strobe, nothing stored).
  // Each TLP's DW0 gives its length, so the next one starts right after it.
  // One true-dual-port RAM of 32-bit entries: the CPU writes on port A; a
  // beat's DW 2k is read on port A, DW 2k+1 on port B, so a TLP may start at
  // any entry, odd or even.
  // The RAM is read ahead of the stream: the fetch side reads beat after beat
  // from flopped addresses into a 4-entry FIFO, and s_axis_tx takes them out
  // of it. tready reaches only the FIFO, never a RAM address (in openPCIE,
  // tready into the RAM address missed x4 Gen2's 250 MHz by 2.2 ns).
  localparam int TX_DW = 1024;  // csr.rdl: tx_payload entries
  localparam int TX_AW = $clog2(TX_DW);
  localparam int TX_FD = 4;  // FIFO entries; at most 3 are used

  typedef logic [TX_AW-1:0] tx_addr_t;

  typedef enum logic [2:0] {
    F_IDLE = 3'd0,
    F_HDR  = 3'd1,  // read beat 0 of the TLP at f_base
    F_WAIT = 3'd2,  // beat 0 out of the RAM: into the FIFO, its DW0 into f_dw0
    F_DEC  = 3'd3,  // the TLP's length, from f_dw0
    F_BODY = 3'd4   // read its other beats, while the FIFO has room
  } tx_fetch_e;

  typedef struct packed {
    logic [63:0] data;  // [72:9]
    logic [7:0]  keep;  // [8:1]
    logic        last;  // [0]
  } tx_beat_t;

  tx_fetch_e        f_state;
  logic      [ 7:0] f_left;  // TLPs of the batch still to read, this one too
  tx_addr_t         f_base;  // entry of the DW0 of the TLP being read
  tx_addr_t         f_addr;  // entry of DW 2k of the next beat to read
  logic      [31:0] f_dw0;
  tlp_dws_t         f_dws;  // DWORDs in the TLP
  tlp_words_t       f_beats;  // beats in the TLP: 18 within Max_Payload_Size, 514 at most
  tlp_words_t       f_nb;  // the next beat to read
  logic             f_room;  // the FIFO takes one more read
  logic             f_rd;  // read beat f_nb now
  logic             f_rd_q;  // its two DWORDs are out of the RAM
  logic      [ 7:0] f_keep;  // keep and last of the beat read now
  logic             f_last;
  logic      [ 7:0] f_keep_q;
  logic             f_last_q;
  logic             tx_start;
  logic             tx_pl_we;
  tx_addr_t         tx_pl_waddr;
  tx_addr_t         tx_a_addr;  // port A: the CPU's write, else DW 2k
  tx_addr_t         tx_b_addr;  // port B: DW 2k+1
  logic      [31:0] tx_pl_a_q;  // DW 2k of the beat read, a clock later
  logic      [31:0] tx_pl_b_q;  // DW 2k+1

  tx_beat_t         q[TX_FD];
  logic      [ 1:0] q_wp;
  logic      [ 1:0] q_rp;
  logic      [ 2:0] q_cnt;
  logic             q_pop;

  assign tx_start    = csr_out.tx.send.req & csr_out.tx.send.req_is_wr;  // no storage

  assign csr_in.tx.send.wr_ack = tx_start;

  // a read is issued only while the FIFO, with the read in flight, holds two
  // beats at most: then the beat it brings has a place
  assign f_room      = (q_cnt + 3'(f_rd_q)) < 3'd3;
  assign f_rd        = f_room & ((f_state == F_HDR) | ((f_state == F_BODY) & (f_nb < f_beats)));

  // beat 0 has both DWORDs (every header has 3 or 4) and is never the last;
  // beat k has DW 2k+1 when the TLP is longer
  assign f_keep      = ((f_state != F_BODY) | ({f_nb, 1'b1} < f_dws)) ? KEEP_ALL : KEEP_LO;
  assign f_last      = (f_state == F_BODY) & (f_nb == f_beats - 11'd1);

  assign tx_pl_we    = csr_out.tx_payload.req & csr_out.tx_payload.req_is_wr;
  assign tx_pl_waddr = csr_out.tx_payload.addr[TX_AW+1:2];
  assign tx_a_addr   = tx_pl_we ? tx_pl_waddr : f_addr;
  assign tx_b_addr   = f_addr + 1'b1;

  logic [31:0] tx_pl[TX_DW];

  // Port A: the CPU's write, else DW 2k. The firmware writes tx_payload only
  // while the Tx side is idle (tx_busy), so no read it needs is lost. Plain
  // always, one process per port, as for the other RAMs here
  always @(posedge clk) begin
    if (tx_pl_we) begin
      tx_pl[tx_a_addr] <= csr_out.tx_payload.wr_data;
    end
    else if (f_rd) begin
      tx_pl_a_q <= tx_pl[tx_a_addr];
    end
  end

  // Port B: DW 2k+1. A read that meets a CPU write is one the idle Tx side
  // does not use; it reads X, as the RAM does, so Yosys needs no read-first
  // logic (4.build/README.md, "Block RAM without read-first")
  always @(posedge clk) begin
    if (f_rd) begin
      tx_pl_b_q <= (tx_pl_we & (tx_pl_waddr == tx_b_addr)) ? 'x : tx_pl[tx_b_addr];
    end
  end

  assign csr_in.tx_payload.wr_ack  = tx_pl_we;
  assign csr_in.tx_payload.rd_ack  = 1'b0;  // write-only
  assign csr_in.tx_payload.rd_data = '0;

  // the fetch side
  always_ff @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      f_state  <= F_IDLE;
      f_left   <= '0;
      f_base   <= '0;
      f_addr   <= '0;
      f_dw0    <= '0;
      f_dws    <= '0;
      f_beats  <= '0;
      f_nb     <= '0;
      f_rd_q   <= 1'b0;
      f_keep_q <= '0;
      f_last_q <= 1'b0;
    end
    else begin
      f_rd_q   <= f_rd;
      f_keep_q <= f_keep;
      f_last_q <= f_last;

      unique case (f_state)
        F_IDLE: begin
          if (tx_start && (csr_out.tx.send.wr_data.count != '0)) begin
            f_left  <= csr_out.tx.send.wr_data.count;
            f_base  <= '0;
            f_addr  <= '0;
            f_state <= F_HDR;
          end
        end
        F_HDR: begin
          if (f_rd) begin
            f_state <= F_WAIT;
          end
        end
        F_WAIT: begin
          f_dw0   <= tx_pl_a_q;
          f_state <= F_DEC;
        end
        F_DEC: begin
          f_dws   <= tlp_body_dw(f_dw0);  // no digest
          f_beats <= tlp_words_t'((tlp_body_dw(f_dw0) + 12'd1) >> 1);
          f_nb    <= 11'd1;
          f_addr  <= f_base + tx_addr_t'(2);
          f_state <= F_BODY;
        end
        F_BODY: begin
          if (f_rd) begin
            f_nb   <= f_nb + 11'd1;
            f_addr <= f_addr + tx_addr_t'(2);
          end
          else if (f_nb == f_beats) begin  // every beat read
            if (f_left > 8'd1) begin  // the next TLP of the batch
              f_left  <= f_left - 8'd1;
              f_base  <= f_base + tx_addr_t'(f_dws);
              f_addr  <= f_base + tx_addr_t'(f_dws);
              f_state <= F_HDR;
            end
            else begin
              f_left  <= '0;
              f_state <= F_IDLE;
            end
          end
        end
        default: f_state <= F_IDLE;
      endcase
    end
  end

  // the FIFO: a beat goes in a clock after its read, out on a take
  assign q_pop            = s_axis_tx.tvalid & s_axis_tx.tready;

  assign s_axis_tx.tvalid = (q_cnt != 3'd0);
  assign s_axis_tx.tdata  = q[q_rp].data;
  assign s_axis_tx.tkeep  = q[q_rp].keep;
  assign s_axis_tx.tlast  = q[q_rp].last;

  // the beats are data: no reset (the pointers and the count have one)
  always_ff @(posedge clk) begin
    if (f_rd_q) begin
      q[q_wp] <= '{data: {tx_pl_b_q, tx_pl_a_q}, keep: f_keep_q, last: f_last_q};
    end
  end

  always_ff @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      q_wp  <= '0;
      q_rp  <= '0;
      q_cnt <= '0;
    end
    else begin
      if (f_rd_q) begin
        q_wp <= q_wp + 2'd1;
      end
      if (q_pop) begin
        q_rp <= q_rp + 2'd1;
      end
      q_cnt <= q_cnt + 3'(f_rd_q) - 3'(q_pop);
    end
  end

`ifndef SYNTHESIS
  // The firmware's contract: at most Max_Payload_Size (128 bytes, 32 DWORDs)
  // of payload, and the batch within tx_payload. The hardware checks neither:
  // a longer TLP goes out as its header says (the host sees a Malformed TLP),
  // and past the last entry the index wraps. Clocked checks, not an assert
  // property, which Icarus does not support (iverilog#120)
  always @(posedge clk) begin : a_tx_max_payload
    if ((f_state == F_DEC) && tlp_has_data(f_dw0) && (tlp_length_dw(f_dw0) > 11'd32)) begin
      $error("SOC_TX_CHECK: payload of %0d DWORDs, over Max_Payload_Size (32)",
             tlp_length_dw(f_dw0));
    end
    if ((f_state == F_DEC) && (32'(f_base) + 32'(tlp_body_dw(f_dw0)) > 32'(TX_DW))) begin
      $error("SOC_TX_CHECK: the batch runs past tx_payload (%0d entries)", TX_DW);
    end
    if (f_rd_q && (q_cnt == 3'(TX_FD)) && !q_pop) begin
      $error("SOC_TX_CHECK: Tx FIFO overflow");
    end
  end
`endif

  // ---- Rx: a ring of TLPs, which the firmware reads one at a time -------
  // Each TLP goes in as-is, header first, from an even entry: beat k is
  // entries 2k (DW 2k, port A) and 2k+1 (port B) past its start. The link
  // is held off only while the ring is full, so a burst of TLPs is taken at
  // link speed while the firmware works on the oldest, the head. rx_payload
  // entry i is DW i of the head. rx.valid says the head is there; writing
  // it 1 frees the head, and the next TLP becomes the head.
  // Port A is the RX beat's write, else a read: the firmware's, else the
  // head's DW0 for its length. A read never meets a write, so the RAM needs
  // no read-first logic. A read an RX beat holds off waits a clock.
  localparam int RX_DW = 1024;  // csr.rdl: rx_payload entries
  localparam int RX_AW = $clog2(RX_DW);
  localparam int RX_BW = RX_AW - 1;  // the ring in beats

  typedef logic [RX_AW-1:0] rx_addr_t;
  typedef logic [RX_BW-1:0] rx_beat_t;

  rx_beat_t        rx_wp;  // the next beat to write
  rx_beat_t        rx_rp;  // the head's first beat
  rx_beat_t        rx_head_beats;  // the head's length, from its DW0
  logic            rx_head_ok;  // the head is there: rx.valid
  logic     [ 7:0] rx_tlps;  // whole TLPs in the ring, the head too
  logic            rx_full;  // flopped: tready comes from it
  rx_beat_t        rx_wp_nx;
  rx_beat_t        rx_rp_nx;
  rx_beat_t        rx_rp_free;  // the head's end: rx_rp once it is freed
  logic            rx_free_now;
  rx_addr_t        rx_ra_idx;  // the firmware read's entry in the RAM: a flop
  logic            rx_beat;
  logic            rx_last;  // the last beat of a TLP is written
  logic            rx_free;  // the firmware frees the head

  logic            rx_pl_rd;  // the firmware's read, a one-clock request
  logic            rx_rd_q;  // a firmware read taken, not yet served
  rx_addr_t        rx_rd_idx;  // its entry in the head, kept while it waits
  logic            rx_rd_now;
  logic            rx_fetch_ok;  // the head's DW0 is to be read, from flops
  logic            rx_fetch;  // read it now: no RX beat holds port A
  logic            rx_fetch_q;  // its data is in rx_pl_q
  logic            rx_fetch_q2;  // and now in rx_head_dw0
  dw0_t            rx_head_dw0;  // the head's DW0: its length a clock later
  rx_addr_t        rx_ra;  // the read's entry in the RAM
  rx_addr_t        rx_aaddr;  // port A
  logic     [31:0] rx_pl_q;
  logic            rx_pl_ack;

  // an RX beat: DW 2k in the low half, an even entry; DW 2k+1, an odd one
  typedef struct packed {
    logic [31:0] odd;   // [63:32] DW 2k+1
    logic [31:0] even;  // [31:0] DW 2k
  } rx_pl_pair_t;

  rx_pl_pair_t rx_data;
  assign rx_data = m_axis_rx.tdata;

  // The ring is full when one more beat would meet the head. The flag is a
  // flop, made from the next pointers, so tready is a flop output (as in
  // openPCIE, where the compare did not fit 250 MHz)
  assign rx_wp_nx         = rx_wp + rx_beat_t'(rx_beat);
  assign rx_free_now      = ~rx_fetch_q2 & rx_free;
  assign rx_rp_free       = rx_rp + rx_head_beats;
  assign rx_rp_nx         = rx_free_now ? rx_rp_free : rx_rp;
  assign m_axis_rx.tready = ~rx_full;
  assign rx_beat          = m_axis_rx.tvalid & ~rx_full;
  assign rx_last          = rx_beat & m_axis_rx.tlast;

  assign rx_pl_rd  = csr_out.rx_payload.req & ~csr_out.rx_payload.req_is_wr;
  // A firmware read is taken into rx_rd_q and rx_rd_idx, and served from
  // them a clock later, or later still while RX beats hold port A: the CPU's
  // request decode never reaches the RAM address
  assign rx_rd_now   = rx_rd_q & ~rx_beat;
  assign rx_fetch_ok = ~rx_rd_q & ~rx_head_ok & ~rx_fetch_q & ~rx_fetch_q2 & (rx_tlps != 8'd0);
  assign rx_fetch    = rx_fetch_ok & ~rx_beat;
  // the address picks from flops only; rx_beat, late, only in rx_aaddr
  assign rx_ra       = rx_fetch_ok ? {rx_rp, 1'b0} : rx_ra_idx;
  assign rx_aaddr    = rx_beat ? {rx_wp, 1'b0} : rx_ra;

  assign rx_free = csr_out.rx.valid.req & csr_out.rx.valid.req_is_wr
                 & csr_out.rx.valid.wr_data.valid & csr_out.rx.valid.wr_biten.valid
                 & rx_head_ok;

  logic [31:0] rx_pl[RX_DW];

  // Port A: the beat's DW 2k, else a read. Plain always: both ports write
  // rx_pl, and an always_ff variable has one writer (IEEE 1800 9.2.2.4)
  always @(posedge clk) begin
    if (rx_beat) begin
      rx_pl[rx_aaddr] <= rx_data.even;
    end
    else begin
      rx_pl_q <= rx_pl[rx_aaddr];
    end
  end

  // Port B: DW 2k+1 of the beat
  always @(posedge clk) begin
    if (rx_beat) begin
      rx_pl[{rx_wp, 1'b1}] <= rx_data.odd;
    end
  end

  always_ff @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      rx_wp         <= '0;
      rx_rp         <= '0;
      rx_full       <= 1'b0;
      rx_head_beats <= '0;
      rx_head_ok    <= 1'b0;
      rx_tlps       <= '0;
      rx_rd_q       <= 1'b0;
      rx_rd_idx     <= '0;
      rx_ra_idx     <= '0;
      rx_fetch_q    <= 1'b0;
      rx_fetch_q2   <= 1'b0;
      rx_head_dw0   <= '0;
      rx_pl_ack     <= 1'b0;
    end
    else begin
      rx_wp   <= rx_wp_nx;
      rx_rp   <= rx_rp_nx;
      // both compares in parallel, the late rx_free picks (9 bits: wraps)
      rx_full <= rx_free_now ? (rx_wp_nx + 1'b1 == rx_rp_free) : (rx_wp_nx + 1'b1 == rx_rp);
      rx_tlps <= rx_tlps + 8'(rx_last) - 8'(rx_free);

      // the firmware's read: taken now, served in the next clock without a beat
      if (rx_pl_rd) begin
        rx_rd_idx <= csr_out.rx_payload.addr[RX_AW+1:2];
      end
      rx_rd_q    <= rx_pl_rd | (rx_rd_q & rx_beat);
      // its entry in the RAM, ready when it is served; the head does not
      // move under a read (the firmware frees it only after its reads)
      rx_ra_idx  <= {rx_rp_nx, 1'b0} + (rx_pl_rd ? csr_out.rx_payload.addr[RX_AW+1:2] : rx_rd_idx);
      rx_pl_ack  <= rx_rd_now;

      // the head: its length from its DW0, then freed by the firmware
      rx_fetch_q  <= rx_fetch;
      rx_fetch_q2 <= rx_fetch_q;
      if (rx_fetch_q) begin
        rx_head_dw0 <= rx_pl_q;
      end
      if (rx_fetch_q2) begin
        rx_head_beats <= rx_beat_t'(tlp_words(rx_head_dw0));
        rx_head_ok    <= 1'b1;
      end
      else if (rx_free) begin
        rx_head_ok <= 1'b0;
      end
    end
  end

  assign csr_in.rx_payload.rd_ack     = rx_pl_ack;
  assign csr_in.rx_payload.rd_data    = rx_pl_q;
  assign csr_in.rx_payload.wr_ack     = 1'b0;  // read-only

  // rx.valid: external, read straight from rx_head_ok; writing 1 frees
  assign csr_in.rx.valid.rd_ack       = csr_out.rx.valid.req & ~csr_out.rx.valid.req_is_wr;
  assign csr_in.rx.valid.rd_data.valid = rx_head_ok;
  assign csr_in.rx.valid.wr_ack       = csr_out.rx.valid.req & csr_out.rx.valid.req_is_wr;

`ifndef SYNTHESIS
  // Simulation-only check (Icarus has no concurrent assertions): the ring
  // full with no whole TLP in it, a TLP longer than the ring, stalls RX for
  // good. Checked on the write side: such a TLP never reaches the head
  always @(posedge clk) begin
    if (rx_full && (rx_tlps == 8'd0)) begin
      $error("soc_top: an RX TLP longer than the ring (%0d beats) stalls RX", RX_DW / 2 - 1);
    end
  end
`endif

  // ---- Status: straight from the PCIe core, no shadow registers ----------
  assign csr_in.status.phy.tx_busy.next = (f_state != F_IDLE) | f_rd_q | (q_cnt != 3'd0);
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
