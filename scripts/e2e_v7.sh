#!/bin/bash
# ============================================================
# e2e_v7.sh — catpm v0.5.3 walkthrough:
#   [1/3] 62-assertion unit tests + fresh catpm53 compile
#   [2/3] prebuilt-binary packages: hellox end-to-end +
#         the 7-case verification matrix (tamper/bad-bin/wrong-arch/
#         old-new compat both ways/source regression/self-update)
#   [3/3] live HTTPS: registry raw checks + self-update 0.5.2 -> 0.5.3
#         + clean-dir prebuilt install over the real registry
# Everything captured to logs/build7.log + logs/run7.log.
# Requires: catbase at $WS/catbase, registry4 local source, GitHub
# catpm-registry already carrying catpm-0.5.3.cpkg + hellox-1.0.0.cpkg.
# ============================================================
WS=/root/.hermes-web-ui/.ekko/workspace/default/person-main-f5f99dc5-b73a-417a-baf6-5b3f41382e6c
CATCC=$WS/catbase/bin/catcc
CPM=$WS/catpm/catpm53         # v0.5.3 (this release)
OLD=$WS/catpm/catpm52         # v0.5.2 (previous, for compat tests)
LOGD=$WS/repo/logs
REG=$WS/registry4             # local source registry (carries hellox 1.0.0)
RAWREG=https://raw.githubusercontent.com/monikalnbo/catpm-registry/main
mkdir -p $LOGD

step() { echo ""; echo "=================================================="; echo "== $*"; echo "=================================================="; }

# ------------------------------------------------ build7.log
{
step "BUILD LOG v7 — catpm 0.5.3 (prebuilt packages release)  $(date -u '+%Y-%m-%d %H:%M:%SZ')"
echo "catcc: $($CATCC --version)   zig: $($WS/tools/zigx/zig version)"
echo ""

step "[1/3] version engine unit tests (62 assertions; unchanged from 0.5.2)"
( cd $WS/catbase && ./bin/catcc $WS/catpm/src2/test_ver.cat -o /tmp/test_ver7 2>&1 | tail -1 )
/tmp/test_ver7; echo "exit=$?"
echo ""

step "[2/3] fresh compile of the 0.5.3 source"
rm -f $WS/catpm/catpm53
( cd $WS/catbase && time ./bin/catcc $WS/catpm/src2/catpm.cat -o $WS/catpm/catpm53 ) 2>&1 | tail -4
ls -l $WS/catpm/catpm53
$WS/catpm/catpm53 --version
echo ""

step "[3/3] package + publish to local registry4 (source snapshot for the diff)"
cd $WS/pkgsrc/hellox && rm -rf dist
$CPM pack 2>&1 | tail -3
$CPM publish $REG 2>&1 | tail -3
python3 -c "
import json
d = json.load(open('$REG/index.json'))
e = d['packages']['hellox']['1.0.0']
print('hellox index entry carries bin fingerprint:')
print(' ', json.dumps(e['bin'], sort_keys=True))
print('note: bin{path,os,arch,sha256} is OPTIONAL — old catpm ignores it,')
print('new catpm tolerates its absence (pure source path).')
"
echo ""
step "DONE build7  $(date -u '+%Y-%m-%d %H:%M:%SZ')"
} > $LOGD/build7.log 2>&1

# ------------------------------------------------ run7.log
{
step "RUN LOG v7 — prebuilt packages + verification matrix  $(date -u '+%Y-%m-%d %H:%M:%SZ')"
T=$(mktemp -d)
echo "scratch dir: $T"

step "[1/8] prebuilt install end-to-end (clean dir, no catcc involved)"
mkdir -p $T/f1 && cd $T/f1
printf '%s\n' "$REG" > package.where
cat > catpm.json <<'EOF'
{"name": "f1", "deps": {}}
EOF
$CPM add hellox 2>&1; echo "add exit=$?"
ls -l deps/hellox/bin/hellox | awk '{print "mode+size:", $1, $5}'
echo "-- direct run of the installed prebuilt (no compile step anywhere):"
deps/hellox/bin/hellox; echo "run exit=$?"
echo "-- installed binary hash vs publisher's:"
sha256sum deps/hellox/bin/hellox $WS/pkgsrc/hellox/bin/hellox | awk '{print $1}' | sort -u | wc -l | sed 's/^/distinct hashes (want 1): /'
echo ""

step "[2/8] sha256 tamper intercepted (junk appended to .cpkg, index unchanged)"
mkdir -p $T/tamper && cp -r $REG/. $T/tamper/
printf 'JUNK' >> $T/tamper/hellox/hellox-1.0.0.cpkg
mkdir -p $T/f2 && cd $T/f2
printf '%s\n' "$T/tamper" > package.where
cat > catpm.json <<'EOF'
{"name": "f2", "deps": {}}
EOF
$CPM add hellox 2>&1 | tail -3
$CPM add hellox >/dev/null 2>&1; echo "add exit=$?"
ls deps 2>/dev/null || echo "(no deps/ — gate held, nothing installed)"
echo ""

step "[3/8] broken prebuilt rejected (text file with exec bit, no ELF no shebang)"
mkdir -p $T/badsrc/bin && cd $T/badsrc
cp $WS/pkgsrc/hellox/index.catc .
sed -i 's/hello 1.0.0/hello 0.9.0/' index.catc
cat > catpm.json <<'EOF'
{"name": "hellox", "version": "0.9.0", "deps": {}, "files": ["bin/hellox"]}
EOF
printf 'this is not an executable and has no shebang' > bin/hellox
chmod +x bin/hellox
$CPM pack >/dev/null 2>&1 && $CPM publish $T/tamper >/dev/null 2>&1
mkdir -p $T/f3 && cd $T/f3
printf '%s\n' "$T/tamper" > package.where
cat > catpm.json <<'EOF'
{"name": "f3", "deps": {}}
EOF
$CPM add 'hellox@0.9.0' 2>&1 | tail -3
$CPM add 'hellox@0.9.0' >/dev/null 2>&1; echo "add exit=$? (source installed; bin flagged not trusted)"
echo "why: sh's ENOEXEC fallback would 'run' the text and exec() still sees rc 0 —"
echo "so the check requires ELF magic or a #! shebang, deterministically."
echo ""

step "[4/8] wrong-arch ELF rejected (e_machine forged 62->183 aarch64)"
mkdir -p $T/arm8/bin && cd $T/arm8
cp $WS/pkgsrc/hellox/index.catc .
sed -i 's/hello 1.0.0/hello 0.8.0/' index.catc
cat > catpm.json <<'EOF'
{"name": "hellox", "version": "0.8.0", "deps": {}, "files": ["bin/hellox"]}
EOF
cp $WS/pkgsrc/hellox/bin/hellox bin/hellox
printf '\xb7\x00' | dd of=bin/hellox bs=1 seek=18 conv=notrunc 2>/dev/null
$CPM pack >/dev/null 2>&1 && $CPM publish $T/tamper >/dev/null 2>&1
mkdir -p $T/f4 && cd $T/f4
printf '%s\n' "$T/tamper" > package.where
cat > catpm.json <<'EOF'
{"name": "f4", "deps": {}}
EOF
$CPM add 'hellox@0.8.0' 2>&1 | tail -3
$CPM add 'hellox@0.8.0' >/dev/null 2>&1; echo "add exit=$?"
echo ""

step "[5/8] compat: OLD catpm 0.5.2 reads NEW index (with bin field)"
mkdir -p $T/f5 && cd $T/f5
printf '%s\n' "$REG" > package.where
cat > catpm.json <<'EOF'
{"name": "f5", "deps": {}}
EOF
$OLD add 'hellox@1.0.0' 2>&1 | tail -2
$OLD add 'hellox@1.0.0' >/dev/null 2>&1; echo "old-catpm add exit=$?"
ls -l deps/hellox/bin/hellox 2>/dev/null | awk '{print "mode:", $1, "(tar preserved the exec bit)"}'
echo ""

step "[6/8] compat: NEW catpm 0.5.3 reads OLD index (bin field stripped)"
mkdir -p $T/oldidx && cp -r $REG/. $T/oldidx/
python3 - <<PYEOF
import json
p = "$T/oldidx/index.json"
d = json.load(open(p))
del d['packages']['hellox']['1.0.0']['bin']
json.dump(d, open(p, 'w'), indent=1)
PYEOF
mkdir -p $T/f6 && cd $T/f6
printf '%s\n' "$T/oldidx" > package.where
cat > catpm.json <<'EOF'
{"name": "f6", "deps": {}}
EOF
$CPM add 'hellox@1.0.0' 2>&1 | tail -2
$CPM add 'hellox@1.0.0' >/dev/null 2>&1; echo "new-catpm old-index add exit=$?"
echo ""

step "[7/8] source packages regression (mathx stack compiles and runs)"
mkdir -p $T/f7 && cd $T/f7
printf '%s\n' "$REG" > package.where
cat > catpm.json <<'EOF'
{"name": "f7", "deps": {}}
EOF
$CPM add 'mathx@^0.2.0' 2>&1 | grep -E "installed|prebuilt"
cat > main.cat <<'EOF'
import ./deps/mathx/index.catc as mathx

def main() {
    print(mathx.fib(10))
}
EOF
( cd $WS/catbase && ./bin/catcc $T/f7/main.cat -o $T/f7/app ) 2>&1 | grep -c successful | sed 's/^/compiled: /'
$T/f7/app; echo "app exit=$? (fib(10)=55)"
echo ""

step "[8/8] live HTTPS: self-update 0.5.2 -> 0.5.3 + clean-dir prebuilt over GitHub"
for f in index.json catpm/catpm-0.5.3.cpkg hellox/hellox-1.0.0.cpkg; do
  code=$(curl -sS -o /dev/null -w '%{http_code}' "$RAWREG/$f")
  echo "$code  $f"
done
mkdir -p $T/su/bin && cd $T/su
cp $OLD bin/catpm
cp $WS/repo/catpm/package.where package.where
echo "step0: $(bin/catpm --version)"
bin/catpm self-update 2>&1 | grep -E 'updated|sha256|verified'
echo "step1: $(bin/catpm --version)"
ls bin/ | grep '\.new' && echo "RESIDUE FOUND" || echo "no .new residue"
echo "-- clean dir install of the prebuilt package over live HTTPS:"
mkdir -p $T/remote && cd $T/remote
cp $WS/repo/catpm/package.where package.where
cat > catpm.json <<'EOF'
{"name": "remote", "deps": {}}
EOF
$T/su/bin/catpm add hellox 2>&1 | tail -3
deps/hellox/bin/hellox; echo "run exit=$?"

echo ""
step "DONE run7  $(date -u '+%Y-%m-%d %H:%M:%SZ')"
} > $LOGD/run7.log 2>&1

echo "== wrote $LOGD/build7.log + $LOGD/run7.log"
tail -4 $LOGD/build7.log
echo "---"
tail -12 $LOGD/run7.log
