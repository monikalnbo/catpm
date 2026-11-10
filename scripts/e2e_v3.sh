#!/bin/bash
# ============================================================
# e2e_v3.sh — catpm v0.3 package.where source-list walkthrough:
#   [1/6] default package.where (same repo as the binary) install
#   [2/6] user rewrites package.where -> different source, no code change
#   [3/6] multi-source: union versions, prio-ordered download, pkg= pinning
#   [4/6] unreachable source: warning + fallback to the remaining source
#   [5/6] error paths: bad format line, unreachable-only, prio junk
#   [6/6] compile + run an app built entirely from package.where installs
# Everything captured to logs/build3.log + logs/where3.log.
# ============================================================
WS=/root/.hermes-web-ui/.ekko/workspace/default/person-main-f5f99dc5-b73a-417a-baf6-5b3f41382e6c
CATCC=$WS/catbase/bin/catcc
CPM=$WS/catpm/catpm3
LOGD=$WS/logs
RAW=https://raw.githubusercontent.com/monikalnbo/catpm/main/registry
mkdir -p $LOGD

step() { echo ""; echo "=================================================="; echo "== $*"; echo "=================================================="; }

{
step "WHERE LOG v3 — package.where source list $(date -u '+%Y-%m-%d %H:%M:%SZ')"
echo "catpm: $($CPM --version)"
echo ""

step "[1/6] DEFAULT package.where (auto-found next to the binary)"
# the catpm3 binary lives in $WS/catpm/ ; drop package.where beside it
cat > $WS/catpm/package.where <<WHERE
# catpm source list v1 (apt sources.list style)
# <dir-or-URL> [prio=N] [pkg=name1,name2]
$WS/registry3
WHERE
echo "--- $WS/catpm/package.where ---"
cat $WS/catpm/package.where
rm -rf $WS/demo_where1 && mkdir -p $WS/demo_where1 && cd $WS/demo_where1
echo "\$ catpm sources"
$CPM sources; echo "exit=$?"
echo "\$ catpm init && catpm add loganx"
$CPM init >/dev/null
$CPM add loganx; echo "exit=$?"
echo "\$ catpm list"; $CPM list

step "[2/6] USER REWRITES package.where -> switch source, zero code change"
cat > $WS/catpm/package.where <<WHERE
# switched to the GitHub raw source by editing one line
$RAW
WHERE
echo "--- edited $WS/catpm/package.where ---"
cat $WS/catpm/package.where
rm -rf $WS/demo_where2 && mkdir -p $WS/demo_where2 && cd $WS/demo_where2
echo "\$ catpm sources"
$CPM sources; echo "exit=$?"
echo "\$ catpm init && catpm add 'mathx@^0.2.0'"
$CPM init >/dev/null
$CPM add 'mathx@^0.2.0'; echo "exit=$?"

step "[3/6] MULTI-SOURCE: union versions + prio download order + pkg= pin"
cat > $WS/catpm/package.where <<WHERE
# two local sources: registry3 is the default, mirror has mathx 0.4.0
$WS/registry3                 prio=10
$WS/registry-mirror           prio=5   pkg=mathx
$RAW                          prio=1
WHERE
echo "--- edited $WS/catpm/package.where ---"
cat $WS/catpm/package.where
echo "\$ catpm sources"
$CPM sources; echo "exit=$?"
rm -rf $WS/demo_where3 && mkdir -p $WS/demo_where3 && cd $WS/demo_where3
$CPM init >/dev/null
echo "\$ catpm add mathx   # union candidates 0.2.0/0.3.0/0.4.0 -> latest wins = 0.4.0 (from mirror)"
$CPM add mathx; echo "exit=$?"
echo "\$ catpm add loganx  # only in registry3"
$CPM add loganx; echo "exit=$?"
echo "--- catpm.lock ---"; cat catpm.lock

step "[4/6] UNREACHABLE SOURCE: warn + continue on the remaining one"
cat > $WS/catpm/package.where <<WHERE
$WS/registry3-broken           prio=9
$WS/registry3                  prio=5
WHERE
echo "--- edited $WS/catpm/package.where ---"
cat $WS/catpm/package.where
rm -rf $WS/demo_where4 && mkdir -p $WS/demo_where4 && cd $WS/demo_where4
$CPM init >/dev/null
echo "\$ catpm add loganx   # first source unreachable -> warning, second serves it"
$CPM add loganx; echo "exit=$?"

step "[5/6] ERROR PATHS: bad line, unreachable-only, junk prio"
rm -rf $WS/demo_where5 && mkdir -p $WS/demo_where5 && cd $WS/demo_where5
$CPM init >/dev/null
cat > $WS/catpm/package.where <<WHERE
no-slash-or-scheme.example/pkgs
WHERE
echo "--- package.where (bad address form) ---"; cat $WS/catpm/package.where
echo "\$ catpm add loganx"; $CPM add loganx; echo "exit=$? (expect 1)"

cat > $WS/catpm/package.where <<WHERE
$WS/registry3-gone
WHERE
echo "--- package.where (unreachable only) ---"; cat $WS/catpm/package.where
echo "\$ catpm add loganx"; $CPM add loganx; echo "exit=$? (expect 1)"

cat > $WS/catpm/package.where <<WHERE
$WS/registry3  prio=high
WHERE
echo "--- package.where (junk prio) ---"; cat $WS/catpm/package.where
echo "\$ catpm add loganx"; $CPM add loganx; echo "exit=$? (expect 1)"

cat > $WS/catpm/package.where <<WHERE
$WS/registry3  color=red
WHERE
echo "--- package.where (unknown option) ---"; cat $WS/catpm/package.where
echo "\$ catpm add loganx"; $CPM add loganx; echo "exit=$? (expect 1)"

step "[6/6] COMPILE + RUN an app built from package.where installs"
rm -rf $WS/demo_where5 && mkdir -p $WS/demo_where5 && cd $WS/demo_where5
cat > $WS/catpm/package.where <<WHERE
# final demo: mirror serves mathx (0.4.0), registry3 the rest
$WS/registry3                 prio=10
$WS/registry-mirror           prio=5   pkg=mathx
WHERE
$CPM init >/dev/null
$CPM add mathx >/dev/null
$CPM add loganx >/dev/null
cat > main.cat <<'SRC'
# demo_where5: everything installed via package.where multi-source rules
import ./deps/mathx/index.catc as mathx
import ./deps/loganx/index.catc as loganx

def main() {
    print("== catpm v0.3 package.where demo ==")
    print("mathx (mirror, pkg= pin) ", mathx.MATHX_VERSION, " fib(10)=", mathx.fib(10))
    print("mathx.collatz_steps(27) = ", mathx.collatz_steps(27))
    print("loganx.tag('multi-source') = ", loganx.tag("multi-source"))
    print("loganx.tri(10) = ", loganx.tri(10))
}
SRC
echo "\$ catcc main.cat -o app"
( cd $WS/catbase && ./bin/catcc $WS/demo_where5/main.cat -o $WS/demo_where5/app 2>&1 | tail -1 )
ls -la app | awk '{print "app:", $5, "bytes"}'
echo "\$ ./app"
./app; echo "exit=$?"

echo ""
echo "END OF WHERE LOG v3"
} > $LOGD/where3.log 2>&1

# build3.log: unit tests + compile timing
{
step "BUILD LOG v3 — catpm 0.3.0 $(date -u '+%Y-%m-%d %H:%M:%SZ')"
echo "catcc: $($CATCC --version)   zig: $($WS/tools/zigx/zig version)"
echo ""
step "[1/3] version engine unit tests (ver.catc, 29 assertions)"
( cd $WS/catbase && ./bin/catcc $WS/catpm/src2/test_ver.cat -o /tmp/test_ver3 2>&1 | tail -1 )
/tmp/test_ver3; echo "exit=$?"
echo ""
step "[2/3] catpm v0.3 -> native binary (fresh compile)"
t0=$(date +%s.%N)
( cd $WS/catbase && ./bin/catcc $WS/catpm/src2/catpm.cat -o $WS/catpm/catpm3 2>&1 | tail -1 )
t1=$(date +%s.%N)
echo "compile wall=$(echo "$t1 $t0" | awk '{printf "%.2f", $1-$2}') s"
echo ""
step "[3/3] artifacts"
ls -la $WS/catpm/catpm3 | awk '{print "catpm3 binary:", $5, "bytes"}'
file $WS/catpm/catpm3 | sed 's/^/file(1): /'
$CPM --version
} > $LOGD/build3.log 2>&1

# restore a clean default package.where for the repo
cat > $WS/catpm/package.where <<WHERE
# catpm source list v1 (apt sources.list style)
# <dir-or-URL> [prio=N] [pkg=name1,name2]
# default: this repository's own registry on GitHub
https://raw.githubusercontent.com/monikalnbo/catpm/main/registry
WHERE

echo "wrote $LOGD/build3.log and $LOGD/where3.log"
