# PCIe MAC Layer

The sources are Cologne Chip's, in the gatemate-pipe submodule: [`2.pipe/pipe_src/src/mac_src`](https://github.com/colognechip/gatemate-pipe/tree/dll_test/src/mac_src).

## Description
The **Media Access Control (MAC)** is the logical sub-block of the PCIe **Physical Layer**, between the **Data Link Layer (DLL)** above and the **PIPE interface / SerDes PHY** below.

- **TX:** turns the DLL's byte stream into a scrambled symbol stream for the PHY; **RX** does the reverse.
- **Link:** owns bring-up and maintenance through the **Link Training and Status State Machine (LTSSM)**.
- **Soft RTL** in the FPGA fabric. **8b/10b** encode/decode, the **elastic buffer** and **word alignment** are done by the GateMate SerDes, behind [PIPE](../2.pipe/README.md).

<img alt="Position of the MAC layer in the PCIe stack" src="./images/MAC_Position.png" width=300 height=330 />

## Architecture
A transmit datapath, a receive datapath, and the control plane binding them.

<img alt="MAC block diagram" src="./images/MAC_Block_Diagram.png" width=700 height=457 />

- **TX datapath**: receive framed packets from DLL → scrambling → `TxData`/`TxDataK` to the PIPE interface.
- **RX datapath**: `RxData`/`RxDataK` from the PIPE interface → descrambling → packet detection → packet stream to the DLL.
- **LTSSM**: drives the PIPE command signals (`i_PowerDown`, `i_TxDetectRx`, `i_TxElecIdle`, `i_RxPolarity`, `i_TxCompliance`) and consumes the PIPE status signals (`o_PhyStatus`, `o_RxValid`, `o_RxElecIdle`, `o_RxStatus`) to sequence the link through Detect → Polling → Configuration → L0, and Recovery.
- **Ordered-set generator/detector**: builds and recognises TS1/TS2, SKP used during link training.
- **Scrambler/descrambler**: LFSR applied to data symbols only; reset by COM and bypassed for training sequences and control symbols.

## The Interface
**Upstream** to the Data Link Layer, **downstream** to the PIPE / PHY.

### Upstream — Data Link Layer
| Signal            | Dir | Description |
| ----------------- |:---:|:----------- |
| `i_TxData`        | in  | Byte stream of the packet to transmit. |
| `i_TxDataK`       | in  | Control flags of the byte stream to transmit. |
| `o_RxData`        | out | Descrambled byte stream from PHY (no TS1/TS2). |
| `o_RxDataK`       | out | Control flags of the received byte stream. |
| `o_LinkUp`        | out | LTSSM in L0 or Recovery. `pcie_core` raises the DLL's link up in L0 and holds it through Recovery, until `o_LinkUp` drops ([#35](https://github.com/chili-chips-ba/openCologne-PCIE/issues/35)). |

### Downstream — PIPE / PHY
The PIPE interface: `PCLK`, `TxData[63:0]`/`TxDataK[7:0]`, `RxData[63:0]`/`RxDataK[7:0]`, the command signals (`i_Reset`, `i_PowerDown[1:0]`, `i_TxElecIdle`, `i_TxDetectRx`, `i_TxCompliance[7:0]`, `i_RxPolarity`) and the status signals (`o_PhyStatus`, `o_RxElecIdle`, `o_RxValid`, `o_RxStatus[2:0]`). Descriptions, 32-/64-bit datapath handling and `RxStatus` encoding: [PIPE](../2.pipe/README.md).

## LTSSM
The heart of the MAC control plane. Top-level states for endpoint bring-up:

| State           | Description |
| --------------- |:----------- |
| Detect          | Detect the presence of a receiver on the link via the PHY's receiver-detection sequence (`i_TxDetectRx` → `o_PhyStatus` / `o_RxStatus = 011`). |
| Polling         | Establish bit lock, symbol lock and lane polarity; exchange TS1/TS2 ordered sets. |
| Configuration   | Assign link and lane numbers and configure link width; TS1/TS2 carry the assigned numbers. |
| L0              | Fully active operational state; TLPs and DLLPs flow. |
| Recovery        | Retrain the link from L0: RcvrLock, RcvrCfg, Idle. |

<img alt="LTSSM state diagram" src="./images/MAC_LTSSM.png" width=300 height=400 />

## Symbols and Ordered Sets
The MAC uses the PHY's control-symbol flags (`TxDataK`/`RxDataK`); 8b/10b lives in the SerDes. Control symbols (K-codes) it emits and recognises:

| Symbol | Code   | Name          | Use |
| ------ |:------ |:------------- |:--- |
| COM    | K28.5  | Comma         | Ordered-set alignment |
| STP    | K27.7  | Start TLP     | Frames a TLP handed down by the DLL. |
| SDP    | K28.2  | Start DLLP    | Frames a DLLP handed down by the DLL. |
| END    | K29.7  | End           | Terminates a TLP/DLLP. |
| EDB    | K30.7  | EnD Bad       | Recognised as a packet end only; nullified TLPs are not supported. |
| PAD    | K23.7  | Pad           | Lane padding during Configuration. |
| SKP    | K28.0  | Skip          | Clock-tolerance-compensation ordered set. |

Ordered sets generated/detected by the MAC: **TS1/TS2** (Polling, Configuration, Recovery), **SKP** (clock compensation — insertion/removal is done by the PHY elastic buffer and reported via `RxStatus`).

## Scrambling
Data (D) symbols are scrambled with the standard PCIe LFSR, **G(x) = x¹⁶ + x⁵ + x⁴ + x³ + 1**, advanced once per symbol and reset on COM. Bypassed for control symbols, TS1/TS2 and SKP. RX descrambles with the identical LFSR.

<!--## Prerequisites
The simulation can be run using the pcieVHost ... TODO

## Run Testbench
make -f makefile.ica run

## Testbench description
The testbench drives the MAC from both sides. On the downstream side it models the PIPE/SerDes responses (`o_PhyStatus`, `o_RxValid`, `o_RxStatus`, `RxData`/`RxDataK`) so the LTSSM can be walked through Detect → Polling → Configuration → L0, including receiver detection and TS1/TS2 exchange. On the upstream side it injects TLP/DLLP packets to exercise framing, scrambling and the return path. Fault injection on the modelled receive symbols (bad 8b/10b, disparity, EDB) is used to check the error-handling and Recovery transitions.-->

## References
- [PIPE Specs, Sept. 2025, v7.1](https://cdrdv2-public.intel.com/643108/643108_PIPE_Arch_Spec_Rev_7_1.pdf)
- [Simon Southwell's Primer](https://www.linkedin.com/pulse/pci-express-primer-1-overview-physical-layer-simon-southwell/)
- [MAC Overview](./Doc/MAC_Overview.pdf)

--------------------
#### End of Document
