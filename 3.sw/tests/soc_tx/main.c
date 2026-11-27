// SPDX-FileCopyrightText: 2026 Chili.CHIPS
//
// SPDX-License-Identifier: BSD-3-Clause

//==========================================================================
// soc_tx: the SOC's Tx path with 3-DW and 4-DW requests, for tb_soc
// (bash 2.rtl/7.soc/sim/run-soc.sh tx). Sends the requests below through
// send_tlp() and tx_payload, then sets the pass marker; tb_soc compares
// every s_axis_tx beat with the one it expects (the same table there).
//==========================================================================

#include <stdint.h>
#include "pcie.h"

// H0..H3 in tx_payload entries 0 to 3; payload from DW4 on
// (tx_payload entry i is DW i)
#define MWR3(len)  (0x40000000u | (len))   // Fmt 10: 3 DW, data
#define MWR4(len)  (0x60000000u | (len))   // Fmt 11: 4 DW, data
#define MRD3(len)  (0x00000000u | (len))   // Fmt 00: 3 DW
#define MRD4(len)  (0x20000000u | (len))   // Fmt 01: 4 DW

// The Tx FSM reads tx_payload while it sends: wait for it before the next
// payload, as send_cpld() does
static void tx_idle(void) {
    while ((PCIE_PHY_STATUS & TX_BUSY_MASK) != 0);
}

int main(void) {
    // 3-DW MWr, 1 DW: H3 is the payload
    send_tlp(MWR3(1), 0x0000010Fu, 0x00001000u, 0xA1B2C3D4u);

    // 4-DW MWr, 1 DW: Address[63:32] in H2, [31:2] in H3, payload in DW4
    tx_idle();
    PCIE_TX_PAYLOAD(4) = 0x11223344u;
    send_tlp(MWR4(1), 0x0000020Fu, 0x00000001u, 0x00002000u);

    // 4-DW MWr, 2 DW
    tx_idle();
    PCIE_TX_PAYLOAD(4) = 0x55667788u;
    PCIE_TX_PAYLOAD(5) = 0x99AABBCCu;
    send_tlp(MWR4(2), 0x000003FFu, 0x00000002u, 0x00003000u);

    // 4-DW MRd, 1 DW
    send_tlp(MRD4(1), 0x0000040Fu, 0x00000003u, 0x00004000u);

    // 3-DW MRd, 1 DW: no H3
    send_tlp(MRD3(1), 0x0000050Fu, 0x00005000u, 0x00000000u);

    halt(0x0000FACEu);
}

// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: NLnet-sponsored open-source implementation
// Version:     1.0
// Date:        Nov 4, 2026
// -----------------------------------------------------------------------------
