#!/usr/bin/env bash
# Replays bugs that got past the tests, to check that JiT would have caught them.
#   tests/jit-backtest.sh [--repo DIR]                  layer 1: fixed invariant checks (claude-setup's hook contract)
#   tests/jit-backtest.sh [--repo DIR] --layer 2 prepare   a worktree per row at its buggy (or clean) revision,
#                                                          for a session to run jit:run in; nothing later is visible there
#   tests/jit-backtest.sh [--repo DIR] --layer 2 score     score the reports those runs wrote
# Rows: tests/jit/benchmarks/<repo>.tsv (id buggy_rev fixed_rev paths what) and tests/jit/clean/<repo>.tsv
# (rev paths). The benchmarks for every repository live here, in claude-setup.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)" layer=1 step=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="$(cd "$2" && pwd)"; shift 2 ;;
    --layer) layer="$2"; step="${3:-}"; shift 3 || shift $# ;;
    *) echo "usage: $0 [--repo DIR] [--layer 2 prepare|score]" >&2; exit 2 ;;
  esac
done
name="$(basename "$repo")"
bench="$here/jit/benchmarks/$name.tsv" clean="$here/jit/clean/$name.tsv"
[ -f "$bench" ] || { echo "no benchmark for $name: $bench" >&2; exit 2; }
rows() { grep -v '^#' "$1" | grep -v '^$' || true; }
caught=0 total=0 alarms=0 cleans=0

if [ "$layer" = 1 ]; then
  [ "$name" = claude-setup ] || { echo "layer 1 is claude-setup's hook contract; other repositories name theirs in their JiT: line" >&2; exit 2; }
  work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
  contract() { rm -rf "$work/t"; mkdir -p "$work/t"; git -C "$repo" archive "$1" plugins | tar -x -C "$work/t"; "$here/hook-contract.sh" "$work/t/plugins" || true; }
  plugin() { sed -n 's#^plugins/\([^/]*\)/.*#\1#p' <<<"$1"; }
  while IFS=$'\t' read -r id buggy fixed paths _; do
    p="$(plugin "$paths")"
    if [ -z "$p" ]; then printf '%s n/a (not a plugin hook)\n' "$id"; continue; fi
    total=$((total + 1))
    if grep -q "^FAIL: $p:" <<<"$(contract "$buggy")"; then
      if grep -q "^FAIL: $p:" <<<"$(contract "$fixed")"; then printf '%s false-alarm (still fails at the fix %s)\n' "$id" "$fixed"; alarms=$((alarms + 1))
      else printf '%s caught at %s, passes at the fix %s\n' "$id" "$buggy" "$fixed"; caught=$((caught + 1)); fi
    else printf '%s missed at %s\n' "$id" "$buggy"; fi
  done < <(rows "$bench")
  while IFS=$'\t' read -r rev paths; do
    p="$(plugin "$paths")"; cleans=$((cleans + 1))
    if grep -q "^FAIL: $p:" <<<"$(contract "$rev")"; then printf 'clean %s false-alarm on %s\n' "$rev" "$p"; alarms=$((alarms + 1)); fi
  done < <(rows "$clean")
  printf 'layer 1: caught=%d/%d false_alarms=%d over %d clean commit(s)\n' "$caught" "$total" "$alarms" "$cleans"
  [ "$caught" = "$total" ] && [ "$alarms" = 0 ]
  exit
fi

# Layer 2: the generator and assessor are agents, so a session runs jit:run in each prepared worktree.
# A worktree is detached at the row's revision: jit.js takes that commit's parent as the base, and the
# generator sees nothing written after it (the fix, later commits). Memory is the one input it can't
# cut; run once with and once without passing environment facts to see how much they carry.
bt="$repo/.work/jit-backtest"
case "$step" in
  prepare)
    mkdir -p "$bt"
    while IFS=$'\t' read -r id buggy _; do
      git -C "$repo" worktree add -f --detach -q "$bt/$id" "$buggy" 2>/dev/null || true
      printf '%s\t%s\t%s\n' "$id" "$bt/$id" "$(git -C "$repo" log -1 --format=%s "$buggy")"
    done < <(rows "$bench")
    while IFS=$'\t' read -r rev _; do
      git -C "$repo" worktree add -f --detach -q "$bt/clean-$rev" "$rev" 2>/dev/null || true
      printf 'clean-%s\t%s\t%s\n' "$rev" "$bt/clean-$rev" "$(git -C "$repo" log -1 --format=%s "$rev")"
    done < <(rows "$clean")
    echo "Run the jit:run skill in each worktree above, giving the generator only that commit's message as intent; then: $0 --repo $repo --layer 2 score" ;;
  score)
    report() { local wt="$bt/$1"; [ -d "$wt" ] || return 0; cat "$wt/.work/jit/$(git -C "$wt" rev-parse HEAD)/report.json" 2>/dev/null || true; }
    ncatch() { node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>console.log(s?(JSON.parse(s).catches||[]).length:-1))'; }
    while IFS=$'\t' read -r id _; do
      n="$(report "$id" | ncatch)"; total=$((total + 1))
      if [ "$n" = -1 ]; then printf '%s not run\n' "$id"; elif [ "$n" -gt 0 ]; then printf '%s caught (%d)\n' "$id" "$n"; caught=$((caught + 1)); else printf '%s missed\n' "$id"; fi
    done < <(rows "$bench")
    while IFS=$'\t' read -r rev _; do
      n="$(report "clean-$rev" | ncatch)"
      if [ "$n" = -1 ]; then printf 'clean-%s not run\n' "$rev"; continue; fi
      cleans=$((cleans + 1)); [ "$n" -gt 0 ] && { printf 'clean-%s false-alarm (%d)\n' "$rev" "$n"; alarms=$((alarms + n)); }
    done < <(rows "$clean")
    printf 'layer 2: caught=%d/%d false_alarms=%d over %d clean commit(s)\n' "$caught" "$total" "$alarms" "$cleans" ;;
  *) echo "--layer 2 needs prepare or score" >&2; exit 2 ;;
esac
