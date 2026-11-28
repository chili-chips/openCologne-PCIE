// -----------------------------------------------------------------------------
// Project:     openCologne-PCIE
// Description: SOC test firmware: RX ring and TX batch, in a loopback
// -----------------------------------------------------------------------------
// tb_soc (run-soc.sh rx) sends RX_TLPS TLPs back to back, more than the RX
// ring holds. The firmware takes each from the ring's head, adds a copy to a
// Tx batch (tx_add), frees it, and sends the copies back with tx_go every
// TX_EVERY TLPs, so Tx sends while RX beats arrive and the CPU reads the
// ring. tb_soc checks they come out as they went in.
// -----------------------------------------------------------------------------

#include <stdint.h>
#include "pcie.h"

#define RX_TLPS  96  // tb_soc: RX_TLPS
#define REST_DW  33  // after DW2, at most: DW3 of a 4-DW header and 32 of data
#define TX_EVERY 7   // TLPs per tx.send

int main(void) {
    uint32_t buf[REST_DW];
    uint32_t k = 0;  // TLPs in the batch (a counter: rv32i has no divide)

    for (uint32_t t = 0; t < RX_TLPS; t++) {
        while ((PCIE_RX_VALID & RX_VALID_MASK) == 0);

        // Fmt[0]: 4-DW header; Fmt[1]: Length DWORDs of data
        uint32_t dw0 = PCIE_RX_PAYLOAD(0);
        uint32_t dws = ((dw0 & (1u << 29)) ? 4 : 3) + ((dw0 & (1u << 30)) ? (dw0 & 0x3FFu) : 0);
        uint32_t n   = (dws - 3 > REST_DW) ? REST_DW : dws - 3;

        for (uint32_t i = 0; i < n; i++) {
            buf[i] = PCIE_RX_PAYLOAD(3 + i);
        }
        tx_add(dw0, PCIE_RX_PAYLOAD(1), PCIE_RX_PAYLOAD(2), buf, n);
        release_request();
        if (++k == TX_EVERY) {
            tx_go();
            k = 0;
        }
    }
    tx_go();
    wait_tx_ready();
    halt(0x0000FACEu);
}
