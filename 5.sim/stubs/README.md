# _openCologne-PCIE_ EP model: `EPPIPEx1__pcieVHost_DUT`

[`EPPIPEx1__pcieVHost_DUT.sv`](EPPIPEx1__pcieVHost_DUT.sv) replaces the DUT (EP RTL + firmware), so the test bench and host can be brought up and checked on their own. We keep it next to the RTL:

| Make option | Runs |
|---|---|
| `make EP=model` | this EP model |
| `make EP=rtl` | the EP RTL + firmware |

Its name mirrors the host's, `RCPIPEx1__pcieVHost`: the same model, in the other role.

It is our pcieVHost wrapper [`PIPEx1__pcieVHost`](../models/PIPEx1__pcieVHost.sv) (instance `bfm_pcie`), configured as an EP at VProc node 1, running [`../usercode/VUserMain1.cpp`](../usercode/VUserMain1.cpp) against the host, openPCIE's Artix-7 RC model at node 2. Its ports are those the real EP will show the test bench:

- PIPE data out and in, 64 bits wide with one K flag per byte, as Cologne Chip's PIPE
- `pclk` (the PIPE clock, 31.25 MHz for 64 bits; the model makes its 250 MHz symbol clock from it)
- an active-low reset

Electrical idle is `NOSIG` on the PIPE data (see [From XSIM to Verilator, via Icarus](../README.md#from-xsim-to-verilator-via-icarus)), on both simulators: no side-band.

Why keep a model-against-model run? It proves the test bench and host on their own, before and alongside the RTL: when the real EP fails to train, `EP=model` shows at once whether the fault is on our side.

-----------
#### End of Document
