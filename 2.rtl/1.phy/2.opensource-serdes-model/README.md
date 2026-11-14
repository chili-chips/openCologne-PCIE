# SerDes BFM

The **_`ccfpga_serdes.BFM.sv`_** and _ccfpga_serdes_pkg.sv_ are the local copies of our **_`open-source simulation model for GateMate SerDes`_**. They are _plug-and-play, pin-compatible_ with CologneChip _ccfpga_serdes_ soft wrapper, and instantiated within our _phy_top_ module.

They are **not a replacement for CologneChip CC_SERDES** primitive (aka Hard-Macro, HM).

As the CologneChip _proprietary SerDes model_ is also written for this same soft wrapper, and not for the CC_SERDES HM, our opensource SerDes BFM is also _swap-in-and-out compatible_ with CologneChip proprietary simulation model. The selection of one or the other is then by a simple file list reference. 

The **_`ccfpga_serdes.SYNTH.sv`_** is the wrapper variant used for synthesis and chip builds. This **.SYNTH** variant instantiates the actual _CC_SERDES_ HM. It is therefore not simulateable. Likewise, the **.BFM** variant is not implementable. 

The model master copy files, along with full documentation and validation tests, are located in our [openCologne `7.SerDes/1.sim-model`](https://github.com/chili-chips/openCologne/blob/main/7.SerDes/1.sim-model/README.md) repo. Always check the master for more recent versions before starting major new work here. The update is then a simple copy of the above three files from there to here.

--------------------
#### End of Document
