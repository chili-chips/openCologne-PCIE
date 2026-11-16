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

// No `timescale: 1ns/10ps from the simulator command line; every delay
// carries its unit.

module tb_dll_wavecrux
  import pipe_pkg::*;
;

    localparam CLK_PERIOD = 10; // ns

    reg                     phy_clk;
    reg                     phy_reset;
    reg                     phy_linkup;

    pipe_data_t    phy_rx_data;
    pipe_flags_t   phy_rx_data_k;

    pipe_data_t    tl_tx_data;
    reg                     tl_tx_tlp_valid;
    reg                     tl_tx_tlp_first;
    reg                     tl_tx_tlp_last;
    wire                    tl_tx_tlp_ready;

    reg  [7:0]              tl_tx_hdr_credit;
    reg  [11:0]             tl_tx_data_credit;
    reg  [1:0]              tl_tx_update_type;
    reg  [1:0]              tl_tx_packet_type;
    reg                     tl_tx_dllp_valid;

    pipe_data_t    phy_tx_data;
    pipe_flags_t   phy_tx_data_k;

    pipe_data_t    tl_rx_data;
    wire                    tl_rx_tlp_valid;
    wire                    tl_rx_tlp_first;
    wire                    tl_rx_tlp_last;

    wire [7:0]              tl_rx_hdr_credit;
    wire [11:0]             tl_rx_data_credit;
    wire [1:0]              tl_rx_update_type;
    wire [1:0]              tl_rx_packet_type;
    wire                    tl_rx_dllp_valid;

    integer errors;

    pipe_data_t     tlp_words [15:0];

    reg                     external_en;
    pipe_data_t    external_data;

    reg                     flip_one_bit;
mac_if mac ();
dll_if tl ();


    dll_top #(
        .NUMBER_OF_VIRTUAL_CHANNELS(1)
    ) dut (
        .phy_clk(phy_clk),
        .phy_reset(phy_reset),
        .mac (mac),
        .tl (tl)

);
    assign mac.link_up     = phy_linkup;
    assign mac.ltssm_state = phy_linkup ? mac_pkg::L0 : mac_pkg::DETECT_QUIET;
    assign mac.rx.data = phy_rx_data;
    assign mac.rx.kcode = phy_rx_data_k;
    assign tl.tx_tlp.data = tl_tx_data;
    assign tl.tx_tlp.valid = tl_tx_tlp_valid;
    assign tl.tx_tlp.first = tl_tx_tlp_first;
    assign tl.tx_tlp.last = tl_tx_tlp_last;
    assign tl.tx_tlp.half = 1'b0;
    assign tl_tx_tlp_ready = tl.tx_tlp_ready;
    assign tl.tx_dllp = {tl_tx_dllp_valid, dll_pkg::dllp_type_e'(tl_tx_packet_type),
                         dll_pkg::fc_class_e'(tl_tx_update_type), tl_tx_hdr_credit, tl_tx_data_credit};
    assign phy_tx_data = mac.tx.data;
    assign phy_tx_data_k = mac.tx.kcode;
    assign tl_rx_data = tl.rx_tlp.data;
    assign tl_rx_tlp_valid = tl.rx_tlp.valid;
    assign tl_rx_tlp_first = tl.rx_tlp.first;
    assign tl_rx_tlp_last = tl.rx_tlp.last;
    assign tl_rx_hdr_credit = tl.rx_dllp.cred.hdr;
    assign tl_rx_data_credit = tl.rx_dllp.cred.data;
    assign tl_rx_update_type = tl.rx_dllp.update_type;
    assign tl_rx_packet_type = tl.rx_dllp.packet_type;
    assign tl_rx_dllp_valid = tl.rx_dllp.valid;

    initial phy_clk = 1'b0;
    always #(CLK_PERIOD/2 * 1ns) phy_clk = ~phy_clk;

    // 1. We can inject external data into DLL with external_en and external_data
    // 2. flip one bit flag will flip one bit of received data to corrupt it. lcrc check should fail
    // 3. Normal loopback
    always @(posedge phy_clk or posedge phy_reset) begin
        if (phy_reset) begin
            phy_rx_data <= {DATA_WIDTH{1'b0}};
            phy_rx_data_k <= {DATA_BYTES{1'b0}};
        end else if (external_en) begin
            phy_rx_data <= external_data;
            phy_rx_data_k <= {DATA_BYTES{1'b0}};
        end else if (flip_one_bit && phy_tx_data_k[DATA_BYTES-1]) begin
            // only for the last datapath that we have a control charactera the end (END symbol)
            phy_rx_data  <= phy_tx_data ^ 64'h0000_0100_0000_0000; // END | LCRC[7:0] | LCRC[15:8] | LCRC[23:16] | ... -> flip bit 8 of LCRC
            phy_rx_data_k <= phy_tx_data_k;
            flip_one_bit <= 1'b0;
        end else begin
            phy_rx_data <= phy_tx_data;
            phy_rx_data_k <= phy_tx_data_k;
        end
    end

    initial begin
        $dumpfile("sim/dll_wavecrux.fst");
        $dumpvars(0, tb_dll_wavecrux);
    end

    // reset all
    task reset_all;
        begin
            phy_reset         = 1'b1;
            phy_linkup        = 1'b0;
            tl_tx_data        = {DATA_WIDTH{1'b0}};
            tl_tx_tlp_valid   = 1'b0;
            tl_tx_tlp_first   = 1'b0;
            tl_tx_tlp_last    = 1'b0;
            tl_tx_hdr_credit  = 8'b0;
            tl_tx_data_credit = 12'b0;
            tl_tx_update_type = 2'b0;
            tl_tx_packet_type = 2'b0;
            tl_tx_dllp_valid  = 1'b0;
            external_en         = 1'b0;
            external_data       = {DATA_WIDTH{1'b0}};
            flip_one_bit  = 1'b0;
            repeat (5) @(posedge phy_clk);
            phy_reset = 1'b0;
            repeat (2) @(posedge phy_clk);
        end
    endtask

    // Wait until DLL is ready to take data from TL again
    // Ready when retry buffer is empty
    task wait_tl_tx_ready;
        integer timeout;
        begin
            timeout = 0;
            while (!tl_tx_tlp_ready && timeout < 2000) begin
                @(posedge phy_clk);
                timeout = timeout + 1;
            end
            if (!tl_tx_tlp_ready) begin
                errors = errors + 1;
                $display("[%0t] ERROR: wait_tl_tx_ready: tl_tx_tlp_ready never asserted (timeout, data in retry buffer was not sent out to the physical layer)", $time);
            end
        end
    endtask

    task dll_linkup;
        integer timeout;
        begin
            phy_linkup = 1'b1;
            timeout = 0;
            while (!tl_tx_tlp_ready && timeout < 500) begin
                @(posedge phy_clk);
                timeout = timeout + 1;
            end
            if (!tl_tx_tlp_ready) begin
                errors = errors + 1;
                $display("[%0t] ERROR: dll_linkup: link did not reach DL_ACTIVE (timeout, link never went up and writting into retry buffer is not allowed)", $time);
            end
        end
    endtask

    task send_tlp(input integer n); // n is the number of data words
        integer i;
        integer timeout;
        begin
            timeout = 0;
            // check if retry buffer is empty
            while (!tl_tx_tlp_ready && timeout < 2000) begin
                @(posedge phy_clk);
                timeout = timeout + 1;
            end
            if (!tl_tx_tlp_ready) begin
                errors = errors + 1;
                $display("[%0t] ERROR: send_tlp: retry buffer not empty before send (timeout)", $time);
            end
            #1ns;
            tl_tx_tlp_valid = 1'b1;
            for (i = 0; i < n; i = i + 1) begin
                tl_tx_data      = tlp_words[i];
                tl_tx_tlp_first = (i == 0);
                tl_tx_tlp_last  = (i == n - 1);
                @(posedge phy_clk);
                #1ns;
            end
            tl_tx_tlp_valid = 1'b0;
            tl_tx_tlp_first = 1'b0;
            tl_tx_tlp_last  = 1'b0;
            tl_tx_data      = {DATA_WIDTH{1'b0}};
        end
    endtask

    task send_dllp(input [7:0] hdr_credit, input [11:0] data_credit, input [1:0] update_type, input [1:0] packet_type);
        begin
            @(posedge phy_clk);
            #1ns;
            tl_tx_hdr_credit  = hdr_credit;
            tl_tx_data_credit = data_credit;
            tl_tx_update_type = update_type;
            tl_tx_packet_type = packet_type;
            tl_tx_dllp_valid  = 1'b1;
            @(posedge phy_clk);
            #1ns;
            tl_tx_dllp_valid = 1'b0;
        end
    endtask

    task check_tlp_rx(input integer n, input integer timeout_limit);
        integer timeout;
        integer i;
        begin
            timeout = 0;
            while (!tl_rx_tlp_valid && timeout < timeout_limit) begin
                @(posedge phy_clk);
                timeout = timeout + 1;
            end
            if (!tl_rx_tlp_valid) begin
                errors = errors + 1;
                $display("[%0t] ERROR: check_tlp_rx: beat0 tl_rx_tlp_valid never asserted (timeout)", $time);
            end else begin
                for (i = 0; i < n; i = i + 1) begin
                    if (i != 0 && !tl_rx_tlp_valid) begin errors = errors + 1; $display("[%0t] ERROR: check_tlp_rx: data word %0d is not valid", $time, i); end
                    if ((i == 0) != tl_rx_tlp_first)   begin errors = errors + 1; $display("[%0t] ERROR: check_tlp_rx: data word %0d is first but not flagged as first word", $time, i); end
                    if ((i == n - 1) != tl_rx_tlp_last) begin errors = errors + 1; $display("[%0t] ERROR: check_tlp_rx: data word %0d is last but not flagged as last word", $time, i); end
                    if (tl_rx_data !== tlp_words[i])   begin errors = errors + 1; $display("[%0t] ERROR: check_tlp_rx: data word %0d mismatch (loopback) expected=%h got=%h", $time, i, tlp_words[i], tl_rx_data); end
                    if (i != n - 1) @(posedge phy_clk);
                end
            end
            @(posedge phy_clk);
        end
    endtask

    task check_dllp_rx(input [7:0] hdr, input [11:0] data, input [1:0] update, input [1:0] packet);
        integer timeout;
        begin
            timeout = 0;
            while (!tl_rx_dllp_valid && timeout < 500) begin
                @(posedge phy_clk);
                timeout = timeout + 1;
            end
            if (!tl_rx_dllp_valid) begin
                errors = errors + 1;
                $display("[%0t] ERROR: check_dllp_rx: dllp valid flag is not asserted (timeout)", $time);
            end else begin
                if (tl_rx_hdr_credit !== hdr) begin
                    errors = errors + 1;
                    $display("[%0t] ERROR: check_dllp_rx: hdr_credit mismatch expected=%0d got=%0d", $time, hdr, tl_rx_hdr_credit);
                end
                if (tl_rx_data_credit !== data) begin
                    errors = errors + 1;
                    $display("[%0t] ERROR: check_dllp_rx: data_credit mismatch expected=%0d got=%0d", $time, data, tl_rx_data_credit);
                end
                if (tl_rx_update_type !== update) begin
                    errors = errors + 1;
                    $display("[%0t] ERROR: check_dllp_rx: update_type mismatch expected=%0d got=%0d", $time, update, tl_rx_update_type);
                end
                if (tl_rx_packet_type !== packet) begin
                    errors = errors + 1;
                    $display("[%0t] ERROR: check_dllp_rx: packet_type mismatch expected=%0d got=%0d", $time, packet, tl_rx_packet_type);
                end
            end
            @(posedge phy_clk);
        end
    endtask

    initial begin
        errors = 0;

        // initialize DLL
        $display("=== Step 1: initialization sequence ===");
        reset_all;
        if (tl_tx_tlp_ready !== 1'b0) begin
            errors = errors + 1;
            $display("[%0t] ERROR: tl_tx_tlp_ready should be low after reset", $time);
        end
        dll_linkup;

        // Send TLP
        // TLPs are real headers so the WaveCrux DLL decoder names them.
        // Lane 0 (bits 7:0) goes on the wire first; TLP DWs are big-endian.
        $display("=== Step 2a: TLP 1, MWr32 to 0x8000_0000, 3 DW (24 bytes) ===");
        tlp_words[0] = 64'hFF00000103000040; // 40000003 010000FF
        tlp_words[1] = 64'h0100000000000080; // 80000000 00000001
        tlp_words[2] = 64'h0300000002000000; // 00000002 00000003
        send_tlp(3);
        check_tlp_rx(3, 500);
        wait_tl_tx_ready; // confirms the ACK for TLP 1 released the retry buffer

        $display("=== Step 2b: TLP 2, MWr64 to 0x2_0000_0000, 4 DW (32 bytes) ===");
        tlp_words[0] = 64'hFF01000104000060; // 60000004 010001FF
        tlp_words[1] = 64'h0000000002000000; // 00000002 00000000
        tlp_words[2] = 64'h0DF0FECAEFBEADDE; // DEADBEEF CAFEF00D
        tlp_words[3] = 64'hF0DEBC9A78563412; // 12345678 9ABCDEF0
        send_tlp(4);
        check_tlp_rx(4, 500);
        wait_tl_tx_ready; // confirms the ACK for TLP 2 released the retry buffer

        $display("=== Step 2c: TLP 3, CplD, 9 DW (48 bytes) ===");
        tlp_words[0] = 64'h240000010900004A; // 4A000009 01000024
        tlp_words[1] = 64'h1111111100020000; // 00000200 11111111
        tlp_words[2] = 64'h3333333322222222; // 22222222 33333333
        tlp_words[3] = 64'h5555555544444444; // 44444444 55555555
        tlp_words[4] = 64'h7777777766666666; // 66666666 77777777
        tlp_words[5] = 64'h9999999988888888; // 88888888 99999999
        send_tlp(6);
        check_tlp_rx(6, 500);
        wait_tl_tx_ready; // confirms the ACK for TLP 3 released the retry buffer

        // send error on loopback path
        $display("=== Step 3: send 1 TLP (MWr32, 24 bytes), trigger error on loopback path ===");
        tlp_words[0] = 64'hFF03000103000040; // 40000003 010003FF
        tlp_words[1] = 64'hAAAA555510000080; // 80000010 5555AAAA
        tlp_words[2] = 64'h09BADCFE78563412; // 12345678 FEDCBA09
        flip_one_bit = 1'b1; // corrupts this TLP's LCRC once, in flight
        send_tlp(3);
        // The corrupted copy makes the RX schedule a NAK
        // NAK loops back and triggers a retransmission
        check_tlp_rx(3, 2000);
        wait_tl_tx_ready; // confirms the ACK released the retry buffer

        $display("=== Step 4: send + receive UpdateFC-P DLLP ===");
        send_dllp(8'd10, 12'd200, 2'b00, 2'b10);
        check_dllp_rx(8'd10, 12'd200, 2'b00, 2'b10);

        $display("=== SUMMARY: %0d errors ===", errors);
        if (errors == 0)
            $display("TEST PASSED");
        else
            $display("TEST FAILED");
        $finish;
    end

endmodule

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Sep 3, 2026
// -----------------------------------------------------------------------------
