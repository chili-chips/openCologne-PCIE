# eduBOS5 RISC-V core

Chili.CHIPS' RV32I core (RV32M and Zicntr optional), the CPU of `soc_top`. The master is on [openPCIE](https://github.com/chili-chips/openPCIE/tree/main/2.rtl/0.common.opensource/src/CPU.eduBOS5), with its docs, formal proofs and WaveCrux views. These files are an unchanged copy from openPCIE `ab4acbf` (2026-11-23), with `edubos5.sv` and `edubos5_rf.sv` from openPCIE of 2026-11-24 (`RF_SYNC_READ`). GateMate has no LUT RAM, so `soc_top` builds the 3-stage core with its register file in block RAM (`EN_WAIT4REGS=1`, `RF_SYNC_READ=1`): 2 block RAM halves instead of 1,024 flip-flops and the 32:1 read muxes. Each instruction takes 1 clock more than in the 2-stage core, each jump 2 more. Three of its parameters are left at 0 here: `USE_HW_MUL`, so no RV32M; `STORE_WAITS_RDY` ([openPCIE#40](https://github.com/chili-chips-ba/openPCIE/issues/40)), so stores do not wait, as before; and `EN_COUNTERS`, so the Zicntr counters (`rdcycle`, `rdtime`, `rdinstret`) are off and the firmware does not use them.

Before major work here, check openPCIE for a newer eduBOS5, as for the SerDes BFM and the pcieVHost models. To update, copy the files above and the view below, and note the commit.

| file | content |
|---|---|
| `edubos5_pkg.sv` | common declarations |
| `edubos5.sv` | the core |
| `edubos5_alu.sv` | the ALU |
| `edubos5_rf.sv` | the register file |

Also copied: [`wavecrux/soc_cpu_view.sv`](wavecrux/soc_cpu_view.sv), the CPU under RVFI names for WaveCrux ([how](../README.md#watching-the-cpu-in-wavecrux)).

Fixes go to openPCIE first, then get copied here.

--------------------
#### End of Document
