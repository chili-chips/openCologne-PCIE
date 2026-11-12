// SPDX-FileCopyrightText: 2026 Chili.CHIPS
//
// SPDX-License-Identifier: BSD-3-Clause

//==========================================================================
// openCologne-PCIE * NLnet-sponsored open-source implementation
//--------------------------------------------------------------------------
// Description:
//   What openPCIE's Artix-7 RC model, the host, expects of our EP RTL
//   (EP=rtl): its IDs and the six BAR sizing reads. The model includes this
//   file in place of its own endpoint's (VUserMain2.cpp, A7RC_EP_EXPECT); with
//   EP=model it keeps its own, which the EP model matches.
//==========================================================================

#ifndef A7RC_EP_H
#define A7RC_EP_H

#define EP_VENDOR_ID          0xCC00  // = PCIE_VENDOR_ID in 2.rtl/5.tlp/tl_pkg.sv
#define EP_DEVICE_ID          0xCC00  // = PCIE_DEVICE_ID in 2.rtl/5.tlp/tl_pkg.sv

// BAR sizing reads: BAR0 4 KB, 32-bit, non-prefetchable; BAR1-5 not implemented
static const uint32_t ep_bar_size[FW_NUM_BARS] = {0xfffff000, 0x00000000, 0x00000000,
                                                  0x00000000, 0x00000000, 0x00000000};

#endif
