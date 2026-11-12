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

module tlp_order #(
    parameter int TLP_ADDR_W = 4
) (
    input  logic clk,
    input  logic rst_n,
    input  logic p_commit,
    input  logic p_done,
    input  logic np_commit,
    input  logic np_done,
    output logic np_ready
);

  localparam int TLP_DEPTH = 1 << TLP_ADDR_W;

  logic [           7:0] p_seen       [TLP_DEPTH];
  logic [TLP_ADDR_W-1:0] wr_ptr;
  logic [TLP_ADDR_W-1:0] rd_ptr;
  logic [           7:0] p_commit_cnt;
  logic [           7:0] p_done_cnt;
  logic [           7:0] np_wait;

  assign np_wait  = p_seen[rd_ptr] - p_done_cnt;
  assign np_ready = (np_wait == 8'd0) | np_wait[7];

  always_ff @(posedge clk) begin
    if (np_commit) begin
      p_seen[wr_ptr] <= p_commit_cnt;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr       <= '0;
      rd_ptr       <= '0;
      p_commit_cnt <= '0;
      p_done_cnt   <= '0;
    end
    else begin
      if (np_commit) begin
        wr_ptr <= wr_ptr + 1'b1;
      end
      if (np_done) begin
        rd_ptr <= rd_ptr + 1'b1;
      end
      if (p_commit) begin
        p_commit_cnt <= p_commit_cnt + 8'd1;
      end
      if (p_done) begin
        p_done_cnt <= p_done_cnt + 8'd1;
      end
    end
  end

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Oct 21, 2026
// -----------------------------------------------------------------------------
