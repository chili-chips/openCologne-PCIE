# SW Architecture

This is where the developers of **PIO TestApp** (the software part of) document their work.

<div align="center"><img src="../0.doc/3.sw/sw-structure.drawio.png" width="100%" alt="Firmware layers: application, PCIE driver, HAL, register map and startup, talking to the CSR block over the CPU memory bus, then through pcie_top to the PCIE link"></div>

### EndPoint firmware

The EP firmware runs bare-metal on the eduBOS5 core of our GateMate SOC. It is the twin of the openPCIE RC firmware, with the roles swapped: there, the CPU sends requests and waits for Completions; here, it waits for the host's requests and sends the Completions.

| File | What it does |
|---|---|
| [`EP/main.c`](EP/main.c) | the PIO target, as large as BAR0 (4 KB): stores every DWORD of a MemWr, 3-DW or 4-DW header; answers a MemRd with CplDs, split at the 64-byte Read Completion Boundary; any other non-posted request with Unsupported Request |
| [`common/pcie.c`](common/pcie.c), [`pcie.h`](common/pcie.h) | the request layer: wait for the TLP at the Rx ring's head, decode its header, build and send its Completions (at most Max_Payload_Size, 32 DW, of data each), free the head. Tx goes in batches: `tx_add()` / `tx_cpld()` per TLP, then `tx_go()`; a full batch goes out by itself. `send_tlp()` sends one TLP on its own, as in openPCIE |
| [`common/start.S`](common/start.S), [`sections.lds`](common/sections.lds) | set the stack, jump to `main()`; code and data in the 8 KB RAM at 0x0000_0000 |
| [`tests/soc_tx/main.c`](tests/soc_tx/main.c) | a test, not the EP: sends 3-DW and 4-DW MWr and MRd, for `tb_soc`'s Tx check ([`run-soc.sh tx`](../2.rtl/7.soc/sim/run-soc.sh)) |
| [`tests/soc_rx/main.c`](tests/soc_rx/main.c) | a test, not the EP: sends every TLP of `tb_soc`'s RX burst back in TX batches (`tx_add()`) ([`run-soc.sh rx`](../2.rtl/7.soc/sim/run-soc.sh)); `run-soc.sh cpl` tests `EP/main.c` itself: split CplDs and UR |

What a reader should take from it:

- **The TL does the configuration, not the firmware.** The host's CfgRd0/CfgWr0 (IDs, Command register, BAR0 sizing) are answered by the soft TL, as AMD's `PCIE_2_1` hard macro answers them in silicon in EP mode. Only Memory requests reach the firmware, so enumeration works even before the firmware has started.
- **One TLP at a time, nothing lost.** The SOC queues incoming TLPs in its RX ring, every DWORD, header first. The oldest shows in `rx_payload`, and `rx.valid` reads 1 while it is there; the firmware frees it (writes 1) once it has answered. The link is held off only while the ring is full.
- **A Completion routes back by the request's IDs.** Requester ID and Tag come from the request, TC and Attr are copied from it, and the Completer ID is our own Bus/Device/Function, read from `status.cfg_id`. That value comes from the host's configuration writes and differs between a direct link and a link behind a switch, so it is never hard-coded.
- **Byte enables matter.** A MemWr updates only the enabled bytes of its first and last DWORD; a MemRd's Byte Count and Lower Address follow from its First and Last DW Byte Enables (Base Specification 2.1, Tables 2-31 and 2-32), and each of its Completions carries the bytes left from its own first byte on. On the TRN interface, payload byte 0 travels in bits [31:24].
- **PASS means the host reached us.** `status.result` reads 0x0000_0001 while the firmware waits, and 0x0000_FACE (the `fw_pass` LED) once it has answered the host's first read.

Build (WSL, with the xPack RISC-V GCC on `PATH`):

```sh
cd 4.build/sw_build && make      # firmware.elf, .bin and .hex for the SOC RAM
```

---
# Three Test Applications

We plan on creating not one, but three "Getting Started" examples, for the three representative compute platforms:
1) **Soft Embedded / BareMetal**: Artix-7 FPGA acting as a RootComplex with soft on-chip RISC-V CPU, on our openPCIE backplane
2) **General-purpose desktop/server class**: Linux PC
3) **Hard Embedded / Hosted**: RaspberryPi

## 1) Artix-7 FPGA as the RootPort for our EndPoint
`TODO`

## 2) Linux PC as the RootPort for our EndPoint
`TODO`

## 3) RaspberryPi as the RootPort for our EndPoint
`TODO`

--------------------
#### End of Document
