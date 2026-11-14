#!/bin/bash
# SPDX-FileCopyrightText: 2026 Chili.CHIPS
#
# SPDX-License-Identifier: BSD-3-Clause
#
# PHY block-level simulation (tb_phy.sv), Icarus Verilog:
#
#   pipe64            the PIPE layer of gatemate-pipe on the SerDes, 64-bit PIPE
#                     (DATA_BYTES in pipe_pkg): TS1 ordered sets, test data, error detection
#   equiv             the opensource SerDes BFM alone, looped back (self-check)
#
# usage:  bash run-phy.sh pipe64 [--vendor] [--dump]
#         bash run-phy.sh equiv [--ref] [--cross] [--dump] [--keep]
#
#   --vendor  pipe: the vendor SerDes model instead of the open one
#   --ref     equiv: the vendor model too, side by side with the open one
#   --cross   equiv: with --ref, each model's TX into the other's RX
#   --dump    write a waveform
#   --keep    keep the throwaway copy of the vendor sources
#
# The vendor model is under NDA and never inside this repository: it is read
# from $CCFPGA_SERDES_SRC (serdes_nda_env.sh). Build products and waveforms go
# to $SERDES_BUILD_DIR (default ~/.cache/opencologne-pcie).
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${HERE}/../../.." && pwd)"
MODEL_DIR="${REPO_ROOT}/2.rtl/1.phy/2.opensource-serdes-model"
PIPE_DIR="${REPO_ROOT}/2.rtl/2.pipe"

. "${HERE}/serdes_nda_env.sh"

IVL=${IVL:-iverilog}
# Icarus 14 or later: the PIPE, MAC and DLL take SystemVerilog interface ports
case "$("${IVL}" -V 2>&1 | head -1)" in
  *"version 1"[4-9]*|*"version "[2-9][0-9]*) ;;
  *) echo "$(basename "$0"): Icarus 14 or later needed (interface ports), e.g. the OSS CAD Suite's; set IVL" >&2; exit 2 ;;
esac
VVP=${VVP:-vvp}

TEST=${1:-}
shift || true
VENDOR=0
WITH_REF=0
DUMP=""
CROSS=""
KEEP=0
for arg in "$@"; do
  case "$arg" in
    --vendor) VENDOR=1 ;;
    --ref)    WITH_REF=1 ;;
    --cross)  CROSS="-DCROSS_LINK" ;;
    --dump)   DUMP="-DDUMP" ;;
    --keep)   KEEP=1 ;;
    *) echo "unknown option: $arg"; exit 1 ;;
  esac
done

case "${TEST}" in
  pipe64) BYTES=8 ;;
  equiv)  ;;
  *) sed -n '/^# usage/,/^#   --keep/p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac

guard_repo_clean "${REPO_ROOT}"

OPEN_SRC="${MODEL_DIR}/ccfpga_serdes_pkg.sv ${MODEL_DIR}/ccfpga_serdes.BFM.sv"
REF_COPY=""
cleanup () {
  if [ "${KEEP}" = "0" ] && [ -n "${REF_COPY}" ] && [ -d "${REF_COPY}" ]; then
    rm -rf "${REF_COPY}"
  fi
}
trap cleanup EXIT INT TERM

if [ "${TEST}" = equiv ]; then
  BUILD="${SERDES_BUILD_DIR}/equiv"
  mkdir -p "${BUILD}/sim"
  rm -f "${BUILD}/equiv.vvp"
  DEFS="-DTB_PHY_EQUIV -DPIPE -DBHV_RX_WORD_PHASE_RANDOM=0 ${DUMP} ${CROSS}"  # the check expects the comma in lane 0
  REF_SRC=""
  if [ "${WITH_REF}" = "1" ]; then
    echo "==> preparing throwaway copy of vendor sources (originals untouched)"
    REF_COPY="${BUILD}/serdes_ref"
    prepare_vendor_copy "${REF_COPY}" || exit 1
    sed -i -E 's/\bmodule[[:space:]]+ccfpga_serdes[[:space:]]*\(/module ccfpga_serdes_ref (/' \
        "${REF_COPY}/ccfpga_serdes.v"
    sed -i -E 's/endmodule[[:space:]]*\/\/[[:space:]]*ccfpga_serdes[[:space:]]*$/endmodule \/\/ ccfpga_serdes_ref/' \
        "${REF_COPY}/ccfpga_serdes.v"
    if ! grep -q 'module ccfpga_serdes_ref' "${REF_COPY}/ccfpga_serdes.v"; then
      echo "ERROR: failed to rename the vendor top module"; exit 1
    fi
    REF_SRC=$(find "${REF_COPY}" -type f \( -name '*.v' -o -name '*.sv' \))
    DEFS="${DEFS} -DHAVE_VENDOR_SERDES"
    echo "==> vendor model WILL be compiled in ($(echo "${REF_SRC}" | wc -w) files)"
    echo "    sources : ${CCFPGA_SERDES_SRC}   (read only)"
    echo "    copy    : ${REF_COPY}"
  else
    echo "==> vendor model NOT compiled in; running behavioural self-check only"
  fi
  echo "==> compiling"
  ${IVL} -g2012 -c <(echo +timescale+1ns/1ps) -gspecify -Ttyp ${DEFS} -I "${MODEL_DIR}" -o "${BUILD}/equiv.vvp" \
         ${OPEN_SRC} ${REF_SRC} "${HERE}/tb_phy.sv"
  echo "==> running"
  cd "${BUILD}"
  ${VVP} -N equiv.vvp ${DUMP:+-fst}
  exit 0
fi

# ---- PIPE test
BUILD="${SERDES_BUILD_DIR}/phy_${TEST}"
mkdir -p "${BUILD}/sim"
rm -f "${BUILD}/sim/vlog_sim.vvp"
if [ "${VENDOR}" = "1" ]; then
  REF_COPY="${BUILD}/serdes_src"
  prepare_vendor_copy "${REF_COPY}" || exit 1
  SERDES_SRC=$(find "${REF_COPY}" -type f \( -name '*.v' -o -name '*.sv' \))
  SERDES_INC="${REF_COPY}"
else
  SERDES_SRC="${OPEN_SRC}"
  SERDES_INC="${MODEL_DIR}"
fi
PIPE_SRC="${PIPE_DIR}/pipe_pkg.sv $(find "${PIPE_DIR}" -maxdepth 1 -type f \( -name '*.v' -o -name '*.sv' \) ! -name pipe_pkg.sv)"

echo "==> PIPE test, $((BYTES * 8))-bit PIPE, $([ "${VENDOR}" = 1 ] && echo vendor || echo open) SerDes model"
${IVL} -g2012 -c <(echo +timescale+1ns/1ps) -gspecify -Ttyp -DPIPE ${DUMP} -I"${SERDES_INC}" \
       -o "${BUILD}/sim/vlog_sim.vvp" ${SERDES_SRC} ${PIPE_SRC} "${HERE}/tb_phy.sv"
cd "${BUILD}"
${VVP} -N sim/vlog_sim.vvp -fst
