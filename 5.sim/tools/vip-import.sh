#!/bin/bash
# SPDX-FileCopyrightText: 2026 Chili.CHIPS
#
# SPDX-License-Identifier: BSD-3-Clause
#
# Import the rv32 ISS from upstream (github.com/wyvernSemi/rv32) into
# 5.sim/vip/rv32, with openPCIE's two ISS fixes applied. Run it only to
# upgrade the ISS: set the pin below, run, then run make EP=rtl CPU=iss run
# and update vip/README.md.
#
#   bash 5.sim/tools/vip-import.sh
#
# VProc, pcieVHost and mem_model come from the openPCIE_BFM submodule
# (vip/openPCIE_BFM); its 4.build/vip-import.sh imports them.
#
# Copies only the files the build uses, with LF line endings, then applies:
#   - openPCIE's rv32-openpcie.patch (models/rv32)
#   - README: <p align="center"> blocks become <div align="center">
#
# DEPS_WORK (default ~/.cache/opencologne-pcie-deps) holds the upstream
# clone. Needs git, patch, sed.
set -euo pipefail
RV32_REF=${RV32_REF:-774d84fa}
HERE=$(cd "$(dirname "$0")" && pwd)
D=$(cd "$HERE/.." && pwd)/vip
U=${DEPS_WORK:-$HOME/.cache/opencologne-pcie-deps}
mkdir -p "$U"

fetch() {  # <repo> <ref>: clone or update, check out
  [ -d "$U/$1/.git" ] || git clone -q "https://github.com/wyvernSemi/$1.git" "$U/$1"
  git -C "$U/$1" cat-file -e "$2^{commit}" 2>/dev/null || git -C "$U/$1" fetch -q --tags origin
  git -C "$U/$1" checkout -q "$2"
}
cp_lf() {  # <src> <dst>: upstream mixes CRLF and LF; we keep LF
  mkdir -p "$(dirname "$2")"
  tr -d '\r' < "$1" > "$2"
}

fetch rv32 "$RV32_REF"
rm -rf "$D"/rv32

# ---- rv32 ISS -------------------------------------------------------------------
for f in "$U"/rv32/iss/src/*; do cp_lf "$f" "$D/rv32/iss/src/$(basename "$f")"; done
for f in LICENSE README.md; do cp_lf "$U/rv32/$f" "$D/rv32/$f"; done
# change: openPCIE's two ISS fixes
patch -s --no-backup-if-mismatch -p0 -d "$D/rv32/iss/src" < "$HERE/../models/rv32/rv32-openpcie.patch"

# ---- upstream README: centred blocks in <div>, which GitLab also honors ----------
sed -i -e '/<p align="center">/,/<\/p>/{s#<p align="center">#<div align="center">#;s#</p>#</div>#}' \
  "$D"/rv32/README.md

echo "imported: rv32 $RV32_REF"
echo "next: update vip/README.md, then run make EP=rtl CPU=iss run"

# -----------------------------------------------------------------------------
# Project:     openCologne-PCIE
# Description: NLnet-sponsored open-source implementation
# Version:     1.0
# Date:        Oct 18, 2026
# -----------------------------------------------------------------------------
