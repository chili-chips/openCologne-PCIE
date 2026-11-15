# _VProc_ and _mem_model_ Co-simulation Components

How _VProc_ and _mem_model_ work, and their APIs: [openPCIE_BFM, VProc and mem_model](https://github.com/chili-chips/openPCIE_BFM/blob/main/0.doc/integration.md#vproc-and-mem_model). What follows is how this repo builds and uses them.

## VProc and mem_model integration into _openCologne-PCIE_

The VProc and mem_model HDL (`f_VProc.sv`, `f_mem_model.sv` and their headers) and the C libraries are built from the openPCIE_BFM submodule ([`../../vip`](../../vip/README.md)) into `$VIP_DIR`, with its `4.build/build-vip.sh`; [`../../tb.f`](../../tb.f) lists the files from there, and openPCIE_BFM's `2.rtl/mem_model.sv`, which wraps upstream's `mem_model.v` in Verilator `lint_off` pragmas.

The software of both models is in `$VIP_DIR/lib`: _VProc_ in `libcosimlnx.a` for DPI-C (Verilator) and `libcosimica.a` for VPI (Icarus); _mem_model_'s C code, part of pcieVHost, in `libpcielnx.a` and `libpcieica.a`. Their headers are in `$VIP_DIR/include`. To use the models' APIs, the user code must include either the  `VProcClass.h` header for the *VProc* C++ API, or `VUser.h` for the *VProc* C API, and the `mem.h` header for the memory model C API. Note that the `VUser.h` and `mem.h` inclusions must be wrapped as C linkage if included in code that will be compiled as C++. E.g.:

```
extern "C" {
#include "VUser.h"
#include "mem.h"
}
```

This is only applicable when writing natively compiled simulation test code. When compiling the application code natively for *VProc*, the headers will be included correctly by the co-simulation hardware abstraction layer (HAL).


## More Information

More information on using these co-simulation models can be found in the [*VProc* manual](https://github.com/wyvernSemi/vproc/blob/master/doc/VProc.pdf) and [*mem_model* manual](https://github.com/wyvernSemi/mem_model/blob/main/doc/mem_model_manual.pdf).

--------------------
#### End of Document
