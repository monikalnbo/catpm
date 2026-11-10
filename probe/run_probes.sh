#!/bin/bash
# Re-run all syntax/capability probes and capture evidence to logs/syntax-probe.log
WS=/root/.hermes-web-ui/.ekko/workspace/default/person-main-f5f99dc5-b73a-417a-baf6-5b3f41382e6c
CATCC=$WS/catbase/bin/catcc
LOG=$WS/logs/syntax-probe.log
exec > >(tee "$LOG") 2>&1
echo "==============================================================="
echo " CatBase v0.1.8 syntax & stdlib probe log"
echo " date: $(date -u '+%Y-%m-%d %H:%M:%SZ')  host: $(uname -srm)"
echo " catcc: $CATCC -> $($CATCC --version)"
echo " zig backend: $($WS/tools/zigx/zig version)"
echo "==============================================================="
run() {  # run <name> <src> [args...]
  local name=$1; local src=$2; shift 2
  echo ""
  echo "### PROBE $name : $src"
  t0=$(date +%s.%N)
  $CATCC "$src" -o "$WS/probe/bin_$name" 2>&1 || { echo "    COMPILE FAILED"; return; }
  t1=$(date +%s.%N)
  echo "    [compile wall $(echo "$t1 $t0" | awk '{printf "%.2f", $1-$2}') s]"
  ls -la $WS/probe/bin_$name | awk '{print "    binary:", $5, "bytes"}'
  echo "    --- run output ---"
  "$WS/probe/bin_$name" "$@"
}
echo ""
echo "== SECTION A: toolchain =="
ls -la $CATCC | awk '{print "catcc size:", $5, "bytes"}'
echo ""
echo "== SECTION B: core language probes (source in probe/p1) =="
run p1  $WS/probe/p1/probe1.cat
run p7  $WS/probe/p1/probe7.cat
run p8  $WS/probe/p1/probe8.cat
run p9  $WS/probe/p1/probe9.cat
run p10 $WS/probe/p1/probe10.cat
run p11 $WS/probe/p1/probe11.cat
run p12 $WS/probe/p1/probe12.cat
run p13 $WS/probe/p1/probe13.cat
run p15 $WS/probe/p1/probe15.cat
run p17 $WS/probe/p1/probe17.cat
run stress1 $WS/probe/p1/stress1.cat
echo ""
echo "== SECTION C: import / multi-file organization =="
run p2 $WS/probe/p1/probe2.cat          # relative import subdir
run p3 $WS/probe/p1/probe3.cat          # transitive nested import
run p14 $WS/probe/p14/main.cat          # .catc module import
run p5 $WS/probe/p5/proj/main.cat       # vendored deps layout + ../ cross-import
run p6 $WS/probe/p6/proj/main3.cat      # diamond: shared dep, same alias everywhere
run p18 $WS/probe/p18/main.cat          # diamond same-alias OK (a/b share s1)
run p19 $WS/probe/p1/probe19.cat        # global catbase packages/ import
echo ""
echo "== SECTION D: negative results (compile failures, kept as evidence) =="
echo "--- D1: multiple .cat files in one catcc call ---"
$CATCC $WS/probe/p1/multi_a.cat $WS/probe/p1/multi_b.cat -o /tmp/multi 2>&1 | head -3
echo "--- D2: elif keyword ---"
printf 'def main() {\n    if 1 == 2 {\n        print("a")\n    } elif 1 == 1 {\n        print("b")\n    }\n}\n' > /tmp/elif.cat
$CATCC /tmp/elif.cat -o /tmp/elif 2>&1 | grep -m1 "Problem"
echo "--- D3: str < str comparison ---"
printf 'def main() {\n    print("a" < "b")\n}\n' > /tmp/strcmp.cat
$CATCC /tmp/strcmp.cat -o /tmp/strcmp 2>&1 | grep -m1 "Error"
echo "--- D4: str * int repeat ---"
printf 'def main() {\n    s: str = "=" * 10\n    print(s)\n}\n' > /tmp/strep.cat
$CATCC /tmp/strep.cat -o /tmp/strep 2>&1 | grep -m1 "Cannot perform"
echo "--- D5: float from str ---"
printf 'def main() {\n    f: float = float("3.5")\n    print(f)\n}\n' > /tmp/fstr.cat
$CATCC /tmp/fstr.cat -o /tmp/fstr 2>&1 | grep -m1 "expected"
echo "--- D6: import same file under two different aliases ---"
mkdir -p /tmp/d6/deps
printf 'SH: str = "s"\ndef sh() -> str { return "sh" }\n' > /tmp/d6/deps/shared.catc
printf 'import ./shared.catc as s1\ndef a_use() -> str { return "a:" + s1.sh() }\n' > /tmp/d6/deps/a.catc
printf 'import ./shared.catc as s2\ndef b_use() -> str { return "b:" + s2.sh() }\n' > /tmp/d6/deps/b.catc
printf 'import ./deps/a.catc as aa\nimport ./deps/b.catc as bb\ndef main() { print(aa.a_use(), bb.b_use()) }\n' > /tmp/d6/main.cat
$CATCC /tmp/d6/main.cat -o /tmp/d6/app 2>&1 | grep -m1 "Cannot perform"
echo "--- D7: list[str].remove (broken codegen) ---"
printf 'def main() {\n    xs: list[str] = ["a","b"]\n    xs.remove("a")\n    print(len(xs))\n}\n' > /tmp/lrm.cat
$CATCC /tmp/lrm.cat -o /tmp/lrm 2>&1 | grep -m1 "expected type"
echo "--- D8: function named like Zig primitive (f16) ---"
printf 'def f16(x: int) -> int { return x }\ndef main() { print(f16(1)) }\n' > /tmp/zp.cat
$CATCC /tmp/zp.cat -o /tmp/zp 2>&1 | grep -m1 "shadows"
echo "--- D9: pop() builtin absent ---"
printf 'def main() {\n    xs: list[int] = [1,2]\n    print(pop(xs))\n}\n' > /tmp/pop.cat
$CATCC /tmp/pop.cat -o /tmp/pop 2>&1 | grep -m1 "undeclared identifier"
echo "--- D10: import without extension fails ---"
mkdir -p /tmp/d10/lib
printf 'X: str = "x"\n' > /tmp/d10/lib/util.catc
printf 'import ./lib/util as u\ndef main() { print(u.X) }\n' > /tmp/d10/main.cat
$CATCC /tmp/d10/main.cat -o /tmp/d10/app 2>&1 | grep -m1 "failed to import"
echo "--- D11: sorted() builtin absent ---"
printf 'def main() {\n    xs: list[int] = [2,1]\n    print(sorted(xs))\n}\n' > /tmp/sort.cat
$CATCC /tmp/sort.cat -o /tmp/sort 2>&1 | grep -m1 "undefined function"
echo "--- D12: delete_file on a directory is a no-op ---"
echo "    (see probe p12 output above: isdir stayed True after delete_file)"
echo ""
echo "== SECTION E: misc file/IO semantics =="
run p20 $WS/probe/p20/probe20.cat
run p21 $WS/probe/p20/probe21.cat
cmp /tmp/cpm_bin_src.bin /tmp/cpm_bin_dst.bin && echo "    binary roundtrip via str read/write: IDENTICAL" || echo "    binary roundtrip: DIFFERS"
echo ""
echo "END OF PROBE LOG"
