#!/usr/bin/env bash
# Tests for install.sh and cloud/setup.sh.
#   tests/test.sh          install.sh into a temporary HOME (any machine with bash and git)
#   tests/test.sh --vm     also runs cloud/setup.sh in a fresh ubuntu:24.04 container, as root,
#                          the way a cloud VM does (needs Docker)
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }
ok()   { pass=$((pass + 1)); printf 'ok: %s\n' "$*"; }

# A local git repository standing in for an upstream skill, so the test needs no network.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/skillsrc/sub/demo"
printf -- '---\nname: demo\ndescription: test skill\n---\n' > "$work/skillsrc/sub/demo/SKILL.md"
git -C "$work/skillsrc" init -q
git -C "$work/skillsrc" add .
git -C "$work/skillsrc" -c user.name=t -c user.email=t@t commit -q -m demo
git -C "$work/skillsrc" config uploadpack.allowAnySHA1InWant true
sha="$(git -C "$work/skillsrc" rev-parse HEAD)"
printf 'demo file://%s %s sub/demo\n' "$work/skillsrc" "$sha" > "$work/skills.lock"

run_install() { CLAUDE_HOME="$work/home/.claude" SKILLS_LOCK="$work/skills.lock" PLUGINS_LOCK=/dev/null "$repo/install.sh"; }

run_install > "$work/first.log"
cmp -s "$repo/CLAUDE.md" "$work/home/.claude/CLAUDE.md" || fail "CLAUDE.md not installed"
ok "CLAUDE.md installed"
[ -f "$work/home/.claude/skills/demo/SKILL.md" ] || fail "pinned skill not installed"
ok "pinned skill installed from its commit"
[ ! -e "$work/home/.claude/skills/demo/.git" ] || fail "skill copied with .git"
ok "skill copied without .git"

run_install > "$work/second.log"
grep -q 'CLAUDE.md up to date' "$work/second.log" || fail "second run reinstalled CLAUDE.md"
grep -q 'skill demo up to date' "$work/second.log" || fail "second run refetched the skill"
ok "second run changes nothing"

printf 'old\n' > "$work/home/.claude/CLAUDE.md"
run_install > "$work/third.log"
ls "$work/home/.claude"/CLAUDE.md.bak-* >/dev/null 2>&1 || fail "existing CLAUDE.md not backed up"
ok "a different CLAUDE.md is backed up before it is replaced"

printf 'bad file://%s %s no/such/path\n' "$work/skillsrc" "$sha" > "$work/bad.lock"
if CLAUDE_HOME="$work/home2" SKILLS_LOCK="$work/bad.lock" PLUGINS_LOCK=/dev/null "$repo/install.sh" > /dev/null 2>&1; then
  fail "a missing skill path did not fail the install"
fi
ok "a bad skill entry fails the install"

# Plugins go through the claude CLI. A stand-in claude records what it was asked to do.
mkdir -p "$work/bin"
printf '#!/usr/bin/env bash\necho "$*" >> "%s/claude.log"\n' "$work" > "$work/bin/claude"
chmod +x "$work/bin/claude"
printf 'demo@market owner/market-repo\n' > "$work/plugins.lock"
PATH="$work/bin:$PATH" CLAUDE_HOME="$work/home3" SKILLS_LOCK=/dev/null PLUGINS_LOCK="$work/plugins.lock" "$repo/install.sh" > /dev/null
grep -qx 'plugin marketplace add owner/market-repo' "$work/claude.log" || fail "marketplace not added"
grep -qx 'plugin install demo@market --scope user' "$work/claude.log" || fail "plugin not installed"
ok "a listed plugin is installed through the claude CLI at user scope"

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$repo/install.sh" "$repo/cloud/setup.sh" "$repo/tests/test.sh" || fail "shellcheck"
  ok "shellcheck clean"
else
  printf 'skip: shellcheck not installed\n'
fi

if [ "${1:-}" = "--vm" ]; then
  docker run --rm -v "$repo:/src:ro" ubuntu:24.04 bash -c '
    set -e
    apt-get update -qq >/dev/null && apt-get install -y -qq git ca-certificates curl nodejs npm >/dev/null
    cp -r /src /opt/claude-setup
    mkdir -p /tmp/bin
    printf "#!/usr/bin/env bash\necho \"\$*\" >> /tmp/claude.log\n" > /tmp/bin/claude
    chmod +x /tmp/bin/claude
    sed -i "s|^ENV_PLUGINS=\"$|ENV_PLUGINS=\"envplug@m owner/m|" /opt/claude-setup/cloud/setup.sh
    PATH="/tmp/bin:$PATH" SETUP_SRC=/opt/claude-setup bash /opt/claude-setup/cloud/setup.sh
    grep -qx "plugin install envplug@m --scope user" /tmp/claude.log
    echo "vm: a plugin listed in the setup script was installed"
    cmp -s /opt/claude-setup/CLAUDE.md /root/.claude/CLAUDE.md
    grep -q "^claude-setup" /root/.claude/claude-setup.status
    grep -q "^warnings: none" /root/.claude/claude-setup.status
    command -v pnpm >/dev/null
    shellcheck /opt/claude-setup/install.sh /opt/claude-setup/cloud/setup.sh /opt/claude-setup/tests/test.sh
    echo "vm: shellcheck clean, pnpm on PATH, no setup warnings"
    echo "vm: setup.sh ran as root and installed /root/.claude/CLAUDE.md"
  ' || fail "cloud/setup.sh in ubuntu:24.04"
  ok "cloud/setup.sh works in a fresh ubuntu:24.04 container"
fi

printf '%d checks passed\n' "$pass"
