#!/bin/bash
# SPDX-FileCopyrightText: 2026 Chili.CHIPS
#
# SPDX-License-Identifier: BSD-3-Clause
#
# tb_rx_ring: tlp_rx_buffer on its own, TLPs back to back and a bad LCRC
# with its replay (#4). Icarus 12 or later.
#
# usage: bash run-rx-ring.sh
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
RTL="$(cd "${HERE}/../.." && pwd)"
BUILD="${SERDES_BUILD_DIR:-$HOME/.cache/opencologne-pcie}/rx-ring"
IVL=${IVL:-iverilog}
VVP=${VVP:-vvp}
mkdir -p "${BUILD}"
"${IVL}" -g2012 -o "${BUILD}/tb_rx_ring.vvp" \
  "${RTL}/2.pipe/pipe_pkg.sv" "${RTL}/4.dll/dll_pkg.sv" "${RTL}/4.dll/lcrc_pipe.sv" \
  "${RTL}/4.dll/tlp_rx_buffer.sv" "${HERE}/tb_rx_ring.sv" 2>&1 | grep -v "sorry" || true
"${VVP}" -n "${BUILD}/tb_rx_ring.vvp"
