#!/bin/bash
# SPDX-FileCopyrightText: 2026 Chili.CHIPS
#
# SPDX-License-Identifier: BSD-3-Clause
#
# tb_soc on Verilator: the SOC alone, eduBOS5 with its RVFI outputs
# (RISCV_FORMAL), running 4.build/sw_build/firmware.hex. Writes tb_soc.fst
# here, for tb_soc.RISCV-ISA.wavecrux; a test (tx, rx, cpl) writes its own
# into its build folder.
#
# usage:  bash run-soc.sh       the EP firmware, 4.build/sw_build/firmware.hex
#         bash run-soc.sh tx    the Tx test: 3.sw/tests/soc_tx (3-DW and 4-DW
#                               requests), built here; tb_soc checks every
#                               s_axis_tx beat
#         bash run-soc.sh rx    the Rx test: 3.sw/tests/soc_rx, a burst of TLPs
#                               through the RX ring, sent back in Tx batches
#         bash run-soc.sh cpl   the EP firmware (3.sw/EP), built here: MemRds
#                               split into CplDs at the RCB, and a UR
#
# SOC_BUILD (default ~/.cache/opencologne-pcie/soc) is the build directory.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$HERE/../.." && pwd)
G=$R/../4.build/csr_build/generated-files
E=$R/7.soc/CPU.eduBOS5
B=${SOC_BUILD:-$HOME/.cache/opencologne-pcie/soc}
mkdir -p "$B"
verilator --binary --timing --trace-fst -Wno-fatal -Wno-lint -Wno-style --timescale 1ns/10ps \
  --assert -DRISCV_FORMAL --top-module tb_soc --Mdir "$B/obj" -o Vtb_soc \
  "$R/2.pipe/pipe_pkg.sv" "$R/4.dll/dll_pkg.sv" "$R/5.tlp/trn_pkg.sv" "$R/5.tlp/tl_pkg.sv" "$R/6.trn_bridge/axis_pkg.sv" "$G/csr_pkg.sv" "$E/edubos5_pkg.sv" \
  "$R/6.trn_bridge/axis_if.sv" "$R/5.tlp/cfg_if.sv" "$R/7.soc/mem_if.sv" "$R/7.soc/rvfi_if.sv" \
  "$E/edubos5_rf.sv" "$E/edubos5_alu.sv" "$E/edubos5.sv" "$G/csr.sv" \
  "$R/7.soc/soc_csr.sv" "$R/7.soc/soc_top.sv" "$E/wavecrux/soc_cpu_view.sv" \
  "$HERE/tb_soc.sv" > "$B/build.log" 2>&1 || { tail -20 "$B/build.log"; exit 1; }
ARGS=()
RUN=$HERE  # the tracked tb_soc.fst: the default run only; a test's goes to its build folder
if [ "${1:-}" = tx ] || [ "${1:-}" = rx ] || [ "${1:-}" = cpl ]; then
  T=soc_$1
  S=tests/$T
  if [ "$1" = cpl ]; then S=EP; fi
  mkdir -p "$B/$T"
  make -s -C "$R/../4.build/sw_build" SW_DIR=../../3.sw/$S OUT="$B/$T" > "$B/$T.log" 2>&1 ||
    { tail -20 "$B/$T.log"; exit 1; }
  RUN=$B/$T
  ARGS=(+$1_check)
else
  cp "$R/../4.build/sw_build/firmware.hex" "$HERE/"
fi
cd "$RUN"
"$B/obj/Vtb_soc" "${ARGS[@]}"
if [ "$RUN" = "$HERE" ]; then rm -f "$HERE/firmware.hex"; fi
echo "waveform: $RUN/tb_soc.fst"

# -----------------------------------------------------------------------------
# Project:     openCologne-PCIE
# Description: NLnet-sponsored open-source implementation
# Version:     1.0
# Date:        Oct 18, 2026
# -----------------------------------------------------------------------------
