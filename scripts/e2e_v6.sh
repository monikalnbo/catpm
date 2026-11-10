#!/bin/bash
# ============================================================
# e2e_v6.sh — catpm v0.5.2 polish release walkthrough:
#   [1/3] 62-assertion unit tests + fresh catpm52 compile
#   [2/3] the four polish fixes reproduced (before/after)
#   [3/3] self-update full chain over live HTTPS:
#         0.5.0 -> @0.5.1 -> 0.5.2 (latest) -> @0.5.1 (downgrade)
# Everything captured to logs/build6.log + logs/run6.log.
# Requires: catbase at $WS/catbase, registry4 local source, and the
# GitHub catpm-registry already carrying catpm-0.5.2.cpkg.
# ============================================================
WS=/root/.hermes-web-ui/.ekko/workspace/default/person-main-f5f99dc5-b73a-417a-baf6-5b3f41382e6c
CATCC=$WS/catbase/bin/catcc
CPM=$WS/catpm/catpm52         # v0.5.2 (this release)
OLD=$WS/catpm/catpm5          # v0.5.0 (pre-polish, for before/after)
LOGD=$WS/repo/logs
REG=$WS/registry4
RAWREG=https://raw.githubusercontent.com/monikalnbo/catpm-registry/main
mkdir -p $LOGD

step() { echo ""; echo "=================================================="; echo "== $*"; echo "=================================================="; }

# ------------------------------------------------ build6.log
{
step "BUILD LOG v6 — catpm 0.5.2 (polish release)  $(date -u '+%Y-%m-%d %H:%M:%SZ')"
echo "catcc: $($CATCC --version)   zig: $($WS/tools/zigx/zig version)"
echo ""

step "[1/3] version engine unit tests (62 assertions; v0.5.2 added 18 junk/empty-input cases)"
( cd $WS/catbase && ./bin/catcc $WS/catpm/src2/test_ver.cat -o /tmp/test_ver6 2>&1 | tail -1 )
/tmp/test_ver6; echo "exit=$?"
echo ""

step "[2/3] fresh compile of the 0.5.2 source"
rm -f $WS/catpm/catpm52
( cd $WS/catbase && time ./bin/catcc $WS/catpm/src2/catpm.cat -o $WS/catpm/catpm52 ) 2>&1 | tail -4
ls -l $WS/catpm/catpm52
$WS/catpm/catpm52 --version
echo ""

step "[3/3] package + publish to local registry4 (source snapshot for the diff)"
cd $WS/pkgsrc/catpm-pkg052 && rm -rf dist
$CPM pack 2>&1 | tail -3
$CPM publish $REG 2>&1 | tail -3
python3 -c "
import json
d = json.load(open('$REG/index.json'))
print('registry4 catpm versions:', sorted(d['packages']['catpm'].keys()))
print('0.5.2 sha256:', d['packages']['catpm']['0.5.2']['sha256'])
"
echo ""
step "DONE build6  $(date -u '+%Y-%m-%d %H:%M:%SZ')"
} > $LOGD/build6.log 2>&1

# ------------------------------------------------ run6.log
{
step "RUN LOG v6 — polish fixes + self-update chain  $(date -u '+%Y-%m-%d %H:%M:%SZ')"
T=$(mktemp -d)

step "[1/4] fix #1 (junk/empty bounds): 0.5.0 accepted '>=x' and 'pkg@', 0.5.2 rejects"
mkdir -p $T/f1 && cd $T/f1
cat > catpm.json <<'EOF'
{"name": "f1", "deps": {}}
EOF
echo "-- old 0.5.0:"
$OLD add 'mathx@>=x' 2>&1 | head -1
echo "  (old build wrote the junk spec into catpm.json AND resolved 0.4.0 — the bug)"
echo "-- new 0.5.2:"
$CPM add 'mathx@>=x' 2>&1; echo "exit=$?"
$CPM add 'mathx@^junk' 2>&1; echo "exit=$?"
$CPM add 'mathx@' 2>&1; echo "exit=$?"
$CPM add 'mathx@>=0.2.0,' 2>&1; echo "exit=$?"
echo "-- manifest after all rejected adds (only old build's write remains; new build touched nothing):"
cat catpm.json
echo "-- legit bounds still work:"
$CPM add 'mathx@^0.2.0' 2>&1 | head -1
echo ""

step "[2/4] fix #2 (exit codes): usage errors used to exit 0, now 1"
echo "-- old 0.5.0:"
$OLD add >/dev/null 2>&1; echo "add-no-arg exit=$?"
$OLD nosuchcmd >/dev/null 2>&1; echo "unknown-cmd exit=$?"
echo "-- new 0.5.2:"
cd $T && mkdir -p f2 && cd f2
cat > catpm.json <<'EOF'
{"name": "f2", "deps": {}}
EOF
$CPM add >/dev/null 2>&1; echo "add-no-arg exit=$?"
$CPM nosuchcmd >/dev/null 2>&1; echo "unknown-cmd exit=$?"
$CPM remove >/dev/null 2>&1; echo "remove-no-arg exit=$?"
$CPM publish >/dev/null 2>&1; echo "publish-no-arg exit=$?"
echo ""

step "[3/4] fix #3 (dir guards): lock/manifest-as-dir used to SIGABRT (rc 134)"
cd $T && mkdir -p f3 && cd f3
cat > catpm.json <<'EOF'
{"name": "f3", "deps": {}}
EOF
mkdir catpm.lock
echo "-- new 0.5.2 (old build dies with rc=134 here):"
$CPM install 2>&1; echo "exit=$?"
$CPM outdated 2>&1; echo "exit=$?"
rm -rf catpm.lock
mkdir catpm.json 2>/dev/null || rmdir catpm.json 2>/dev/null; rm -f catpm.json; mkdir catpm.json
$CPM list 2>&1; echo "exit=$?"
rm -rf catpm.json
mkdir package.where
$CPM sources 2>&1 | head -1
$CPM sources >/dev/null 2>&1; echo "sources-with-dir-where exit=$?"
rm -rf package.where
echo "-- normal ops restored after cleanup:"
$CPM list 2>&1; echo "exit=$?"
echo ""

step "[4/4] self-update full chain over live HTTPS"
mkdir -p $T/su/bin && cd $T/su
cp $OLD bin/catpm
cp $WS/repo/catpm/package.where package.where
echo "step0: $(bin/catpm --version)"
bin/catpm self-update @0.5.1 2>&1 | grep -E 'updated|sha256|verified'
echo "step1: $(bin/catpm --version)"
bin/catpm self-update 2>&1 | grep -E 'updated|sha256|verified'
echo "step2: $(bin/catpm --version)"
bin/catpm self-update @0.5.1 2>&1 | grep updated
echo "step3 (explicit downgrade): $(bin/catpm --version)"
ls bin/ | grep '\.new' && echo "RESIDUE FOUND" || echo "no .new residue"

echo ""
step "raw direct-link checks"
for f in catpm/catpm-0.5.2.cpkg index.json; do
  code=$(curl -sS -o /dev/null -w '%{http_code}' "$RAWREG/$f")
  echo "$code  $f"
done

echo ""
step "DONE run6  $(date -u '+%Y-%m-%d %H:%M:%SZ')"
} > $LOGD/run6.log 2>&1

echo "== wrote $LOGD/build6.log + $LOGD/run6.log"
tail -5 $LOGD/build6.log
echo "---"
tail -8 $LOGD/run6.log
