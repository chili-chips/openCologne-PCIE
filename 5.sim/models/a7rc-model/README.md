# Artix-7 RC model: the host

A copy of openPCIE's [Artix-7 RC model](https://github.com/chili-chips/openPCIE/tree/main/5.sim#the-rc-model), the host of our simulations: driver (tester) and spec checker. The masters are in openPCIE; do not edit here.

| File | Master in openPCIE `5.sim` | What |
|---|---|---|
| `VUserMain2.cpp` | `usercode/` | the RC model: the lab RC's sequence, then the tester's stimulus |
| `a7rc_check.cpp`, `.h` | `usercode/` | the spec checker, 59 rules |
| `ep_dma.h` | `usercode/` | the endpoint DMA the tester asks for (also used by our EP model) |
| `ltssm.c` | `models/pcievhost/ltssm/` | link training, with the Artix-7 RC profile |
| `pcievhost-speed.patch` | `models/pcievhost/` | applied to pcieVHost before the VIP build |
| `vproc-coroutine.patch` | `models/cosim/` | applied to VProc before the VIP build |

To update: copy the files from openPCIE, check with `cmp`, then run `bash run-sanity.sh`.

#### End of Document
