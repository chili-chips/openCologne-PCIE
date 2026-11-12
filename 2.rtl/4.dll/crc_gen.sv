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
//----------------------------------------------------------------------------------------
// Description: Top module for the parallel crc
// - LFSR with polynomial x^16 + x^12 + x^3 + x + 1
//========================================================================================

module crc_gen
  import dll_pkg::*;
#(
    localparam int DLLP_WIDTH = 32,         // the 4 bytes a DLLP CRC covers
    localparam int LFSR_WIDTH = DLLP_CRC_W
) (
    input logic                      crc_en,
    input logic [DLLP_WIDTH - 1 : 0] data_in,

    output logic [LFSR_WIDTH - 1 : 0] calc_crc
);

  localparam int BYTE = 8;

  logic [LFSR_WIDTH-1:0] first_lfsr;
  assign first_lfsr = {LFSR_WIDTH{1'b1}};
  logic [LFSR_WIDTH*DLLP_WIDTH/BYTE - 1 : 0] lfsr_vector;
  logic [LFSR_WIDTH*DLLP_WIDTH/BYTE - 1 : 0] lfsr_out;
  logic [LFSR_WIDTH*DLLP_WIDTH/BYTE - 1 : 0] lfsr_out_inv;
  logic [              LFSR_WIDTH/2 - 1 : 0] crc_hi;
  logic [              LFSR_WIDTH/2 - 1 : 0] crc_lo;
  assign lfsr_vector  = {lfsr_out[LFSR_WIDTH*(DLLP_WIDTH/BYTE-1)-1 : 0], first_lfsr};
  assign lfsr_out_inv = ~lfsr_out;

  // Generate crc coefficients for each byte
  genvar i;
  generate
    for (i = 0; i < DLLP_WIDTH / BYTE; i = i + 1) begin : g_bytes
      crc_byte u_crc_byte (
          .data_in(data_in[i*8+:8]),
          .crc_en (crc_en),
          .crc_in (lfsr_vector[i*LFSR_WIDTH+:LFSR_WIDTH]),
          .crc_out(lfsr_out[i*LFSR_WIDTH+:LFSR_WIDTH])
      );
    end
  endgenerate

  genvar l;
  for (l = 0; l < LFSR_WIDTH / 2; l = l + 1) begin : g_crc_hi
    assign crc_hi[l] = lfsr_out_inv[LFSR_WIDTH*DLLP_WIDTH/BYTE-l-1];
  end

  genvar m;
  for (m = 0; m < LFSR_WIDTH / 2; m = m + 1) begin : g_crc_lo
    assign crc_lo[m] = lfsr_out_inv[LFSR_WIDTH*DLLP_WIDTH/BYTE-LFSR_WIDTH/2-m-1];
  end

  assign calc_crc = {crc_lo, crc_hi};

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Jan 10, 2026
// -----------------------------------------------------------------------------
