# SerDes BFM

`ccfpga_serdes.BFM.sv` and `ccfpga_serdes_pkg.sv` are a copy of the open-source GateMate SerDes model. It models Cologne Chip's simulation model `ccfpga_serdes`, not the `CC_SERDES` primitive. `ccfpga_serdes.SYNTH.sv` is the same module for the chip: `CC_SERDES` behind those ports. `phy_top` instantiates `ccfpga_serdes` once; the file list picks the file. The master copy, its documentation and its tests are in [openCologne `7.SerDes/1.sim-model`](https://github.com/chili-chips-ba/openCologne/blob/main/7.SerDes/1.sim-model/README.md).

Check the master for updates before new work here; to update, copy the three files from there.

--------------------
#### End of Document
