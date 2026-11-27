#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
memjs="$repo/plugins/outerpale-mem/hooks/mem.js"
[ -f "$memjs" ] || { echo "no outerpale-mem hook"; exit 77; }
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

# A proposal whose name contains "error" (a memory about error handling) must still leave the outbox once uploaded.
ob="$work/h/.outerpale-mem/outbox"; mkdir -p "$ob"
f=20261127T1000-error-handling.md; touch "$ob/$f"
in="{\"tool_name\":\"mcp__Microsoft_365__sharepoint_upload_file\",\"tool_input\":{\"filename\":\"$f\"},\"tool_response\":\"File uploaded (90 bytes).\\nwebUrl: https://x/Claude/memory/demo/log/$f\"}"
(cd "$work" && HOME="$work/h" node "$memjs" uploaded <<<"$in")
[ ! -e "$ob/$f" ] || fail "a successful upload of $f stayed in the outbox"
out="$(cd "$work" && HOME="$work/h" node "$memjs" stop <<<'{"stop_hook_active":false}')"
[ -z "$out" ] || fail "the stop hook still blocked after the upload"
echo ok
