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

// PCIE descriptors: every TLP header and sideband bit position lives here, and
// only here. The RTL declares signals of these types and uses their members.
//
// Layout of the 64-bit transaction interface between the SOC and the TL
// (TRN_DATA_W = 64), the same as on openPCIE, where it is the interface of
// the AMD PCIE_2_1 hard macro (UG477 in 0.doc/2.rtl, tables 2-9 / 2-10): a TLP starts with
// header DW0 in tdata[31:0] and DW1 in tdata[63:32]; DW2 and DW3 follow in
// the next beat.
// Header fields follow the PCI Express Base Specification. Reserved bits are
// listed as rsvd0, rsvd1, ... so that each struct spans its full width.
// The TL's own types, codes and header decoder follow the descriptors.

package tl_pkg;

  import dll_pkg::*;  // dl_state_e, dllp_type_e, fc_class_e
  import trn_pkg::*;  // TRN_DATA_W

  // ---- TLP header codes, named so a waveform viewer shows them --------------

  // Fmt[1:0]: [0] 4-DW header, [1] with data
  typedef enum logic [1:0] {
    TLP_FMT_3DW      = 2'd0,
    TLP_FMT_4DW      = 2'd1,
    TLP_FMT_3DW_DATA = 2'd2,
    TLP_FMT_4DW_DATA = 2'd3
  } tlp_fmt_e;

  // Type[4:0]
  typedef enum logic [4:0] {
    TLP_TYPE_MEM        = 5'd0,
    TLP_TYPE_MEM_LK     = 5'd1,
    TLP_TYPE_IO         = 5'd2,
    TLP_TYPE_CFG0       = 5'd4,
    TLP_TYPE_CFG1       = 5'd5,
    TLP_TYPE_CPL        = 5'd10,  // Completion (Cpl, CplD)
    TLP_TYPE_CPL_LK     = 5'd11,
    TLP_TYPE_FETCH_ADD  = 5'd12,
    TLP_TYPE_SWAP       = 5'd13,
    TLP_TYPE_CAS        = 5'd14,
    TLP_TYPE_MSG_RC     = 5'd16,  // Message, routed to the Root Complex
    TLP_TYPE_MSG_ADDR   = 5'd17,
    TLP_TYPE_MSG_ID     = 5'd18,
    TLP_TYPE_MSG_BCAST  = 5'd19,
    TLP_TYPE_MSG_LOCAL  = 5'd20,
    TLP_TYPE_MSG_GATHER = 5'd21
  } tlp_type_e;

  // Parts of Type[4:0] the decoder matches on
  localparam logic [3:0] TLP_TYPE_CFG = 4'd2;  // Type[4:1]: Configuration; Type[0]: 0 or 1
  localparam logic [1:0] TLP_TYPE_MSG = 2'd2;  // Type[4:3]: Message; Type[2:0]: routing

  // Message codes
  typedef enum logic [7:0] {
    MSG_UNLOCK         = 8'd0,
    MSG_PM_ASPM_NAK    = 8'd20,
    MSG_PME_TURN_OFF   = 8'd25,
    MSG_PME_TO_ACK     = 8'd27,
    MSG_ERR_NONFATAL   = 8'd49,
    MSG_ERR_FATAL      = 8'd51,
    MSG_IGNORED_FIRST  = 8'd64,  // the Ignored Messages, up to MSG_IGNORED_LAST
    MSG_IGNORED_LAST   = 8'd72,
    MSG_SET_SLOT_POWER = 8'd80,
    MSG_VENDOR_TYPE1   = 8'd127
  } msg_code_e;

  // Message routing, Type[2:0]
  typedef enum logic [2:0] {
    MSG_ROUTE_TO_RC  = 3'd0,
    MSG_ROUTE_GATHER = 3'd5
  } msg_route_e;

  // Completion status
  typedef enum logic [2:0] {
    CPL_SC = 3'd0,  // successful
    CPL_UR = 3'd1   // unsupported request
  } cpl_status_e;

  // ---- TLP header -----------------------------------------------------------

  // TLP sizes
  typedef logic [9:0] tlp_len_t;  // the Length field: payload DWs, 0 = 1024
  typedef logic [10:0] tlp_dw_cnt_t;  // payload DWs, 1 .. 1024
  typedef logic [11:0] tlp_dws_t;  // the whole TLP in DWs: header, payload, digest
  typedef logic [10:0] tlp_words_t;  // the whole TLP in 64-bit words

  // DW0, common to all TLPs
  typedef struct packed {
    logic       rsvd0;     // [31]
    tlp_fmt_e   fmt;       // [30:29]
    tlp_type_e  tlp_type;  // [28:24]
    logic       rsvd1;     // [23]
    logic [2:0] tc;        // [22:20] traffic class
    logic [3:0] rsvd2;     // [19:16]
    logic       td;        // [15]   TLP digest (ECRC) present
    logic       ep;        // [14]   poisoned
    logic [1:0] attr;      // [13:12]
    logic [1:0] rsvd3;     // [11:10]
    tlp_len_t   length;    // [9:0]  payload length in DW, 0 = 1024
  } dw0_t;

  // A PCIe function: Requester ID, Completer ID, the Core ID
  typedef struct packed {
    logic [7:0] bus;     // [15:8]
    logic [4:0] device;  // [7:3]
    logic [2:0] func;    // [2:0]
  } pcie_id_t;

  // Completion DW1
  typedef struct packed {
    pcie_id_t    completer_id;  // [31:16]
    cpl_status_e cpl_status;    // [15:13]
    logic        bcm;           // [12]
    logic [11:0] byte_count;    // [11:0]
  } dw1_cpl_t;

  // Completion DW2
  typedef struct packed {
    pcie_id_t   requester_id;  // [31:16]
    logic [7:0] tag;           // [15:8]
    logic       rsvd0;         // [7]
    logic [6:0] lower_addr;    // [6:0]
  } dw2_cpl_t;

  // Configuration request DW2
  typedef struct packed {
    pcie_id_t   id;       // [31:16] the target function
    logic [3:0] rsvd0;    // [15:12]
    logic [3:0] ext_reg;  // [11:8]
    logic [5:0] reg_num;  // [7:2]
    logic [1:0] rsvd1;    // [1:0]
  } dw2_cfg_t;

  typedef struct packed {
    pcie_id_t   requester_id;  // [31:16]
    logic [7:0] tag;           // [15:8]
    logic [3:0] last_be;       // [7:4]
    logic [3:0] first_be;      // [3:0]
  } dw1_req_t;

  typedef struct packed {
    pcie_id_t   requester_id;  // [31:16]
    logic [7:0] tag;           // [15:8]
    msg_code_e  msg_code;      // [7:0]
  } dw1_msg_t;

  typedef struct packed {
    logic [29:0] addr;   // [31:2]
    logic [1:0]  rsvd0;  // [1:0]
  } dw_addr_lo_t;

  // Header words whose layout depends on the TLP kind. The low address word
  // (Address[31:2]) is DW2 in a 3DW header, DW3 in a 4DW one, where DW2 holds
  // Address[63:32]
  typedef union packed {
    dw1_req_t req;  // [31:0] requests
    dw1_cpl_t cpl;  // [31:0] completions
    dw1_msg_t msg;  // [31:0] messages
  } dw1_t;

  typedef union packed {
    dw2_cpl_t    cpl;      // [31:0] completions
    dw2_cfg_t    cfg;      // [31:0] configuration requests
    dw_addr_lo_t addr_lo;  // [31:0] memory and IO requests, 3DW header
    logic [31:0] addr_hi;  // [31:0] memory requests, 4DW header: Address[63:32]
  } dw2_t;

  typedef union packed {
    dw_addr_lo_t addr_lo;  // [31:0] memory requests, 4DW header
    logic [31:0] data;     // [31:0] 3DW header with data: the first payload DW
  } dw3_t;

  // First beat of a TLP on the 64-bit bus
  typedef struct packed {
    dw1_t dw1;  // [63:32]
    dw0_t dw0;  // [31:0]
  } hdr_dw01_t;

  typedef struct packed {
    dw3_t dw3;  // [63:32]
    dw2_t dw2;  // [31:0]
  } hdr_dw23_t;

  typedef logic [3:0][7:0] dw_bytes_t;

  function automatic logic [31:0] dw_byte_swap(input dw_bytes_t dw);
    return {dw[0], dw[1], dw[2], dw[3]};
  endfunction

  // the DLL <-> TL byte order of a word: byte 0 of each DW in [31:24]
  function automatic logic [TRN_DATA_W-1:0] wire_byte_swap(
      input dw_bytes_t [TRN_DATA_W/32-1:0] beat);
    logic [TRN_DATA_W/32-1:0][31:0] swapped;
    for (int i = 0; i < TRN_DATA_W / 32; i++) begin
      swapped[i] = dw_byte_swap(beat[i]);
    end
    return swapped;
  endfunction

  // Configuration space IDs, the defaults of tl_top and config_space; the RC
  // model expects the same (5.sim/usercode/a7rc_ep.h). Placeholders, not
  // assigned by PCI-SIG
  localparam logic [15:0] PCIE_VENDOR_ID        = 16'hCC00;
  localparam logic [15:0] PCIE_DEVICE_ID        = 16'hCC00;
  localparam logic [15:0] PCIE_SUBSYS_VENDOR_ID = 16'h0000;
  localparam logic [15:0] PCIE_SUBSYS_ID        = 16'hCABA;

  typedef enum logic [3:0] {
    K_MRD     = 4'd0,
    K_MRDLK   = 4'd1,
    K_MWR     = 4'd2,
    K_IORD    = 4'd3,
    K_IOWR    = 4'd4,
    K_CFGRD0  = 4'd5,
    K_CFGWR0  = 4'd6,
    K_CFGRD1  = 4'd7,
    K_CFGWR1  = 4'd8,
    K_MSG     = 4'd9,
    K_MSGD    = 4'd10,
    K_CPL     = 4'd11,
    K_CPLD    = 4'd12,
    K_ATOMIC  = 4'd13,
    K_UNKNOWN = 4'd15
  } tlp_kind_e;

  function automatic logic [2:0] tlp_fmt(input dw0_t hdr_dw0);
    return {hdr_dw0.rsvd0, hdr_dw0.fmt};
  endfunction

  function automatic tlp_kind_e tlp_kind(input dw0_t hdr_dw0);
    tlp_kind_e       kind;
    logic      [2:0] fmt;
    fmt  = tlp_fmt(hdr_dw0);
    kind = K_UNKNOWN;
    if (hdr_dw0.tlp_type[4:3] == TLP_TYPE_MSG && hdr_dw0.tlp_type[2:0] <= 3'b101) begin
      if (fmt == {1'b0, TLP_FMT_4DW}) begin
        kind = K_MSG;
      end
      else if (fmt == {1'b0, TLP_FMT_4DW_DATA}) begin
        kind = K_MSGD;
      end
    end
    unique0 case ({
      fmt, hdr_dw0.tlp_type
    })
      {1'b0, TLP_FMT_3DW, TLP_TYPE_MEM}, {1'b0, TLP_FMT_4DW, TLP_TYPE_MEM} : kind = K_MRD;
      {1'b0, TLP_FMT_3DW, TLP_TYPE_MEM_LK}, {1'b0, TLP_FMT_4DW, TLP_TYPE_MEM_LK} : kind = K_MRDLK;
      {1'b0, TLP_FMT_3DW_DATA, TLP_TYPE_MEM}, {1'b0, TLP_FMT_4DW_DATA, TLP_TYPE_MEM} : kind = K_MWR;
      {1'b0, TLP_FMT_3DW, TLP_TYPE_IO} : kind = K_IORD;
      {1'b0, TLP_FMT_3DW_DATA, TLP_TYPE_IO} : kind = K_IOWR;
      {1'b0, TLP_FMT_3DW, TLP_TYPE_CFG, 1'b0} : kind = K_CFGRD0;
      {1'b0, TLP_FMT_3DW_DATA, TLP_TYPE_CFG, 1'b0} : kind = K_CFGWR0;
      {1'b0, TLP_FMT_3DW, TLP_TYPE_CFG, 1'b1} : kind = K_CFGRD1;
      {1'b0, TLP_FMT_3DW_DATA, TLP_TYPE_CFG, 1'b1} : kind = K_CFGWR1;
      {1'b0, TLP_FMT_3DW, TLP_TYPE_CPL}, {1'b0, TLP_FMT_3DW, TLP_TYPE_CPL_LK} : kind = K_CPL;
      {
        1'b0, TLP_FMT_3DW_DATA, TLP_TYPE_CPL
      }, {
        1'b0, TLP_FMT_3DW_DATA, TLP_TYPE_CPL_LK
      } :
      kind = K_CPLD;
      {
        1'b0, TLP_FMT_3DW_DATA, TLP_TYPE_FETCH_ADD
      }, {
        1'b0, TLP_FMT_4DW_DATA, TLP_TYPE_FETCH_ADD
      }, {
        1'b0, TLP_FMT_3DW_DATA, TLP_TYPE_SWAP
      }, {
        1'b0, TLP_FMT_4DW_DATA, TLP_TYPE_SWAP
      }, {
        1'b0, TLP_FMT_3DW_DATA, TLP_TYPE_CAS
      }, {
        1'b0, TLP_FMT_4DW_DATA, TLP_TYPE_CAS
      } :
      kind = K_ATOMIC;
    endcase
    return kind;
  endfunction

  function automatic fc_class_e tlp_class(input tlp_kind_e kind);
    fc_class_e fc_class;
    fc_class = FC_NP;
    if (kind == K_CPL || kind == K_CPLD) begin
      fc_class = FC_CPL;
    end
    else if (kind == K_MWR || kind == K_MSG || kind == K_MSGD || kind == K_UNKNOWN) begin
      fc_class = FC_P;
    end
    return fc_class;
  endfunction

  function automatic logic tlp_has_data(input dw0_t hdr_dw0);
    return hdr_dw0.fmt[1];
  endfunction

  function automatic logic tlp_4dw(input dw0_t hdr_dw0);
    return hdr_dw0.fmt[0];
  endfunction

  function automatic tlp_dw_cnt_t tlp_length_dw(input dw0_t hdr_dw0);
    return (hdr_dw0.length == 10'd0) ? 11'd1024 : {1'b0, hdr_dw0.length};
  endfunction

  function automatic fc_data_t tlp_data_credits(input dw0_t hdr_dw0);
    return tlp_has_data(hdr_dw0) ? ({1'b0, tlp_length_dw(hdr_dw0)} + 12'd3) >> 2 : 12'd0;
  endfunction

  // header and payload DWs: the TLP without its digest
  function automatic tlp_dws_t tlp_body_dw(input dw0_t hdr_dw0);
    return (tlp_4dw(hdr_dw0) ? 12'd4 : 12'd3)
         + (tlp_has_data(hdr_dw0) ? {1'b0, tlp_length_dw(hdr_dw0)} : 12'd0);
  endfunction

  // the whole TLP: header, payload and digest
  function automatic tlp_dws_t tlp_total_dw(input dw0_t hdr_dw0);
    return tlp_body_dw(hdr_dw0) + {11'd0, hdr_dw0.td};
  endfunction

  function automatic tlp_words_t tlp_words(input dw0_t hdr_dw0);
    return 11'((tlp_total_dw(hdr_dw0) + 12'd1) >> 1);
  endfunction

  function automatic logic tlp_last_half(input dw0_t hdr_dw0);
    return tlp_total_dw(hdr_dw0) % 12'd2 == 12'd1;
  endfunction

  typedef struct packed {
    logic                  valid;  // [66]
    logic                  first;  // [65]
    logic                  last;   // [64]
    logic [TRN_DATA_W-1:0] data;   // [63:0]
  } tl_beat_t;

  typedef struct packed {
    logic                  valid;  // [65]
    logic                  last;   // [64]
    logic [TRN_DATA_W-1:0] data;   // [63:0]
  } tl_app_rx_t;

  typedef struct packed {
    logic                  valid;         // [81]
    logic                  first;         // [80]
    logic                  last;          // [79]
    logic                  half;          // [78]
    fc_class_e             fc_class;      // [77:76]
    fc_data_t              data_credits;  // [75:64]
    logic [TRN_DATA_W-1:0] data;          // [63:0]
  } tl_src_t;

  typedef struct packed {
    logic                  last;  // [64]
    logic [TRN_DATA_W-1:0] data;  // [63:0]
  } tl_qword_t;

  typedef struct packed {
    logic      en;    // [66]
    logic      drop;  // [65]
    tl_qword_t word;  // [64:0]
  } tl_qwr_t;

  typedef struct packed {
    logic                  avail;  // [130]
    logic                  valid;  // [129]
    tl_qword_t             head;   // [128:64]
    logic [TRN_DATA_W-1:0] next;   // [63:0]
  } tl_qrd_t;

  typedef struct packed {
    logic      valid;     // [14]
    fc_class_e fc_class;  // [13:12]
    fc_data_t  data;      // [11:0]
  } fc_rel_t;

  typedef struct packed {
    fc_cred_t limit;     // [42:23]
    fc_cred_t consumed;  // [22:3]
    logic     inf_hdr;   // [2]
    logic     inf_data;  // [1]
    logic     init;      // [0]
  } fc_tx_t;

  typedef struct packed {
    logic        is_msg;        // [96]
    logic        with_data;     // [95]
    logic        locked;        // [94]
    logic [2:0]  tc;            // [93:91]
    logic [1:0]  attr;          // [90:89]
    pcie_id_t    requester_id;  // [88:73]
    logic [7:0]  tag;           // [72:65]
    cpl_status_e status;        // [64:62]
    logic [11:0] byte_count;    // [61:50]
    logic [6:0]  lower_addr;    // [49:43]
    logic [31:0] data;          // [42:11]
    msg_code_e   msg_code;      // [10:3]
    msg_route_e  msg_route;     // [2:0]
  } tl_cpl_t;

  // Configuration Space registers, by DW number (byte offset / 4)
  typedef enum logic [9:0] {
    R_ID       = 10'h000,
    R_CMD      = 10'h001,
    R_CLASS    = 10'h002,
    R_MISC     = 10'h003,
    R_BAR0     = 10'h004,
    R_SUBSYS   = 10'h00B,
    R_CAP_PTR  = 10'h00D,
    R_INT      = 10'h00F,
    R_PM_CAP   = 10'h010,
    R_PM_CSR   = 10'h011,
    R_PCIE_CAP = 10'h014,
    R_DEV_CAP  = 10'h015,
    R_DEV_CTL  = 10'h016,
    R_LNK_CAP  = 10'h017,
    R_LNK_CTL  = 10'h018,
    R_LNK_CTL2 = 10'h020
  } cfg_reg_e;

  // Max_Payload_Size, Max_Read_Request_Size (PCIe 2.1 7.8.3, 7.8.4); 6, 7 reserved
  typedef enum logic [2:0] {
    SZ_128B  = 3'd0,
    SZ_256B  = 3'd1,
    SZ_512B  = 3'd2,
    SZ_1024B = 3'd3,
    SZ_2048B = 3'd4,
    SZ_4096B = 3'd5
  } pcie_size_e;

  typedef struct packed {
    logic        write;   // [46]
    cfg_reg_e    regnum;  // [45:36]
    logic [3:0]  be;      // [35:32]
    logic [31:0] wdata;   // [31:0]
  } tl_cfg_acc_t;

  // PMCSR PowerState (PCI PM 1.2)
  typedef enum logic [1:0] {
    PM_D0    = 2'd0,
    PM_D1    = 2'd1,
    PM_D2    = 2'd2,
    PM_D3HOT = 2'd3
  } pm_dstate_e;

  // Capability IDs
  typedef enum logic [7:0] {
    CAP_ID_PM   = 8'h01,
    CAP_ID_PCIE = 8'h10
  } cap_id_e;

  // Link speed: Max Link Speed, Current Link Speed, Target Link Speed
  typedef enum logic [3:0] {
    SPEED_2G5 = 4'd1,
    SPEED_5G  = 4'd2
  } link_speed_e;

  // Link width: Maximum Link Width, Negotiated Link Width
  typedef enum logic [5:0] {
    WIDTH_X1 = 6'd1,
    WIDTH_X4 = 6'd4
  } link_width_e;

  // ASPM Support, ASPM Control
  typedef enum logic [1:0] {
    ASPM_NONE   = 2'd0,
    ASPM_L0S    = 2'd1,
    ASPM_L1     = 2'd2,
    ASPM_L0S_L1 = 2'd3
  } aspm_e;

  typedef struct packed {
    logic       capture;  // [13]
    logic [7:0] bus;      // [12:5]
    logic [4:0] device;   // [4:0]
  } tl_id_t;

  typedef struct packed {
    logic       capture;  // [10]
    logic [1:0] scale;    // [9:8]
    logic [7:0] value;    // [7:0]
  } tl_sspl_t;

  typedef struct packed {
    logic ur;         // [3]
    logic malformed;  // [2]
    logic overflow;   // [1]
    logic poisoned;   // [0]
  } tl_err_t;

  typedef struct packed {
    logic [7:0]  bus_number;         // [49:42]
    logic [4:0]  device_number;      // [41:37]
    logic        memory_enable;      // [36]
    logic        bus_master_enable;  // [35]
    logic [31:0] bar0_base;          // [34:3]
    pcie_size_e  max_payload_size;   // [2:0]
  } tl_cfg_t;

  typedef struct packed {
    logic [4:0] rsvd0;            // [15:11]
    logic       int_disable;      // [10]
    logic       fast_b2b;         // [9]
    logic       serr_en;          // [8]
    logic       idsel_stepping;   // [7]
    logic       parity_err_resp;  // [6]
    logic       vga_snoop;        // [5]
    logic       mwi_en;           // [4]
    logic       special_cycles;   // [3]
    logic       bus_master;       // [2]
    logic       mem_space;        // [1]
    logic       io_space;         // [0]
  } command_t;

  typedef struct packed {
    logic       detected_parity_err;     // [15]
    logic       signaled_sys_err;        // [14]
    logic       rcvd_master_abort;       // [13]
    logic       rcvd_target_abort;       // [12]
    logic       signaled_target_abort;   // [11]
    logic [1:0] devsel_timing;           // [10:9]
    logic       master_data_parity_err;  // [8]
    logic       fast_b2b_capable;        // [7]
    logic       rsvd0;                   // [6]
    logic       capable_66mhz;           // [5]
    logic       cap_list;                // [4]
    logic       int_status;              // [3]
    logic [2:0] rsvd1;                   // [2:0]
  } status_t;

  typedef struct packed {
    status_t  status;   // [31:16]
    command_t command;  // [15:0]
  } cfg_cmd_dw_t;

  typedef struct packed {
    logic       pme_status;     // [15]
    logic [1:0] data_scale;     // [14:13]
    logic [3:0] data_select;    // [12:9]
    logic       pme_en;         // [8]
    logic [3:0] rsvd0;          // [7:4]
    logic       no_soft_reset;  // [3]
    logic       rsvd1;          // [2]
    pm_dstate_e power_state;    // [1:0]
  } pm_csr_t;

  typedef struct packed {
    logic [15:0] bse_data;  // [31:16]
    pm_csr_t     csr;       // [15:0]
  } cfg_pm_dw_t;

  typedef struct packed {
    logic [2:0] rsvd0;             // [31:29]
    logic       flr_capable;       // [28]
    logic [1:0] slot_power_scale;  // [27:26]
    logic [7:0] slot_power_value;  // [25:18]
    logic [1:0] rsvd1;             // [17:16]
    logic       role_based_err;    // [15]
    logic [2:0] rsvd2;             // [14:12]
    logic [2:0] l1_accept_lat;     // [11:9]
    logic [2:0] l0s_accept_lat;    // [8:6]
    logic       ext_tag;           // [5]
    logic [1:0] phantom_func;      // [4:3]
    pcie_size_e max_payload;       // [2:0]
  } dev_cap_t;

  typedef struct packed {
    logic       initiate_flr;        // [15]
    pcie_size_e max_read_req;        // [14:12]
    logic       no_snoop_en;         // [11]
    logic       aux_power_en;        // [10]
    logic       phantom_func_en;     // [9]
    logic       ext_tag_en;          // [8]
    pcie_size_e max_payload;         // [7:5]
    logic       relaxed_ord_en;      // [4]
    logic       ur_report_en;        // [3]
    logic       fatal_report_en;     // [2]
    logic       nonfatal_report_en;  // [1]
    logic       corr_report_en;      // [0]
  } dev_ctl_t;

  typedef struct packed {
    logic [9:0] rsvd0;              // [15:6]
    logic       trans_pending;      // [5]
    logic       aux_power;          // [4]
    logic       ur_detected;        // [3]
    logic       fatal_detected;     // [2]
    logic       nonfatal_detected;  // [1]
    logic       corr_detected;      // [0]
  } dev_sta_t;

  typedef struct packed {
    dev_sta_t status;   // [31:16]
    dev_ctl_t control;  // [15:0]
  } cfg_dev_dw_t;

  typedef struct packed {
    logic [7:0]  port_number;            // [31:24]
    logic [1:0]  rsvd0;                  // [23:22]
    logic        bw_notify_cap;          // [21]
    logic        dll_active_report_cap;  // [20]
    logic        surprise_down_cap;      // [19]
    logic        clock_pm;               // [18]
    logic [2:0]  l1_exit_lat;            // [17:15]
    logic [2:0]  l0s_exit_lat;           // [14:12]
    aspm_e       aspm_support;           // [11:10]
    link_width_e max_width;              // [9:4]
    link_speed_e max_speed;              // [3:0]
  } lnk_cap_t;

  typedef struct packed {
    logic [6:0] rsvd0;         // [15:9]
    logic       clock_pm_en;   // [8]
    logic       ext_synch;     // [7]
    logic       common_clock;  // [6]
    logic       retrain;       // [5]
    logic       link_disable;  // [4]
    logic       rcb;           // [3]
    logic       rsvd1;         // [2]
    aspm_e      aspm_ctl;      // [1:0]
  } lnk_ctl_t;

  typedef struct packed {
    logic [1:0]  rsvd0;       // [15:14]
    logic        dll_active;  // [13]
    logic        slot_clock;  // [12]
    logic        training;    // [11]
    logic        rsvd1;       // [10]
    link_width_e width;       // [9:4]
    link_speed_e speed;       // [3:0]
  } lnk_sta_t;

  typedef struct packed {
    lnk_sta_t status;   // [31:16]
    lnk_ctl_t control;  // [15:0]
  } cfg_lnk_dw_t;

  typedef struct packed {
    logic [2:0]  rsvd0;                 // [15:13]
    logic        compliance_deemph;     // [12]
    logic        compliance_sos;        // [11]
    logic        enter_mod_compliance;  // [10]
    logic [2:0]  tx_margin;             // [9:7]
    logic        sel_deemph;            // [6]
    logic        hw_auto_speed_dis;     // [5]
    logic        enter_compliance;      // [4]
    link_speed_e target_speed;          // [3:0]
  } lnk_ctl2_t;

  typedef struct packed {
    logic [15:0] status;   // [31:16] Link Status 2
    lnk_ctl2_t   control;  // [15:0]
  } cfg_lnk2_dw_t;

  function automatic logic [31:0] cfg_write_merge(input logic [31:0] old, input logic [31:0] wdata,
                                                  input logic [3:0] be, input logic [31:0] wmask);
    logic [3:0][7:0] be_mask;
    for (int i = 0; i < 4; i++) begin
      be_mask[i] = {8{be[i]}};
    end
    return (old & ~(wmask & be_mask)) | (wdata & wmask & be_mask);
  endfunction

  function automatic logic [31:0] cfg_w1c(input logic [31:0] wdata, input logic [3:0] be,
                                          input logic [31:0] w1c_mask);
    logic [3:0][7:0] be_mask;
    for (int i = 0; i < 4; i++) begin
      be_mask[i] = {8{be[i]}};
    end
    return wdata & w1c_mask & be_mask;
  endfunction

endpackage

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        April 2025
// -----------------------------------------------------------------------------
