#!/bin/bash
# ============================================================
# e2e_v2.sh — catpm v0.2 full ecosystem walkthrough:
#   pack x4 -> publish to registry2 -> local-dir install with
#   specifiers (^ ~ >= exact, cache, sha256) -> compile+run demo2
#   -> REAL remote install from GitHub raw URL -> compile+run
# Everything captured to logs/build2.log + logs/run2.log.
# ============================================================
WS=/root/.hermes-web-ui/.ekko/workspace/default/person-main-f5f99dc5-b73a-417a-baf6-5b3f41382e6c
CATCC=$WS/catbase/bin/catcc
CPM=$WS/catpm/catpm2
LOGD=$WS/logs
RAW=https://raw.githubusercontent.com/monikalnbo/catpm/main/registry
mkdir -p $LOGD

step() { echo ""; echo "=================================================="; echo "== $*"; echo "=================================================="; }

{
step "BUILD LOG v2 — catpm 0.2.0 $(date -u '+%Y-%m-%d %H:%M:%SZ')"
echo "catcc: $($CATCC --version)   zig: $($WS/tools/zigx/zig version)"
echo ""
step "[1/3] version engine unit tests (ver.catc, 29 assertions)"
echo "\$ catcc catpm/src2/test_ver.cat -o /tmp/test_ver"
( cd $WS/catbase && ./bin/catcc $WS/catpm/src2/test_ver.cat -o /tmp/test_ver 2>&1 | tail -1 )
/tmp/test_ver; echo "exit=$?"
echo ""
step "[2/3] compile catpm v0.2 -> native binary"
echo "\$ catcc catpm/src2/catpm.cat -o catpm/catpm2"
t0=$(date +%s.%N)
( cd $WS/catbase && ./bin/catcc $WS/catpm/src2/catpm.cat -o $WS/catpm/catpm2 2>&1 | tail -1 )
rc=$?
t1=$(date +%s.%N)
echo "compile exit=$rc  wall=$(echo "$t1 $t0" | awk '{printf "%.2f", $1-$2}') s"
echo ""
step "[3/3] artifacts"
ls -la $CPM | awk '{print "catpm2 binary:", $5, "bytes"}'
file $CPM | sed 's/^/file(1): /'
$CPM --version
} > $LOGD/build2.log 2>&1

{
step "RUN LOG v2 — catpm ecosystem demo $(date -u '+%Y-%m-%d %H:%M:%SZ')"

step "[1/8] pack all packages from pkgsrc/"
for d in stringx mathx mathx3 fmtx; do
  echo "\$ (cd pkgsrc/$d && catpm pack)"
  ( cd $WS/pkgsrc/$d && $CPM pack ); echo "exit=$?"
done

step "[2/8] publish into fresh registry2/"
rm -rf $WS/registry2 && mkdir -p $WS/registry2
for d in stringx mathx mathx3 fmtx; do
  echo "\$ (cd pkgsrc/$d && catpm publish ../registry2)"   # abs path below
  ( cd $WS/pkgsrc/$d && $CPM publish $WS/registry2 ) >/dev/null; echo "exit=$? $d"
done
echo "--- registry2/index.json ---"
cat $WS/registry2/index.json

export CATPM_REGISTRY=$WS/registry2
step "[3/8] fresh project: add with ^0.2.0 (must pin 0.2.0, not 0.3.0)"
rm -rf $WS/demo2 && mkdir -p $WS/demo2 && cd $WS/demo2
$CPM init
$CPM add 'mathx@^0.2.0'; echo "exit=$?"
cat > main.cat <<'SRC'
# demo2: v0.2 flow — packs published to registry2, installed via catpm2
import ./deps/mathx/index.catc as mathx
import ./deps/fmtx/index.catc as fmtx
import ./deps/stringx/index.catc as stringx

def main() {
    print("== catpm v0.2 spec-resolved demo ==")
    print("mathx pinned by ^0.2.0 -> ", mathx.MATHX_VERSION, " fib(10)=", mathx.fib(10))
    print("transitive: mathx.loud_double(21) = ", mathx.loud_double(21))
    print("diamond: fmtx.banner('catpm') = ", fmtx.banner("catpm"))
    print("stringx.reverse('pack') = ", stringx.reverse("pack"))
}
SRC

step "[4/8] add fmtx (diamond via stringx) + list + lock"
$CPM add fmtx; echo "exit=$?"
$CPM list
echo "--- catpm.lock ---"; cat catpm.lock
echo "--- catpm.json ---"; cat catpm.json

step "[5/8] specifier re-check: fresh dir, ~0.2.0 and >=0.3"
rm -rf $WS/demo_spec && mkdir -p $WS/demo_spec && cd $WS/demo_spec
$CPM init >/dev/null
echo "\$ catpm add 'mathx@~0.2.0'"
$CPM add 'mathx@~0.2.0' 2>&1 | head -4
echo "\$ catpm add 'mathx@>=0.3' (in another fresh dir)"
rm -rf $WS/demo_spec2 && mkdir -p $WS/demo_spec2 && cd $WS/demo_spec2
$CPM init >/dev/null
$CPM add 'mathx@>=0.3' 2>&1 | head -4
echo "\$ catpm add 'mathx@^9.0.0' (unsatisfiable -> must fail rc=1)"
$CPM remove mathx >/dev/null 2>&1
$CPM add 'mathx@^9.0.0'; echo "exit=$? (expect 1)"

step "[6/8] compile + run demo2 (local source, ^-pinned)"
cd $WS/demo2
echo "\$ catcc main.cat -o app"
( cd $WS/catbase && ./bin/catcc $WS/demo2/main.cat -o $WS/demo2/app 2>&1 | tail -1 )
ls -la app | awk '{print "app:", $5, "bytes"}'
echo "\$ ./app"
./app; echo "exit=$?"

step "[7/8] REAL REMOTE install from GitHub raw URL"
echo "CATPM_REGISTRY=$RAW"
rm -rf $WS/demo_remote && mkdir -p $WS/demo_remote && cd $WS/demo_remote
CATPM_REGISTRY=$RAW $CPM init
CATPM_REGISTRY=$RAW $CPM add 'mathx@^0.2.0'; echo "exit=$?"
echo "--- lock ---"; cat catpm.lock
echo "--- cache ---"; find .catpm-cache -type f | sort

step "[8/8] compile + run remote-installed app"
cat > main.cat <<'SRC'
import ./deps/mathx/index.catc as mathx
import ./deps/stringx/index.catc as stringx

def main() {
    print("== remote-source install demo ==")
    print("mathx ", mathx.MATHX_VERSION, " fib(10)=", mathx.fib(10), " gcd(48,36)=", mathx.gcd(48,36))
    print("transitive stringx.reverse('tar') = ", stringx.reverse("tar"))
}
SRC
echo "\$ catcc main.cat -o app"
( cd $WS/catbase && ./bin/catcc $WS/demo_remote/main.cat -o $WS/demo_remote/app 2>&1 | tail -1 )
echo "\$ ./app"
./app; echo "exit=$?"
echo ""
echo "END OF RUN LOG v2"
} > $LOGD/run2.log 2>&1

echo "wrote $LOGD/build2.log and $LOGD/run2.log"
