#!/bin/bash
# SPDX-FileCopyrightText: 2026 Chili.CHIPS
#
# SPDX-License-Identifier: BSD-3-Clause
#
# Sanity, after every change (README.md, Sanity and regression): five runs,
# about 40 s. Each must end RC MODEL RESULT: PASS; Verilator and Icarus must
# print the same ===> lines. The EP DMA stage is off (DMA=0, #41).
# Prints one line per run, logs in obj/sanity/; exits 1 if any run fails.
#
# Usage: bash run-sanity.sh [make variables, e.g. OPTFLAG=-O0]

set -u
cd "$(dirname "$0")"
LOG=obj/sanity
mkdir -p $LOG
fails=0

run() {  # name, make variables
    local n=$1 t0=$SECONDS r
    shift
    make run DMA=0 "$@" > $LOG/$n.log 2>&1
    r=$(grep -a -m1 'RC MODEL RESULT\|time limit' $LOG/$n.log)
    case "$r" in *"RESULT: PASS"*) ;; *) fails=$((fails + 1));; esac
    printf '%-16s %4d s  %-36s %s\n' "$n" $((SECONDS - t0)) "$*" "${r:-no result, see $LOG/$n.log}"
}

run model         "$@"
run model-icarus  SIM=icarus "$@"
run model-serial  IFACE=serial "$@"
run rtl           EP=rtl A7RC=1 "$@"
run rtl-vproc     EP=rtl CPU=vproc A7RC=1 "$@"

if diff -q <(grep -a '===>' $LOG/model.log) <(grep -a '===>' $LOG/model-icarus.log) > /dev/null; then
    echo "Verilator = Icarus: the same ===> lines"
else
    echo "Verilator and Icarus differ: diff <(grep -a '===>' $LOG/model.log) <(grep -a '===>' $LOG/model-icarus.log)"
    fails=$((fails + 1))
fi
echo "sanity: $fails failed"
[ $fails = 0 ]
