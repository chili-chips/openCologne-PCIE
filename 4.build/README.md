# _openCologne-PCIE_ Build

The build process for the _openCologne-PCIE_ project consists of three steps:
- Compilation of the control and status registers (CSR) from their RDL specification into RTL for the hardware design and a hardware abstraction layer (HAL) for the software application
- Compilation of the software application for the RISC-V hardware target
- Compilation of SystemVerilog designs into a bitstream for the hardware target

Each step has its own `Makefile` or scripts. Run them in order - the software can pick up the generated HAL, and the hardware build embeds the firmware image into the bitstream.

The flow is Yosys + nextpnr-himbaechel, the same as [openXC7](https://github.com/openXC7) on openPCIE: Yosys synthesizes (`read_slang` for SystemVerilog), nextpnr-himbaechel places and routes with the pins from a `.ccf` file and the timing from an `.sdc` file, and `gmpack` writes the bitstream. The build is simpler than on openPCIE: one CPU core (eduBOS5) and one tool flow, with no Vivado option.

## Build environment

We aim for Linux-native tools throughout, and accept WSL for convenience and inclusivity. Yet, as the GUI apps run worse on Linux and WSL (GPU drivers are not on par), we enjoy WaveCrux on Windows.

| Step | Makefile / Directory | Produces |
|---|---|---|
| 1. CSR | [`MakefileCSR`](./MakefileCSR) | `csr_build/generated-files/` - `csr.sv`, `csr_pkg.sv`, `csr.h`, `csr_top.h`, `opencologne_pcie.md`, `html/` |
| 2. SW | [`sw_build`](./sw_build) | `firmware.elf`, `firmware.bin`, `firmware.hex` |
| 3. HW | [`hw_build`](./hw_build):<br>`run-lint.sh`<br>`run-format.sh`<br>`run-leq.sh`<br>`run-synth.sh`<br>`run-pnr.sh` | lint, format and equivalence reports, the GateMate netlist (`top.json`); the placed and routed design and the bitstream (`top.bit`), on mock pins for the GateMate A1 EVB (`GateMateA1-EVB.ccf`) until the board exists |

eduBOS5 is a copy of openPCIE's, in [`2.rtl/7.soc/CPU.eduBOS5`](../2.rtl/7.soc/CPU.eduBOS5).

### Build Structure

<div align="center"><img src="../0.doc/4.build/build-flow.drawio.png" width="100%" alt="Build flow: csr.rdl through PeakRDL into the register RTL and the firmware HAL, firmware build, Yosys + nextpnr-himbaechel to the bitstream, co-simulation, lint and logic equivalence"></div>

## Tool versions

The versions this repo has been run with so far. "Runs" means the step completes here.

| Tool | Version | Used for | Status |
|---|---|---|---|
| PeakRDL | 1.5.0 | CSR RTL, headers, docs (`MakefileCSR`) | generates |
| xPack RISC-V GCC | 15.2.0-1 | firmware (`sw_build`), `-Os -flto`: 1,248 bytes of code, 3,228 at `-O0` | builds |
| GCC | 15.2 | co-sim C/C++: VProc, pcieVHost, the RC model; `-O0`/`-O2`, UBSan, ASan | builds |
| Yosys | 0.70, with `read_slang` | 8b/10b proofs, standalone SerDes test synthesis, `run-synth.sh`, `run-lint.sh`, `run-leq.sh` | runs |
| Verible | v0.0-4296-g0f262651 | `run-lint.sh`, `run-format.sh` | runs |
| Icarus Verilog | 14.0 (devel, master `addeab31d`, 2026-11-23) | PHY and DLL-over-PHY simulations, co-sim (`make SIM=icarus run`); 14 or later for the PIPE, MAC and DLL interface ports | runs |
| Verilator | 5.055 (devel, `v5.054-260-gb9f22851`) | co-sim (`make run`, default), SOC lint; its FST writer needs `liblz4-dev` | runs, checks |
| JanusHDL | 0.22.0 | co-sim (`make SIM=janushdl run`): `EP=model`; `EP=rtl` waits on [#24](https://github.com/chili-chips/openCologne-PCIE/issues/24); free, closed source | runs |
| OSS CAD Suite | 2026-11-26 | Cologne Chip's toolchain package ([UG1002](../0.doc/4.build/ug1002-GateMate-toolchain.May2026.pdf)): nextpnr-himbaechel `nextpnr-0.11.1-127-gc54af70b`, GateMate chipdb 1.15, for `run-pnr.sh` (`NEXTPNR=`); router2 converges since [nextpnr#1943](https://github.com/YosysHQ/nextpnr/pull/1943). Its Yosys is a development build, not used | places and routes; timing fails |
| gmpack | OSS CAD Suite, or Project Peppercorn v1.14 | bitstream (`run-pnr.sh`) | not yet run: P&R stops on timing |
| openFPGALoader | 1.2.0 | loading the bitstream over JTAG | not yet used on the board |
| WaveCrux Pro | 1.2.0 | waveforms; PIPE, DLL and serial-line decoding (wcx-pcie 0.3.0), TLP decoding (Pro, and [our plugin](https://github.com/Ferrite-Engineering/wavecrux-decoders/tree/main/decoders/pcie-tlp), pcie-tlp 0.1.1), RISC-V (Windows) | runs |
| Python | 3.12 | build scripts, `run-format.sh` | runs |

## Utilization

`run-synth.sh`, then `run-pnr.sh`, on the CCGM1A1 (EVB pins, PCLK 31.25 MHz). One row per change that moves the numbers.

| Date | Design | CPE_LT | CPE_FF | RAM_HALF | PCLK | Result |
|---|---|---|---|---|---|---|
| 2026-11-02 | retry buffer in flip-flops | 80,093 (195%) | 39,808 (97%) | 20 / 64 | – | does not place |
| 2026-11-02 | retry buffer in block RAM | 22,076 (53%) | 7,261 (17%) | 22 / 64 | 12.2 MHz, 3 hold violations | routes; fails timing ([#15](https://github.com/chili-chips/openCologne-PCIE/issues/15)) |
| 2026-11-02 | no latch in the MAC scrambler | 22,181 (54%) | 7,147 (17%) | 22 / 64 | 12.75 MHz, no hold violation | routes; fails setup ([#15](https://github.com/chili-chips/openCologne-PCIE/issues/15)) |
| 2026-11-13 | the same RTL (renames and formatting only), OSS CAD Suite 2026-11-12 | 21,536 (52%) | 7,076 (17%) | 22 / 64 | 13.07 MHz | routes; fails setup ([#15](https://github.com/chili-chips/openCologne-PCIE/issues/15)) |
| 2026-11-25 | eduBOS5 register file in block RAM, `packet_handler` rewrite, OSS CAD Suite 2026-11-12, default router with `--tmg-ripup` | 19,608 (47%) | 6,199 (15%) | 24 / 64 | 22.28 MHz | routes; fails setup ([Timing closure difficulties](#timing-closure-difficulties)) |
| 2026-11-26 | the same netlist, OSS CAD Suite 2026-11-26, static placer with `--tmg-ripup` | 19,608 (47%) | 6,199 (15%) | 24 / 64 | 24.54 MHz | routes; fails setup ([Timing closure difficulties](#timing-closure-difficulties)) |

Out of 40,960 CPE_LT and CPE_FF, and 64 RAM_HALF.

**Per block** (2026-11-03):

| Block | CPE_LT | CPE_FF | RAM_HALF |
|---|---|---|---|
| SOC (`soc_top`: eduBOS5, RAM, CSR) | 5,999 (27%) | 2,091 (30%) | 12 |
| TL (`tl_top`) | 4,588 (20%) | 1,789 (26%) | 6 |
| DLL (`dll_top`) | 7,286 (32%) | 1,695 (24%) | 4 |
| Other (MAC, PHY, `trn_bridge`, clocks and resets) | 4,597 (20%) | 1,365 (20%) | 0 |
| Total | 22,470 | 6,940 | 22 |

Neither Yosys nor nextpnr reports a flat build per block. These numbers come from a second build that keeps the three blocks (`read_slang --best-effort-hierarchy`, `keep_hierarchy`), packed by nextpnr and counted by cell name. Nothing is optimised across the block boundaries there, so it is 1.2% larger in CPE_LT (9% in Yosys LUTs), and its routing did not converge; a second build per change is not sustainable, so this table is a snapshot.

## Timing closure difficulties

> **At a glance**
> - **Routing-bound at half full.** Ours and Goran's pci_eerie port both use about 50% of CPE_LT, yet routing takes most of each clock period.
> - **The routed ceiling is about 33 MHz.** The PCLK target is 31.25 MHz, so the margin is thin for anyone.
> - **We went from 12.2 to 24.54 MHz in November.** The next 7 MHz starts with the TL TX arbiter.
> - **nextpnr fixed router2 for us.** Since OSS CAD Suite 2026-11-26 it converges in 65 iterations (7 min), where it diverged before (the chart below).
> - **A true Gen2 is hardly possible on the A1.** A "fake Gen2", with only the PIPE at 128 bits, can still test CC_SERDES training at 5 GT/s ([details](#gen2-on-the-a1)).

<div align="center"><img src="../0.doc/4.build/router2-divergence-heatmap.png" width="100%" alt="router2 overused wires per iteration for seeds 2 and 3: both fall to a minimum, then rise again. Below, seed 2 congestion maps at iterations 133 and 220: the overuse spreads over the left 60% of the chip"></div>

### Ours and Goran's, side by side

[Goran's GateMate port of eerie](https://github.com/goran-mahovlic/pci_eerie/tree/gatemate-w16) hits the same limit as ours.

| | Ours (2026-11-26) | Goran's (EERIE_W8, 64-bit) |
|---|---|---|
| CPE_LT | 19,608 (47%) | 20,662 (50%) |
| Routed PCLK | **24.54 MHz** (static placer, router1, `--tmg-ripup`, 44 min)<br>24.22 MHz (HeAP placer, router1, `--tmg-ripup`, 49 min)<br>23.08 MHz (HeAP placer, router2, 7 min) | **31.35 to 34.65 MHz** |
| Placer estimate | 16.06 MHz; it was 37.31 MHz before nextpnr#1943 fixed GateMate's delay estimate | |
| Worst path | TL TX arbiter credit check: 40.8 ns, of which **28.4 ns (70%) is routing** | closed |

### Routing, not logic

**One net shows it.** In a router2 run with OSS CAD Suite 2026-11-12, `u_tlp_rx_buffer.u_lcrc.crc_q[2]` takes **14.3 ns** to route from tile (40,118) to (41,113). Its ends are only **5 rows apart**, so the delay is a routing detour, not logic depth.

**One seed is not a measurement.** Until OSS CAD Suite 2026-11-26, router2 got close, then fell apart (the chart above), and the default router took **84 min** to converge. Check a timing change on 2 or 3 seeds before trusting it; router2's 7 min now makes that cheap.

### Progress

| Date | Change | Routed PCLK | Gain | Of the 31.25 MHz target |
|---|---|---|---|---|
| 2026-11-02 | retry buffer in block RAM | 12.2 MHz | | `████░░░░░░` 39% |
| 2026-11-02 | no latch in the MAC scrambler | 12.75 MHz | +0.55 | `████░░░░░░` 41% |
| 2026-11-13 | OSS CAD Suite 2026-11-12 | 13.07 MHz | +0.32 | `████░░░░░░` 42% |
| 2026-11-25 | register file in block RAM, `packet_handler` rewrite, `--tmg-ripup` | 22.28 MHz | **+9.21** | `███████░░░` 71% |
| 2026-11-26 | OSS CAD Suite 2026-11-26 (nextpnr#1943) | 24.22 MHz | +1.94 | `████████░░` 78% |
| 2026-11-26 | static placer | **24.54 MHz** | +0.32 | `████████░░` 79% |

6.71 MHz to go. Same netlist since 2026-11-25: the last two rows are tool gains only.

### What helps

1. **An up-to-date nextpnr and the static placer**, with `--tmg-ripup`: +2.26 MHz on the same netlist, and 40 min faster. `run-pnr.sh` uses them; `PNR_OPTS="--router router2"` gives 23.08 MHz in 7 min, for a quick look.
2. **No asynchronous-read memories.** GateMate has no LUT RAM, so such a memory becomes flip-flops and wide muxes, all of which must be routed. Moving eduBOS5's register file to block RAM cut DFF from 1,490 to 466 and MX from 1,101 to 405.
3. **Fewer logic levels and lower fan-out.** Goran duplicates high-fan-out registers, decodes K symbols a clock early, and uses prefix ANDs, popcount trees, flat matrices and a CRC precomputed from the RAM output. He measures each change on its own, in a shift-register harness.
4. **Register cuts on the worst paths.** The `packet_handler` rewrite took the DLL off the worst path. The TL TX arbiter is next.
5. **Aim at the big blocks.** The DLL is 32% of the logic (2026-11-03). The LCRC is only about 6%, and its form hardly matters: 1,113 cells flat, 1,197 chained.

### Block RAM without read-first

**GateMate block RAM has no read-first mode.** `WR_MODE` is `NO_CHANGE` or `WRITE_THROUGH`, and SDP mode, the one a register file needs, has no `WRITE_THROUGH`. A memory that reads and writes in the same clock simulates read-first, so Yosys rebuilds that behaviour in fabric, and says so only in its debug log ("emulate read-first behavior"; [yosys#6566](https://github.com/YosysHQ/yosys/issues/6566)).

For eduBOS5's 32x32 register file, with two read ports, `synth_gatemate` gives:

| RTL | Besides 2 CC_BRAM_20K |
|---|---|
| `if (we) m[wa] <= d;`<br>`if (re) q <= m[ra];` | 72 DFF, 76 LUT |
| `(* no_rw_check *)` on `m` | none |
| `if (we) m[wa] <= d;`<br>`else if (re) q <= m[ra];` | 1 LUT |

**Use `else if`.** A write excludes the read in the same clock, so there is nothing to emulate, and simulation matches the hardware. `edubos5_rf.sv` does this; its core never reads while writing anyway.

**`(* no_rw_check *)` is only a band-aid.** It tells Yosys to ignore collisions, so on a collision the RTL simulates read-first while the hardware returns undefined data. We don't use it.

**A FIFO must read and write in one clock**, so `else` does not fit. There, read X on a collision: that is what the RAM does, so Yosys builds no logic and simulation matches the hardware (Yosys's own [pattern](https://yosyshq.readthedocs.io/projects/yosys/en/latest/using_yosys/synthesis/memory.html#synchronous-sdp-with-undefined-collision-behavior)):

```systemverilog
if (we) m[wa] <= d;
if (re) q <= (we & (wa == ra)) ? 'x : m[ra];
```

| 128x64 FIFO RAM, read and write every clock | Besides 1 CC_BRAM_40K |
|---|---|
| read-first, as written | 137 DFF, 74 LUT/MX |
| collision reads X | none |

**With byte enables, X per byte.** Yosys matches the collision condition by structure, byte lane by byte lane, so each lane must use the very enable its write uses. One condition for the whole word, such as "any byte written", is not recognised, and the read-first logic comes back without a word:

```systemverilog
for (int b = 0; b < 4; b++)
  q[8*b+:8] <= (wstrb[b] & (wa == ra)) ? 'x : m[ra][8*b+:8];
```

Here: the TL queues, the DLL retry buffer and the SOC RAM read X on a collision, with a check that it never happens where the read is used (`a_mem_rw`, `a_buffer_rw`, `a_ram_rw`; Verilator turns X into a constant, so the checks catch what X would show); the SOC RAM per byte. The DLL RX buffer and the SOC RX window use `else`.

**`run-lint.sh ram` checks it.** It flags every memory that Yosys maps to block RAM with read-first or transparency logic ([`run-lint-ram.py`](hw_build/run-lint-ram.py)).

### Gen2 on the A1

**A true Gen2 is hardly possible on the CCGM1A1.** Gen2 carries 4 Gb/s, which is 64 bits at 62.5 MHz or 128 bits at 31.25 MHz, end to end.

- **Routing is the main limit.** 62.5 MHz leaves about 6 to 8 logic levels per clock, at about 1.8 ns each, mostly wire. No PHY block reaches that even alone: Goran's best is 52.8 MHz.
- **Logic is the second limit.** A 128-bit datapath at 31.25 MHz does not fit. Goran's 128-bit PHY alone takes 81% of the CPEs, so a 128-bit DLL and TL would not fit beside it.

**A "fake Gen2" is possible.** Widen only the PIPE to 128 bits, and keep the DLL and TL at 64 bits behind a FIFO. That is Goran's `EERIE_W16`. The link trains at 5 GT/s but carries Gen1 throughput, 250 MB/s.

Its use is to test CC_SERDES training at 5 GT/s, not yet proven in silicon. On the ULX5M, the PLL path that 5 GT/s needs was already far worse than the current one when measured at 2.4 Gb/s.

### Router issues we reported

| Issue | What happens |
|---|---|
| [nextpnr#1732](https://github.com/YosysHQ/nextpnr/issues/1732) (our comment) | **Oscillation:** router2 never clears one overused wire, because two nets take it in turns |
| [nextpnr#1942](https://github.com/YosysHQ/nextpnr/issues/1942) | **Divergence:** overuse falls, then rises. Seed 2 bottoms at 1,770 (iteration 133) and climbs to 5,555. **Fixed for us** by [nextpnr#1943](https://github.com/YosysHQ/nextpnr/pull/1943) (OSS CAD Suite 2026-11-26): 65 iterations |
| [#28](https://github.com/chili-chips/openCologne-PCIE/issues/28) | our tracker for the divergence |

## Porting to other FPGAs

Everything above `pipe_if` is generic RTL: only `2.rtl/1.phy` and `2.rtl/2.pipe` are GateMate-specific. On another FPGA, put that vendor's SerDes behind a PIPE shim (receiver detection, PhyStatus, RxValid, electrical idle, reset sequencing) and feed the core 8 symbols per clock at 31.25 MHz (Gen1). A SerDes that gives 2 symbols at 125 MHz needs a 2-to-8 gearbox, with asynchronous FIFOs both ways, outside the core.

On Lattice ECP5 with the OSS CAD Suite (Yosys `read_slang`, nextpnr-ecp5), two netlist fixes go into the build script:

- memories without an initial value get `INITVAL = x`, which nextpnr-ecp5 cannot parse: `setundef -zero -params` on `TRELLIS_DPR16X4`;
- the DCU's default parameters come out as `"DONTCARE"`, which nextpnr cannot parse either: remove them from the netlist.

#### References:
- [GateMate FPGA Toolchain Installation, UG1002](../0.doc/4.build/ug1002-GateMate-toolchain.May2026.pdf) by Cologne Chip, May 2026
- GateMate pin lists, from the DS1001 attachment, September 2026: [CCGM1A1](../0.doc/4.build/gatemate-ccgm1a1-pinlist.csv), [CCGM1A2](../0.doc/4.build/gatemate-ccgm1a2-pinlist.csv)
- nextpnr constraints: [general](https://github.com/YosysHQ/nextpnr/blob/master/docs/constraints.md), and the GateMate `.ccf` reader in nextpnr-himbaechel, [`ccf.cc`](https://github.com/YosysHQ/nextpnr/blob/master/himbaechel/uarch/gatemate/ccf.cc)
- [prjpeppercorn-test-cases](https://github.com/YosysHQ/prjpeppercorn-test-cases): open-flow GateMate test designs
- [Yosys](https://github.com/YosysHQ/yosys) with [slang](https://github.com/MikePopoloski/slang), and [nextpnr](https://github.com/YosysHQ/nextpnr) (himbaechel, GateMate): the tool flow; prebuilt in the [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build/releases), as UG1002 recommends
- [PeakRDL](https://github.com/SystemRDL): `MakefileCSR`, CSR RTL, headers and docs from `csr_build/csr.rdl`
- [openFPGALoader](https://github.com/trabucayre/openFPGALoader): loads the bitstream over JTAG, GateMate included
- [fpgacapZero](https://github.com/lcapossio/fpgacapZero) (fcapz) -- open-source, vendor-agnostic FPGA debug cores: embedded logic analyzer, embedded I/O, JTAG-to-AXI and JTAG-to-UART bridges.

-----------
#### End of Document
