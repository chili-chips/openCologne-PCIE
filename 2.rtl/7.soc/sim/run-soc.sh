#!/bin/bash
# SPDX-FileCopyrightText: 2026 Chili.CHIPS
#
# SPDX-License-Identifier: BSD-3-Clause
#
# tb_soc on Verilator: the SOC alone, eduBOS5 with its RVFI outputs
# (RISCV_FORMAL), running 4.build/sw_build/firmware.hex. Writes tb_soc.fst
# here, for tb_soc.RISCV-ISA.wavecrux.
#
# usage:  bash run-soc.sh       the EP firmware, 4.build/sw_build/firmware.hex
#         bash run-soc.sh tx    the Tx test: 3.sw/tests/soc_tx (3-DW and 4-DW
#                               requests), built here; tb_soc checks every
#                               s_axis_tx beat
#
# SOC_BUILD (default ~/.cache/opencologne-pcie/soc) is the build directory.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$HERE/../.." && pwd)
G=$R/../4.build/csr_build/generated-files
E=$R/7.soc/CPU.eduBOS5
B=${SOC_BUILD:-$HOME/.cache/opencologne-pcie/soc}
mkdir -p "$B"
verilator --binary --timing --trace-fst -Wno-fatal -Wno-lint -Wno-style --timescale 1ns/1ps \
  --assert -DRISCV_FORMAL --top-module tb_soc --Mdir "$B/obj" -o Vtb_soc \
  "$R/2.pipe/pipe_pkg.sv" "$R/4.dll/dll_pkg.sv" "$R/5.tlp/trn_pkg.sv" "$R/5.tlp/tl_pkg.sv" "$R/6.trn_bridge/axis_pkg.sv" "$G/csr_pkg.sv" "$E/edubos5_pkg.sv" \
  "$R/6.trn_bridge/axis_if.sv" "$R/5.tlp/cfg_if.sv" "$R/7.soc/mem_if.sv" "$R/7.soc/rvfi_if.sv" \
  "$E/edubos5_rf.sv" "$E/edubos5_alu.sv" "$E/edubos5.sv" "$G/csr.sv" \
  "$R/7.soc/soc_csr.sv" "$R/7.soc/riscv_pcie_soc.sv" "$E/wavecrux/soc_cpu_view.sv" \
  "$HERE/tb_soc.sv" > "$B/build.log" 2>&1 || { tail -20 "$B/build.log"; exit 1; }
ARGS=()
if [ "${1:-}" = tx ]; then
  mkdir -p "$B/soc_tx"
  make -s -C "$R/../4.build/sw_build" SW_DIR=../../3.sw/tests/soc_tx OUT="$B/soc_tx" > "$B/soc_tx.log" 2>&1 ||
    { tail -20 "$B/soc_tx.log"; exit 1; }
  cp "$B/soc_tx/firmware.hex" "$HERE/"
  ARGS=(+tx_check)
else
  cp "$R/../4.build/sw_build/firmware.hex" "$HERE/"
fi
cd "$HERE"
"$B/obj/Vtb_soc" "${ARGS[@]}"
rm -f "$HERE/firmware.hex"
echo "waveform: $HERE/tb_soc.fst"

# -----------------------------------------------------------------------------
# Project:     openCologne-PCIE
# Description: NLnet-sponsored open-source implementation
# Version:     1.0
# Date:        Oct 18, 2026
# -----------------------------------------------------------------------------
