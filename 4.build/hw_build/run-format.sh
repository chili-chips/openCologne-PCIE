#!/bin/bash
# SPDX-FileCopyrightText: 2026 Chili.CHIPS
#
# SPDX-License-Identifier: BSD-3-Clause
#
# Format the RTL (own_rtl in sources.sh, the PIPE, MAC and DLL) in the project style:
#   0. no CR (^M) or TAB in any HDL file under 2.rtl, Cologne Chip's code included;
#   1. every if, else, always, for, foreach, while, forever and initial body is
#      a begin ... end block, also when it is a single statement (the statement
#      positions come from the verible-verilog-syntax tree);
#   1b. every packed-struct member carries its bit slice as a comment;
#   2. verible-verilog-format: Verible defaults (100-column limit) plus every
#      alignment option set to align, end and else on separate lines, LF line
#      endings. It does not wrap lines over the limit: wrap those by hand;
#   2b. an assignment that does not fit on one line: one operand per line, the
#      operator first, under the '=' (run-format-wrap.py; Verible cannot);
#   2c. at least one space before the '(' of a named parameter or port
#      connection: .NAME (signal) (run-format-conn.py; Verible puts the '('
#      against the longest name of a block);
#   2d. a logic declaration next to the assign that drives it: in a block of
#      adjacent logic and assign lines the names share a column, and so do
#      the '=' (run-format-align.py);
#   2e. a module's port list is one alignment: the direction, type,
#      dimension, name and comment columns are the same in every group of
#      ports (run-format-align.py; Verible aligns each group on its own);
#   3. no ?: in a port connection (reported, not fixed), PIPE/MAC/DLL included;
#   4. && and || only in an if/while/for condition, & and | for bits elsewhere
#      (reported, not fixed: run-format-ops.py --fix, then prove it with LEQ).
#
# usage:  bash run-format.sh            format every RTL file in place
#         bash run-format.sh --check    only report the files that are not
#                                       formatted; exit 1 if there are any
#
# Needs python3 and Verible (VERIBLE_FORMAT, VERIBLE_SYNTAX, VERIBLE_LINT can
# override the commands). Generated code (the PeakRDL csr.sv / csr_pkg.sv in
# 4.build/csr_build) is left as the generator writes it; eduBOS5 is formatted
# on openPCIE.

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
RTL=$HERE/../../2.rtl
. "$HERE/sources.sh"
VERIBLE_FORMAT=${VERIBLE_FORMAT:-verible-verilog-format}
VERIBLE_SYNTAX=${VERIBLE_SYNTAX:-verible-verilog-syntax}
VERIBLE_LINT=${VERIBLE_LINT:-verible-verilog-lint}

STYLE=(
  --line_terminator=LF
  --column_limit=100
  --assignment_statement_alignment=align
  --case_items_alignment=align
  --distribution_items_alignment=align
  --enum_assignment_statement_alignment=align
  --formal_parameters_alignment=align
  --module_net_variable_alignment=align
  --named_parameter_alignment=align
  --named_port_alignment=align
  --parameter_declaration_alignment=align
  --port_declarations_alignment=align
  --struct_union_members_alignment=align
  --wrap_end_else_clauses=true
)

for t in python3 "$VERIBLE_FORMAT" "$VERIBLE_SYNTAX" "$VERIBLE_LINT"; do
  command -v "$t" >/dev/null || { echo "run-format: $t not found" >&2; exit 2; }
done

MODE=format
[ "${1:-}" = "--check" ] && MODE=check

# Step 1: begin ... end around single-statement bodies. The syntax tree leaves
# out code under an undefined `ifdef, so a file is parsed as is, with all its
# `ifdef/`ifndef/`elsif macros defined, and once per macro with only that one
# defined (a `define put in front). --count only reports the number of bodies.
explicit_begin() {
  VERIBLE_SYNTAX="$VERIBLE_SYNTAX" python3 - "$@" <<'PY'
import json, os, re, subprocess, sys, tempfile

LOOPS = ('kForLoopStatement', 'kWhileLoopStatement', 'kForeachLoopStatement',
         'kForeverLoopStatement', 'kInitialStatement')

def leaves(n):
    if 'children' in n:
        for c in n['children']:
            if c is not None: yield from leaves(c)
    elif 'start' in n:
        yield n

def span(n):
    ls = list(leaves(n)); return ls[0]['start'], ls[-1]['end']

def bodies(n, parent, out):
    t, ks = n.get('tag'), [c for c in n.get('children', []) if c is not None]
    b = ks[-1] if ks else None
    if b is not None and b.get('tag') != 'kSeqBlock':
        if t == 'kIfBody' or (t == 'kElseBody' and b.get('tag') != 'kConditionalStatement') \
           or (t == 'kProceduralTimingControlStatement' and parent == 'kAlwaysStatement') \
           or (t in LOOPS and b.get('tag') != 'kGenerateBlock'):
            out.add(span(b))
    for c in ks:
        bodies(c, t, out)

def parse(data):
    with tempfile.NamedTemporaryFile(suffix='.sv', delete=False) as f:
        f.write(data)
    try:
        r = subprocess.run([os.environ['VERIBLE_SYNTAX'], '--export_json', '--printtree', f.name],
                           capture_output=True, text=True)
        tree = list(json.loads(r.stdout).values())[0].get('tree')
    finally:
        os.unlink(f.name)
    out = set()
    if tree: bodies(tree, None, out)
    return out

def views(data):
    """the file as is, all macros defined, each macro defined alone: (text, prefix length)"""
    names = sorted(set(re.findall(rb'`(?:ifn?def|elsif)\s+(\w+)', data)))
    sets = [[]] + ([names] if len(names) > 1 else []) + [[n] for n in names]
    for ns in sets:
        pre = b''.join(b'`define ' + n + b'\n' for n in ns)
        yield pre + data, len(pre)

count_only = sys.argv[1] == '--count'
total = 0
for path in sys.argv[2:]:
    data = open(path, 'rb').read()
    spans = set()
    for text, n in views(data):
        spans |= {(a - n, e - n) for a, e in parse(text) if a >= n}
    total += len(spans)
    if count_only or not spans:
        if spans: print('needs begin/end: %d body(ies) in %s' % (len(spans), os.path.basename(path)))
        continue
    ins = []
    for a, e in spans:
        ins.append((a, b'begin '))
        m = re.match(rb'[ \t]*//[^\n]*', data[e:])      # keep a trailing comment on its statement
        ins.append((e + m.end(), b'\nend') if m else (e, b' end'))
    for p, txt in sorted(ins, key=lambda x: x[0], reverse=True):
        data = data[:p] + txt + data[p:]
    open(path, 'wb').write(data)
print('-- explicit-begin: %d body(ies) %s' % (total, 'without begin/end' if count_only else 'wrapped'))
sys.exit(1 if count_only and total else 0)
PY
}

# Every packed-struct member carries its bit slice as a comment, for debugging:
#   logic [7:0] tag;  // [15:8] ...
# The slices are computed from the declarations (logic dims, typedefs, enums,
# nested structs, constants of the packages and of the file), from the top bit
# down, so they are contiguous. --check: report missing, wrong or gapped slices;
# --apply: write them. A wrong one is reported in both modes.
bit_slices() {
  python3 - "$@" <<'PY'
import re, sys
mode, files = sys.argv[1], sys.argv[2:]
check = mode == '--check'
BASE = {'logic': 1, 'bit': 1, 'int': 32, 'integer': 32, 'byte': 8, 'shortint': 16, 'longint': 64}
MEMBER = re.compile(r'^\s*((?:\w+::)?\w+)\s*((?:\[[^\]]*\]\s*)*)(\w+)\s*;', re.M)
STRUCT = re.compile(r'typedef\s+(struct|union)\s+packed\s*\{(.*?)\}\s*\w+\s*;', re.S)

def ev(e, c):
    e = re.sub(r"\b\w+::", '', e)
    e = re.sub(r"\$clog2\(([^)]*)\)", lambda m: str((ev(m.group(1), c) - 1).bit_length()), e)
    e = re.sub(r"\b\d+'[dD](\d+)", r'\1', e)
    for k in sorted(c, key=len, reverse=True):
        e = re.sub(rf'\b{k}\b', str(c[k]), e)
    return int(eval(e.replace('/', '//'), {}))

def dims_w(d, c):
    w = 1
    for hi, lo in re.findall(r'\[([^:\]]+):([^\]]+)\]', d):
        w *= abs(ev(hi, c) - ev(lo, c)) + 1
    for n in re.findall(r'\[([^:\]]+)\]', d):  # [N]: N elements
        w *= ev(n, c)
    return w

def type_w(t, w):
    return w[re.sub(r'^\w+::', '', t)]

def collect(code, c, w):
    for _ in range(4):  # until nested definitions settle
        for n, v in re.findall(r'(?:localparam|parameter)\s+(?:int(?:\s+unsigned)?|integer|'
                               r'logic\s*(?:\[[^\]]*\])?)?\s*(\w+)\s*=\s*([^;,)]+)', code):
            try: c[n] = ev(v, c)
            except Exception: pass
        for _, d, n in re.findall(r'typedef\s+(logic|bit)\s*((?:\[[^\]]*\]\s*)*)(\w+)\s*;', code):
            try: w[n] = dims_w(d, c)
            except Exception: pass
        for d, n in re.findall(r'typedef\s+enum\s+(?:logic|bit)\s*((?:\[[^\]]*\]\s*)*)\{[^}]*\}\s*(\w+)\s*;', code):
            try: w[n] = dims_w(d, c)
            except Exception: pass
        for kind, body, n in re.findall(r'typedef\s+(struct|union)\s+packed\s*\{(.*?)\}\s*(\w+)\s*;', code, re.S):
            try:
                ws = [type_w(t, w) * dims_w(d, c) for t, d, _ in MEMBER.findall(body)]
                w[n] = sum(ws) if kind == 'struct' else max(ws)  # union: every member is as wide
            except Exception: pass

nocomment = lambda s: re.sub(r'//[^\n]*', '', s)
pc, pw = {}, dict(BASE)
for p in [f for f in files if f.endswith('_pkg.sv')]:
    collect(nocomment(open(p).read()), pc, pw)

todo = bad = 0
for f in files:
    s = open(f).read()
    if not STRUCT.search(s):
        continue
    c, w = dict(pc), dict(pw)
    collect(nocomment(s), c, w)
    rel = re.sub(r'^.*/2\.rtl/', '', f)

    def struct(m):
        global todo, bad
        union = m.group(1) == 'union'
        lines = m.group(2).split('\n')
        mem = [i for i, l in enumerate(lines) if MEMBER.match(l)]
        sizes = [type_w(MEMBER.match(lines[i]).group(1), w) * dims_w(MEMBER.match(lines[i]).group(2), c)
                 for i in mem]
        if union and len(set(sizes)) > 1:
            bad += 1
            print(f'bit slice: {rel}: union members of different widths {sizes}')
        top = (max(sizes) if union else sum(sizes)) - 1
        hi = top
        pad = len(f'[{hi}:0]')  # the widest slice: descriptions line up
        col = max(len(lines[i].partition('//')[0].rstrip()) for i in mem)
        for i, sz in zip(mem, sizes):
            sl = f'[{hi}]' if sz == 1 else f'[{hi}:{hi - sz + 1}]'
            hi = top if union else hi - sz  # a union's members all start at the top
            code, _, cmt = lines[i].partition('//')
            cmt = cmt.strip()
            old = re.match(r'^\[(\d+)(?::(\d+))?\]\s*', cmt)
            if old:
                if old.group(0).strip() != sl:
                    bad += 1
                    print(f'wrong bit slice: {rel}: {code.strip()} {old.group(0).strip()}, is {sl}')
                cmt = cmt[old.end():]
            elif check:
                print(f'no bit slice: {rel}: {code.strip()} {sl}')
            new = f'{code.rstrip():<{col}}  // {sl}' + (f' {" " * (pad - len(sl))}{cmt}' if cmt else '')
            if old is None:
                todo += 1
            lines[i] = new
        return m.group(0).replace(m.group(2), '\n'.join(lines))

    try:
        s2 = STRUCT.sub(struct, s)
    except KeyError as e:
        bad += 1; print(f'bit slice: {rel}: unknown type {e}'); continue
    if not check and s2 != s:
        open(f, 'w').write(s2)
if check:
    print(f'-- bit slices: {todo} missing, {bad} wrong')
else:
    print(f'-- bit slices: {todo} added, {bad} wrong')
sys.exit(1 if bad or (check and todo) else 0)
PY
}

# Ours, the DLL, and Cologne Chip's PIPE and MAC (still theirs, refined here)
FILES=($(own_rtl "$RTL") $(ls "$RTL"/2.pipe/*.sv "$RTL"/3.mac/*.sv "$RTL"/4.dll/*.sv |
  grep -v -E '_(if|pkg)\.sv'))
bad=0

# Step 0: CR (^M) and TABs in any HDL file under 2.rtl, Cologne Chip's code
# included: reported with --check, otherwise removed (TABs: 4 spaces)
HDL=($(find "$RTL" \( -name '*.sv' -o -name '*.v' -o -name '*.svh' -o -name '*.vh' \) -not -path '*/obj/*'))
CR_FILES=($(grep -l $'\r' "${HDL[@]}"))
TAB_FILES=($(grep -l $'\t' "${HDL[@]}"))
for f in "${CR_FILES[@]}"; do
  if [ $MODE = check ]; then echo "CR line endings: ${f#$RTL/}"; else sed -i 's/\r//g' "$f"; fi
done
for f in "${TAB_FILES[@]}"; do
  if [ $MODE = check ]; then echo "TABs: ${f#$RTL/}"; else expand -t 4 "$f" > "$f.tmp" && mv "$f.tmp" "$f"; fi
done
ncr=$(( ${#CR_FILES[@]} + ${#TAB_FILES[@]} ))
if [ $MODE = check ]; then
  echo "-- CR, TAB: ${#CR_FILES[@]} file(s) with CR, ${#TAB_FILES[@]} with TABs"
else
  echo "-- CR, TAB: removed from ${#CR_FILES[@]} and ${#TAB_FILES[@]} file(s)"; ncr=0
fi

if [ $MODE = check ]; then
  explicit_begin --count "${FILES[@]}" || bad=$((bad + 1))
else
  explicit_begin --apply "${FILES[@]}" || bad=$((bad + 1))
fi

# Step 1b: struct bit slices (before the formatter, which aligns them)
if [ $MODE = check ]; then
  bit_slices --check "${FILES[@]}"; nb=$?
else
  bit_slices --apply "${FILES[@]}"; nb=$?
fi

# Step 2: verible-verilog-format. It can exit 0 on a file it cannot parse, so a
# message on stderr also counts as a failure.
nf=0
for f in "${FILES[@]}"; do
  if [ $MODE = check ]; then
    # what steps 2, 2b and 2c would make of it, compared with the file
    tmp=$(mktemp --suffix=.sv)
    err=$("$VERIBLE_FORMAT" "${STYLE[@]}" "$f" 2>&1 >"$tmp"); rc=$?
    [ $rc -eq 0 ] && [ -z "$err" ] && python3 "$HERE/run-format-wrap.py" "$tmp" &&
      python3 "$HERE/run-format-conn.py" "$tmp" &&
      python3 "$HERE/run-format-align.py" "$tmp" && cmp -s "$f" "$tmp"
    if [ $? -ne 0 ]; then echo "not formatted: ${f#$RTL/}"; nf=$((nf + 1)); fi
    rm -f "$tmp"
  else
    err=$("$VERIBLE_FORMAT" "${STYLE[@]}" --inplace "$f" 2>&1); rc=$?
    if [ $rc -ne 0 ] || [ -n "$err" ]; then echo "failed: ${f#$RTL/}: $(echo "$err" | head -1)" >&2; nf=$((nf + 1)); fi
    python3 "$HERE/run-format-wrap.py" "$f"
    python3 "$HERE/run-format-conn.py" "$f"
    python3 "$HERE/run-format-align.py" "$f"
  fi
done

# Cross-check with the Verible lint rule for the same thing
lint_out=$("$VERIBLE_LINT" --ruleset=none --rules=explicit-begin "${FILES[@]}" 2>&1); lrc=$?
nl=$(printf '%s\n' "$lint_out" | grep -c 'explicit-begin')
# exit 0: clean, 1: findings; anything else, or 1 with nothing found, is the
# tool failing (a syntax error, a bad option), never "0 findings"
lint_failed=0
if [ $lrc -gt 1 ] || { [ $lrc -eq 1 ] && [ $nl -eq 0 ]; }; then lint_failed=1; bad=$((bad + 1)); fi

if [ $MODE = check ]; then
  echo "-- verible-format: $nf file(s) not formatted"
else
  echo "-- verible-format: done, $nf failure(s)"
fi
if [ $lint_failed -eq 1 ]; then
  echo "-- verible-lint explicit-begin: FAILED (exit $lrc): $(printf '%s\n' "$lint_out" | head -1)"
else
  echo "-- verible-lint explicit-begin: $nl finding(s)"
fi

# Lines over the 100-column limit (the formatter leaves them as they are)
awk 'length > 100 { sub(".*/2.rtl/", "", FILENAME); print "over 100 columns: " FILENAME ":" FNR }' "${FILES[@]}"
nc=$(awk 'length > 100' "${FILES[@]}" | wc -l)
echo "-- line length: $nc line(s) over 100 columns"

# An expression in a port connection: give it a signal and a continuous assign
# instead (as VHDL port maps require; Icarus 14 also gets a package constant
# in one wrong, steveicarus/iverilog#1699; a package constant alone on a
# port reads z too, so an ALL_CAPS name the file does not declare is
# reported). A port takes a signal, an
# interface member, a literal, a concatenation of those, or a bit/part-select
# of one (the index may be an expression). Parameter overrides #( ... ) are
# constants and not checked. Reported in both modes; the fix needs a name,
# so it is not automatic.
PORT_FILES=("${FILES[@]}")
port_out=$(RTL="$RTL" perl -e '
  sub close_of { my ($s, $i) = @_; my $d = 1;
    $d += (substr($s, $i, 1) eq "(") - (substr($s, $i, 1) eq ")"), $i++ while $d && $i < length $s; $i }
  for my $f (@ARGV) {
    open my $h, "<", $f or next; my $s = do { local $/; <$h> };
    $s =~ s{//[^\n]*}{}g; $s =~ s{/\*.*?\*/}{ my $c = $&; $c =~ s/[^\n]//g; $c }gse;
    my @skip;   # parameter overrides: #( ... )
    while ($s =~ /#\s*\(/g) { push @skip, [pos($s), close_of($s, pos $s)] }
    while ($s =~ /\.\w+\s*\(/g) {
      my ($start, $i) = ($-[0], close_of($s, pos $s));
      next if grep { $start > $_->[0] && $start < $_->[1] } @skip;
      my $e = substr($s, pos($s), $i - 1 - pos($s));
      1 while $e =~ s/\[[^\[\]]*\]//g;              # selects, nested ones too
      $e =~ s/\s+//g;
      my $line = 1 + (substr($s, 0, $start) =~ tr/\n//);
      (my $r = $f) =~ s{^\Q$ENV{RTL}\E/}{};
      if ($e =~ /^[A-Z][A-Z0-9_]*$/) {
        next if $s =~ /\b(localparam|parameter)\b[^;]*\b\Q$e\E\b/ || $s =~ /\w\s+\Q$e\E\s*[;,=\[)]/;
        print "package constant in a port connection: $r:$line\n"; next;
      }
      next if $e =~ /^(\{)?([\w.\$\x27]+(,[\w.\$\x27]+)*)?(\})?$/;
      print "expression in a port connection: $r:$line\n";
    }
  }' "${PORT_FILES[@]}")
[ -n "$port_out" ] && printf '%s\n' "$port_out"
np=$(printf '%s' "$port_out" | grep -c 'port connection')
echo "-- port connections: $np with an expression"
# && / || outside a condition
ops_out=$(python3 "$HERE/run-format-ops.py" --report "${FILES[@]}" | sed "s#$RTL/##")
[ -n "$ops_out" ] && printf '%s\n' "$ops_out"
no=$(printf '%s' "$ops_out" | grep -c 'outside if')
echo "-- logic ops: $no && or || outside a condition"
[ $no -eq 0 ] && [ $bad -eq 0 ] && [ $ncr -eq 0 ] && [ $nb -eq 0 ] && [ $nf -eq 0 ] && [ $nl -eq 0 ] && [ $nc -eq 0 ] &&
  [ $np -eq 0 ]

# -----------------------------------------------------------------------------
# Project:     openCologne-PCIE
# Description: NLnet-sponsored open-source implementation
# Version:     1.0
# Date:        Oct 18, 2026
# -----------------------------------------------------------------------------
