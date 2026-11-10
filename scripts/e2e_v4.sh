#!/bin/bash
# ============================================================
# e2e_v4.sh — catpm v0.4 round-4 walkthrough:
#   [1/6] unit tests (44 assertions) + fresh v0.4 compile
#   [2/6] basic-command sweep: init/add/install/list/remove/sources/pack/publish
#   [3/6] version control: comma AND, *, exact pin, upgrade/downgrade,
#         lock-exact restore, drift honored, outdated, update
#   [4/6] repo split: new packages installed purely from catpm-registry
#         (timex+randx over HTTPS), compile + run
#   [5/6] installers: POSIX sh / bash / zsh / fish real runs + syntax checks
#   [6/6] raw reachability of the split repos (curl status codes)
# Everything captured to logs/build4.log + logs/run4.log.
# ============================================================
WS=/root/.hermes-web-ui/.ekko/workspace/default/person-main-f5f99dc5-b73a-417a-baf6-5b3f41382e6c
CATCC=$WS/catbase/bin/catcc
CPM=$WS/catpm/catpm4
LOGD=$WS/logs
REG4=$WS/registry4
RAWMAIN=https://raw.githubusercontent.com/monikalnbo/catpm/main
RAWREG=https://raw.githubusercontent.com/monikalnbo/catpm-registry/main
mkdir -p $LOGD

step() { echo ""; echo "=================================================="; echo "== $*"; echo "=================================================="; }

# ------------------------------------------------ build4.log
{
step "BUILD LOG v4 — catpm 0.4.0 $(date -u '+%Y-%m-%d %H:%M:%SZ')"
echo "catcc: $($CATCC --version)   zig: $($WS/tools/zigx/zig version)"
echo ""

step "[1/4] version engine unit tests (ver.catc, 44 assertions incl. AND lists)"
( cd $WS/catbase && ./bin/catcc $WS/catpm/src2/test_ver.cat -o /tmp/test_ver4 2>&1 | tail -1 )
/tmp/test_ver4; echo "exit=$?"
echo ""

step "[2/4] catpm v0.4 -> native binary (fresh compile)"
t0=$(date +%s.%N)
( cd $WS/catbase && ./bin/catcc $WS/catpm/src2/catpm.cat -o $WS/catpm/catpm4 2>&1 | tail -1 )
t1=$(date +%s.%N)
echo "compile wall=$(echo "$t1 $t0" | awk '{printf "%.2f", $1-$2}') s"
echo ""

step "[3/4] artifacts"
ls -la $WS/catpm/catpm4 | awk '{print "catpm4 binary:", $5, "bytes"}'
file $WS/catpm/catpm4 | sed 's/^/file(1): /'
$CPM --version
echo ""

step "[4/4] new packages compiled standalone (timex + randx behavior probe)"
cat > $WS/pkgsrc/_probe_v4.cat <<'SRC'
import ./timex/index.catc as timex
import ./randx/index.catc as randx
import ./stringx/index.catc as stringx

def main() {
    print("timex.iso8601() = ", timex.iso8601())
    print("timex.stamp('hello') = ", timex.stamp("hello"))
    print("timex.shout_stamp('shout') = ", timex.shout_stamp("shout"))
    e: int = timex.epoch()
    print("timex.epoch() = ", e)
    print("timex.days_between(e, e + 90000) = ", timex.days_between(e, e + 90000))
    randx.seed(42)
    a: int = randx.between(1, 100)
    b: int = randx.between(1, 100)
    c: int = randx.between(1, 100)
    print("randx seed42 first three between(1,100): ", a, b, c)
    randx.seed(42)
    print("reseed 42 -> same first two: ", randx.between(1, 100), randx.between(1, 100))
    print("randx.die6() = ", randx.die6())
    names: list[str] = ["alice", "bob", "carol"]
    print("randx.pick(names) = ", randx.pick(names))
    print("stringx.shout('done') = ", stringx.shout("done"))
}
SRC
( cd $WS/catbase && ./bin/catcc $WS/pkgsrc/_probe_v4.cat -o /tmp/probe_v4 2>&1 | tail -1 )
/tmp/probe_v4; echo "exit=$?"
rm -f $WS/pkgsrc/_probe_v4.cat
} > $LOGD/build4.log 2>&1

# ------------------------------------------------ run4.log
{
step "RUN LOG v4 — commands / version control / repo split / installers  $(date -u '+%Y-%m-%d %H:%M:%SZ')"
echo "catpm: $($CPM --version)"
echo ""

# ================= [2/6] basic command sweep (local registry4 source)
step "[2/6] BASIC COMMAND SWEEP (source: local registry4 = same tree pushed to catpm-registry)"
echo "$REG4" > /tmp/v4_where
rm -rf /tmp/v4_sweep && mkdir -p /tmp/v4_sweep && cd /tmp/v4_sweep
export CATPM_WHERE=/tmp/v4_where

echo "\$ catpm init"
$CPM init; echo "exit=$?"
echo ""
echo "\$ catpm add randx"
$CPM add randx 2>&1 | sed 's/^/  /'; echo "exit=$?"
echo ""
echo "\$ catpm list"
$CPM list
echo ""
echo "\$ catpm sources"
$CPM sources
echo ""
echo "--- lock-exact restore: rm -rf deps .catpm-cache; catpm install ---"
rm -rf deps .catpm-cache
$CPM install 2>&1 | sed 's/^/  /'
echo ""
echo "\$ catpm remove timex   (timex is transitive dep of randx -> must refuse, stringx stays)"
$CPM remove timex 2>&1 | tail -3 || true
echo "\$ catpm remove randx   (direct dep: goes + orphans timex; stringx stays: still needed by manifest? no -> check prune)"
$CPM remove randx 2>&1 | tail -4
echo "deps after remove randx:"; find deps -type f | sort | sed 's/^/  /'
echo ""
echo "--- pack/publish roundtrip with a scratch package ---"
mkdir -p /tmp/v4_sweep/mypkg && cd /tmp/v4_sweep/mypkg
printf '{"name":"mypkg","version":"9.9.9","catpm":"0.4.0","deps":{}}\n' > catpm.json
printf 'MYPKG_VERSION: str = "9.9.9"\ndef hello() -> str { return "hi" }\n' > index.catc
$CPM pack 2>&1 | sed 's/^/  /'
rm -rf /tmp/v4_reg_tmp && mkdir /tmp/v4_reg_tmp
$CPM publish /tmp/v4_reg_tmp 2>&1 | sed 's/^/  /'
echo "index.json of scratch registry:"; cat /tmp/v4_reg_tmp/index.json | head -3 | sed 's/^/  /'
cd /tmp/v4_sweep

# ================= [3/6] version control
step "[3/6] VERSION CONTROL: AND / * / exact / up-downgrade / lock semantics"
rm -rf /tmp/v4_ver && mkdir -p /tmp/v4_ver && cd /tmp/v4_ver
export CATPM_WHERE=/tmp/v4_where
$CPM init >/dev/null

echo "\$ catpm add 'mathx@>=0.2.0,<0.4.0'   (comma AND: only 0.3.0 qualifies)"
$CPM add 'mathx@>=0.2.0,<0.4.0' 2>&1 | head -1
grep mathx catpm.lock
echo ""
echo "\$ catpm add 'mathx@*'               (star = any, resolves highest)"
$CPM add 'mathx@*' 2>&1 | head -1
grep mathx catpm.lock
echo ""
echo "\$ catpm add 'mathx@0.2.0'           (exact pin -> downgrade)"
$CPM add 'mathx@0.2.0' 2>&1 | head -1
grep mathx catpm.lock
echo ""
echo "--- drift honored: hand-edit lock 0.2.0 -> 0.3.0; install must obey lock ---"
sed -i 's/mathx 0.2.0/mathx 0.3.0/' catpm.lock
$CPM install 2>&1 | grep -E "lock-exact|installed mathx"
grep mathx catpm.lock
echo ""
echo "\$ catpm outdated"
$CPM outdated
echo ""
echo "\$ catpm update                     (re-resolve: 0.2.0 pinned in manifest stays)"
$CPM update >/dev/null 2>&1
grep mathx catpm.lock
echo ""
echo "--- stale-file fix: upgrade must not leave old files (filer 1.0.0 with src/ -> 1.1.0 without) ---"
mkdir -p /tmp/v4_filer/src && cd /tmp/v4_filer
printf '{"name":"filer","version":"1.0.0","catpm":"0.4.0","deps":{},"files":["src/extra.catc"]}\n' > catpm.json
printf 'import ./src/extra.catc as extra\nFILER_VERSION: str = "1.0.0"\ndef one() -> int { return 1 }\ndef bonus() -> int { return extra.extra_one() }\n' > index.catc
printf 'def extra_one() -> int { return 100 }\n' > src/extra.catc
$CPM pack >/dev/null 2>&1
printf '{"name":"filer","version":"1.1.0","catpm":"0.4.0","deps":{}}\n' > catpm.json
printf 'FILER_VERSION: str = "1.1.0"\ndef one() -> int { return 1 }\n' > index.catc
$CPM pack >/dev/null 2>&1
rm -rf /tmp/v4_freg && mkdir -p /tmp/v4_freg/filer
cp dist/filer-1.0.0.cpkg dist/filer-1.1.0.cpkg /tmp/v4_freg/filer/
python3 - <<'PY'
import json,hashlib,os
reg='/tmp/v4_freg'; idx={'packages':{'filer':{}}}
for v in ['1.0.0','1.1.0']:
    p=f'{reg}/filer/filer-{v}.cpkg'
    idx['packages']['filer'][v]={'path':f'filer/filer-{v}.cpkg','sha256':hashlib.sha256(open(p,'rb').read()).hexdigest(),'deps':{}}
json.dump(idx,open(f'{reg}/index.json','w'))
PY
echo "/tmp/v4_freg" > /tmp/v4_fwhere
rm -rf /tmp/v4_fproj && mkdir /tmp/v4_fproj && cd /tmp/v4_fproj
CATPM_WHERE=/tmp/v4_fwhere $CPM init >/dev/null
CATPM_WHERE=/tmp/v4_fwhere $CPM add 'filer@1.0.0' >/dev/null 2>&1
echo "filer 1.0.0 files:"; find deps -type f | sort | sed 's/^/  /'
CATPM_WHERE=/tmp/v4_fwhere $CPM add 'filer@1.1.0' >/dev/null 2>&1
echo "filer 1.1.0 files (src/extra.catc must be gone):"; find deps -type f | sort | sed 's/^/  /'
echo ""
echo "--- sha256 tamper detection still intact (index sha zeroed) ---"
python3 - <<'PY'
import json
p='/tmp/v4_freg/index.json'
d=json.load(open(p))
d['packages']['filer']['1.1.0']['sha256']='0'*64
json.dump(d,open(p,'w'))
PY
CATPM_WHERE=/tmp/v4_fwhere $CPM add 'filer@1.1.0' > /tmp/v4_tamper.out 2>&1; RC=$?
tail -2 /tmp/v4_tamper.out | sed 's/^/  /'; echo "exit=$RC (expect 1)"

# ================= [4/6] repo split live
step "[4/6] REPO SPLIT: clean dir + only catpm4 & package.where -> pure HTTPS from catpm-registry"
rm -rf /tmp/live4 && mkdir -p /tmp/live4/bin
cp $WS/catpm/catpm4 /tmp/live4/bin/catpm
cp $WS/catpm/package.where /tmp/live4/bin/package.where
cd /tmp/live4
unset CATPM_WHERE   # must use the package.where sitting next to the binary
echo "--- package.where (as shipped in the repo) ---"
cat bin/package.where | sed 's/^/  /'
echo ""
echo "\$ ./bin/catpm sources"
./bin/catpm sources | sed 's/^/  /'
echo ""
echo "\$ ./bin/catpm init && ./bin/catpm add randx   (timex+stringx come transitively)"
./bin/catpm init >/dev/null
./bin/catpm add randx 2>&1 | sed 's/^/  /'; echo "exit=$?"
echo ""
echo "\$ ./bin/catpm add 'mathx@>=0.2.0,<0.4.0'      (AND list over remote index)"
./bin/catpm add 'mathx@>=0.2.0,<0.4.0' 2>&1 | grep -E "added|resolved|installed" | sed 's/^/  /'
grep mathx catpm.lock | sed 's/^/  lock: /'
echo ""
cat > main.cat <<'SRC'
# live4: everything installed from the catpm-registry repo over HTTPS
import ./deps/randx/index.catc as randx
import ./deps/timex/index.catc as timex
import ./deps/mathx/index.catc as mathx

def main() {
    print("== catpm v0.4 live demo (source: catpm-registry repo) ==")
    print("timex.iso8601() = ", timex.iso8601())
    print("timex.stamp('event') = ", timex.stamp("event"))
    randx.seed(42)
    print("randx seed42 between(1,100) x3 = ", randx.between(1, 100), randx.between(1, 100), randx.between(1, 100))
    print("randx.die6() = ", randx.die6())
    print("mathx.fib(12) = ", mathx.fib(12))
    print("mathx.loud_double(21) = ", mathx.loud_double(21))
}
SRC
echo "\$ catcc main.cat -o app && ./app"
( cd $WS/catbase && ./bin/catcc /tmp/live4/main.cat -o /tmp/live4/app 2>&1 | tail -1 ) | sed 's/^/  /'
ls -la app | awk '{print "  app:", $5, "bytes"}'
./app; echo "  exit=$?"

# ================= [5/6] installers
step "[5/6] INSTALLERS: sh / bash / zsh / fish"
echo "--- syntax checks ---"
sh   -n $WS/repo/install.sh   && echo "  sh -n install.sh: OK"
bash -n $WS/repo/install.sh   && echo "  bash -n install.sh: OK"
zsh  -n $WS/repo/install.sh   && echo "  zsh -n install.sh: OK"
fish --no-execute $WS/repo/install.fish && echo "  fish --no-execute install.fish: OK"
echo ""
echo "--- real installs from GitHub raw (clean HOMEs, restricted PATH) ---"
rm -rf /tmp/h1 /tmp/h2 /tmp/h3 /tmp/h4
mkdir -p /tmp/h1 /tmp/h2 /tmp/h3 /tmp/h4
echo "\$ sh:   curl .../install.sh | sh"
env -i HOME=/tmp/h1 PATH=/usr/bin:/bin:/usr/local/bin sh  -c "curl -fsSL $RAWMAIN/install.sh | sh"  2>&1 | head -2 | sed 's/^/  /'
echo "\$ bash: curl .../install.sh | bash"
env -i HOME=/tmp/h2 PATH=/usr/bin:/bin:/usr/local/bin bash -c "curl -fsSL $RAWMAIN/install.sh | bash" 2>&1 | head -2 | sed 's/^/  /'
echo "\$ zsh:  curl .../install.sh | zsh"
env -i HOME=/tmp/h3 PATH=/usr/bin:/bin:/usr/local/bin zsh  -c "curl -fsSL $RAWMAIN/install.sh | zsh"  2>&1 | head -2 | sed 's/^/  /'
echo "\$ fish: curl .../install.fish | source"
env -i HOME=/tmp/h4 PATH=/usr/bin:/bin:/usr/local/bin fish -c "curl -fsSL $RAWMAIN/install.fish | source" 2>&1 | head -2 | sed 's/^/  /'
echo ""
echo "--- verify all four installs ---"
for h in h1 h2 h3 h4; do
  if [ -x /tmp/$h/.local/bin/catpm ]; then
    V=$(/tmp/$h/.local/bin/catpm --version)
    W=$(grep -c catpm-registry /tmp/$h/.local/bin/package.where)
    echo "  /tmp/$h/.local/bin/catpm: $V (package.where->catpm-registry: $W)"
  else
    echo "  /tmp/$h: INSTALL MISSING"
  fi
done
echo ""
echo "--- PATH snippet works: bash with exported PATH uses installed catpm ---"
rm -rf /tmp/h2/proj && mkdir /tmp/h2/proj && cd /tmp/h2/proj
PATH=/tmp/h2/.local/bin:$PATH catpm init >/dev/null
PATH=/tmp/h2/.local/bin:$PATH catpm add timex 2>&1 | grep -E "resolved|installed" | sed 's/^/  /'

# ================= [6/6] raw reachability
step "[6/6] RAW REACHABILITY (curl HTTP status, split repos)"
echo "--- catpm (PM repo) ---"
for f in catpm/catpm4 catpm/package.where install.sh install.fish PROTOCOL.md README.md; do
  C=$(curl -sS -o /dev/null -w "%{http_code}" "$RAWMAIN/$f"); echo "  $C  $f"
done
echo "--- catpm-registry (packages) ---"
C=$(curl -sS -o /dev/null -w "%{http_code}" "$RAWREG/index.json"); echo "  $C  index.json"
for f in fmtx/fmtx-0.1.0.cpkg loganx/loganx-0.1.0.cpkg mathx/mathx-0.2.0.cpkg mathx/mathx-0.3.0.cpkg mathx/mathx-0.4.0.cpkg randx/randx-0.1.0.cpkg stringx/stringx-0.3.0.cpkg timex/timex-0.1.0.cpkg; do
  C=$(curl -sS -o /dev/null -w "%{http_code}" "$RAWREG/$f"); echo "  $C  $f"
done

echo ""
echo "END OF RUN LOG v4"
} > $LOGD/run4.log 2>&1

echo "wrote $LOGD/build4.log and $LOGD/run4.log"
