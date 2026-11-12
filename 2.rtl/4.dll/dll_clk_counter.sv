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
//----------------------------------------------------------------------------------
// Description: This is a generic clock counter module
// - Count up at each clock cycle until reaching a target count value
// - Reset enabled zeros out the count
// - Flag output is set when the target count value is reached and hold until reset
//==================================================================================

module dll_clk_counter #(
    parameter int BIT_WIDTH = 21  // Width of Count Register
) (
    input  logic                 i_clk,
    input  logic                 i_reset,    // Asynchronous Reset
    input  logic                 i_clear,    // Synchronous Clear
    input  logic [BIT_WIDTH-1:0] max_count,  // Max Count
    output logic                 o_flag      // Output Flag when Count reaches max count
);

  logic [BIT_WIDTH-1:0] s_count;

  always_ff @(posedge i_clk, posedge i_reset) begin
    if (i_reset == 1'b1) begin
      o_flag  <= 1'b0;
      s_count <= {BIT_WIDTH{1'b0}};
    end
    else if (i_clear == 1'b1) begin
      o_flag  <= 1'b0;
      s_count <= {BIT_WIDTH{1'b0}};
    end
    else begin
      if (s_count >= max_count - 1) begin
        o_flag  <= 1'b1;
        s_count <= {BIT_WIDTH{1'b0}};
      end
      else begin
        o_flag  <= 1'b0;
        s_count <= s_count + 1'b1;
      end
    end
  end

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Sep 29, 2026
// -----------------------------------------------------------------------------
