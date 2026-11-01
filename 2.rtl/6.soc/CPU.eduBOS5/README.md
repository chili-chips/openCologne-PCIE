# eduBOS5 RISC-V core

Chili.CHIPS' RV32I core, the CPU of `riscv_pcie_soc`. The master is on [openPCIE](https://github.com/chili-chips-ba/openPCIE/tree/main/2.rtl/0.common.opensource/src/CPU.eduBOS5), with its docs, formal proofs and WaveCrux views. These files are an unchanged copy from openPCIE `8b55545`. Its `STORE_WAITS_RDY` ([openPCIE#40](https://github.com/chili-chips-ba/openPCIE/issues/40)) is left at 0 here: stores do not wait, as before.

Before major work here, check openPCIE for a newer eduBOS5, as for the SerDes BFM and the pcieVHost models. To update, copy the files above and the view below, and note the commit.

| file | content |
|---|---|
| `edubos5_pkg.sv` | common declarations |
| `edubos5.sv` | the core |
| `edubos5_alu.sv` | the ALU |
| `edubos5_rf.sv` | the register file |

Also copied: [`wavecrux/soc_cpu_view.sv`](wavecrux/soc_cpu_view.sv), the CPU under RVFI names for WaveCrux ([how](../README.md#watching-the-cpu-in-wavecrux)).

Fixes go to openPCIE first, then get copied here.
