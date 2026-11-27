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

# install.sh records where this repository is, so the outerpale-startup hook can find projects/.
[ "$(cat "$work/home/.claude/claude-setup-dir")" = "$repo" ] || fail "claude-setup-dir not recorded"
ok "install.sh records where claude-setup is"

# The outerpale-startup SessionStart hook fetches a repository's project CLAUDE.md.
hook="$repo/plugins/outerpale-startup/hooks/session-start.sh"
mkdir -p "$work/hookhome/.claude" "$work/store/projects"
printf '%s' "$work/store" > "$work/hookhome/.claude/claude-setup-dir"
printf '# demo project\n' > "$work/store/projects/demo.md"
git init -q "$work/demo"
out="$(cd "$work/demo" && HOME="$work/hookhome" bash "$hook")"
cmp -s "$work/store/projects/demo.md" "$work/demo/CLAUDE.md" || fail "hook did not copy projects/demo.md"
grep -qx '/CLAUDE.md' "$work/demo/.git/info/exclude" || fail "hook did not exclude CLAUDE.md from git"
[ -z "$(git -C "$work/demo" status --porcelain)" ] || fail "fetched CLAUDE.md shows in git status"
grep -q '# demo project' <<<"$out" || fail "hook did not hand the fetched file to Claude"
ok "hook copies projects/<repo>.md to ./CLAUDE.md, kept out of git"
out="$(cd "$work/demo" && HOME="$work/hookhome" bash "$hook")"
[ -z "$out" ] || fail "hook spoke when ./CLAUDE.md already exists"
[ "$(grep -c '/CLAUDE.md' "$work/demo/.git/info/exclude")" = 1 ] || fail "exclude line repeated"
ok "hook leaves an existing ./CLAUDE.md alone"
grep -qx '/.work/' "$work/demo/.git/info/exclude" || fail "hook did not keep .work/ out of git"
git init -q "$work/committed" && printf '# own\n' > "$work/committed/CLAUDE.md"
(cd "$work/committed" && HOME="$work/hookhome" bash "$hook") >/dev/null
grep -qx '/.work/' "$work/committed/.git/info/exclude" || fail ".work/ not excluded in a repository with its own CLAUDE.md"
mkdir -p "$work/committed/.work/egm" && touch "$work/committed/.work/egm/draft.md"
[ "$(git -C "$work/committed" status --porcelain)" = "?? CLAUDE.md" ] || fail ".work/ shows in git status"
ok "hook keeps .work/ (scratch, EGM files, reviews) out of git in every repository"
git init -q "$work/fresh"
out="$(cd "$work/fresh" && HOME="$work/hookhome" bash "$hook")"
[ ! -e "$work/fresh/CLAUDE.md" ] || fail "hook wrote a CLAUDE.md nobody has written"
grep -q 'projects/fresh.md' <<<"$out" || fail "hook did not say which file it looked for"
grep -q 'AskUserQuestion' <<<"$out" || fail "hook did not ask to write the missing file"
ok "a missing project file is reported, with a question to write it"
out="$(cd "$work" && HOME="$work/hookhome" bash "$hook")"
[ -z "$out" ] || fail "hook spoke outside a git repository"
ok "hook is silent outside a git repository"

# The suggestion hook: a correction, or a project command run three times, prompts Claude to offer
# a one-line addition to the project CLAUDE.md. Silent otherwise.
suggest="$repo/plugins/outerpale-startup/hooks/suggest.js"
sug() { (cd "$work/demo" && HOME="$work/sughome" node "$suggest" "$1" <<<"$2"); }
out="$(sug prompt '{"session_id":"q1","prompt":"No, we always use pnpm here, not npm"}')"
grep -q 'corrected' <<<"$out" || fail "a correction did not prompt a suggestion"
grep -q 'project-claude-md' <<<"$out" || fail "the suggestion did not name the skill"
[ -z "$(sug prompt '{"session_id":"q1","prompt":"now add a footer link"}')" ] || fail "an ordinary prompt prompted a suggestion"
[ -z "$(sug prompt '{"session_id":"q1","prompt":"<task-notification>no, wrong</task-notification>"}')" ] || fail "a notification counted as a correction"
ok "a correction prompts a CLAUDE.md suggestion; ordinary prompts and notifications don't"
bash_call='{"session_id":"q2","tool_name":"Bash","tool_input":{"command":"cd /x && pnpm test --filter web"}}'
for _ in 1 2; do [ -z "$(sug bash "$bash_call")" ] || fail "spoke before the third run"; done
out="$(sug bash "$bash_call")"
grep -q 'pnpm test --filter web' <<<"$out" || fail "a third run of a command did not prompt a suggestion"
[ -z "$(sug bash "$bash_call")" ] || fail "the same command was suggested twice"
for _ in 1 2 3; do o="$(sug bash '{"session_id":"q2","tool_name":"Bash","tool_input":{"command":"git status"}}')"; done
[ -z "$o" ] || fail "an everyday command was suggested"
for _ in 1 2 3; do o="$(sug bash '{"session_id":"q2","tool_name":"Bash","tool_input":{"command":"python3 - <<EOF\nprint(1)\nEOF"}}')"; done
[ -z "$o" ] || fail "an inline script was suggested as a project command"
# shellcheck disable=SC2016 # literal backticks, as a CLAUDE.md writes a command
printf 'Run `make check` before pushing.\n' >> "$work/demo/CLAUDE.md"
for _ in 1 2 3; do o="$(sug bash '{"session_id":"q3","tool_name":"Bash","tool_input":{"command":"make check"}}')"; done
[ -z "$o" ] || fail "a command already in CLAUDE.md was suggested"
ok "a project command run three times is suggested once; everyday and known commands aren't"
for p in 'no thats okay' 'No, that'"'"'s fine' 'dont worry about the size limit, always onedrive' 'actually let'"'"'s add a footer'; do
  [ -z "$(sug prompt "{\"session_id\":\"q4\",\"prompt\":\"$p\"}")" ] || fail "\"$p\" counted as a correction"
done
for p in 'That'"'"'s wrong, use the v2 endpoint' 'I told you the tests live in spec/' 'no, you keep forgetting the lockfile'; do
  grep -q 'corrected' <<<"$(sug prompt "{\"session_id\":\"q4\",\"prompt\":\"$p\"}")" || fail "\"$p\" was not seen as a correction"
done
ok "agreement and ordinary instructions are not corrections; clear corrections are"

# Magister, a plugin of its own: design and decision moments prompt Claude to consider it, in the background.
mag="$repo/plugins/magister/hooks/magister.js"
mg() { (cd "$work/demo" && HOME="$work/maghome" node "$mag" "$1" <<<"$2"); }
out="$(mg prompt '{"session_id":"c1","prompt":"I think we should design the settings page as a two-column layout"}')"
grep -q 'magister:magister' <<<"$out" || fail "a design moment did not mention Magister"
grep -q 'background' <<<"$out" || fail "Magister was not to run in the background"
[ -z "$(mg prompt '{"session_id":"c1","prompt":"run the tests"}')" ] || fail "an ordinary prompt mentioned Magister"
[ -z "$(mg prompt '{"session_id":"c1","prompt":"<task-notification>design review done</task-notification>"}')" ] || fail "a notification counted as a design moment"
[ -z "$(sug prompt '{"session_id":"c1","prompt":"I think we should design the settings page"}')" ] || fail "outerpale-startup still speaks for Magister"
ok "a design or decision moment suggests Magister, in the background; ordinary prompts and outerpale-startup don't"

# Magister writes only to .work/ and its outbox, and runs no shell commands.
mw() { printf '{"agent_type":"magister:magister","cwd":"%s","tool_name":"%s","tool_input":{"file_path":"%s","command":"ls"}}' "$work/demo" "$1" "$2"; }
grep -q '"deny"' <<<"$(mg guard "$(mw Write "$work/demo/src/app.ts")")" || fail "Magister could write into the code"
grep -q '"deny"' <<<"$(mg guard "$(mw Bash '')")" || fail "Magister could run a shell command"
[ -z "$(mg guard "$(mw Write "$work/demo/.work/alt/settings-v2.html")")" ] || fail "Magister could not write into .work/"
[ -z "$(mg guard "$(mw Write "$work/maghome/.magister/outbox/2026-11-27-x.md")")" ] || fail "Magister could not write its outbox"
[ -z "$(mg guard "{\"cwd\":\"$work/demo\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$work/demo/src/app.ts\"}}")" ] || fail "the main session was restricted"
out="$(cd "$work/demo" && HOME="$work/maghome" MAGISTER_HOME="$work/evalhome" node "$mag" guard <<<"$(mw Write "$work/evalhome/outbox/x.md")")"
[ -z "$out" ] || fail "MAGISTER_HOME did not move the outbox"
ok "Magister writes only to .work/ and its outbox (MAGISTER_HOME moves it), and runs no shell; the main session is unaffected"

# Unsent findings from an earlier session are flagged at session start, wherever it is.
mkdir -p "$work/maghome/.magister/outbox" && touch "$work/maghome/.magister/outbox/2026-11-27-a.md"
grep -q '1 Magister finding' <<<"$(mg session-start '{}')" || fail "an unsent finding was not flagged at session start"
rm "$work/maghome/.magister/outbox/2026-11-27-a.md"
[ -z "$(mg session-start '{}')" ] || fail "an empty outbox was mentioned"
ok "unsent Magister findings are flagged at session start"
touch "$work/maghome/.magister/outbox/2026-11-27-b.md"
up() { printf '{"tool_name":"mcp__Microsoft_365__sharepoint_upload_file","tool_input":{"filename":"%s"},"tool_response":"%s"}' "$1" "$2"; }
mg uploaded "$(up 2026-11-27-b.md 'Error: rate limited')"
[ -f "$work/maghome/.magister/outbox/2026-11-27-b.md" ] || fail "a failed upload removed the outbox file"
mg uploaded "$(up 2026-11-27-b.md 'File uploaded (12 bytes).\nwebUrl: https://x')"
[ ! -e "$work/maghome/.magister/outbox/2026-11-27-b.md" ] || fail "a successful upload left the outbox file"
ok "a successful OneDrive upload clears its outbox file; a failed one keeps it"

# outerpale-mem: memory kept in OneDrive, loaded at session start, proposals uploaded before the session ends.
memjs="$repo/plugins/outerpale-mem/hooks/mem.js"
mm() { (cd "$1" && HOME="$work/memhome" node "$memjs" "$2" <<<"$3"); }
out="$(mm "$work/demo" session-start '{}')"
grep -q 'outerpale-mem:loader' <<<"$out" || fail "session start did not ask for memory to be loaded"
grep -q 'Claude/memory/demo/' <<<"$out" || fail "session start did not name the repository's memory folder"
[ -z "$(mm "$work" session-start '{}')" ] || fail "memory was loaded outside a git repository"
ok "session start loads the repository's memory, and nothing outside a repository"
mkdir -p "$work/memhome/.outerpale-mem/outbox" && touch "$work/memhome/.outerpale-mem/outbox/20261127T1000-canary.md"
grep -q '1 memory proposal' <<<"$(mm "$work/demo" session-start '{}')" || fail "an unsent proposal was not flagged at session start"
out="$(mm "$work/demo" stop '{"stop_hook_active":false}')"
grep -q '"block"' <<<"$out" || fail "the session could finish with a proposal not uploaded"
[ -z "$(mm "$work/demo" stop '{"stop_hook_active":true}')" ] || fail "the stop check blocked twice in a row"
mm "$work/demo" uploaded '{"tool_name":"mcp__Microsoft_365__sharepoint_upload_file","tool_input":{"filename":"20261127T1000-canary.md"},"tool_response":"File uploaded (90 bytes).\nwebUrl: https://x"}'
[ ! -e "$work/memhome/.outerpale-mem/outbox/20261127T1000-canary.md" ] || fail "an uploaded proposal stayed in the outbox"
[ -z "$(mm "$work/demo" stop '{"stop_hook_active":false}')" ] || fail "the stop check blocked with an empty outbox"
ok "a session can't finish with memory proposals not uploaded, and isn't held twice; an upload clears the outbox"
grep -q '"deny"' <<<"$(mm "$work/demo" guard '{"agent_type":"outerpale-mem:loader","tool_name":"Write","tool_input":{"file_path":"/x"}}')" || fail "the loader could write"
[ -z "$(mm "$work/demo" guard '{"tool_name":"Write","tool_input":{"file_path":"/x"}}')" ] || fail "the main session was restricted"
ok "the memory loader only reads"
[ -z "$(sug prompt '{"session_id":"q5","prompt":"2) Yes - i meant to do it so parallel sessions can update"}')" ] || fail "\"i meant\" counted as a correction"
ok "\"i meant\" in the person's own explanation is not a correction"

# Magister's eval grader, on fixtures (no model), and every case well formed.
node --test "$repo/tests/evals/magister/grade.test.js" >/dev/null 2>&1 || fail "Magister's eval grader"
node -e '
const fs=require("fs"),p=process.argv[1]+"/tests/evals/magister/cases/";
for (const f of fs.readdirSync(p)) { const c=JSON.parse(fs.readFileSync(p+f));
  if (!["flaw","literal","sound","variant"].includes(c.kind)||!c.brief||!c.brief.goal||!Object.keys(c.files||{}).length) throw new Error(f);
  if (["flaw","literal"].includes(c.kind)&&!(c.expect.mention_any||[]).length) throw new Error(f); }' "$repo" || fail "a Magister eval case is malformed"
ok "Magister's eval grader passes its tests, and every eval case is well formed"

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$repo/install.sh" "$repo/cloud/setup.sh" "$repo/cloud/bootstrap.sh" "$repo/tests/test.sh" "$hook" || fail "shellcheck"
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
    # Cloud VMs have an older node ahead of /usr/local/bin on PATH (/opt/node22/bin). Stand one in.
    mkdir -p /opt/oldnode/bin && cp /usr/bin/node /opt/oldnode/bin/node
    ENV_PLUGINS="envplug@m owner/m" PATH="/tmp/bin:/opt/oldnode/bin:$PATH" bash /opt/claude-setup/cloud/setup.sh
    grep -qx "plugin install envplug@m --scope user" /tmp/claude.log
    echo "vm: a plugin in ENV_PLUGINS was installed"
    PATH="/opt/oldnode/bin:$PATH" node --version | grep -q "^v26\."
    echo "vm: node 26 replaced the older node that comes first on PATH"
    cmp -s /opt/claude-setup/CLAUDE.md /root/.claude/CLAUDE.md
    grep -q "^claude-setup" /root/.claude/claude-setup.status
    grep -q "^warnings: none" /root/.claude/claude-setup.status
    command -v pnpm >/dev/null
    shellcheck /opt/claude-setup/install.sh /opt/claude-setup/cloud/setup.sh /opt/claude-setup/cloud/bootstrap.sh /opt/claude-setup/tests/test.sh
    echo "vm: shellcheck clean, pnpm on PATH, no setup warnings"
    echo "vm: setup.sh ran as root and installed /root/.claude/CLAUDE.md"
  ' || fail "cloud/setup.sh in ubuntu:24.04"
  ok "cloud/setup.sh works in a fresh ubuntu:24.04 container"
fi

printf '%d checks passed\n' "$pass"
