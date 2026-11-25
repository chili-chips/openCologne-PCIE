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
//==========================================================================

// The LCRC of the words of a TLP in two stages (#15). Stage 1 registers each
// word's data part (lcrc_part, the wide XOR over the data); stage 2 adds the
// state's part (lcrc_state, 32 inputs). Only stage 2 is in the loop.
// crc covers the words up to the clock before: a word in at clock t is in crc
// at t+1, from the stage 1 registers, as a register of the one-stage LCRC had it.
module lcrc_pipe
  import pipe_pkg::*;
  import dll_pkg::*;
(
    input  logic              clk,
    input  logic              reset,

    input  logic              en,         // a word of the TLP
    input  logic              seq,        // its first: the sequence number goes ahead
    input  logic              half,       // only its lower half (the last DW)
    input  pipe_data_t        data,
    input  logic       [15:0] seq_bytes,  // byte 0 in [7:0]

    output lcrc_t             crc
);

  logic  part_en;
  logic  part_seq;
  logic  part_half;
  lcrc_t part;
  lcrc_t crc_q;

  // part feeds the FSMs' LCRC check through crc: a control flop, reset
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      part_en   <= 1'b0;
      part_seq  <= 1'b0;
      part_half <= 1'b0;
      part      <= '0;
      crc_q     <= '1;
    end
    else begin
      part_en <= en;
      if (en) begin
        part_seq  <= seq;
        part_half <= half;
        part      <= lcrc_part(data, seq_bytes, seq, half);
      end
      crc_q <= crc;
    end
  end

  // a first word's state is the seed, already in its part
  always_comb begin
    crc = crc_q;
    if (part_en && part_seq) begin
      crc = part;
    end
    else if (part_en) begin
      crc = lcrc_state(crc_q, part_half) ^ part;
    end
  end

endmodule
// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Nov 24, 2026
// -----------------------------------------------------------------------------
