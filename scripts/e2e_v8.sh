#!/bin/bash
# ============================================================
# e2e_v8.sh — catpm v0.5.4 walkthrough:
#   [1/2] build: 62-assertion unit tests + fresh catpm54 compile
#   [2/2] run: apt-update-style index cache + pip-style notice:
#     [1/8] catpm update refreshes the cache, installs NOTHING
#     [2/8] read path uses the cache (offline add works, no re-fetch)
#     [3/8] TTL: cached index expires -> auto live re-fetch
#     [4/8] partial failure: dead source keeps last good copy,
#           others refresh, exit code 1
#     [5/8] STALE fallback: TTL fresh but live dead + old cache ->
#           resolve from stale cache with a warning
#     [6/8] upgrade (old update semantics) still works + regression
#     [7/8] pip-style notice: fake 0.5.5 in a source -> --version
#           and update both print the notice
#     [8/8] live HTTPS: registry raw checks + self-update
#           0.5.2 -> 0.5.4 + fresh-install path
# Everything captured to logs/build8.log + logs/run8.log.
# Requires: catbase at $WS/catbase, registry4 local source, GitHub
# catpm-registry already carrying catpm-0.5.4.cpkg.
# ============================================================
WS=/root/.hermes-web-ui/.ekko/workspace/default/person-main-f5f99dc5-b73a-417a-baf6-5b3f41382e6c
CATCC=$WS/catbase/bin/catcc
CPM=$WS/catpm/catpm54         # v0.5.4 (this release)
OLD=$WS/catpm/catpm52         # v0.5.2 (previous, for self-update chain)
LOGD=$WS/repo/logs
REG=$WS/registry4             # local source registry (13 entries, catpm<=0.5.2)
RAWREG=https://raw.githubusercontent.com/monikalnbo/catpm-registry/main
mkdir -p $LOGD

step() { echo ""; echo "=================================================="; echo "== $*"; echo "=================================================="; }

# ------------------------------------------------ build8.log
{
step "BUILD LOG v8 — catpm 0.5.4 (index cache + apt update semantics)  $(date -u '+%Y-%m-%d %H:%M:%SZ')"
echo "catcc: $($CATCC --version)   zig: $($WS/tools/zigx/zig version)"
echo ""

step "[1/2] version engine unit tests (62 assertions; unchanged from 0.5.3)"
( cd $WS/catbase && ./bin/catcc $WS/catpm/src2/test_ver.cat -o /tmp/test_ver8 2>&1 | tail -1 )
/tmp/test_ver8; echo "exit=$?"
echo ""

step "[2/2] fresh compile of the 0.5.4 source"
rm -f $WS/catpm/catpm54
( cd $WS/catbase && time ./bin/catcc $WS/catpm/src2/catpm.cat -o $WS/catpm/catpm54 ) 2>&1 | tail -4
ls -l $WS/catpm/catpm54
$WS/catpm/catpm54 --version
echo ""
step "DONE build8  $(date -u '+%Y-%m-%d %H:%M:%SZ')"
} > $LOGD/build8.log 2>&1

# restore the binary we just rebuilt (e2e below uses it)
CPM=$WS/catpm/catpm54

# ------------------------------------------------ run8.log
{
step "RUN LOG v8 — index cache (apt update) + new-version notice (pip)  $(date -u '+%Y-%m-%d %H:%M:%SZ')"
T=$(mktemp -d)
echo "scratch dir: $T"

step "[1/8] catpm update refreshes the index cache, installs NOTHING"
mkdir -p $T/f1 && cd $T/f1
printf '%s\n' "$REG" > package.where
cat > catpm.json <<'EOF'
{"name": "f1", "deps": {}}
EOF
$CPM update; echo "update exit=$?"
echo "-- cache on disk after update:"
ls $T/f1/.catpm-cache/index-cache/
echo "-- deps/ must NOT exist (update touches only the index cache):"
ls deps 2>/dev/null && echo "BUG: deps/ created" || echo "no deps/ (correct: apt update installs nothing)"
echo "-- second refresh shows entry counts vs last refresh:"
$CPM update
echo ""

step "[2/8] read path uses the cache (offline add, no re-fetch)"
mkdir -p $T/f2 && cd $T/f2
printf '%s\n' "$REG" > package.where
cat > catpm.json <<'EOF'
{"name": "f2", "deps": {}}
EOF
$CPM update > /dev/null
$CPM add mathx > /dev/null 2>&1
$CPM remove mathx > /dev/null 2>&1
echo "-- kill the source dir, then re-add purely from caches"
echo "   (index cache resolves the version, package cache serves the tarball):"
mv $REG ${REG}.hidden
$CPM add mathx 2>&1 | tail -3
mv ${REG}.hidden $REG
test -f deps/mathx/index.catc && echo "mathx present (resolved + fetched entirely from caches)"

step "[3/8] TTL: cached index expires -> auto live re-fetch"
mkdir -p $T/f3 && cd $T/f3
printf '%s\n' "$REG" > package.where
cat > catpm.json <<'EOF'
{"name": "f3", "deps": {}}
EOF
$CPM update > /dev/null
echo "-- TTL=0: refresh reports 'age out after 0s':"
CATPM_INDEX_TTL=0 $CPM update 2>&1 | tail -1
echo "-- after 1s of age a TTL=0 read must re-fetch live (source present):"
sleep 1.1
CATPM_INDEX_TTL=0 $CPM add loganx 2>&1 | tail -2
test -f deps/loganx/index.catc && echo "loganx present (re-fetched after expiry)"
echo "-- invalid TTL falls back to the default 86400:"
CATPM_INDEX_TTL=junk $CPM update 2>&1 | tail -1
echo ""

step "[4/8] partial failure: dead source keeps last good copy, exit 1"
mkdir -p $T/f4 && cd $T/f4
cat > package.where <<EOF
$REG
/nonexistent/registry-should-not-exist
EOF
cat > catpm.json <<'EOF'
{"name": "f4", "deps": {}}
EOF
echo "-- first refresh warms both (the dead one fails, no cache for it):"
$CPM update 2>&1 | grep -E "OK|ERR|updated"
echo "-- make the GOOD source dead too (rename), refresh again:"
mv $REG ${REG}.hidden
$CPM update; echo "update exit=$? (nonzero: partial failure, as designed)"
mv ${REG}.hidden $REG
echo "-- good source's cache is still on disk and usable:"
ls $T/f4/.catpm-cache/index-cache/ | grep -c json | sed 's/^/cached index files: /'
$CPM add fmtx 2>&1 | tail -2
test -f deps/fmtx/index.catc && echo "fmtx present (remaining source still serves)"

step "[5/8] STALE fallback: live dead + old cache -> resolve with warning"
mkdir -p $T/f5 && cd $T/f5
printf '%s\n' "$REG" > package.where
cat > catpm.json <<'EOF'
{"name": "f5", "deps": {}}
EOF
$CPM update > /dev/null
$CPM add stringx > /dev/null 2>&1
$CPM remove stringx > /dev/null 2>&1
echo "-- source dir vanishes AND cache aged out (TTL=0 + 1s) -> STALE fallback:"
mv $REG ${REG}.hidden
sleep 1.1
CATPM_INDEX_TTL=0 $CPM add stringx 2>&1 | grep -E "warning|note|installed|STALE"
mv ${REG}.hidden $REG
test -f deps/stringx/index.catc && echo "stringx present (installed via STALE index + package cache)"

step "[6/8] upgrade (the pre-0.5.4 'update' semantics) + regression"
mkdir -p $T/f6 && cd $T/f6
printf '%s\n' "$REG" > package.where
cat > catpm.json <<'EOF'
{"name": "f6", "deps": {"mathx": "^0.2.0"}}
EOF
$CPM add 'mathx@^0.2.0' > /dev/null 2>&1
echo "-- pin manifest to 0.4.0, then upgrade re-resolves and installs:"
python3 - <<'PYEOF'
import json
m = json.load(open('catpm.json'))
m['deps']['mathx'] = '^0.4.0'
json.dump(m, open('catpm.json', 'w'), indent=1)
PYEOF
$CPM upgrade 2>&1 | tail -3
grep mathx catpm.lock
echo "-- 'update <pkg>' no longer installs; it refreshes the index cache:"
$CPM update mathx 2>&1 | tail -1

step "[7/8] pip-style notice: fake 0.5.5 -> --version and update both notice"
mkdir -p $T/fake && cp -r $REG/. $T/fake/
mkdir -p $T/f7 && cd $T/f7
printf '%s\n' "$T/fake" > package.where
cat > catpm.json <<'EOF'
{"name": "f7", "deps": {}}
EOF
# stage a fake catpm 0.5.5 by re-publishing the 0.5.2 cpkg under a bumped name
cp $REG/catpm/catpm-0.5.2.cpkg $T/fake/catpm/catpm-0.5.5.cpkg
FAKE=$T/fake python3 - <<'PYEOF'
import json, hashlib, os
p = os.path.join(os.environ["FAKE"], "index.json")
d = json.load(open(p))
e = dict(d['packages']['catpm']['0.5.2'])
e['path'] = 'catpm/catpm-0.5.5.cpkg'
e['sha256'] = hashlib.sha256(open(os.path.join(os.environ["FAKE"], "catpm/catpm-0.5.5.cpkg"),"rb").read()).hexdigest()
d['packages']['catpm']['0.5.5'] = e
json.dump(d, open(p, 'w'), indent=1)
PYEOF
echo "-- --version notices the newer self (live index, never cache):"
$CPM --version
echo "-- update prints the notice too:"
CATPM_INDEX_TTL=0 $CPM update 2>&1 | tail -2
echo "-- sources stays live-only and still works:"
$CPM sources 2>&1 | tail -2
echo ""

step "[8/8] live HTTPS: registry raw checks + self-update 0.5.2 -> 0.5.4"
for f in index.json catpm/catpm-0.5.4.cpkg; do
  code=$(curl -sS -o /dev/null -w '%{http_code}' "$RAWREG/$f")
  echo "$code  $f"
done
mkdir -p $T/su/bin && cd $T/su
cp $OLD bin/catpm
cp $WS/repo/catpm/package.where package.where
echo "step0: $(bin/catpm --version)"
bin/catpm self-update 2>&1 | grep -E 'updated|sha256|verified|target'
echo "step1: $(bin/catpm --version)"
ls bin/ | grep '\.new' && echo "RESIDUE FOUND" || echo "no .new residue"
echo "-- fresh 0.5.4 over HTTPS: update (cache) then add prebuilt hellox:"
mkdir -p $T/remote && cd $T/remote
cp $WS/repo/catpm/package.where package.where
cat > catpm.json <<'EOF'
{"name": "remote", "deps": {}}
EOF
$T/su/bin/catpm update 2>&1 | tail -2
$T/su/bin/catpm add hellox 2>&1 | tail -2
deps/hellox/bin/hellox; echo "run exit=$?"

echo ""
step "DONE run8  $(date -u '+%Y-%m-%d %H:%M:%SZ')"
} > $LOGD/run8.log 2>&1

echo "== wrote $LOGD/build8.log + $LOGD/run8.log"
tail -4 $LOGD/build8.log
echo "---"
tail -12 $LOGD/run8.log
