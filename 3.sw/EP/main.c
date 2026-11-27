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
// Description:
//   EP firmware: a PIO target. The host (openPCIE Artix-7 RC, Raspberry Pi or
//   PC) enumerates the EP and gives BAR0 an address -- the TL handles all of
//   that -- then reads and writes inside BAR0. Each Memory request reaches
//   the firmware here:
//     - MemWr, 3-DW or 4-DW header: every payload DWORD is stored, First and
//       Last DW Byte Enables honoured; posted, so no answer
//     - MemRd: the stored DWORDs go back in Completions with Data, split at
//       the Read Completion Boundary
//     - any other non-posted request: a Completion with Unsupported Request
//   The PIO window is an array in the SOC RAM as large as BAR0, PIO_WORDS
//   DWORDs; an access past the end of BAR0 wraps around to its start.
//==========================================================================

#include "pcie.h"

#define PIO_WORDS    1024         // 4 KB of the 8 KB RAM: all of BAR0 (config_space BAR0_SIZE_BITS)
#define PIO_INDEX(a) (((a) >> 2) & (PIO_WORDS - 1))
#define RCB_BYTES    64           // Read Completion Boundary (Link Control RCB = 0)

// Result markers written to PCIE_RESULT
#define RESULT_RUNNING 0x00000001 // waiting for the host
#define RESULT_PASS    0x0000FACE // the host has read from us: the PIO path works end to end

static uint32_t pio_mem[PIO_WORDS];

// First and last enabled byte of a DWORD's Byte Enables; none enabled counts
// as byte 0
static uint32_t be_first(uint32_t be) {
    uint32_t i = 0;

    while (i < 3 && !(be & (1u << i))) i++;
    return i;
}

static uint32_t be_last(uint32_t be) {
    uint32_t i = 3;

    while (i > 0 && !(be & (1u << i))) i--;
    return i;
}

// MemWr: payload DWORD i is rx_payload entry 3+i, or 4+i behind a 4-DW header
static void mem_write(const tlp_t *req) {
    uint32_t len   = tlp_length(req);
    uint32_t first = 3 + (TLP_FMT(req->dw0) & 0x1);
    uint32_t idx   = PIO_INDEX(req_addr(req));

    for (uint32_t i = 0; i < len && first + i < PAYLOAD_DW; i++) {
        uint32_t be   = (i == 0) ? REQ_FIRST_BE(req->dw1) : (i == len - 1) ? REQ_LAST_BE(req->dw1) : 0xF;
        uint32_t mask = be_mask(be);
        uint32_t data = PCIE_RX_PAYLOAD(first + i);
        uint32_t w    = (idx + i) & (PIO_WORDS - 1);

        pio_mem[w] = (pio_mem[w] & ~mask) | (data & mask);
    }
}

// MemRd: one Completion per RCB block the read touches. Byte Count is what is
// left of the read from the Completion's first byte on, Lower Address that
// first byte (Base Specification 2.1, 2.3.1.1 and 2.2.9)
static void mem_read(const tlp_t *req) {
    uint32_t data[RCB_BYTES / 4];
    uint32_t len  = tlp_length(req);
    uint32_t addr = req_addr(req) & ~0x3u;
    uint32_t fbe  = REQ_FIRST_BE(req->dw1);
    uint32_t lbe  = (len == 1) ? fbe : REQ_LAST_BE(req->dw1);
    uint32_t lo   = be_first(fbe);
    uint32_t hi   = (fbe == 0 && len == 1) ? 0 : be_last(lbe);
    uint32_t left = len * 4 - lo - (3 - hi);  // Byte Count of the whole read
    uint32_t dw   = 0;

    tx_begin();  // all Completions of the read, one tx.send
    while (dw < len) {
        uint32_t a = addr + dw * 4;
        uint32_t n = (RCB_BYTES - (a & (RCB_BYTES - 1))) / 4;

        if (n > len - dw) {
            n = len - dw;
        }
        for (uint32_t i = 0; i < n; i++) {
            data[i] = pio_mem[PIO_INDEX(a + i * 4)];
        }
        tx_cpld(req, left, (dw == 0) ? (a | lo) : a, data, n);

        left -= n * 4 - ((dw == 0) ? lo : 0);
        dw   += n;
    }
    tx_go();
}

int main() {

    PCIE_RESULT = RESULT_RUNNING;

    // 8 DWORDs a turn: the firmware is built without -O, and a plain loop
    // over all of BAR0 keeps the host's first read waiting about 1 ms
    for (uint32_t *p = pio_mem; p < pio_mem + PIO_WORDS; p += 8) {
        p[0] = 0; p[1] = 0; p[2] = 0; p[3] = 0;
        p[4] = 0; p[5] = 0; p[6] = 0; p[7] = 0;
    }

    while (1) {
        tlp_t req;

        wait_for_request(&req);

        uint32_t fmt  = TLP_FMT(req.dw0);
        uint32_t type = TLP_TYPE(req.dw0);

        if (type == TYPE_MEM && (fmt == FMT_3DW_DATA || fmt == FMT_4DW_DATA)) {
            mem_write(&req);

        } else if (type == TYPE_MEM && (fmt == FMT_3DW_NODATA || fmt == FMT_4DW_NODATA)) {
            mem_read(&req);
            PCIE_RESULT = RESULT_PASS;

        } else if (!is_posted(&req)) {
            send_completion(&req, CPL_STAT_UR, 0, 0);
        }
        // anything else posted (a Message) is dropped

        release_request();
    }
}

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        April 2025
// -----------------------------------------------------------------------------
