#!/bin/bash
# SPDX-FileCopyrightText: 2026 Chili.CHIPS
#
# SPDX-License-Identifier: BSD-3-Clause
#
# Regression, before a push (README.md, Sanity and regression): about 8
# minutes. 100 random seeds, Verilator against Icarus on the serial line, our
# EP against the tester and with the real PHY, and the block benches of the
# PHY, the DLL and the TL. The EP DMA stage is off (DMA=0, #41).
# A run that fails on open issues is reported as "known" with them; update
# KNOWN as they close. Prints one line per run, logs in obj/regression/;
# exits 1 if a run fails that should pass, or a known one passes.
#
# Usage: bash run-regression.sh [make variables, e.g. SIM=icarus]

set -u
cd "$(dirname "$0")"
HERE=$PWD
LOG=$HERE/obj/regression
mkdir -p $LOG
fails=0

# the runs that fail today, and why
declare -A KNOWN=(
    [rtl-tester]="#24 #26 #36-#40"
)

report() {  # name, seconds, pass (0/1), what, result
    local n=$1 t=$2 ok=$3 what=$4 r=$5 st
    if [ -n "${KNOWN[$n]:-}" ]; then
        if [ $ok = 1 ]; then st="PASS, known ${KNOWN[$n]}: update KNOWN"; fails=$((fails + 1))
        else st="known: ${KNOWN[$n]}"; fi
    elif [ $ok = 1 ]; then st="PASS"
    else st="FAIL"; fails=$((fails + 1)); fi
    printf '%-14s %4d s  %-44s %s  (%s)\n' "$n" "$t" "$what" "$st" "$r"
}

run() {  # name, make variables
    local n=$1 t0=$SECONDS r ok=0
    shift
    make run DMA=0 "$@" > $LOG/$n.log 2>&1
    r=$(grep -a -m1 'RC MODEL RESULT\|time limit' $LOG/$n.log)
    case "$r" in *"RESULT: PASS"*) ok=1;; esac
    report $n $((SECONDS - t0)) $ok "make $*" "${r:-no result}"
}

bench() {  # name, directory, command, pass pattern
    local n=$1 d=$2 c=$3 p=$4 t0=$SECONDS ok=0
    (cd "$d" && bash $c) > $LOG/$n.log 2>&1 && grep -a -q -E "$p" $LOG/$n.log && ok=1
    report $n $((SECONDS - t0)) $ok "$c" "log: $LOG/$n.log"
}

t0=$SECONDS
make regress SEEDS=100 REGRESS_JOBS=8 DMA=0 "$@" > $LOG/regress.log 2>&1
r=$(tail -1 $LOG/regress.log)
case "$r" in "0 of "*) ok=1;; *) ok=0;; esac
report regress $((SECONDS - t0)) $ok "make regress SEEDS=100 REGRESS_JOBS=8" "$r; $(tail -2 $LOG/regress.log | head -1)"

run serial         IFACE=serial "$@"
run serial-icarus  SIM=icarus IFACE=serial "$@"
if diff -q <(grep -a '===>' $LOG/serial.log) <(grep -a '===>' $LOG/serial-icarus.log) > /dev/null; then
    report sim-match 0 1 "Verilator = Icarus, serial" "the same ===> lines"
else
    report sim-match 0 0 "Verilator = Icarus, serial" "diff the ===> lines of serial.log and serial-icarus.log"
fi
run rtl-tester     EP=rtl "$@"
run rtl-serial     EP=rtl IFACE=serial A7RC=1 "$@"

bench pipe64  ../2.rtl/1.phy/3.sim "run-phy.sh pipe64" '^ ####    ###    ####  ####  #####  ####'  # the PASSED banner
bench equiv   ../2.rtl/1.phy/3.sim "run-phy.sh equiv"  'RESULT: PASSED'
bench dll-phy ../2.rtl/4.dll/sim   "run-dll-phy.sh"    'TEST PASSED'
bench tl      ../2.rtl/5.tlp/sim   "run-tl.sh"         'TEST PASSED'

echo "regression: $fails unexpected"
[ $fails = 0 ]
