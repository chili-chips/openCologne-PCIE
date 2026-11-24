# SPDX-FileCopyrightText: 2026 Chili.CHIPS
#
# SPDX-License-Identifier: BSD-3-Clause

# =============================================================================
# Co-simulation of the openCologne-PCIE test bench, in Verilator, Icarus or JanusHDL
#
# Run FROM THIS FOLDER, on Linux or WSL:
#   make          build the C/C++ models and the simulation
#   make run      build and run
#   make clean
#
# Open-source simulators: Verilator (default) or Icarus (SIM); JanusHDL, free but
# closed source, is an option. The VIP is the same as on openPCIE: VProc, the
# pcieVHost PCIE model, mem_model, from openPCIE_BFM (the submodule
# vip/openPCIE_BFM: upstream copies, our PIPE wrappers, the host), built by its
# 4.build/build-vip.sh into ~/.cache. models/ holds our own models.
#
# Nodes: VProc node 2 is the host, RCPIPEx1__pcieVHost, a pcieVHost in RC mode
# running openPCIE's Artix-7 RC model, from openPCIE_BFM (3.sw/a7rc):
# VUserMain2.cpp, the checker, 3.sw/ltssm/ltssm.c, and pcieVHost and VProc built with
# pcievhost-speed.patch and vproc-coroutine.patch. What it expects of our EP RTL: usercode/a7rc_ep.h.
# The EP is selected with EP: the EP RTL + firmware, or the EP model
# EPPIPEx1__pcieVHost_DUT, a pcieVHost in EP mode at node 1 (stubs/,
# usercode/VUserMain1.cpp), which proves the test bench and the host on their own.
# =============================================================================

# ---- simulator ------------------------------------------------------------------
#   verilator  (default) compiled to a native executable; the models talk DPI-C
#   icarus     Icarus Verilog; the same C/C++ models talk VPI
#   janushdl   JanusHDL (jhdl, 0.22 or later); it loads the Icarus build of the
#              VPI models, so it needs Icarus too (vpi_user.h). EP=rtl stops on a
#              JanusHDL issue (openCologne-PCIE#24)
SIM           ?= verilator

# ---- EP and IFACE: what the endpoint is, and where the host meets it ---------
#   EP=model    (default) a pcieVHost in EP mode at node 1, program VUserMain1.cpp:
#               EPPIPEx1__pcieVHost_DUT at the PIPE, PcieVhostSerial on the line
#   EP=rtl      the EP RTL + firmware: pcie_top (rtl.f); the firmware is copied
#               in for the run. Verilator only: Icarus 13 parsed neither the
#               interface ports nor the generated csr_pkg.sv (unpacked structs); not retried on 14
#   IFACE=pipe  (default) the host at the PIPE; with EP=rtl in the phy_top
#               socket (models/phy_vproc_rc.sv)
#   IFACE=serial the host on the serial line, 8b/10b and scrambling on. It adds
#               the PHY: with EP=rtl all of top (phy_top, Cologne Chip's PIPE
#               logic, the opensource SerDes BFM, phy.f; CDR_MODEL=FAST), with
#               EP=model pcieVHost's own serialiser
#   IFACE=phy   EP=model only: the host on the serial line, the EP model behind
#               our PHY: phy_top as in EP=rtl IFACE=serial, with the EP model
#               on its PIPE through openPCIE_BFM's pipe_mac_adapter.sv in place of
#               pcie_top (ep_phy.f). A failure points at the PHY. Verilator only
ifneq ($(origin DUT)$(origin PHY),undefinedundefined)
  $(error DUT and PHY are now EP=model|rtl and IFACE=pipe|serial (PHY=rtl and PHY=mock become IFACE=serial))
endif
ifeq ($(EP),mock)
  $(error EP=mock is now EP=model)
endif
EP            ?= model
IFACE         ?= pipe
ifeq ($(EP),model)
  USER_C      ?= VUserMain1.cpp
else ifeq ($(EP),rtl)
  ifeq ($(filter verilator janushdl,$(SIM)),)
    $(error EP=rtl needs SIM=verilator or janushdl: Icarus 13 parsed neither our interface ports nor the generated csr_pkg.sv; not retried on 14)
  endif
  A7RC_EXPECT  = -DA7RC_EP_EXPECT='"a7rc_ep.h"' -DA7RC_PIPE_SCRAMBLE  # our EP scrambles at the PIPE too
  EP_FILES     = rtl.f
  EP_VLT       = +define+EP_RTL -F rtl.f --assert models/ep_sva.sv
  EP_JHDL      = -DEP_RTL                # JanusHDL: the same define, and ep_sva.sv in the list
  EP_JHDL_SV   = models/ep_sva.sv
  EP_OBJ       = _rtl
  FW_IN        = cp $(CURDIR)/../4.build/sw_build/firmware.hex firmware.hex &&
  FW_OUT       = rm -f firmware.hex;
else
  $(error EP must be model or rtl (got "$(EP)"))
endif
ifeq ($(IFACE),serial)
  ifeq ($(EP),rtl)
    EP_FILES  += phy.f
    EP_VLT    += +define+CDR_MODEL=FAST ../2.rtl/top.sv -F phy.f
  endif
  EP_VLT      += +define+IFACE_SERIAL
  ICA_IFACE    = -DIFACE_SERIAL
  EP_OBJ      := $(EP_OBJ)_serial
else ifeq ($(IFACE),phy)
  ifneq ($(EP),model)
    $(error IFACE=phy is the EP model behind our PHY: EP=rtl IFACE=serial already runs our EP behind it)
  endif
  ifneq ($(SIM),verilator)
    $(error IFACE=phy needs SIM=verilator: not tried on Icarus (phy_top has pipe_if ports, which Icarus 13 did not parse))
  endif
  # the host scrambles on the line; the EP model scrambles at the PIPE, our
  # PHY does 8b/10b (usercode/VUserMain1.cpp)
  EP_VLT      += +define+IFACE_SERIAL +define+IFACE_PHY +define+CDR_MODEL=FAST \
                 --assert -F ep_phy.f
  EP_FILES     = ep_phy.f phy.f
  IFACE_DEFS   = -DIFACE_PHY
  EP_OBJ      := $(EP_OBJ)_phy
else ifneq ($(IFACE),pipe)
  $(error IFACE must be pipe, serial or phy (got "$(IFACE)"))
endif

# ---- host ---------------------------------------------------------------------
# openPCIE's Artix-7 RC model, from openPCIE_BFM: at the PIPE, or on the serial
# line (IFACE=serial) with 8b/10b and scrambling on
BFM            = $(CURDIR)/vip/openPCIE_BFM
A7RC_DIR       = $(BFM)/3.sw/a7rc
LTSSM_DIR      = $(BFM)/3.sw/ltssm
# A7RC=0 (default): the host is a tester: the lab RC's sequence, then what its
# firmware never sends but the spec allows (README.md, Tester and literal).
# A7RC=1: literal, only what the lab RC sends
# DMA=0 (default): the tester skips its EP DMA stage (our EP has no DMA, #14);
# DMA=1: runs it
# SEED: the seed of the tester's random stimulus (default 1), read at run time
# (A7RC_SEED): no rebuild. make regress SEEDS=N runs seeds 1 to N, each with a
# wall-clock limit of REGRESS_S seconds, again (up to REGRESS_TRIES times) after
# that limit or a crash, not after the test bench's own time limit;
# REGRESS_JOBS at a time, each in
# obj/regress/<seed>/, the packet display off (REGRESS_QUIET=0: kept)
# MIX: the tester's random mix, N writes and reads (default 64), read at run
# time (A7RC_MIX): sustained load, as the hardware BAR0 test. About 0.4 us a
# request with the EP model
A7RC          ?= 0
DMA           ?= 0
SEED          ?= 1
MIX           ?= 64
export A7RC_MIX = $(MIX)
# SIM_FAULT (EP=model): none (default), or the EP model misbehaves, to drive
# the RC model's error paths: crs (CRS to the first 3 Configuration
# Requests), nocpl (no Completion for the request after the BAR0 write), late
# (electrically idle for 200 us after reset); usercode/VUserMain1.cpp
SIM_FAULT     ?= none
SEEDS         ?= 10
REGRESS_S     ?= 900
REGRESS_TRIES ?= 3
REGRESS_JOBS  ?= 1
REGRESS_QUIET ?= 1
REGRESS_DUMP  ?= none
# make wavecrux SEED=N: that seed again with DUMP=1, in obj/wavecrux/<N>/, then
# its FST in WaveCrux at the checker's first violation (openPCIE_BFM 4.build/wavecrux.py; WaveCrux
# runs with --wcp-port 54321). WCX_OPEN=0: the dump only. REGRESS_DUMP=fail: after
# make regress, every failing seed dumped that way
WCX_OPEN      ?= 1
WCX_FST        = $(if $(filter rtl,$(EP)),tb_rtl,tb)$(if $(filter pipe,$(IFACE)),,_$(IFACE)).fst
WCX_SIGNALS    = $(if $(filter serial phy,$(IFACE)),tb.ser_dn_line tb.ser_up_line,tb.downdata tb.updata \
                 tb.u_rc.tx_tlp_valid tb.u_rc.tx_tlp_data tb.u_rc.rx_tlp_valid tb.u_rc.rx_tlp_data)
ifeq ($(filter 0 1,$(A7RC)),)
  $(error A7RC must be 0 or 1 (got "$(A7RC)"))
endif
ifeq ($(filter none crs nocpl late,$(SIM_FAULT)),)
  $(error SIM_FAULT must be none, crs, nocpl or late (got "$(SIM_FAULT)"))
endif
ifneq ($(SIM_FAULT)$(EP),none$(EP))
  ifneq ($(EP),model)
    $(error SIM_FAULT=$(SIM_FAULT) needs EP=model: the EP model misbehaves)
  endif
endif
ifeq ($(filter 0 1,$(DMA)),)
  $(error DMA must be 0 or 1 (got "$(DMA)"))
endif
HOST_DEFS      = -DRC_GEN=2 -DA7RC_LITERAL=$(A7RC) $(A7RC_EXPECT) $(if $(filter serial phy,$(IFACE)),-DSIM_SERIAL) \
                 $(if $(filter 0,$(DMA)),-DA7RC_NO_DMA) $(IFACE_DEFS) \
                 $(if $(filter-out none,$(SIM_FAULT)),-DSIM_FAULT_$(shell echo $(SIM_FAULT) | tr a-z A-Z))
VIP_ENV        = VIP_PATCH=$(BFM)/1.upstream/patches/pcievhost-speed.patch \
                 VPROC_PATCH=$(BFM)/1.upstream/patches/vproc-coroutine.patch \
                 VIP_BUILD=$(HOME)/.cache/opencologne-pcie/vip

# ---- CPU ----------------------------------------------------------------------
#   rtl    (default) the eduBOS5 RTL core, running firmware.hex
#   vproc  VProc at node 0 (models/soc_cpu.VPROC.sv), running the 3.sw firmware
#          compiled for the host (usercode/VUserMain0.cpp calls its main)
#   iss    VProc at node 0, running the rv32 ISS on firmware.elf, with
#          eduBOS5's 2-stage timing (vusermain.cfg)
# Only the module in the soc_top CPU socket changes (SOC_CPU_VPROC).
CPU           ?= rtl
ifneq ($(CPU),rtl)
  ifneq ($(EP),rtl)
    $(error CPU=$(CPU) needs EP=rtl)
  endif
  CPU_SV       = models/soc_cpu.VPROC.sv
  EP_VLT      += +define+SOC_CPU_VPROC $(CPU_SV)
  EP_OBJ      := $(EP_OBJ)_$(CPU)
  FW_DIR       = $(CURDIR)/../3.sw
  ifeq ($(CPU),vproc)
    USER_C    += VUserMain0.cpp
    FW_HOST_C  = fw_pcie fw_main
  else ifeq ($(CPU),iss)
    ISS_C     = VUserMain0.cpp mem_vproc_api.cpp uart.cpp rv32_cache.cpp vuserutils.cpp
    ISSCODEDIR = $(CURDIR)/models/rv32/usercode
    RV32SRC    = $(CURDIR)/vip/rv32/iss/src
    RV32_CPP   = rv32i_cpu_elf rv32_cpu_gdb rv32i_cpu rv32csr_cpu rv32m_cpu rv32a_cpu \
                 rv32f_cpu rv32d_cpu rv32c_cpu rv32zba_cpu rv32zbb_cpu rv32zbs_cpu rv32zbc_cpu
  else
    $(error CPU must be rtl, vproc or iss (got "$(CPU)"))
  endif
endif

# ---- user code ----------------------------------------------------------------
# USER_C: our programs in USRCODEDIR (the EP model, the native CPU). The host,
# openPCIE's VUserMain2.cpp, its spec checker a7rc_check.cpp and its ltssm.c
# (openPCIE_BFM 3.sw),
# the link-training helper, are always compiled with them
USRCODEDIR    ?= $(CURDIR)/usercode
OPTFLAG       ?= -O2 -g
USRSIMFLAGS   ?=

# ---- models -------------------------------------------------------------------
# VIP_DIR: lib/, include/, hdl/ of the VIP; built once, then reused
VIP_DIR       ?= $(shell $(VIP_ENV) bash $(BFM)/4.build/build-vip.sh)
export VIP_DIR

# ---- tools --------------------------------------------------------------------
HOST_CC       ?= gcc
HOST_CXX      ?= g++
HOST_AR       ?= ar
VERILATOR     ?= verilator
IVERILOG      ?= iverilog
VVP           ?= vvp
JHDL          ?= jhdl

CPPSTD         = -std=c++20
INCLPATHS      = -I$(USRCODEDIR) -I$(A7RC_DIR) -I$(VIP_DIR)/include
OBJDIR         = $(CURDIR)/obj/$(SIM)$(EP_OBJ)$(if $(filter 1,$(A7RC)),_a7rc)$(if $(filter 1,$(DMA)),_dma)$(if $(filter 1,$(DUMP)),_dump)$(if $(filter-out none,$(SIM_FAULT)),_fault-$(SIM_FAULT))
USERLIB        = $(OBJDIR)/libuser.a

USER_ALL       = $(USER_C) VUserMain2.cpp a7rc_check.cpp ltssm.c

ifeq ($(SIM),verilator)
  DEFS         = -DVPROC_SV -DVPROC -DEXCLUDE_LTSSM
  SIMEXE       = $(OBJDIR)/Vtb
else ifneq ($(filter icarus janushdl,$(SIM)),)
  ICA_INC      = $(dir $(shell command -v $(IVERILOG)))../include/iverilog
  ICA_LIB      = $(dir $(shell command -v $(IVERILOG)))../lib
  DEFS         = -DICARUS -DVPROC -DEXCLUDE_LTSSM -I$(ICA_INC)
  VPROC_SO     = $(OBJDIR)/VProc.vpi
  ifeq ($(SIM),icarus)
    SIMEXE     = $(OBJDIR)/sim
  else
    SIMEXE     = $(VPROC_SO) $(ICA_FILES)   # JanusHDL compiles the sources at each run
  endif
else
  $(error SIM must be verilator, icarus or janushdl (got "$(SIM)"))
endif
DEFS          += $(HOST_DEFS)

VOBJS          = $(addprefix $(OBJDIR)/, $(patsubst %.cpp,%.o,$(patsubst %.c,%.o,$(notdir $(USER_ALL)))))
VOBJS         += $(addprefix $(OBJDIR)/, $(ISS_C:.cpp=.o) $(FW_HOST_C:=.o))

# CPU=iss: the rv32 ISS library, built from vip/rv32 (with rv32-openpcie.patch)
RV32OBJDIR     = $(OBJDIR)/rv32
RV32LIB        = $(if $(RV32SRC),$(RV32OBJDIR)/librv32.a)
RV32OBJS       = $(addprefix $(RV32OBJDIR)/, $(RV32_CPP:=.o))

# ---- Verilator ----------------------------------------------------------------
# The C/C++ side: our user code (whole-archive, so VProc finds VUserMain<n>),
# then the VProc and pcieVHost libraries
LDLIBS         = -Wl,-whole-archive $(USERLIB) -Wl,-no-whole-archive \
                 $(RV32LIB) -L$(VIP_DIR)/lib -lcosimlnx -lpcielnx \
                 -lpthread -lrt -ldl -rdynamic

# DUMP=1: tb.fst, written natively (Verilator --trace-fst, vvp -fst); depth 3
# reaches the decoder pages, tb.u_rc (RC) and tb.dut.bfm_pcie (EP); tb.vlt keeps the
# upstream models out of it (IFACE=serial: tb_serial.fst, the line; the serial
# host is upstream's, so its ports are not in it; IFACE=phy: tb_phy.fst, the
# line, the PIPE of our PHY and the EP model's page). With EP=rtl: tb_rtl.fst (IFACE=serial: tb_rtl_serial.fst),
# with the EP's decoder pages (wavecrux.f), 6 levels down with IFACE=serial; eduBOS5
# drives its RVFI outputs (RISCV_FORMAL) for the CPU's page
DUMP          ?= 0
ifeq ($(DUMP),1)
  VLTDUMP      = --trace-fst --trace-depth 3 +define+DUMP tb.vlt
  ICADUMP      = -DDUMP
  VVPDUMP      = -fst
  ifeq ($(EP),rtl)
    VLTDUMP    = --trace-fst --trace-depth 6 +define+DUMP +define+RISCV_FORMAL tb.vlt
    VLTVIEWS   = -F wavecrux.f   # after rtl.f: the views import its packages (Verilator 5.055: USEBEFOREDECL)
  endif
endif

# --timing: the test bench and the models use delays and event controls
# CFG_LDFLAGS_VERILATED cleared: a Verilator built with mold links through it
# (-fuse-ld=mold), and mold fails on network shares (fchmod); the default
# linker works everywhere
VLTFLAGS       = --binary -sv --timing --timescale 1ns/10ps --top-module tb -Mdir $(OBJDIR) $(VLTDUMP) \
                 -Wno-fatal -Wno-WIDTH -Wno-lint -Wno-style                     \
                 +define+VPROC_SV +define+VPROC_BYTE_ENABLE                      \
                 $(EP_VLT) $(VLTVIEWS) -F tb.f $(USRSIMFLAGS)                  \
                 -MAKEFLAGS "--quiet CFG_LDFLAGS_VERILATED="                    \
                 -CFLAGS "$(CPPSTD) -Wno-attributes"                            \
                 -LDFLAGS "$(LDLIBS)"

# ---- Icarus -------------------------------------------------------------------
# The same file list, with $VIP_DIR filled in; mem_model.sv is left out, as
# this test bench does not instantiate it. Its first line is the default
# timescale, for files without one (no `timescale in RTL)
ICA_FILES      = $(OBJDIR)/tb.icarus.f
ICAFLAGS       = -g2012 -DVPROC_BYTE_ENABLE $(ICA_IFACE) $(ICADUMP) -s tb -c $(ICA_FILES) $(USRSIMFLAGS)

# =============================================================================
# TARGETS
# =============================================================================

.PHONY: all run regress mutants wavecrux wavecrux_run clean help FORCE
.DEFAULT_GOAL := all

all: $(SIMEXE)

$(OBJDIR):
	@mkdir -p $@

# CPU=iss: the ISS integration (models/rv32/usercode) and the rv32 library.
# This rule comes first, so its VUserMain0.o wins over usercode/'s.
ifneq ($(ISS_C),)
$(OBJDIR)/%.o: $(ISSCODEDIR)/%.cpp | $(OBJDIR)
	@$(HOST_CXX) -c -fPIC -MMD -MP $(OPTFLAG) $(CPPSTD) -Wno-write-strings $(DEFS) -I$(ISSCODEDIR) $(INCLPATHS) -I$(RV32SRC) $< -o $@

$(RV32OBJDIR):
	@mkdir -p $@

$(RV32OBJDIR)/%.o: $(RV32SRC)/%.cpp $(wildcard $(RV32SRC)/*.h) | $(RV32OBJDIR)
	@$(HOST_CXX) -c -fPIC -MMD -MP $(OPTFLAG) -I$(RV32SRC) -D_REENTRANT $< -o $@

$(RV32LIB): $(RV32OBJS)
	@rm -f $@
	@$(HOST_AR) cr $@ $(RV32OBJS)
endif

# CPU=vproc: the 3.sw firmware itself, compiled for the host as C++ with
# main() renamed fw_main() for usercode/VUserMain0.cpp to call. Under VPROC,
# CSR_REG32 (csr_regs.h) is a VProc bus cycle.
FW_HOST_FLAGS  = -x c++ -Dmain=fw_main -Wno-volatile -I$(FW_DIR)/common \
                 -I$(CURDIR)/../4.build/csr_build -I$(CURDIR)/../4.build/csr_build/generated-files
FW_HOST_DEPS   = $(FW_DIR)/common/pcie.h $(CURDIR)/../4.build/csr_build/csr_regs.h

$(OBJDIR)/fw_pcie.o: $(FW_DIR)/common/pcie.c $(FW_HOST_DEPS) | $(OBJDIR)
	@$(HOST_CXX) -c -fPIC -MMD -MP $(OPTFLAG) $(CPPSTD) $(FW_HOST_FLAGS) $(DEFS) $(INCLPATHS) $< -o $@

$(OBJDIR)/fw_main.o: $(FW_DIR)/EP/main.c $(FW_HOST_DEPS) | $(OBJDIR)
	@$(HOST_CXX) -c -fPIC -MMD -MP $(OPTFLAG) $(CPPSTD) $(FW_HOST_FLAGS) $(DEFS) $(INCLPATHS) $< -o $@

$(OBJDIR)/%.o: $(USRCODEDIR)/%.c | $(OBJDIR)
	@$(HOST_CC) -c -fPIC -MMD -MP $(OPTFLAG) $(DEFS) $(INCLPATHS) $< -o $@

$(OBJDIR)/%.o: $(USRCODEDIR)/%.cpp | $(OBJDIR)
	@$(HOST_CXX) -c -fPIC -MMD -MP $(OPTFLAG) $(CPPSTD) -Wno-write-strings $(DEFS) $(INCLPATHS) $< -o $@

# The host: the model, its checker and its ltssm.c (openPCIE_BFM 3.sw), without
# LTSSM_ABBREVIATED, as openPCIE compiles them (the model sets its own
# Polling count)
$(OBJDIR)/VUserMain2.o: $(A7RC_DIR)/VUserMain2.cpp $(A7RC_DIR)/a7rc_check.h | $(OBJDIR)
	@$(HOST_CXX) -c -fPIC -MMD -MP $(OPTFLAG) $(CPPSTD) -Wno-write-strings $(DEFS) $(INCLPATHS) $< -o $@

$(OBJDIR)/a7rc_check.o: $(A7RC_DIR)/a7rc_check.cpp $(A7RC_DIR)/a7rc_check.h | $(OBJDIR)
	@$(HOST_CXX) -c -fPIC -MMD -MP $(OPTFLAG) $(CPPSTD) -Wno-write-strings $(DEFS) $(INCLPATHS) $< -o $@

$(OBJDIR)/ltssm.o: $(LTSSM_DIR)/ltssm.c | $(OBJDIR)
	@$(HOST_CC) -c -fPIC -MMD -MP $(OPTFLAG) $(DEFS) $(INCLPATHS) $< -o $@

$(USERLIB): $(VOBJS)
	@rm -f $@
	@$(HOST_AR) cr $@ $(VOBJS)

ifeq ($(SIM),verilator)
# Verilator decides itself what to rebuild; always ask it
$(SIMEXE): $(USERLIB) $(RV32LIB) FORCE
	@for l in $(USERLIB) $(RV32LIB); do [ $$l -nt $@ ] && rm -f $@; done; true   # Verilator's make does not track them
	@$(VERILATOR) $(VLTFLAGS)
else
$(VPROC_SO): $(USERLIB) $(RV32LIB)
	@$(HOST_CXX) -shared -fPIC -pthread -rdynamic -o $@ \
	    -Wl,-whole-archive $(USERLIB) -Wl,-no-whole-archive $(RV32LIB) -Wl,-whole-archive -L$(VIP_DIR)/lib -lpcieica -lcosimica -Wl,-no-whole-archive \
	    -L$(ICA_LIB) -lvpi -lrt -ldl

# JanusHDL reads the list at each run, also from obj/regress/<seed>/: full paths
$(ICA_FILES): tb.f $(EP_FILES) FORCE | $(OBJDIR)
	@{ echo '+timescale+1ns/10ps'; sed -e 's#$$VIP_DIR#$(VIP_DIR)#g' -e '/mem_model\.sv/d' \
	    $(if $(filter janushdl,$(SIM)),-e 's#^[A-Za-z0-9_.]#$(CURDIR)/&#') $(EP_FILES) tb.f; \
	  $(if $(filter janushdl,$(SIM)),$(foreach f,$(EP_JHDL_SV),echo $(CURDIR)/$(f);)) } > $@

ifeq ($(SIM),icarus)
$(SIMEXE): $(VPROC_SO) $(ICA_FILES) FORCE
	@$(IVERILOG) -o $@ $(ICAFLAGS)
endif
endif

FORCE:

ifeq ($(SIM),verilator)
SIM_CMD        = $(SIMEXE) $(SIM_ARGS)
else ifeq ($(SIM),icarus)
SIM_CMD        = $(VVP) -n -M $(OBJDIR) -m VProc $(SIMEXE) $(VVPDUMP)
else
# DUMP=1: JanusHDL's own --fst, every signal
SIM_CMD        = $(JHDL) --top tb $(patsubst -D%,+define+%,-DVPROC_BYTE_ENABLE $(ICA_IFACE) $(EP_JHDL)) -f $(ICA_FILES) \
                 --vpi $(VPROC_SO) $(if $(filter 1,$(DUMP)),--fst $(WCX_FST)) $(USRSIMFLAGS)
endif

run: all
	@cd $(CURDIR) && $(FW_IN) A7RC_SEED=$(SEED) $(SIM_CMD); s=$$?; $(FW_OUT) exit $$s

# The tester over seeds 1 to SEEDS, each in obj/regress/<seed>/, so seeds can
# run side by side (openPCIE_BFM 4.build/regress.sh). PL.SPEED and PL.EIOS are listed apart:
# our EP and the EP model are Gen1, so no seed changes the speed
regress: all
	@cd $(CURDIR) && $(FW_IN) REGRESS_NA="PL.SPEED PL.EIOS" bash $(BFM)/4.build/regress.sh $(SEEDS) $(REGRESS_JOBS) $(REGRESS_S) $(REGRESS_TRIES) \
	    $(REGRESS_QUIET) $(CURDIR)/obj/regress "vusermain.cfg firmware.hex" -- $(SIM_CMD); s=$$?; $(FW_OUT) \
	$(if $(filter fail,$(REGRESS_DUMP)),for d in obj/regress/*/; do [ ! -e $$d/failed ] || \
	    $(MAKE) --no-print-directory wavecrux SEED=$$(basename $$d) WCX_OPEN=0; done;) exit $$s

# One seed with its waveform, opened in WaveCrux at the first violation
wavecrux:
	@$(MAKE) --no-print-directory DUMP=1 wavecrux_run

wavecrux_run: all
	@d=$(CURDIR)/obj/wavecrux/$(SEED); rm -rf $$d; mkdir -p $$d/hex; cp hex/ContDisps.hex $$d/hex/; \
	for f in vusermain.cfg; do if [ -f $$f ]; then cp $$f $$d/; fi; done; \
	cd $$d && $(FW_IN) A7RC_SEED=$(SEED) $(SIM_CMD) > run.log 2>&1; \
	echo "seed $(SEED): $$(grep -a -m1 'RC MODEL RESULT' $$d/run.log), $$d/$(WCX_FST)"; \
	$(if $(filter 1,$(WCX_OPEN)),python3 $(BFM)/4.build/wavecrux.py $$d/$(WCX_FST) $$d/run.log $(WCX_SIGNALS),echo "  open it: make wavecrux SEED=$(SEED)")

# The checker against broken endpoint models (EP=model, at the PIPE), each in
# obj/mutants/<name>/: each must fail the rule it breaks (openPCIE_BFM
# 4.build/mutants.py). Our EP model is Gen1: the PL.EIOS mutants are n/a
MUTANT_JOBS   ?= 3
mutants:
	@python3 $(BFM)/4.build/mutants.py --jobs $(MUTANT_JOBS) --out obj/mutants -- run EP=model IFACE=pipe SIM=$(SIM)

help:
	@echo "make [SIM=verilator|icarus|janushdl] [EP=model|rtl] [IFACE=pipe|serial|phy]   build the models and the simulation (EP=rtl: Verilator, JanusHDL once #24 is fixed; IFACE=phy: Verilator only)"
	@echo "make IFACE=phy run                 the EP model behind our PHY (phy_top, PIPE logic, SerDes BFM), the host on the serial line"
	@echo "make A7RC=1 run                    literal host: only what the lab RC sends (default: the tester, also back to back)"
	@echo "make DMA=1 run                     the tester also runs its EP DMA stage (off by default: our EP has no DMA, #14)"
	@echo "make SEED=N run                    the tester's random stimulus with seed N (default 1), no rebuild"
	@echo "make regress SEEDS=N               the tester over seeds 1 to N (default 10), in obj/regress/<seed>/"
	@echo "make mutants                       the checker against broken EP models: each must fail its rule"
	@echo "    REGRESS_JOBS=J                 J seeds side by side (default 1); REGRESS_QUIET=0 keeps the packet display"
	@echo "    REGRESS_DUMP=fail              dump every failing seed (obj/wavecrux/<seed>/)"
	@echo "make wavecrux SEED=N               seed N with its waveform, in WaveCrux at the first violation (--wcp-port 54321)"
	@echo "make EP=rtl CPU=vproc|iss run      the SOC CPU: native firmware or the rv32 ISS (default CPU=rtl, eduBOS5)"
	@echo "make [SIM=verilator|icarus|janushdl] run   build and run"
	@echo "make DUMP=1 run                    also write tb.fst (WaveCrux: tb.DLL-PIPE.wavecrux)"
	@echo "make EP=rtl DUMP=1 run             also write tb_rtl.fst, the EP's layers (WaveCrux: tb_rtl.*.wavecrux)"
	@echo "make clean                         remove obj/"
	@echo "USER_C, USRCODEDIR, OPTFLAG, USRSIMFLAGS (extra simulator flags) can be overridden"

clean:
	@rm -rf $(CURDIR)/obj

# -----------------------------------------------------------------------------
# Project:     openCologne-PCIE
# Description: NLnet-sponsored open-source implementation
# Version:     1.0
# Date:        April 2025
# -----------------------------------------------------------------------------

# Header dependencies of the user objects (-MMD -MP)
-include $(wildcard $(OBJDIR)/*.d)
