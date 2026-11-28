#!/usr/bin/env bash
# Gives a new GitHub repository its baseline before any code: the files in templates/repo/
# (CI, Dependabot, .gitattributes; no Claude setup), squash-only auto-merge, secret scanning
# with push protection, Dependabot, and a ruleset on main that requires CI's `ci` check.
#   ./new-repo.sh <name>     creates harry's <name> as a public repository, or updates its settings
# Run it where gh is signed in as you (PC or server). Safe to run again.
set -euo pipefail

name="${1:?usage: new-repo.sh <name>}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
full="$(gh api user --jq .login)/$name"

gh repo view "$full" >/dev/null 2>&1 || gh repo create "$full" --public
url="$(gh repo view "$full" --json url --jq .url)"

# The files go straight to main, before the ruleset exists. A repository with commits keeps its own.
if [ -z "$(git ls-remote --heads "$url")" ]; then
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  git -C "$work" init -q -b main
  cp -r "$here/templates/repo/." "$work/"
  git -C "$work" add -A
  git -C "$work" commit -q -m "Add the repository baseline"
  git -C "$work" push -q "$url" main
  echo "baseline files pushed to $full"
else
  echo "$full already has commits: baseline files not pushed"
fi

gh api -X PATCH "repos/$full" --input - >/dev/null <<'EOF'
{
  "allow_squash_merge": true,
  "allow_merge_commit": false,
  "allow_rebase_merge": false,
  "squash_merge_commit_title": "PR_TITLE",
  "squash_merge_commit_message": "PR_BODY",
  "delete_branch_on_merge": true,
  "allow_auto_merge": true,
  "security_and_analysis": {
    "secret_scanning": { "status": "enabled" },
    "secret_scanning_push_protection": { "status": "enabled" }
  }
}
EOF
gh api -X PUT "repos/$full/vulnerability-alerts"
gh api -X PUT "repos/$full/automated-security-fixes"

# integration_id 15368 is GitHub Actions: only its `ci` check counts, not a status anyone could post.
ruleset='{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "pull_request", "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false,
        "allowed_merge_methods": ["squash"] } },
    { "type": "required_status_checks", "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [{ "context": "ci", "integration_id": 15368 }] } }
  ]
}'
id="$(gh api "repos/$full/rulesets" --jq '.[] | select(.name == "main") | .id')"
if [ -n "$id" ]; then
  gh api -X PUT "repos/$full/rulesets/$id" --input - >/dev/null <<<"$ruleset"
else
  gh api -X POST "repos/$full/rulesets" --input - >/dev/null <<<"$ruleset"
fi
echo "$full: settings and the main ruleset applied"
