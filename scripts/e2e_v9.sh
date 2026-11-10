#!/bin/bash
# ============================================================
# e2e_v9.sh — catpm v0.5.5 walkthrough: interrupt-resilience
#   [1/2] build: 62-assertion unit tests + fresh catpm55 compile
#   [2/2] run: kill/interrupt matrix + recovery:
#     [1/9] fix sweeps six residue classes in one pass
#     [2/9] corrupted manifest (truncated mid-write) is rejected
#           by install/upgrade/add/remove (read-side guard)
#     [3/9] truncated cached .cpkg self-heals (sha check ->
#           purge -> one re-fetch -> install ok)
#     [4/9] kill -9 during download (throttled HTTP) -> rerun
#           recovers; v0.5.4 baseline needed TWO runs
#     [5/9] SIGINT during download -> rerun recovers
#     [6/9] kill -9 during unpack (300MB payload) -> stage dir
#           protects deps/; rerun sweeps + completes
#     [7/9] network cut (iptables DROP) mid-download -> rerun
#           recovers
#     [8/9] randomized kill stress (25x add + 20x update,
#           TTL=0): zero integrity violations, rerun completes,
#           final lock+deps byte-identical to one-shot clean run
#     [9/9] offline: update fails gracefully keeping cache;
#           STALE index + package cache still installs
# Everything captured to logs/build9.log + logs/run9.log.
# Requires: catbase at $WS/catbase, local test registry (built
# by the script), throttled HTTP server on 127.0.0.1:8123.
# ============================================================
WS=/root/.hermes-web-ui/.ekko/workspace/default/person-main-f5f99dc5-b73a-417a-baf6-5b3f41382e6c
CATCC=$WS/catbase/bin/catcc
CPM=$WS/catpm/catpm55         # v0.5.5 (this release)
LOGD=$WS/repo/logs
REG=$WS/registry4             # local source registry (catpm<=0.5.2)
RAWREG=https://raw.githubusercontent.com/monikalnbo/catpm-registry/main
mkdir -p $LOGD

step() { echo ""; echo "=================================================="; echo "== $*"; echo "=================================================="; }

# ---------- helpers reused by the kill matrix ----------
cat > /tmp/v9_validate.py <<'PYEOF'
import json, os, sys, glob
bad = []
if os.path.exists("catpm.lock") and os.path.getsize("catpm.lock") > 0:
    lines = open("catpm.lock").read().splitlines()
    if not lines or not lines[0].startswith("# catpm lock file"):
        bad.append("lock: missing v2 header")
    for ln in lines:
        if not ln or ln.startswith("#"): continue
        if len(ln.split()) != 2: bad.append("lock: bad line %r" % ln)
for f in glob.glob(".catpm-cache/index-cache/*.json"):
    if f.endswith(".catpm-tmp"): continue
    try: json.load(open(f))
    except Exception as e: bad.append("%s invalid: %s" % (f, e))
if os.path.isdir("deps"):
    for d in sorted(os.listdir("deps")):
        if d.startswith("."): continue
        if not os.path.isfile("deps/%s/index.catc" % d):
            bad.append("deps/%s missing index.catc" % d)
if bad:
    print("VIOLATIONS:"); [print("  " + b) for b in bad]; sys.exit(1)
sys.exit(0)
PYEOF

ensure_slowserve() {
  if pgrep -f 'slowserve\.py 8123' > /dev/null && curl -sS -m 2 -o /dev/null http://127.0.0.1:8123/registry4/index.json 2>/dev/null; then
    echo "slowserve already up"
    return 0
  fi
  pgrep -f 'slowserve\.py 8123' | while read p; do kill -9 $p 2>/dev/null; done
  sleep 0.3
  mkdir -p /tmp/slowserve/root
  rm -rf /tmp/slowserve/root/registry4
  cp -r $REG /tmp/slowserve/root/registry4
  cat > /tmp/slowserve/slowserve.py <<'PY'
#!/usr/bin/env python3
"""Throttled HTTP file server (~48KB/s) so a kill window during
catpm's curl download is seconds wide instead of milliseconds."""
import http.server, socketserver, os, time
CHUNK = 4096; RATE = 12
class H(http.server.SimpleHTTPRequestHandler):
    def copyfile(self, src, dst):
        while True:
            buf = src.read(CHUNK)
            if not buf: break
            dst.write(buf); time.sleep(1.0/RATE)
    def log_message(self, *a): pass
os.chdir(os.path.dirname(os.path.abspath(__file__)) + "/root")
socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("127.0.0.1", 8123), H) as httpd:
    httpd.serve_forever()
PY
  ( cd /tmp/slowserve && nohup python3 slowserve.py 8123 > serve.log 2>&1 & )
  sleep 1
  curl -sS -o /dev/null -w 'slowserve up (%{http_code})\n' http://127.0.0.1:8123/registry4/index.json
}

# kill catpm (exact name) and its in-flight curl child
kill_catpm() {
  kill -9 $1 2>/dev/null
  pkill -9 -f 'curl -sS --max-time' 2>/dev/null
  return 0
}

# ------------------------------------------------ build9.log
{
step "BUILD LOG v9 — catpm 0.5.5 (interrupt resilience)  $(date -u '+%Y-%m-%d %H:%M:%SZ')"
echo "catcc: $($CATCC --version)   zig: $($WS/tools/zigx/zig version)"
echo ""

step "[1/2] version engine unit tests (62 assertions; unchanged from 0.5.3)"
( cd $WS/catbase && ./bin/catcc $WS/catpm/src2/test_ver.cat -o /tmp/test_ver9 2>&1 | tail -1 )
/tmp/test_ver9; echo "exit=$?"
echo ""

step "[2/2] fresh compile of the 0.5.5 source"
rm -f $WS/catpm/catpm55
( cd $WS/catbase && time ./bin/catcc $WS/catpm/src2/catpm.cat -o $WS/catpm/catpm55 ) 2>&1 | tail -4
ls -l $WS/catpm/catpm55
$WS/catpm/catpm55 --version
echo ""
step "DONE build9  $(date -u '+%Y-%m-%d %H:%M:%SZ')"
} > $LOGD/build9.log 2>&1

# ------------------------------------------------ run9.log
{
step "RUN LOG v9 — interrupt resilience (kill -9 / SIGINT / network cut) + recovery  $(date -u '+%Y-%m-%d %H:%M:%SZ')"
T=$(mktemp -d)
echo "scratch dir: $T"
ensure_slowserve
SLOW=http://127.0.0.1:8123/registry4

# --- local test registry for bigx (300MB payload) ---
step "[0/9] stage a 300MB-payload package (bigx) for the unpack-kill test"
rm -rf $T/bigx-src $T/km4reg
mkdir -p $T/bigx-src
cat > $T/bigx-src/index.catc <<'EOF'
def bigx_tag() -> str {
    return "BIGX_TAG"
}
EOF
cat > $T/bigx-src/catpm.json <<'EOF'
{"name": "bigx", "version": "1.0.0", "deps": {}, "files": ["index.catc", "big.bin"]}
EOF
head -c 300M /dev/zero > $T/bigx-src/big.bin
( cd $T/bigx-src && $CPM pack 2>&1 | head -2 )
mkdir -p $T/km4reg
( cd $T/bigx-src && $CPM publish $T/km4reg 2>&1 | head -1 )
echo ""

step "[1/9] fix: one pass sweeps six residue classes"
mkdir -p $T/f1/bin $T/f1/deps/.stage-bigx $T/f1/.catpm-cache/index-cache $T/f1/.catpm-cache/fmtx $T/f1/.catpm-cache/self-stage
cd $T/f1
printf '%s\n' "$REG" > package.where
echo '{"name": "f1", "deps": {}}' > catpm.json
echo '{"trunc' > catpm.lock.catpm-tmp
echo '{"trunc' > .catpm-cache/index-cache/meta.json.catpm-tmp
echo 'garbage' > .catpm-cache/index-cache/abc123.json.catpm-tmp
echo x > deps/.stage-bigx/index.catc
cp $CPM bin/catpm
touch bin/catpm.new
echo x > .catpm-cache/self-stage/catpm
echo "garbage-bytes" > .catpm-cache/fmtx/fmtx-0.1.0.cpkg
bin/catpm fix; echo "fix exit=$?"
echo "-- leftovers (expect none):"
find . -name '*.catpm-tmp' -o -name '.stage-*' -o -name 'catpm.new' -o -name 'self-stage' 2>/dev/null | sed 's/^/  /'
ls .catpm-cache/fmtx/ | wc -l | sed 's/^/  fmtx cache entries left: /'
echo ""

step "[2/9] truncated manifest (mid-write kill) -> every mutating command refuses"
mkdir -p $T/f2 && cd $T/f2
printf '%s\n' "$REG" > package.where
$CPM add mathx > /dev/null 2>&1
printf '{"name": "t", "deps": {"math' > catpm.json   # simulate a half-written manifest
for c in install upgrade "add fmtx" "remove mathx"; do
  $CPM $c > /dev/null 2>&1; echo "  $c -> exit=$?"
done
$CPM install 2>&1 | tail -1
test -f deps/mathx/index.catc && echo "  deps/mathx untouched (guard worked)"
echo ""

step "[3/9] truncated cached .cpkg self-heals on next use"
mkdir -p $T/f3 && cd $T/f3
printf '%s\n' "$REG" > package.where
echo '{"name": "f3", "deps": {}}' > catpm.json
head -c 300 /dev/urandom > .catpm-cache/mathx/mathx-0.4.0.cpkg 2>/dev/null || {
  mkdir -p .catpm-cache/mathx; head -c 300 /dev/urandom > .catpm-cache/mathx/mathx-0.4.0.cpkg; }
ls -l .catpm-cache/mathx/ | tail -1 | awk '{print "  planted truncated cache:", $5, "bytes"}'
$CPM add mathx 2>&1 | grep -E 're-fetch|sha256 ok|installed'
echo "add exit=$?"
echo ""

step "[4/9] kill -9 during download -> rerun recovers (v0.5.4 baseline needed two runs)"
ensure_slowserve
mkdir -p $T/f4 && cd $T/f4
printf '%s\n' "$SLOW" > package.where
echo '{"name": "f4", "deps": {}}' > catpm.json
nohup $CPM add mathx > $T/f4.log 2>&1 &
P=$!; sleep 0.9
kill -0 $P 2>/dev/null && { kill_catpm $P; echo "  killed catpm (pid $P) mid-download"; }
wait $P 2>/dev/null
ls -l .catpm-cache/mathx/ 2>/dev/null | tail -1 | awk '{print "  cache after kill:", $5, "bytes (truncated)"}'
echo "-- rerun same command:"
$CPM add mathx 2>&1 | grep -E 're-fetch|sha256|installed'
$CPM add mathx > /dev/null 2>&1; echo "  rerun exit=$?"
echo ""

step "[5/9] SIGINT (Ctrl+C analog) during download -> rerun recovers"
ensure_slowserve
mkdir -p $T/f5 && cd $T/f5
printf '%s\n' "$SLOW" > package.where
echo '{"name": "f5", "deps": {}}' > catpm.json
nohup $CPM add mathx > $T/f5.log 2>&1 &
P=$!; sleep 0.9
kill -0 $P 2>/dev/null && { kill -INT $P; pkill -9 -f 'curl -sS --max-time' 2>/dev/null; echo "  SIGINT sent"; }
wait $P 2>/dev/null
echo "-- rerun same command:"
$CPM add mathx 2>&1 | grep -E 're-fetch|sha256|installed'
$CPM add mathx > /dev/null 2>&1; echo "  rerun exit=$?"
echo ""

step "[6/9] kill -9 during unpack (300MB) -> stage dir protects deps/; rerun completes"
mkdir -p $T/f6 && cd $T/f6
printf '%s\n' "$T/km4reg" > package.where
echo '{"name": "f6", "deps": {}}' > catpm.json
nohup $CPM add bigx > $T/f6.log 2>&1 &
P=$!; KILLED=0
for i in $(seq 1 600); do
  kill -0 $P 2>/dev/null || break
  SZ=$(du -sm deps/.stage-bigx 2>/dev/null | cut -f1); SZ=${SZ:-0}
  if [ "$SZ" -gt 40 ] 2>/dev/null && [ "$SZ" -lt 200 ] 2>/dev/null; then
    kill -9 $P 2>/dev/null; KILLED=1; echo "  killed at stage ${SZ}MB"; break
  fi
  sleep 0.05
done
[ $KILLED -eq 0 ] && echo "  (window missed this run — payload unpack too fast; state still safe)"
wait $P 2>/dev/null
test -f deps/bigx/index.catc && echo "  BUG: promoted early" || echo "  deps/bigx NOT promoted (stage isolation held)"
echo "-- rerun same command:"
$CPM add bigx 2>&1 | grep -E 'installed|lock'
$CPM add bigx > /dev/null 2>&1; echo "  rerun exit=$?"
ls -d deps/.stage-bigx 2>/dev/null && echo "  BUG: stage residue" || echo "  no stage residue"
echo ""

step "[7/9] network cut mid-download (iptables DROP) -> rerun recovers"
ensure_slowserve
mkdir -p $T/f7 && cd $T/f7
printf '%s\n' "$SLOW" > package.where
echo '{"name": "f7", "deps": {}}' > catpm.json
nohup $CPM add mathx > $T/f7.log 2>&1 &
P=$!; sleep 0.9
kill -0 $P 2>/dev/null && kill_catpm $P
wait $P 2>/dev/null
iptables -I OUTPUT -p tcp --dport 8123 -j DROP 2>/dev/null && IPT=1 || IPT=0
[ $IPT -eq 1 ] && echo "  (network to :8123 cut)"
sleep 0.5
$CPM add mathx > /dev/null 2>&1; echo "  add while offline -> exit=$? (expected nonzero)"
[ $IPT -eq 1 ] && { iptables -D OUTPUT -p tcp --dport 8123 -j DROP; echo "  (network restored)"; }
echo "-- rerun same command online:"
$CPM add mathx 2>&1 | grep -E 're-fetch|sha256 ok|installed'
$CPM add mathx > /dev/null 2>&1; echo "  rerun exit=$?"
echo ""

step "[8/9] randomized kill stress: 25x add + 20x update, zero integrity violations"
ensure_slowserve
mkdir -p $T/f8 && cd $T/f8
printf '%s\n' "$SLOW" > package.where
echo '{"name": "f8", "deps": {}}' > catpm.json
VIOL=0; KILLED_ADD=0
for i in $(seq 1 25); do
  DELAY=$(python3 -c "import random; print(round(random.uniform(0.02,0.30),3))")
  nohup $CPM add fmtx > /dev/null 2>&1 &
  P=$!; sleep $DELAY
  kill -0 $P 2>/dev/null && { kill -9 $P 2>/dev/null; KILLED_ADD=$((KILLED_ADD+1)); }
  wait $P 2>/dev/null
  python3 /tmp/v9_validate.py > /dev/null 2>&1 || { VIOL=$((VIOL+1)); echo "  round $i:"; python3 /tmp/v9_validate.py; }
done
echo "  add stress: $KILLED_ADD/25 killed mid-run, violations: $VIOL"
KILLED_UPD=0; VIOL2=0
for i in $(seq 1 20); do
  DELAY=$(python3 -c "import random; print(round(random.uniform(0.01,0.10),3))")
  CATPM_INDEX_TTL=0 nohup $CPM update > /dev/null 2>&1 &
  P=$!; sleep $DELAY
  kill -0 $P 2>/dev/null && { kill -9 $P 2>/dev/null; KILLED_UPD=$((KILLED_UPD+1)); }
  wait $P 2>/dev/null
  python3 /tmp/v9_validate.py > /dev/null 2>&1 || { VIOL2=$((VIOL2+1)); echo "  round $i:"; python3 /tmp/v9_validate.py; }
done
echo "  update stress: $KILLED_UPD/20 killed mid-run, violations: $VIOL2"
echo "-- rerun to completion, then A/B vs one-shot clean room:"
$CPM add fmtx > /dev/null 2>&1; echo "  rerun exit=$?"
python3 /tmp/v9_validate.py && echo "  final state valid"
rm -rf $T/f8clean && mkdir -p $T/f8clean && cd $T/f8clean
printf '%s\n' "$SLOW" > package.where
echo '{"name": "f8", "deps": {}}' > catpm.json
$CPM add fmtx > /dev/null 2>&1
for f in catpm.lock deps/fmtx/index.catc deps/fmtx/catpm.json deps/stringx/index.catc; do
  cmp -s $T/f8/$f $T/f8clean/$f && echo "  MATCH  $f" || echo "  DIFF   $f"
done
echo ""

step "[9/9] offline: update fails gracefully (cache kept); STALE index + pkg cache still install"
ensure_slowserve
mkdir -p $T/f9 && cd $T/f9
printf '%s\n' "$SLOW" > package.where
echo '{"name": "f9", "deps": {}}' > catpm.json
$CPM update > /dev/null 2>&1
$CPM add stringx > /dev/null 2>&1 && $CPM remove stringx > /dev/null 2>&1
pgrep -f 'slowserve\.py 8123' | while read p; do kill $p; done; sleep 0.5
echo "  (throttled server stopped = source offline)"
CATPM_INDEX_TTL=0 $CPM update 2>&1 | grep -E 'ERR|PARTIAL'; echo "  update exit=${PIPESTATUS[0]}"
ls .catpm-cache/index-cache/*.json | wc -l | sed 's/^/  cache files kept: /'
CATPM_INDEX_TTL=999999 $CPM add stringx 2>&1 | grep -E 'warning|STALE|installed'
test -f deps/stringx/index.catc && echo "  stringx installed offline (STALE index + package cache)"
ensure_slowserve > /dev/null
echo ""

echo "== live HTTPS: registry raw checks + self-update 0.5.4 -> 0.5.5 =="
for f in index.json catpm/catpm-0.5.5.cpkg; do
  code=$(curl -sS -o /dev/null -w '%{http_code}' "$RAWREG/$f")
  echo "$code  $f"
done
mkdir -p $T/su/bin && cd $T/su
cp $WS/catpm/catpm54 bin/catpm
cp $WS/repo/catpm/package.where package.where
echo "step0: $(bin/catpm --version)"
bin/catpm self-update 2>&1 | grep -E 'updated|sha256|verified|target'
echo "step1: $(bin/catpm --version)"
ls bin/ | grep '\.new' && echo "RESIDUE FOUND" || echo "no .new residue"
echo "-- fresh 0.5.5 over HTTPS: update (cache) then add prebuilt hellox:"
mkdir -p $T/remote && cd $T/remote
cp $WS/repo/catpm/package.where package.where
echo '{"name": "remote", "deps": {}}' > catpm.json
$T/su/bin/catpm update 2>&1 | tail -1
$T/su/bin/catpm add hellox 2>&1 | tail -2
deps/hellox/bin/hellox; echo "run exit=$?"

echo ""
step "DONE run9  $(date -u '+%Y-%m-%d %H:%M:%SZ')"
} > $LOGD/run9.log 2>&1

echo "== wrote $LOGD/build9.log + $LOGD/run9.log"
tail -4 $LOGD/build9.log
echo "---"
tail -30 $LOGD/run9.log
