#!/bin/bash
# ============================================================
# e2e.sh — full end-to-end walkthrough of catpm:
#   build catpm -> fresh demo project -> init -> add (transitive,
#   diamond) -> compile app that uses the installed packages -> run
#   -> list -> remove/prune. Everything captured to build.log/run.log.
# ============================================================
WS=/root/.hermes-web-ui/.ekko/workspace/default/person-main-f5f99dc5-b73a-417a-baf6-5b3f41382e6c
CATCC=$WS/catbase/bin/catcc
CATPM_BIN=$WS/catpm/catpm
DEMO=$WS/demo
REG=$WS/registry
LOGD=$WS/logs
mkdir -p $LOGD

step() { echo ""; echo "=================================================="; echo "== $*"; echo "=================================================="; }

# ---------------- build.log: compile catpm itself ----------------
{
step "BUILD LOG — catpm $(date -u '+%Y-%m-%d %H:%M:%SZ')"
echo "catcc: $($CATCC --version)   zig: $($WS/tools/zigx/zig version)"
echo "host: $(uname -srm)"
echo ""
step "[1/2] compile catpm source -> native binary"
echo "\$ catcc catpm/src/catpm.cat -o catpm/catpm"
t0=$(date +%s.%N)
( cd $WS/catbase && ./bin/catcc $WS/catpm/src/catpm.cat -o $WS/catpm/catpm 2>&1 )
rc=$?
t1=$(date +%s.%N)
echo "compile exit=$rc  wall=$(echo "$t1 $t0" | awk '{printf "%.2f", $1-$2}') s"
echo ""
step "[2/2] artifacts"
ls -la $CATPM_BIN | awk '{print "catpm binary:", $5, "bytes"}'
file $CATPM_BIN | sed 's/^/file(1): /'
echo ""
echo "smoke: \$ catpm/catpm --version"
$CATPM_BIN --version
} > $LOGD/build.log 2>&1

# ---------------- run.log: the demo project walkthrough ----------------
{
step "RUN LOG — catpm end-to-end demo $(date -u '+%Y-%m-%d %H:%M:%SZ')"
export CATPM_REGISTRY=$REG

step "[1/7] fresh project + init"
rm -rf $DEMO
mkdir -p $DEMO
cd $DEMO
echo "\$ catpm init"
$CATPM_BIN init
echo "--- catpm.json ---"
cat catpm.json

step "[2/7] add mathx (latest) — expect transitive stringx 0.3.0"
echo "\$ catpm add mathx"
$CATPM_BIN add mathx; echo "exit=$?"

step "[3/7] add fmtx — diamond: fmtx and mathx share stringx"
echo "\$ catpm add fmtx"
$CATPM_BIN add fmtx; echo "exit=$?"

step "[4/7] list + lock + vendored tree"
echo "\$ catpm list"
$CATPM_BIN list
echo "--- catpm.lock ---"
cat catpm.lock
echo "--- catpm.json ---"
cat catpm.json
echo "--- deps/ tree ---"
find deps -type f | sort

step "[5/7] compile demo app that imports the installed packages"
cat > main.cat <<'SRC'
# demo app: mathx (direct), fmtx (direct), stringx (transitive dep of both)
# NOTE: every importer of ./deps/stringx/index.catc must use the alias
# "stringx" — catcc v0.1.8 rejects one file imported under two aliases.
import ./deps/mathx/index.catc as mathx
import ./deps/fmtx/index.catc as fmtx
import ./deps/stringx/index.catc as stringx

def main() {
    print("== catpm end-to-end demo ==")
    print("mathx version: ", mathx.MATHX_VERSION, " (", mathx.fib(10), " fib)")
    print("gcd(48,36) = ", mathx.gcd(48, 36), "  lcm(4,6) = ", mathx.lcm(4, 6), "  prime(17) = ", mathx.is_prime(17))
    print("transitive call mathx.loud_double(21) = ", mathx.loud_double(21))
    print("fmtx.banner: ", fmtx.banner("catpm"))
    print("fmtx.bracket('ok') = ", fmtx.bracket("ok"))
    print("stringx.reverse('cat') = ", stringx.reverse("cat"), "  palindrome('level') = ", stringx.is_palindrome("level"))
    w: list[str] = stringx.words("  the quick   brown fox  ")
    print("stringx.words count = ", len(w), " [1] = ", w[1])
}
SRC
echo "\$ catcc main.cat -o app"
t0=$(date +%s.%N)
( cd $WS/catbase && ./bin/catcc $DEMO/main.cat -o $DEMO/app 2>&1 )
rc=$?
t1=$(date +%s.%N)
echo "compile exit=$rc  wall=$(echo "$t1 $t0" | awk '{printf "%.2f", $1-$2}') s"
ls -la app | awk '{print "app binary:", $5, "bytes"}'

step "[6/7] run the app (uses direct + transitive deps)"
echo "\$ ./app"
./app; echo "exit=$?"

step "[7/7] remove fmtx -> prune; remove mathx -> prune all"
echo "\$ catpm remove fmtx"
$CATPM_BIN remove fmtx; echo "exit=$?"
echo "deps after: $(ls deps | tr '\n' ' ')"
echo "\$ catpm remove mathx"
$CATPM_BIN remove mathx; echo "exit=$?"
echo "deps after: $(ls deps 2>/dev/null | tr '\n' ' ') (should be empty)"
echo "--- final catpm.lock ---"
cat catpm.lock
echo ""
echo "END OF RUN LOG"
} > $LOGD/run.log 2>&1

echo "wrote $LOGD/build.log and $LOGD/run.log"
