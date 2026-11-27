#!/usr/bin/env bash
# Layer 1 of JiT for claude-setup: every plugin's SessionStart hook, found from its hooks.json,
# runs in the three shapes a session can start in: one repository, a non-git folder holding two,
# and a folder holding none. In every shape it must exit 0, and output that starts with "{" must be
# JSON. A hook that names the repository when there is one must name both when there are two.
#   tests/hook-contract.sh [plugins-dir]     default: this repository's plugins/
# Prints one line per hook, ok or FAIL, and exits 1 if any hook breaks the contract.
set -euo pipefail

plugins="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/plugins}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }
broken=0

mkdir -p "$work/one" "$work/two" "$work/none"
git init -q "$work/one/demo"
git init -q "$work/two/demo"
git init -q "$work/two/other"

# Each SessionStart command, with the plugin folder it runs from.
for json in "$plugins"/*/hooks/hooks.json; do
  [ -f "$json" ] || continue
  root="$(dirname "$(dirname "$json")")"
  node -e 'const h=require(process.argv[1]).hooks||{};for(const g of h.SessionStart||[])for(const x of g.hooks||[])if(x.type==="command")console.log(x.command)' "$json" |
    while IFS= read -r command; do printf '%s\t%s\n' "$root" "$command"; done
done > "$work/hooks.tsv"
[ -s "$work/hooks.tsv" ] || fail "no SessionStart hooks found under $plugins"

run_in() { # shape-dir root command -> stdout; fails on a non-zero exit
  local home; home="$(mktemp -d "$work/home.XXXX")"
  (cd "$1" && printf '{"cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$1" |
    HOME="$home" CLAUDE_PLUGIN_ROOT="$2" bash -c "$3")
}

while IFS=$'\t' read -r root command; do
  name="$(basename "$root")"
  why=""
  for shape in one/demo two none; do
    if ! out="$(run_in "$work/$shape" "$root" "$command")"; then why="exits non-zero in the '$shape' shape"; break; fi
    if [[ "$out" == \{* ]] && ! node -e 'JSON.parse(process.argv[1])' "$out" 2>/dev/null; then why="output in the '$shape' shape starts with { but is not JSON"; break; fi
    printf '%s' "$out" > "$work/$name.${shape%%/*}.out"
  done
  if [ -z "$why" ] && grep -q 'demo' "$work/$name.one.out"; then
    for r in demo other; do grep -q "$r" "$work/$name.two.out" || { why="names the repository when there is one, but not '$r' when a non-git folder holds two"; break; }; done
  fi
  if [ -n "$why" ]; then printf 'FAIL: %s: %s\n' "$name" "$why"; broken=1
  else printf 'ok: %s SessionStart hook keeps the contract in all three shapes\n' "$name"; fi
done < "$work/hooks.tsv"
exit "$broken"
