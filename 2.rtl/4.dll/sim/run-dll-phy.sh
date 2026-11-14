#!/bin/bash
# SPDX-FileCopyrightText: 2026 Chili.CHIPS
#
# SPDX-License-Identifier: BSD-3-Clause
#
# DLL over a real PHY (tb_dll_phy.sv), Icarus Verilog: an Endpoint and a Root
# Complex, each DLL + MAC/LTSSM + PIPE + opensource SerDes BFM (pcie_stack.sv),
# connected by a bit-level serial link in both directions.
#
# usage:  bash run-dll-phy.sh [--dump] [--scramble] [--inject=stp|end]
#
# --inject: a TLP with its STP or END corrupted at the RC's receiver, in place
# of steps 4 to 7. Fails until #24 is fixed (no REPLAY_TIMER).
#
# Build products and the waveform go to $SERDES_BUILD_DIR/dll (default
# ~/.cache/opencologne-pcie).
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${HERE}/../../.." && pwd)"
PHY_DIR="${REPO_ROOT}/2.rtl/1.phy"
MODEL_DIR="${PHY_DIR}/2.opensource-serdes-model"
PIPE_DIR="${REPO_ROOT}/2.rtl/2.pipe"
MAC_DIR="${REPO_ROOT}/2.rtl/3.mac"
DLL_DIR="${REPO_ROOT}/2.rtl/4.dll"

BUILD="${SERDES_BUILD_DIR:-$HOME/.cache/opencologne-pcie}/dll"

IVL=${IVL:-iverilog}
# Icarus 14 or later: the PIPE, MAC and DLL take SystemVerilog interface ports
case "$("${IVL}" -V 2>&1 | head -1)" in
  *"version 1"[4-9]*|*"version "[2-9][0-9]*) ;;
  *) echo "$(basename "$0"): Icarus 14 or later needed (interface ports), e.g. the OSS CAD Suite's; set IVL" >&2; exit 2 ;;
esac
VVP=${VVP:-vvp}

DUMP=""
DEFS=""
PLUS=""
for arg in "$@"; do
  case "$arg" in
    --dump)     DUMP="-DDUMP" ;;
    --scramble) DEFS="${DEFS} -DSCRAMBLE" ;;
    --inject=*) PLUS="+inject=${arg#--inject=}" ;;
    -h|--help)  echo "usage: $0 [--dump] [--scramble] [--inject=stp|end]"; exit 0 ;;
    *) echo "unknown option: $arg"; exit 1 ;;
  esac
done

for d in "${PIPE_DIR}" "${MAC_DIR}" "${DLL_DIR}"; do
  if [ -z "$(find "$d" -maxdepth 1 -name '*.sv' 2>/dev/null)" ]; then
    echo "ERROR: no sources in $d"
    exit 1
  fi
done

mkdir -p "${BUILD}/sim"

DLL_SRC="${DLL_DIR}/dll_pkg.sv $(find "${DLL_DIR}" -maxdepth 1 \( -name '*.v' -o -name '*.sv' \) ! -name dll_pkg.sv)"  # not sim/
MAC_SRC="${MAC_DIR}/mac_pkg.sv $(find "${MAC_DIR}" -maxdepth 1 \( -name '*.v' -o -name '*.sv' \) ! -name mac_pkg.sv)"
PIPE_SRC="${PIPE_DIR}/pipe_pkg.sv $(find "${PIPE_DIR}" -maxdepth 1 \( -name '*.v' -o -name '*.sv' \) ! -name pipe_pkg.sv)"

${IVL} -g2012 -c <(echo +timescale+1ns/1ps) -gspecify -Ttyp ${DUMP} ${DEFS} \
       -I "${MODEL_DIR}" \
       -o "${BUILD}/dll_phy.vvp" \
       ${PIPE_SRC} \
       ${MAC_SRC} \
       ${DLL_SRC} \
       "${MODEL_DIR}/ccfpga_serdes_pkg.sv" \
       "${MODEL_DIR}/ccfpga_serdes.BFM.sv" \
       "${HERE}/phy_model.sv" \
       "${HERE}/pcie_stack.sv" \
       "${HERE}/tb_dll_phy.sv"

cd "${BUILD}"
${VVP} -N dll_phy.vvp ${DUMP:+-fst} ${PLUS}
if [ -n "${DUMP}" ]; then
  echo "waveform: ${BUILD}/sim/dll_phy.fst"
fi
