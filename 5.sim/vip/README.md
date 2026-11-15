# Co-simulation VIP

| Folder | What | Version |
|---|---|---|
| `openPCIE_BFM` | git submodule: [openPCIE_BFM](https://github.com/chili-chips/openPCIE_BFM), our PCIE model with the upstream copies of VProc, pcieVHost and mem_model ([versions](https://github.com/chili-chips/openPCIE_BFM/blob/main/1.upstream/vip/README.md)) | the submodule's commit |
| `rv32` | upstream copy of [wyvernSemi/rv32](https://github.com/wyvernSemi/rv32), the RISC-V ISS, with openPCIE's fixes ([`../models/rv32`](../models/rv32/README.md)); GPL-3.0-or-later, by Simon Southwell | `main` 774d84f |

The make file builds the PCIE VIP with the submodule's `4.build/build-vip.sh`, and the ISS itself. After a fresh clone: `git submodule update --init`.

To upgrade the ISS: set the new version in [`../tools/vip-import.sh`](../tools/vip-import.sh), run it, update this table, run `make EP=rtl CPU=iss run`. To upgrade the PCIE model: `git submodule update --remote openPCIE_BFM`, then `bash ../run-sanity.sh`.

--------------------
#### End of Document