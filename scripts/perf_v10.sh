#!/bin/bash
# ============================================================
# perf_v10.sh — catpm v0.5.5 performance vs apt/cargo + before/
# after optimization deltas. All real wall-clock measurements,
# median of N samples (N labeled per scenario), fresh mktemp
# project per cold sample. Output -> logs/perf-final.log.
# Requires: catbase at $WS/catbase, catpm binaries catpm54
# (v0.5.4 baseline) + catpm55 (current), local registry at
# $WS/registry4, network for the HTTPS scenarios.
# ============================================================
WS=/root/.hermes-web-ui/.ekko/workspace/default/person-main-f5f99dc5-b73a-417a-baf6-5b3f41382e6c
CPM55=$WS/catpm/catpm55
CPM54=$WS/catpm/catpm54        # v0.5.4 baseline
REG=$WS/registry4
RAWREG=https://raw.githubusercontent.com/monikalnbo/catpm-registry/main
LOGD=$WS/repo/logs
mkdir -p $LOGD

step() { echo ""; echo "== $*"; }

run_n() { # run_n <n> <setup-fn> <cmd>  -> prints samples + median
  local n=$1 setup=$2 cmd=$3
  for i in $(seq 1 $n); do
    T=$(mktemp -d); ( cd $T; $setup >/dev/null 2>&1 )
    S=$(date +%s%N); ( cd $T; eval "$cmd" ) >/dev/null 2>&1; E=$(date +%s%N)
    echo $(( (E-S)/1000000 ))
    rm -rf $T
  done | sort -n | awk -v tag="$4" '{v[NR]=$1} END {printf "  %-42s median %5d ms (n=%d)\n", tag, v[int((NR+1)/2)], NR}'
}

setup_local() { printf '%s\n' "$REG" > package.where; echo '{"name": "b", "deps": {}}' > catpm.json; }
setup_raw()   { printf '%s\n' "$RAWREG" > package.where; echo '{"name": "b", "deps": {}}' > catpm.json; }

{
step "perf-final.log — catpm 0.5.5 (parallel prefetch + batch sha) vs baselines  $(date -u '+%Y-%m-%d %H:%M:%SZ')"
echo "method: median-of-N wall clock (date +%s%N); fresh mktemp project per cold sample"

step "[1] catpm cold install, 2-pkg closure (add mathx)"
run_n 7 setup_local "$CPM55 add mathx" "v0.5.5 local dir source"
run_n 5 setup_raw   "$CPM55 add mathx" "v0.5.5 HTTPS raw source"
run_n 7 setup_local "$CPM54 add mathx" "v0.5.4 local (baseline)"

step "[2] catpm 3-add 6-pkg closure, local source"
run_n 7 setup_local "$CPM55 add mathx; $CPM55 add fmtx; $CPM55 add loganx" "v0.5.5"
run_n 7 setup_local "$CPM54 add mathx; $CPM54 add fmtx; $CPM54 add loganx" "v0.5.4 (baseline)"

step "[3] reference: apt / cargo (run manually; see docs/perf.md for recorded numbers)"




step "done  $(date -u '+%Y-%m-%d %H:%M:%SZ')"
} | tee $LOGD/perf-final.log
