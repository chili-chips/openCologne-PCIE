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
//   PCIe request layer of the EP firmware. See pcie.h.
//==========================================================================

#include "pcie.h"

__attribute__((noreturn)) void halt(uint32_t marker) {
    PCIE_RESULT = marker;
#ifdef VPROC
    // Co-simulation (CPU=vproc): park the VProc node without stopping
    // the simulation
    while (1) VTick(10000, SOC_CPU_VPNODE);
#else
    while (1) {}
#endif
}

// Waits until the Tx side is idle: tx_payload may then be written. A full
// core TX buffer holds the Tx side (no tready), so this also waits for room.
void wait_tx_ready(void) {
    while ((PCIE_PHY_STATUS & TX_BUSY_MASK) != 0);
}

// The header's first 3 DWORDs and n DWORDs from data into tx_payload from
// entry pos. For a 4-DW header, data[0] is DW3 and the payload follows.
// Always inlined: a call costs about as much as the stores themselves
static inline __attribute__((always_inline)) void
tx_put(uint32_t pos, uint32_t h0, uint32_t h1, uint32_t h2, const uint32_t *data, uint32_t n) {
    PCIE_TX_PAYLOAD(pos)     = h0;
    PCIE_TX_PAYLOAD(pos + 1) = h1;
    PCIE_TX_PAYLOAD(pos + 2) = h2;
    for (uint32_t i = 0; i < n; i++) {
        PCIE_TX_PAYLOAD(pos + 3 + i) = data[i];
    }
}

// One TLP on its own, from entry 0. Not inside a batch: it would overwrite
// one not sent yet
void send_tlp(uint32_t h0, uint32_t h1, uint32_t h2, const uint32_t *data, uint32_t n) {
    wait_tx_ready();
    tx_put(0, h0, h1, h2, data, n);
    PCIE_TX_SEND = 1;
}

// A batch: TLPs back to back in tx_payload from entry 0, then their number
// into tx.send. Each header's Fmt and Length tell the Tx side where the next
// starts. tx_payload must not change while the Tx side sends, so the first
// TLP of a batch waits until it is idle.
static uint32_t tx_pos;   // next free entry
static uint32_t tx_tlps;  // TLPs in the batch

// Drops what tx_add() collected and not sent yet
void tx_begin(void) {
    tx_pos  = 0;
    tx_tlps = 0;
}

// Sends the batch, and leaves the next one empty
void tx_go(void) {
    if (tx_tlps != 0) {
        PCIE_TX_SEND = tx_tlps;
        tx_pos  = 0;
        tx_tlps = 0;
    }
}

// Adds a TLP to the batch. A batch that is full goes first
void tx_add(uint32_t h0, uint32_t h1, uint32_t h2, const uint32_t *data, uint32_t n) {
    if (tx_pos + 3 + n > TX_PAYLOAD_DW || tx_tlps == TX_BATCH_MAX) {
        tx_go();
    }
    if (tx_tlps == 0) {
        wait_tx_ready();
    }
    tx_put(tx_pos, h0, h1, h2, data, n);
    tx_pos += 3 + n;
    tx_tlps++;
}

// Waits for the next TLP from the host. The SOC queues TLPs in its RX ring
// while the firmware works on this one, the ring's head.
void wait_for_request(tlp_t *req) {
    while ((PCIE_RX_VALID & RX_VALID_MASK) == 0);

    req->dw0  = PCIE_RX_PAYLOAD(0);
    req->dw1  = PCIE_RX_PAYLOAD(1);
    req->dw2  = PCIE_RX_PAYLOAD(2);
    req->data = PCIE_RX_PAYLOAD(3);
}

// Writing 1 to rx.valid frees the head: the next TLP in the ring takes its place
void release_request(void) {
    PCIE_RX_VALID = RX_VALID_MASK;
}

// Our own Bus/Device/Function, as the TL captured it from the host's last
// Type 0 Configuration Write. It goes into the Completer ID of every
// Completion. Behind a switch the bus number is not the one of a direct link,
// so it is read here, never hard-coded.
uint32_t completer_id(void) {
    return PCIE_CFG_ID & CFG_ID_MASK;
}

// Length in DWORDs, 0 standing for 1024
uint32_t tlp_length(const tlp_t *req) {
    uint32_t len = TLP_LENGTH(req->dw0);

    return (len == 0) ? 1024 : len;
}

// 3-DW request: the address is DW2; 4-DW (64-bit) request: the low half is DW3
uint32_t req_addr(const tlp_t *req) {
    return (TLP_FMT(req->dw0) & 0x1) ? req->data : req->dw2;
}

// Posted requests get no Completion: Memory Writes and Messages
int is_posted(const tlp_t *req) {
    uint32_t fmt  = TLP_FMT(req->dw0);
    uint32_t type = TLP_TYPE(req->dw0);

    if (type == TYPE_MEM && (fmt == FMT_3DW_DATA || fmt == FMT_4DW_DATA)) {
        return 1;
    }
    return (type & TYPE_MSG_MASK) == TYPE_MSG;
}

// Bits of the payload DWORD that the First DW Byte Enables select. On the TRN
// interface the payload travels big-endian: byte 0 in bits [31:24], so byte
// enable bit i covers bits [31-8i : 24-8i].
uint32_t be_mask(uint32_t first_be) {
    uint32_t mask = 0;

    for (int i = 0; i < 4; i++) {
        if (first_be & (1u << i)) {
            mask |= 0xFFu << (24 - 8 * i);
        }
    }
    return mask;
}

// Byte Count and Lower Address of a 1-DW read, from its First DW Byte
// Enables (Base Specification 2.1, tables 2-21 and 2-22): the count runs from
// the first to the last enabled byte, the low address bits point at the first
// enabled byte. No byte enabled still counts as 1 byte, at offset 0.
static uint32_t cpl_byte_count(uint32_t be) {
    if (be == 0) {
        return 1;
    }
    int first = 0, last = 3;
    while (!(be & (1u << first))) first++;
    while (!(be & (1u << last)))  last--;
    return (uint32_t)(last - first + 1);
}

static uint32_t cpl_lower_addr(const tlp_t *req) {
    uint32_t be    = REQ_FIRST_BE(req->dw1);
    uint32_t addr  = req_addr(req);
    uint32_t first = 0;

    if (be != 0) {
        while (!(be & (1u << first))) first++;
    }
    return (addr & 0x7C) | first;
}

// Builds and sends the Completion of a non-posted request. TC and Attr are
// copied from the request; Requester ID and Tag route it back to the host's
// request; the Completer ID says who answers. Byte Count and Lower Address:
// a Memory Read's, from its byte enables, also with an error status (as if
// Successful, Base 2.1 2.3.1.1); for every other request, I/O and
// Configuration, Byte Count 4 and Lower Address 0 (2.2.9). The Memory Read
// case covers a 1-DW read only (Byte Count from its First DW BE); the EP sends
// its read Completions with tx_cpld, and this only for UR today
void send_completion(const tlp_t *req, uint32_t status, int with_data, uint32_t data) {
    int      mem = (TLP_TYPE(req->dw0) == TYPE_MEM);  // non-posted: a Memory Read
    uint32_t dw0 = (with_data ? (TLP_CPLD | 1) : TLP_CPL) | TLP_TC_ATTR(req->dw0);
    uint32_t dw1 = (completer_id() << 16) | ((status & 0x7) << 13) |
                   (mem ? cpl_byte_count(REQ_FIRST_BE(req->dw1)) : 4);
    uint32_t dw2 = (REQ_REQUESTER_ID(req->dw1) << 16) | (REQ_TAG(req->dw1) << 8) |
                   (mem ? cpl_lower_addr(req) : 0);

    send_tlp(dw0, dw1, dw2, &data, with_data ? 1 : 0);
}

// A Completion with Data of n DWORDs, Successful, added to the batch: the
// caller gives the Byte Count and Lower Address, as a read longer than 1 DW
// takes several Completions. A batch that is full goes out first.
void tx_cpld(const tlp_t *req, uint32_t byte_count, uint32_t lower_addr,
             const uint32_t *data, uint32_t n) {
    uint32_t dw0 = TLP_CPLD | (n & 0x3FF) | TLP_TC_ATTR(req->dw0);
    uint32_t dw1 = (completer_id() << 16) | (byte_count & 0xFFF);
    uint32_t dw2 = (REQ_REQUESTER_ID(req->dw1) << 16) | (REQ_TAG(req->dw1) << 8) |
                   (lower_addr & 0x7F);

    tx_add(dw0, dw1, dw2, data, n);
}

// One Completion with Data, sent at once (with a batch not sent yet)
void send_cpld(const tlp_t *req, uint32_t byte_count, uint32_t lower_addr,
               const uint32_t *data, uint32_t n) {
    tx_cpld(req, byte_count, lower_addr, data, n);
    tx_go();
}

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        April 2025
// -----------------------------------------------------------------------------
