# Simulation Models

This directory contains the following models

* `soc_cpu.VPROC.sv` : _VProc_ based `soc_cpu` compatible virtual processor.
* `PIPEx1__pcieVHost.sv` : a pcieVHost on an x1 PIPE link, as RC or EP, with the link offered at the PIPE, Data Link and Transaction layers.
* `RCPIPEx1__pcieVHost.sv` : the host, `PIPEx1__pcieVHost` fixed to the RC role.
* `phy_vproc_rc.sv` : the `phy_top` socket with `IFACE=pipe`, the host at the PIPE: a wrapper of `pipe_phy_core.sv`.
* `pipe_phy_core.sv` : the PHY side of PIPE with its handshakes (PhyStatus, receiver detection, power state), shared with openPCIE (master there).
* `pipe_sym_pkg.sv` : the symbol values on the PIPE (`NOSIG_SYM`, electrical idle) for `pipe_phy_core.sv`, shared with openPCIE (master there).
* `ep_wavecrux_view.sv` : our EP's layer boundaries, for the WaveCrux decoders (`EP=rtl DUMP=1`).
* `tlp_dw_if.sv`, `tlp_dw_monitor.sv`, `tlp_wavecrux_view.sv` : the SOC's AXI-Stream TLPs, one DW per clock, for the TLP decoder.
* `gatemate_cells_sim.sv` : simulation models of the GateMate primitives `clk_rst_gen` uses: `CC_USR_RSTN`, `CC_BUFG`.
* `bfm_uart.sv` : a minimal UART BFM, 115.2 kb/s, 8N1.

In addition, sub-directories contain the following models

* [`cosim`](cosim/README.md) : Contains the _VProc_ and _mem_model_ co-simulation VIP.
* [`rv32`](rv32/README.md) : Contains the _rv32_ RISC-V RV32GCC_Zbb instruction set simulator C++ model
* [`pcievhost`](pcievhost/README.md) : Points to the pcieVHost VIP, the PCIE link partner with a PIPE interface, copied into [`../vip`](../vip/README.md).

## soc_cpu.VPROC

The `soc_cpu.VPROC` module is pin compatible with the other `soc_cpu` components with RTL softcore implementations of 32-bit RISC-V processors, such as eduBOS5. In place of the softcore is a [_VProc_](https://github.com/wyvernSemi/vproc) virtual processor which can run natively compiled code and drive its memory mapped bus in the logic simulation (see [here](../README.md#vproc-software)). The module, `soc_cpu_vproc`, has only a clock (`clk`), an active-low reset (`resetn`) and the SOC's CPU bus, `mem_if` (`mem_valid`, `mem_ready`, `mem_addr`, `mem_wdata`, `mem_wstrb`, `mem_rdata`), the external bus to the rest of the logic, just as for the softcores.

<p align="center"><img alt="soc_cpu.VPROC block diagram" width="600" src="../../0.doc/5.sim/soc_cpu_vproc.drawio.png"></p>

--------------------
#### End of Document
