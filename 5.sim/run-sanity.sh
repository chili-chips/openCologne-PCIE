#!/bin/bash
# SPDX-FileCopyrightText: 2026 Chili.CHIPS
#
# SPDX-License-Identifier: BSD-3-Clause
#
# Sanity, after every change (README.md, Sanity and regression): six runs,
# about 2 minutes. Each must end RC MODEL RESULT: PASS; Verilator and Icarus must
# print the same ===> lines. The EP DMA stage is off (DMA=0, #41).
# rtl-serial is the one run through top (its SerDes nets, by hierarchy).
# Our EP (rtl, rtl-vproc, rtl-serial) drops an SKP (#38): those run on past the SVA
# and pass as "known #38" while SVA #38 fired, PL.SKP holds every checker
# violation and the firmware still ends 0x0000face. Drop KNOWN when #38 closes.
# Prints one line per run, logs in obj/sanity/; exits 1 if any run fails.
#
# Usage: bash run-sanity.sh [make variables, e.g. OPTFLAG=-O0]

set -u
cd "$(dirname "$0")"
LOG=obj/sanity
mkdir -p $LOG
fails=0
KNOWN="#38"   # the runs marked known38 below; empty once #38 closes

known38() {  # log, result line: only SVA #38 fired, PL.SKP holds every error, the firmware done
    local e s
    e=$(echo "$2" | sed -n 's/.*FAIL, \([0-9]*\) errors.*/\1/p')
    s=$(grep -a '===>   PL.SKP ' $1 | awk '{print $5}')
    grep -a -q 'SVA #38' $1 && ! grep -a '\*\*\*\* SVA #' $1 | grep -q -v 'SVA #38' &&
        grep -a -q 'firmware result 0x0000face' $1 &&
        [ -n "$e" ] && [ "$e" -gt 0 ] && [ "$e" = "$s" ]
}

run() {  # name, [known38], make variables
    local n=$1 t0=$SECONDS r k=
    shift
    if [ "${1:-}" = known38 ]; then k=$KNOWN; shift; fi
    make run DMA=0 "$@" > $LOG/$n.log 2>&1
    r=$(grep -a -m1 'RC MODEL RESULT\|time limit' $LOG/$n.log)
    case "$r" in
        *"RESULT: PASS"*)
            if [ -n "$k" ]; then r="$r, known $k not seen: update KNOWN"; fails=$((fails + 1)); fi ;;
        *)
            if [ -n "$k" ] && known38 $LOG/$n.log "$r"; then r="known $k ($r)"
            else fails=$((fails + 1)); fi ;;
    esac
    printf '%-16s %4d s  %-36s %s\n' "$n" $((SECONDS - t0)) "$*" "${r:-no result, see $LOG/$n.log}"
}

# #38: the runs of our EP go on past the SVA (the error limit)
run model         "$@"
run model-icarus  SIM=icarus "$@"
run model-serial  IFACE=serial "$@"
run rtl           known38 EP=rtl A7RC=1 SIM_ARGS=+verilator+error+limit+100 "$@"
run rtl-vproc     known38 EP=rtl CPU=vproc A7RC=1 SIM_ARGS=+verilator+error+limit+100 "$@"
run rtl-serial    known38 EP=rtl IFACE=serial A7RC=1 SIM_ARGS=+verilator+error+limit+100 "$@"

if diff -q <(grep -a '===>' $LOG/model.log) <(grep -a '===>' $LOG/model-icarus.log) > /dev/null; then
    echo "Verilator = Icarus: the same ===> lines"
else
    echo "Verilator and Icarus differ: diff <(grep -a '===>' $LOG/model.log) <(grep -a '===>' $LOG/model-icarus.log)"
    fails=$((fails + 1))
fi
echo "sanity: $fails failed"
[ $fails = 0 ]
