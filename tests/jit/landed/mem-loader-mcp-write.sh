#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
memjs="$repo/plugins/outerpale-mem/hooks/mem.js"
[ -f "$memjs" ] || { echo "no outerpale-mem hook"; exit 77; }
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

# The loader only reads: writes through the OneDrive connector (upload, delete) must be refused too,
# and its reads must not be.
for t in mcp__Microsoft_365__sharepoint_upload_file mcp__Microsoft_365__sharepoint_delete_item; do
  node -e '
    const h = require(process.argv[1]).hooks.PreToolUse;
    if (!h.some(e => new RegExp("^(?:" + e.matcher + ")$").test(process.argv[2]) && e.hooks.some(x => /mem\.js" guard/.test(x.command)))) process.exit(1);
  ' "$repo/plugins/outerpale-mem/hooks/hooks.json" "$t" || fail "the guard hook is not run for $t"
  out="$(cd "$work" && HOME="$work/h" node "$memjs" guard <<<"{\"agent_type\":\"outerpale-mem:loader\",\"tool_name\":\"$t\",\"tool_input\":{}}")"
  grep -q '"deny"' <<<"$out" || fail "the loader could call $t"
done
out="$(cd "$work" && HOME="$work/h" node "$memjs" guard <<<'{"agent_type":"outerpale-mem:loader","tool_name":"mcp__Microsoft_365__read_resource","tool_input":{}}')"
[ -z "$out" ] || fail "the loader could not read"
echo ok
