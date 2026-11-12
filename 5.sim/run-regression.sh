#!/bin/bash
# SPDX-FileCopyrightText: 2026 Chili.CHIPS
#
# SPDX-License-Identifier: BSD-3-Clause
#
# Regression, before a push (README.md, Sanity and regression): about 8
# minutes. 100 random seeds, Verilator against Icarus on the serial line, our
# EP against the tester and with the real PHY, and the block benches of the
# PHY, the DLL and the TL. The EP DMA stage runs on the EP model only (DMA=1
# in the seeds); our EP has no DMA (#41).
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
    [rtl-tester]="#24 #26 #38 #40 #42"
    [rtl-serial]="#38"
    [dll-stp]="#24"
    [dll-end]="#24"
)
# ... and what the log of each must show: another failure is not the known one
declare -A KNOWN_SIG=(
    [rtl-tester]="still in RcvrLock at Gen1"   # #42; SVA #24 comes before it
    [rtl-serial]="SVA #38"
    [dll-stp]="stp corrupted: EP did not replay"
    [dll-end]="end corrupted: EP did not replay"
)

other_assert() {  # name: the first design assertion that is not an SVA of its
    local re      # known issues (the bench's own ends are KNOWN_SIG's business)
    re=$(echo "${KNOWN[$1]}" | sed 's/#\([0-9]*\)/SVA #\1:/g; s/ /|/g')
    grep -a 'Assertion failed in tb\.dut' $LOG/$1.log | grep -a -v -E "\*\*\*\* ($re)" | head -1 | sed -E 's/^\[[0-9]+\] //' | cut -c1-100
}

report() {  # name, seconds, pass (0/1), what, result
    local n=$1 t=$2 ok=$3 what=$4 r=$5 st
    if [ -n "${KNOWN[$n]:-}" ]; then
        if [ $ok = 1 ]; then st="PASS, known ${KNOWN[$n]}: update KNOWN"; fails=$((fails + 1))
        elif ! grep -a -q -F "${KNOWN_SIG[$n]}" $LOG/$n.log; then
            st="FAIL, not as known ${KNOWN[$n]}: no \"${KNOWN_SIG[$n]}\""; fails=$((fails + 1))
        elif other=$(other_assert $n) && [ -n "$other" ]; then
            st="FAIL, not as known ${KNOWN[$n]}: $other"; fails=$((fails + 1))
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
make regress SEEDS=100 REGRESS_JOBS=8 DMA=1 "$@" > $LOG/regress.log 2>&1
r=$(tail -1 $LOG/regress.log)
case "$r" in "0 of "*) ok=1;; *) ok=0;; esac
report regress $((SECONDS - t0)) $ok "make regress SEEDS=100 REGRESS_JOBS=8 DMA=1" "$r; $(tail -2 $LOG/regress.log | head -1)"

run serial         IFACE=serial "$@"
run serial-icarus  SIM=icarus IFACE=serial "$@"
if diff -q <(grep -a '===>' $LOG/serial.log) <(grep -a '===>' $LOG/serial-icarus.log) > /dev/null; then
    report sim-match 0 1 "Verilator = Icarus, serial" "the same ===> lines"
else
    report sim-match 0 0 "Verilator = Icarus, serial" "diff the ===> lines of serial.log and serial-icarus.log"
fi
# SVA #24 stops the run at 2.86 ms; going on, it reaches the TL issues, then
# hangs from the first Recovery (#42) to the 10 ms limit
run rtl-tester     EP=rtl SIM_ARGS=+verilator+error+limit+100 "$@"
run rtl-serial     EP=rtl IFACE=serial A7RC=1 "$@"

bench pipe64  ../2.rtl/1.phy/3.sim "run-phy.sh pipe64" '^ ####    ###    ####  ####  #####  ####'  # the PASSED banner
bench equiv   ../2.rtl/1.phy/3.sim "run-phy.sh equiv"  'RESULT: PASSED'
bench dll-phy ../2.rtl/4.dll/sim   "run-dll-phy.sh"    'TEST PASSED'
bench dll-stp ../2.rtl/4.dll/sim   "run-dll-phy.sh --inject=stp" 'TEST PASSED'
bench dll-end ../2.rtl/4.dll/sim   "run-dll-phy.sh --inject=end" 'TEST PASSED'
bench tl      ../2.rtl/5.tlp/sim   "run-tl.sh"         'TEST PASSED'

echo "regression: $fails unexpected"
[ $fails = 0 ]
