#!/bin/bash
# ============================================================
# e2e_v5.sh — catpm v0.5 self-update walkthrough:
#   [1/5] unit tests + v0.5 compile (self-update binary)
#   [2/5] catpm as a package: pack/publish 0.4.0 + 0.5.0 + 0.5.1
#   [3/5] upgrade path in an isolated prefix (local source)
#   [4/5] failure scenarios: unreachable source, sha256 tamper,
#         broken candidate — old binary must survive all
#   [5/5] live HTTPS self-update from the catpm-registry GitHub repo
# Everything captured to logs/build5.log + logs/selfupdate5.log.
# ============================================================
WS=/root/.hermes-web-ui/.ekko/workspace/default/person-main-f5f99dc5-b73a-417a-baf6-5b3f41382e6c
CATCC=$WS/catbase/bin/catcc
CPM=$WS/catpm/catpm5          # v0.5.0 (the self-update-capable build)
LOGD=$WS/logs
REG=$WS/registry4
RAWREG=https://raw.githubusercontent.com/monikalnbo/catpm-registry/main
mkdir -p $LOGD

step() { echo ""; echo "=================================================="; echo "== $*"; echo "=================================================="; }

# ------------------------------------------------ build5.log
{
step "BUILD LOG v5 — catpm 0.5.0 (self-update)  $(date -u '+%Y-%m-%d %H:%M:%SZ')"
echo "catcc: $($CATCC --version)   zig: $($WS/tools/zigx/zig version)"
echo ""

step "[1/4] version engine unit tests (44 assertions, unchanged from v0.4)"
( cd $WS/catbase && ./bin/catcc $WS/catpm/src2/test_ver.cat -o /tmp/test_ver5 2>&1 | tail -1 )
/tmp/test_ver5; echo "exit=$?"
echo ""

step "[2/4] catpm v0.5.0 -> native binary (fresh compile)"
t0=$(date +%s.%N)
( cd $WS/catbase && ./bin/catcc $WS/catpm/src2/catpm.cat -o $WS/catpm/catpm5 2>&1 | tail -1 )
t1=$(date +%s.%N)
echo "compile wall=$(echo "$t1 $t0" | awk '{printf "%.2f", $1-$2}') s"
ls -la $WS/catpm/catpm5 | awk '{print "catpm5 binary:", $5, "bytes"}'
$CPM --version
echo ""

step "[3/4] catpm 0.5.1 (target-of-update build, same source + version bump)"
sed 's/CATPM_VERSION: str = "0.5.0"/CATPM_VERSION: str = "0.5.1"/' $WS/catpm/src2/catpm.cat > /tmp/build51/main.cat
( cd $WS/catbase && ./bin/catcc /tmp/build51/main.cat -o /tmp/build51/catpm 2>&1 | tail -1 )
/tmp/build51/catpm --version
echo ""

step "[4/4] catpm published AS A PACKAGE (self-hosting)"
python3 - <<PY
import json
d = json.load(open("$REG/index.json"))
print("registry4 packages:", len(d["packages"]))
print("catpm versions:", json.dumps(d["packages"]["catpm"], indent=1))
PY
curl -sS "$RAWREG/index.json" | python3 -c "import json,sys; d=json.load(sys.stdin); print('GitHub raw catpm versions:', sorted(d['packages']['catpm'].keys()))"
} > $LOGD/build5.log 2>&1

# ------------------------------------------------ selfupdate5.log
{
step "SELF-UPDATE LOG v5  $(date -u '+%Y-%m-%d %H:%M:%SZ')"
echo "mechanism: catpm is a normal package (name 'catpm', prebuilt bin/catpm inside);"
echo "self-update resolves via package.where sources -> sha256 gate -> candidate"
echo "smoke test (--version must report the target) -> mv (rename, atomic)."
echo ""

# ================= [1/5] upgrade path (local source)
step "[1/5] UPGRADE PATH (isolated prefix, local registry4 source)"
rm -rf /tmp/prefix5 && mkdir -p /tmp/prefix5/bin
cp $CPM /tmp/prefix5/bin/catpm
echo "$REG" > /tmp/prefix5/where5
cd /tmp/prefix5
echo "\$ bin/catpm --version   (BEFORE)"
bin/catpm --version | sed 's/^/  /'
echo ""
echo "\$ catpm self-update"
CATPM_WHERE=/tmp/prefix5/where5 bin/catpm self-update 2>&1 | sed 's/^/  /'; echo "  exit=$?"
echo ""
echo "\$ bin/catpm --version   (AFTER)"
bin/catpm --version | sed 's/^/  /'
echo ""
echo "\$ ls bin/   (no .new / stage leftovers)"
ls bin/ | sed 's/^/  /'
echo ""
echo "\$ catpm self-update   (idempotent re-run)"
CATPM_WHERE=/tmp/prefix5/where5 bin/catpm self-update 2>&1 | sed 's/^/  /'; echo "  exit=$?"
echo ""
echo "\$ catpm self-update @0.4.0   (explicit pinned downgrade)"
CATPM_WHERE=/tmp/prefix5/where5 bin/catpm self-update @0.4.0 2>&1 | sed 's/^/  /'; echo "  exit=$?"
bin/catpm --version | sed 's/^/  after: /'
echo "  (note: 0.4.0 predates self-update; upgrading back from it needs the"
echo "   install.sh/registry route — same as an ancient apt needing apt-get first)"
cp $CPM /tmp/prefix5/bin/catpm   # restore 0.5.0 for the failure tests
echo ""
echo "\$ catpm self-update @9.9.9   (unsatisfiable spec)"
CATPM_WHERE=/tmp/prefix5/where5 bin/catpm self-update @9.9.9 2>&1 | sed 's/^/  /'; echo "  exit=$?"
bin/catpm --version | sed 's/^/  still: /'

# ================= [2/5] failure: unreachable source
step "[2/5] FAILURE: unreachable source (old binary must survive, no half-replace)"
echo "/tmp/nonexistent-reg-xyz" > /tmp/prefix5/where_bad
CATPM_WHERE=/tmp/prefix5/where_bad bin/catpm self-update 2>&1 | sed 's/^/  /'; echo "  exit=$?"
bin/catpm --version | sed 's/^/  binary still: /'
ls bin/ | sed 's/^/  bin\/: /'

# ================= [3/5] failure: sha256 tamper
step "[3/5] FAILURE: sha256 tamper (index sha zeroed; download must be rejected)"
rm -rf /tmp/tamper5 && mkdir -p /tmp/tamper5
cp -r $REG/catpm /tmp/tamper5/
python3 - <<'PY'
import json
d = json.load(open("/root/.hermes-web-ui/.ekko/workspace/default/person-main-f5f99dc5-b73a-417a-baf6-5b3f41382e6c/registry4/index.json"))
d["packages"] = {"catpm": d["packages"]["catpm"]}
d["packages"]["catpm"]["0.5.1"]["sha256"] = "0" * 64
json.dump(d, open("/tmp/tamper5/index.json", "w"))
PY
echo "/tmp/tamper5" > /tmp/prefix5/where_tamper
cd /tmp/prefix5 && rm -rf .catpm-cache
CATPM_WHERE=/tmp/prefix5/where_tamper bin/catpm self-update 2>&1 | sed 's/^/  /'; echo "  exit=$?"
bin/catpm --version | sed 's/^/  binary still: /'
ls bin/ | sed 's/^/  bin\/: /'

# ================= [4/5] failure: broken candidate binary
step "[4/5] FAILURE: broken candidate (cpkg with garbage bin/catpm but valid sha)"
rm -rf /tmp/broken5 && mkdir -p /tmp/broken5/catpm
cd /tmp/broken5 && mkdir -p stage/bin
echo "not an elf binary" > stage/bin/catpm
printf '{"name":"catpm","version":"0.5.1","catpm":"0.5.1","deps":{}}\n' > stage/catpm.json
printf 'x\n' > stage/index.catc
tar -czf catpm/catpm-0.5.1.cpkg -C stage .
python3 - <<'PY'
import json, hashlib
h = hashlib.sha256(open("/tmp/broken5/catpm/catpm-0.5.1.cpkg", "rb").read()).hexdigest()
json.dump({"packages": {"catpm": {"0.5.1": {"path": "catpm/catpm-0.5.1.cpkg", "sha256": h, "deps": {}}}}},
          open("/tmp/broken5/index.json", "w"))
PY
echo "/tmp/broken5" > /tmp/prefix5/where_broken
cd /tmp/prefix5 && rm -rf .catpm-cache
CATPM_WHERE=/tmp/prefix5/where_broken bin/catpm self-update 2>&1 | sed 's/^/  /'; echo "  exit=$?"
bin/catpm --version | sed 's/^/  binary still: /'
ls bin/ | sed 's/^/  bin\/: /'

# ================= [5/5] live HTTPS self-update
step "[5/5] LIVE: self-update over HTTPS from github.com/monikalnbo/catpm-registry"
rm -rf /tmp/live5 && mkdir -p /tmp/live5/bin
cp $CPM /tmp/live5/bin/catpm
cp $WS/catpm/package.where /tmp/live5/bin/package.where
cd /tmp/live5
echo "--- package.where (default, ships next to binary) ---"
sed 's/^/  /' bin/package.where
echo ""
echo "\$ bin/catpm self-update   (no env vars; pure GitHub raw)"
bin/catpm --version | sed 's/^/  before: /'
bin/catpm self-update 2>&1 | sed 's/^/  /'; echo "  exit=$?"
bin/catpm --version | sed 's/^/  after:  /'
ls bin/ | sed 's/^/  bin\/: /'
echo ""
echo "--- and the updated binary keeps working for normal ops ---"
rm -rf /tmp/live5/proj && mkdir /tmp/live5/proj && cd /tmp/live5/proj
../bin/catpm init >/dev/null
../bin/catpm add randx 2>&1 | grep -E "resolved|installed" | sed 's/^/  /'
echo ""
echo "--- raw reachability (catpm packages on the registry repo) ---"
for f in catpm/catpm-0.4.0.cpkg catpm/catpm-0.5.0.cpkg catpm/catpm-0.5.1.cpkg index.json; do
  C=$(curl -sS -o /dev/null -w "%{http_code}" "$RAWREG/$f"); echo "  $C  $f"
done

echo ""
echo "END OF SELF-UPDATE LOG v5"
} > $LOGD/selfupdate5.log 2>&1

echo "wrote $LOGD/build5.log and $LOGD/selfupdate5.log"
