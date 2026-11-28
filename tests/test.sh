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

# Third-party plugins are pinned: plugins.lock installs only from Harry's own repositories, and every
# plugin claude-setup's marketplace takes from elsewhere names an exact commit.
grep -vE '^\s*(#|$)' "$repo/plugins.lock" | awk '$2 !~ /^harry-burton-dev\//' | grep -q . && fail "plugins.lock installs from a third-party marketplace, which can't be pinned"
node -e '
  const m = require(process.argv[1]);
  const loose = m.plugins.filter(p => typeof p.source !== "string" && !/^[0-9a-f]{40}$/.test(p.source.sha || ""));
  if (loose.length) { console.error(loose.map(p => p.name).join(", ")); process.exit(1); }
' "$repo/.claude-plugin/marketplace.json" || fail "a third-party plugin in marketplace.json has no exact sha"
ok "third-party plugins are pinned to an exact commit"

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
mkdir -p "$work/committed/.work/notes" && touch "$work/committed/.work/notes/draft.md"
[ "$(git -C "$work/committed" status --porcelain)" = "?? CLAUDE.md" ] || fail ".work/ shows in git status"
ok "hook keeps .work/ (scratch and reviews) out of git in every repository"
git init -q "$work/fresh"
out="$(cd "$work/fresh" && HOME="$work/hookhome" bash "$hook")"
[ ! -e "$work/fresh/CLAUDE.md" ] || fail "hook wrote a CLAUDE.md nobody has written"
grep -q 'projects/fresh.md' <<<"$out" || fail "hook did not say which file it looked for"
grep -q 'AskUserQuestion' <<<"$out" || fail "hook did not ask to write the missing file"
ok "a missing project file is reported, with a question to write it"
(cd "$work/demo" && HOME="$work/hookhome" bash "$hook") >/dev/null
[ "$(grep -cx '/.work/' "$work/demo/.git/info/exclude")" = 1 ] || fail ".work/ exclude line repeated"
git -C "$work/demo" check-ignore -q .work/x || fail ".work/x not ignored"
ok "in a repository, .work/ is excluded exactly once after repeated runs"
mkdir -p "$work/empty"
out="$(cd "$work/empty" && HOME="$work/hookhome" bash "$hook")" || fail "hook failed in a folder with no repositories"
[ -z "$out" ] || fail "hook spoke outside a git repository"
ok "hook is silent in a folder that is not, and holds no, git repository"

# A cloud session with several repositories starts in their non-git parent folder. The hook
# covers each one, as Claude Code loads each one's CLAUDE.md, and says which repository it means.
mkdir -p "$work/multi"
git init -q "$work/multi/demo" && git init -q "$work/multi/other"
for _ in 1 2; do out="$(cd "$work/multi" && HOME="$work/hookhome" bash "$hook")"; [ -n "$out" ] || fail "hook silent with two repositories"; done
for r in demo other; do
  [ "$(grep -cx '/.work/' "$work/multi/$r/.git/info/exclude")" = 1 ] || fail ".work/ not excluded exactly once in $r"
  git -C "$work/multi/$r" check-ignore -q .work/x || fail ".work/x not ignored in $r"
done
ok "with two repositories under the start folder, .work/ is excluded exactly once in each"
cmp -s "$work/store/projects/demo.md" "$work/multi/demo/CLAUDE.md" || fail "projects/demo.md not copied into demo"
[ ! -e "$work/multi/other/CLAUDE.md" ] || fail "a CLAUDE.md was written into other"
[ ! -e "$work/multi/CLAUDE.md" ] || fail "a CLAUDE.md was written into the parent folder"
out="$(rm "$work/multi/demo/CLAUDE.md" && cd "$work/multi" && HOME="$work/hookhome" bash "$hook")"
grep -q 'to demo/CLAUDE.md' <<<"$out" || fail "the copy did not name its repository"
grep -q 'other has no other/CLAUDE.md' <<<"$out" || fail "the missing file did not name its repository"
grep -q 'projects/other.md' <<<"$out" || fail "hook did not say which file it looked for in other"
ok "each repository gets its own project CLAUDE.md lookup, and the output names the repository"

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
# shellcheck disable=SC2016
printf 'Run `make lint` first.\n' > "$work/multi/other/CLAUDE.md"
msug() { (cd "$work/multi" && HOME="$work/sughome" node "$suggest" "$1" <<<"$2"); }
for _ in 1 2 3; do o="$(msug bash '{"session_id":"q6","tool_name":"Bash","tool_input":{"command":"cd other && make lint"}}')"; done
[ -z "$o" ] || fail "a command in one repository's CLAUDE.md was suggested in a multi-repository session"
for _ in 1 2 3; do o="$(msug bash '{"session_id":"q6","tool_name":"Bash","tool_input":{"command":"cd demo && make build"}}')"; done
grep -q 'repository it belongs to (demo, other)' <<<"$o" || fail "a multi-repository suggestion did not name the repositories"
grep -q 'repository it belongs to (demo, other)' <<<"$(msug prompt '{"session_id":"q6","prompt":"No, we always use pnpm"}')" || fail "a multi-repository correction did not name the repositories"
ok "with several repositories, suggestions check every CLAUDE.md and name the repositories"
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

# Magister writes only to its outbox, and runs no shell commands.
mw() { printf '{"agent_type":"magister:magister","cwd":"%s","tool_name":"%s","tool_input":{"file_path":"%s","command":"ls"}}' "$work/demo" "$1" "$2"; }
grep -q '"deny"' <<<"$(mg guard "$(mw Write "$work/demo/src/app.ts")")" || fail "Magister could write into the code"
grep -q '"deny"' <<<"$(mg guard "$(mw Bash '')")" || fail "Magister could run a shell command"
grep -q '"deny"' <<<"$(mg guard "$(mw Write "$work/demo/.work/alt/settings-v2.html")")" || fail "Magister could write variants into the project"
[ -z "$(mg guard "$(mw Write "$work/maghome/.magister/outbox/2026-11-27-x.md")")" ] || fail "Magister could not write its outbox"
[ -z "$(mg guard "$(mw Write "$work/maghome/.magister/outbox/2026-11-27-x--two-column.html")")" ] || fail "Magister could not write a variant to its outbox"
[ -z "$(mg guard "$(mw Read "$work/maghome/.magister/outbox/2026-11-27-x.md")")" ] || fail "Magister could not read its own outbox"
[ -z "$(mg guard "{\"cwd\":\"$work/demo\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$work/demo/src/app.ts\"}}")" ] || fail "the main session was restricted"
out="$(cd "$work/demo" && HOME="$work/maghome" MAGISTER_HOME="$work/evalhome" node "$mag" guard <<<"$(mw Write "$work/evalhome/outbox/x.md")")"
[ -z "$out" ] || fail "MAGISTER_HOME did not move the outbox"
ok "Magister writes only to its outbox (MAGISTER_HOME moves it), and runs no shell; the main session can still write"

# A finding is for Harry: the main session, and any other agent, can't read it, so it gets only the link.
ms() { printf '{"cwd":"%s","tool_name":"%s","tool_input":%s}' "$work/demo" "$1" "$2"; }
for call in \
  "$(ms Read "{\"file_path\":\"$work/maghome/.magister/outbox/2026-11-27-x.md\"}")" \
  "$(ms Grep "{\"pattern\":\"x\",\"path\":\"$work/maghome/.magister\"}")" \
  "$(ms Glob "{\"pattern\":\"*.md\",\"path\":\"$work/maghome/.magister/outbox\"}")" \
  "$(ms Bash '{"command":"cat ~/.magister/outbox/*.md"}')" \
  "$(ms mcp__Microsoft_365__read_resource '{"uri":"file:///b!abc/Claude/magister/2026-11-27-x.md"}')" \
  "$(printf '{"agent_type":"Explore","cwd":"%s","tool_name":"Read","tool_input":{"file_path":"%s"}}' "$work/demo" "$work/maghome/.magister/outbox/x.md")"; do
  grep -q '"deny"' <<<"$(mg guard "$call")" || fail "a finding could be read outside Magister: $call"
done
[ -z "$(mg guard "$(ms Read "{\"file_path\":\"$work/demo/src/app.ts\"}")")" ] || fail "the main session could not read the project"
[ -z "$(mg guard "$(ms mcp__Microsoft_365__read_resource '{"uri":"file:///b!abc/Claude/memory/claude-setup/MEMORY.md"}')")" ] || fail "the main session could not read its memory"
[ -z "$(mg guard "$(ms Bash '{"command":"node plugins/magister/hooks/magister.js"}')")" ] || fail "a command naming the plugin was refused"
ok "only Magister reads its findings; the session reads the project, its memory and the plugin as before"

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
# The text Claude reads: a hook's additionalContext, or its Stop reason.
ctx() { node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{if(s){const o=JSON.parse(s);process.stdout.write((o.hookSpecificOutput||{}).additionalContext||o.reason||"")}})'; }
out="$(mm "$work/demo" session-start '{}' | ctx)"
grep -q 'outerpale-mem:loader' <<<"$out" || fail "session start did not ask for memory to be loaded"
grep -q 'Claude/memory/demo/' <<<"$out" || fail "session start did not name the repository's memory folder"
grep -q 'repository name "demo"' <<<"$out" || fail "session start did not give the loader the repository's name"
[ "$(grep -o 'repository name "[^"]*"' <<<"$out" | sort -u | wc -l)" = 1 ] || fail "a single-repository session asked for more than one repository's memory"
ok "session start in a repository loads that repository's memory"
# A cloud session with several repositories starts in their non-git parent folder ($work/multi, from
# the outerpale-startup tests above): each repository's memory is asked for, by name.
out="$(mm "$work/multi" session-start '{}' | ctx)"
for r in demo other; do
  grep -q "repository name \"$r\"" <<<"$out" || fail "session start in a parent folder did not ask for $r's memory"
  grep -q "Claude/memory/$r/" <<<"$out" || fail "session start in a parent folder did not name $r's memory folder"
done
grep -q 'repo' <<<"$(grep -i 'save' <<<"$out")" || fail "a multi-repository session was not told to name the repository when saving"
# Both plugins find the same repositories (each plugin is installed on its own, so they can't share code):
# outerpale-startup's are the ones it keeps .work/ out of.
mkdir -p "$work/both/notgit" && git init -q "$work/both/b" && git init -q "$work/both/a" && touch "$work/both/file"
(cd "$work/both" && HOME="$work/hookhome" bash "$hook") >/dev/null
startup_repos="$(cd "$work/both" && for d in */; do if grep -qsx '/.work/' "$d.git/info/exclude"; then printf '%s ' "${d%/}"; fi; done)"
mem_repos="$(mm "$work/both" session-start '{}' | ctx | grep -o 'repository name "[^"]*"' | sed 's/.*"\(.*\)"/\1/' | tr '\n' ' ')"
[ "$startup_repos" = "a b " ] || fail "outerpale-startup found $startup_repos, not a b"
[ "$mem_repos" = "$startup_repos" ] || fail "outerpale-mem ($mem_repos) and outerpale-startup ($startup_repos) found different repositories"
mkdir -p "$work/empty"
[ -z "$(mm "$work/empty" session-start '{}')" ] || fail "memory was loaded in a folder holding no git repository"
ok "from a parent folder, each repository's memory is loaded by name, as outerpale-startup finds them; none from a folder with none"
mkdir -p "$work/memhome/.outerpale-mem/outbox" && touch "$work/memhome/.outerpale-mem/outbox/20261127T1000-canary.md"
grep -q '1 memory proposal' <<<"$(mm "$work/demo" session-start '{}')" || fail "an unsent proposal was not flagged at session start"
out="$(mm "$work/demo" stop '{"stop_hook_active":false}')"
grep -q '"block"' <<<"$out" || fail "the session could finish with a proposal not uploaded"
[ -z "$(mm "$work/demo" stop '{"stop_hook_active":true}')" ] || fail "the stop check blocked twice in a row"
mm "$work/demo" uploaded '{"tool_name":"mcp__Microsoft_365__sharepoint_upload_file","tool_input":{"filename":"20261127T1000-canary.md"},"tool_response":"File uploaded (90 bytes).\nwebUrl: https://x"}'
[ ! -e "$work/memhome/.outerpale-mem/outbox/20261127T1000-canary.md" ] || fail "an uploaded proposal stayed in the outbox"
[ -z "$(mm "$work/demo" stop '{"stop_hook_active":false}')" ] || fail "the stop check blocked with an empty outbox"
ok "a session can't finish with memory proposals not uploaded, and isn't held twice; an upload clears the outbox"
printf -- '---\nname: "x"\nrepo: "other"\n---\nx\n' > "$work/memhome/.outerpale-mem/outbox/20261127T1100-other.md"
out="$(mm "$work/multi" stop '{"stop_hook_active":false}')"
grep -q '"block"' <<<"$out" || fail "a multi-repository session could finish with the second repository's proposal not uploaded"
grep -q 'Claude/memory/other/' <<<"$out" || fail "the stop check did not name the proposal's repository"
rm "$work/memhome/.outerpale-mem/outbox/20261127T1100-other.md"
ok "the stop check catches a proposal for the second repository, and names where it goes"
grep -q '"deny"' <<<"$(mm "$work/demo" guard '{"agent_type":"outerpale-mem:loader","tool_name":"Write","tool_input":{"file_path":"/x"}}')" || fail "the loader could write"
[ -z "$(mm "$work/demo" guard '{"tool_name":"Write","tool_input":{"file_path":"/x"}}')" ] || fail "the main session was restricted"
ok "the memory loader only reads"
[ -z "$(sug prompt '{"session_id":"q5","prompt":"2) Yes - i meant to do it so parallel sessions can update"}')" ] || fail "\"i meant\" counted as a correction"
ok "\"i meant\" in the person's own explanation is not a correction"

# outerpale-mem-global: memory every session shares, wherever it runs.
memg="$repo/plugins/outerpale-mem-global/hooks/memg.js"
mgx() { (cd "$1" && HOME="$work/memghome" node "$memg" "$2" <<<"$3"); }
for d in "$work" "$work/demo" "$work/committed"; do
  out="$(mgx "$d" session-start '{}')"
  grep -q 'outerpale-mem-global:loader' <<<"$out" || fail "global memory was not loaded in $d"
  grep -q 'Claude/memory/_global/' <<<"$out" || fail "session start did not name the global memory folder in $d"
done
ok "global memory is loaded in every session: outside a repository and in any repository"
mkdir -p "$work/memghome/.outerpale-mem-global/outbox" && touch "$work/memghome/.outerpale-mem-global/outbox/20261127T1800-g.md"
grep -q '1 global memory proposal' <<<"$(mgx "$work" session-start '{}')" || fail "an unsent global proposal was not flagged"
grep -q '"block"' <<<"$(mgx "$work" stop '{"stop_hook_active":false}')" || fail "a session could finish with a global proposal not uploaded"
[ -z "$(mgx "$work" stop '{"stop_hook_active":true}')" ] || fail "the global stop check blocked twice"
mgx "$work" uploaded '{"tool_name":"mcp__Microsoft_365__sharepoint_upload_file","tool_input":{"filename":"20261127T1800-g.md"},"tool_response":"File uploaded (9 bytes).\nwebUrl: https://x"}'
[ ! -e "$work/memghome/.outerpale-mem-global/outbox/20261127T1800-g.md" ] || fail "an uploaded global proposal stayed in the outbox"
grep -q '"deny"' <<<"$(mgx "$work" guard '{"agent_type":"outerpale-mem-global:loader","tool_name":"Bash","tool_input":{}}')" || fail "the global loader could run a command"
ok "global proposals can't be left un-uploaded, the stop check never loops, and the global loader only reads"
grep -q '_global' "$repo/plugins/outerpale-mem/skills/dream/SKILL.md" || fail "the repository dream doesn't leave _global to its own dream"
ok "the repository dream leaves _global to outerpale-mem-global"

# JiT (plugins/jit): layer 1 is the hook contract, generated from every plugin's hooks.json; the backtest
# replays the bugs it was built to catch. Then the runner, end to end, on a small repository.
"$repo/tests/hook-contract.sh" >/dev/null || { "$repo/tests/hook-contract.sh"; fail "a SessionStart hook breaks the three-shape contract"; }
ok "every SessionStart hook keeps the contract: exits 0, valid JSON, names each repository from a parent folder"
"$repo/tests/jit-backtest.sh" >/dev/null || fail "the layer 1 backtest no longer catches B1 and B2 without false alarms"
ok "the layer 1 backtest catches B1 and B2 at their buggy revisions, with no false alarms"
for t in "$repo"/tests/jit/landed/*.sh; do
  [ -e "$t" ] || continue
  (cd "$repo" && HOME="$(mktemp -d)" bash "$t") >/dev/null 2>&1 || fail "landed JiT test $(basename "$t")"
  ok "landed JiT test $(basename "$t")"
done

# The test bodies below are literal shell, so $ in single quotes is meant.
# shellcheck disable=SC2016
{
jit="$repo/plugins/jit/scripts/jit.js"
g() { git -c user.name=t -c user.email=t@t "$@"; }
git init -q --bare "$work/jo.git" && git clone -q "$work/jo.git" "$work/jr" 2>/dev/null
printf 'add(){ echo $(( $1 + $2 )); }\n' > "$work/jr/lib.sh"
(cd "$work/jr" && g add . && g commit -qm base && git push -q origin HEAD:main 2>/dev/null && git fetch -q && git checkout -qb feat)
jj() { (cd "$work/jr" && node "$jit" "$@"); }
field() { node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>console.log(JSON.parse(s)[process.argv[1]]))' "$1"; }
printf '# notes\n' > "$work/jr/README.md" && (cd "$work/jr" && g add . && g commit -qm docs)
[ "$(jj triage | field decision)" = skip ] || fail "a docs-only change was not skipped"
printf 'add(){ echo $(( $1 + $2 )); }\nsub(){ echo $(( $1 - $2 )); }\n' > "$work/jr/lib.sh" && (cd "$work/jr" && g commit -qam sub)
[ "$(jj triage | field reason)" = "tiny change (1 line(s))" ] || fail "a one-line change was not skipped as tiny"
ok "JiT triage skips docs-only and tiny changes, and writes the report"
cat > "$work/jr/lib.sh" <<'EOF'
add(){ echo $(( $1 + $2 )); }
sub(){ echo $(( $1 - $2 )); }
# mul multiplies two integers
mul(){ echo $(( $1 + $2 )); }
neg(){ echo $(( 0 - $1 )); }
sq(){ echo $(( $1 * $1 )); }
half(){ echo $(( $1 / 2 )); }
EOF
(cd "$work/jr" && g commit -qam "mul, neg, sq, half")
[ "$(jj triage | field decision)" = run ] || fail "a real change was skipped"
sha="$(git -C "$work/jr" rev-parse HEAD)" jw="$work/jr/.work/jit/$(git -C "$work/jr" rev-parse HEAD)"
mkdir -p "$jw/tests/tests/jit"
cat > "$jw/tests.json" <<'EOF'
{"tests":[
 {"id":"mul","risk":"mul adds","file":"tests/jit/mul.sh","cmd":"bash tests/jit/mul.sh","exists":"grep -q '^mul()' lib.sh"},
 {"id":"sq","risk":"sq wrong","file":"tests/jit/sq.sh","cmd":"bash tests/jit/sq.sh"},
 {"id":"add","risk":"add regressed","file":"tests/jit/add.sh","cmd":"bash tests/jit/add.sh"},
 {"id":"net","risk":"x","file":"tests/jit/net.sh","cmd":"bash tests/jit/net.sh"},
 {"id":"both","risk":"y","file":"tests/jit/both.sh","cmd":"bash tests/jit/both.sh"},
 {"id":"flaky","risk":"z","file":"tests/jit/flaky.sh","cmd":"bash tests/jit/flaky.sh"},
 {"id":"neg","risk":"neg wrong","file":"tests/jit/neg.sh","cmd":"bash tests/jit/neg.sh"}
]}
EOF
printf '. ./lib.sh; [ "$(mul 2 3)" = 6 ]\n' > "$jw/tests/tests/jit/mul.sh"
printf '. ./lib.sh; type sq >/dev/null 2>&1 || exit 77; [ "$(sq 3)" = 9 ]\n' > "$jw/tests/tests/jit/sq.sh"
printf '. ./lib.sh; [ "$(add 2 3)" = 5 ]\n' > "$jw/tests/tests/jit/add.sh"
printf 'type mul >/dev/null 2>&1; . ./lib.sh; type mul >/dev/null 2>&1 || exit 0; echo "curl: (6) Could not resolve host: x"; exit 6\n' > "$jw/tests/tests/jit/net.sh"
printf 'exit 1\n' > "$jw/tests/tests/jit/both.sh"
printf '. ./lib.sh; type neg >/dev/null 2>&1 || exit 77; [ "$(neg 2)" = 2 ]\n' > "$jw/tests/tests/jit/neg.sh"
printf '. ./lib.sh; type mul >/dev/null 2>&1 || exit 0; f=/tmp/jit-flaky-%s; if [ -e "$f" ]; then rm "$f"; exit 0; fi; touch "$f"; exit 1\n' "$$" > "$jw/tests/tests/jit/flaky.sh"
decisions="$(jj run | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{for(const r of JSON.parse(s).results)console.log(r.id+"="+r.decision)})' | tr '\n' ' ')"
[ "$decisions" = "mul=report sq=land add=discard net=discard both=discard flaky=discard neg=report " ] || fail "JiT classified $decisions"
! git -C "$work/jr" worktree list | grep -q 'wt-' || fail "JiT left its worktrees behind"
ok "JiT runs each test at the change and its parent: a new-function bug is reported (exit 77 or an exists check marks code not there yet), a test of new code lands, passes-on-both, fails-on-both, network and flaky failures are dropped"
printf '{}' > "$jw/verdicts.json"
[ "$(jj finish | field catches)" = "[]" ] || fail "an unassessed catch was reported"
printf '{"mul":"should-fail"}' > "$jw/verdicts.json"
out="$(jj finish)"
grep -q '"risk": "mul adds"' <<<"$out" || fail "the assessed catch was not reported"
[ -f "$work/jr/tests/jit/sq.sh" ] || fail "landing missed the test that pins new code"
[ ! -e "$work/jr/tests/jit/mul.sh" ] || fail "landing copied a failing test"
ok "JiT finish reports only catches the assessor upheld, and lands the tests that pin the change"
pr='{"tool_name":"mcp__github__create_pull_request","tool_input":{"owner":"o","repo":"jr","head":"feat"},"cwd":"'"$work/jr"'"}'
hk() { (cd "$work" && node "$jit" hook <<<"$1"); }
[ -z "$(hk "$pr")" ] || fail "the PR hook refused a branch with a JiT report"
(cd "$work/jr" && g add tests && g commit -qm "jit: landed test")
[ -z "$(hk "$pr")" ] || fail "committing the landed test invalidated the report"
printf 'mul(){ echo $(( $1 * $2 )); }\nneg2(){ echo $(( 0 - $1 )); }\nsq2(){ echo $(( $1 * $1 )); }\none(){ echo 1; }\ntwo(){ echo 2; }\nthree(){ echo 3; }\n' >> "$work/jr/lib.sh" && (cd "$work/jr" && g commit -qam more)
grep -q '"deny"' <<<"$(hk "$pr")" || fail "the PR hook allowed a branch changed since JiT ran"
grep -q '"deny"' <<<"$(hk "${pr/mcp__github__/mcp__GitHub__}")" || fail "the PR hook missed the other GitHub tool spelling"
[ -z "$(hk "${pr/\"repo\":\"jr\"/\"repo\":\"elsewhere\"}")" ] || fail "the PR hook refused a PR for a repository not in this session"
[ -z "$(hk 'not json')" ] || fail "the PR hook did not fail open on bad input"
git -C "$work/jr" worktree add -q --detach "$work/jr-wt" && (cd "$work/jr-wt" && g commit -q --allow-empty -m wt)
printf 'x(){ :; }\ny(){ :; }\nz(){ :; }\n' >> "$work/jr-wt/lib.sh" && printf 'w(){ :; }\nv(){ :; }\nu(){ :; }\n' > "$work/jr-wt/more.sh" && (cd "$work/jr-wt" && g add . && g commit -qm wt-change)
grep -q '"deny"' <<<"$(cd "$work/jr-wt" && node "$jit" hook <<<"${pr/\"cwd\":\"$work\/jr\"/\"cwd\":\"$work\/jr-wt\"}")" || fail "the PR hook let a worktree's PR through by its folder name"
git -C "$work/jr" worktree remove --force "$work/jr-wt"
(cd "$work/jr" && node "$jit" skip --reason "low risk: helpers only" >/dev/null)
[ -z "$(hk "$pr")" ] || fail "a judged skip did not satisfy the PR hook"
node -e 'const m=require(process.argv[1]).hooks.PreToolUse[0].matcher;for(const t of["mcp__github__create_pull_request","mcp__GitHub__create_pull_request"])if(!new RegExp("^("+m+")$").test(t))process.exit(1)' "$repo/plugins/jit/hooks/hooks.json" || fail "the PR hook's matcher misses a GitHub tool name"
ok "the PR hook needs a JiT report or a judged skip for the branch, survives committing landed tests, matches both GitHub spellings, and fails open"
gd() { (cd "$work" && node "$jit" guard <<<"$1"); }
grep -q '"deny"' <<<"$(gd '{"agent_type":"jit:generator","tool_name":"Write","tool_input":{"file_path":"/r/lib.sh"}}')" || fail "the generator could write outside .work/jit/"
[ -z "$(gd '{"agent_type":"jit:generator","tool_name":"Write","tool_input":{"file_path":"/r/.work/jit/abc/tests.json"}}')" ] || fail "the generator could not write its manifest"
grep -q '"deny"' <<<"$(gd '{"agent_type":"jit:assessor","tool_name":"Write","tool_input":{"file_path":"/r/.work/jit/abc/tests.json"}}')" || fail "the assessor could write more than verdicts.json"
[ -z "$(gd '{"tool_name":"Write","tool_input":{"file_path":"/r/lib.sh"}}')" ] || fail "the JiT guard restricted the main session"
ok "the JiT generator writes only under .work/jit/, the assessor only its verdicts"

# vm-paths: a repository whose CLAUDE.md is something else keeps its JiT line in claude-setup's
# projects/<repo>.md. A change under a vm-path is flagged, and a test marked vm with no Docker is
# reported as not run, never as a catch.
git init -q --bare "$work/vo.git" && git clone -q "$work/vo.git" "$work/vmr" 2>/dev/null
mkdir -p "$work/vmr/cloud" "$work/vmstore/projects" "$work/vmhome/.claude" "$work/nodocker"
printf '%s' "$work/vmstore" > "$work/vmhome/.claude/claude-setup-dir"
printf '# vmr\nJiT: vm-paths cloud/\n' > "$work/vmstore/projects/vmr.md"
printf '# its own instructions, no JiT line\n' > "$work/vmr/CLAUDE.md"
printf 'echo one\n' > "$work/vmr/cloud/setup.sh"
(cd "$work/vmr" && g add . && g commit -qm base && git push -q origin HEAD:main 2>/dev/null && git fetch -q && git checkout -qb feat)
printf 'echo one\necho two\necho three\necho four\necho five\necho six\n' > "$work/vmr/cloud/setup.sh" && (cd "$work/vmr" && g commit -qam more)
vj() { (cd "$work/vmr" && HOME="$work/vmhome" PATH="$work/nodocker:$PATH" node "$jit" "$@"); }
[ "$(vj triage | field vm)" = true ] || fail "a change under a vm-path from projects/<repo>.md was not flagged"
vw="$work/vmr/.work/jit/$(git -C "$work/vmr" rev-parse HEAD)" && mkdir -p "$vw/tests/t"
printf '{"tests":[{"id":"root","risk":"r","file":"t/root.sh","cmd":"bash t/root.sh","vm":true}]}' > "$vw/tests.json"
printf '[ "$(id -u)" = 0 ]\n' > "$vw/tests/t/root.sh"
printf '#!/bin/sh\nexit 1\n' > "$work/nodocker/docker" && chmod +x "$work/nodocker/docker"
[ "$(vj run | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{const r=JSON.parse(s).results[0];console.log(r.R+" "+r.decision)})')" = "novm discard" ] || fail "a vm test without Docker was not set aside"
printf '{}' > "$vw/verdicts.json"
[ "$(vj finish | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>console.log(JSON.parse(s).notRun.join(" ")))')" = root ] || fail "the report did not name the vm test it could not run"
ok "JiT reads vm-paths from projects/<repo>.md, flags a change under them, and reports a vm test it can't run without Docker"
}

node "$repo/tests/evals/jit/run.js" --check >/dev/null || { node "$repo/tests/evals/jit/run.js" --check; fail "a JiT assessor eval case is malformed, or its test doesn't fail on its code"; }
ok "every JiT assessor eval case is well formed, and its test really fails on its code"

# Magister's eval grader, on fixtures (no model), and every case well formed.
node --test "$repo/tests/evals/magister/grade.test.js" >/dev/null 2>&1 || fail "Magister's eval grader"
node -e '
const fs=require("fs"),p=process.argv[1]+"/tests/evals/magister/cases/";
for (const f of fs.readdirSync(p)) { const c=JSON.parse(fs.readFileSync(p+f));
  if (!["flaw","literal","sound","variant"].includes(c.kind)||!c.brief||!c.brief.goal||!Object.keys(c.files||{}).length) throw new Error(f);
  if (["flaw","literal"].includes(c.kind)&&!(c.expect.mention_any||[]).length) throw new Error(f); }' "$repo" || fail "a Magister eval case is malformed"
ok "Magister's eval grader passes its tests, and every eval case is well formed"

# Every plugin in this repository's marketplace ships through plugins.lock, or the lock says it doesn't.
for name in $(node -e 'for (const p of require(process.argv[1]).plugins) console.log(p.name)' "$repo/.claude-plugin/marketplace.json"); do
  grep -qx "$name@claude-setup harry-burton-dev/claude-setup" "$repo/plugins.lock" || grep -qx "# not installed: $name.*" "$repo/plugins.lock" ||
    fail "marketplace plugin $name is neither in plugins.lock nor marked '# not installed: $name' there"
done
ok "every marketplace plugin is in plugins.lock or marked not installed"

# The magister-avatar mod ships through plugins.lock, so a broken one would reach every machine.
if command -v claude >/dev/null 2>&1; then
  claude plugin validate "$repo/plugins/magister-avatar" 2>&1 | grep -q 'Validation passed' || fail "magister-avatar does not validate"
  claude plugin test "$repo/plugins/magister-avatar" >/dev/null 2>&1 || fail "magister-avatar's tests"
  ok "magister-avatar validates and passes its tests"
else
  printf 'skip: claude not installed, magister-avatar not tested\n'
fi

# new-repo.sh gives a new repository its baseline through gh. A stand-in gh records each call,
# keeps what it is sent, and serves a local bare repository as the GitHub remote.
cat > "$work/bin/gh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$work/gh.log"
case "\$*" in
  "api user"*) echo harry ;;
  "repo create"*) git init -q --bare "$work/remote.git" ;;
  "repo view harry/demo --json url"*) echo "$work/remote.git" ;;
  "repo view"*) [ -d "$work/remote.git" ] ;;
  "api repos/harry/demo/rulesets --jq"*) if [ -f "$work/ruleset.json" ]; then echo 7; fi ;;
  *"repos/harry/demo/rulesets"*) cat > "$work/ruleset.json" ;;
  "api -X PATCH repos/harry/demo "*) cat > "$work/settings.json" ;;
esac
EOF
chmod +x "$work/bin/gh"
PATH="$work/bin:$PATH" "$repo/new-repo.sh" demo > "$work/newrepo1.log"
grep -qx 'repo create harry/demo --public' "$work/gh.log" || fail "new-repo.sh did not create a public repository"
files="$(git --git-dir="$work/remote.git" ls-tree -r --name-only main)"
for f in .github/workflows/ci.yml .github/dependabot.yml .gitattributes; do
  grep -qx "$f" <<<"$files" || fail "baseline file $f not pushed"
done
! grep -qE 'CLAUDE.md|^\.claude/' <<<"$files" || fail "Claude setup was pushed into the project repository"
ok "new-repo.sh creates a public repository and pushes the baseline files, with no Claude setup"
node -e '
const s=require(process.argv[1]), r=require(process.argv[2]);
const want={allow_squash_merge:true,allow_merge_commit:false,allow_rebase_merge:false,delete_branch_on_merge:true,allow_auto_merge:true};
for (const k in want) if (s[k]!==want[k]) throw new Error("setting "+k);
if (s.security_and_analysis.secret_scanning_push_protection.status!=="enabled") throw new Error("push protection");
const rules=Object.fromEntries(r.rules.map(x=>[x.type,x.parameters||{}]));
if (r.enforcement!=="active"||!rules.deletion||!rules.non_fast_forward) throw new Error("ruleset basics");
if (rules.pull_request.allowed_merge_methods.join()!=="squash") throw new Error("merge methods");
if (rules.required_status_checks.required_status_checks.map(c=>c.context).join()!=="ci") throw new Error("required check");' \
  "$work/settings.json" "$work/ruleset.json" || fail "new-repo.sh sent the wrong settings or ruleset"
grep -qx 'api -X PUT repos/harry/demo/vulnerability-alerts' "$work/gh.log" || fail "Dependabot alerts not enabled"
grep -qx 'api -X POST repos/harry/demo/rulesets --input -' "$work/gh.log" || fail "ruleset not created"
ok "new-repo.sh sets squash-only auto-merge, push protection, Dependabot, and a ruleset requiring ci"
: > "$work/gh.log"
PATH="$work/bin:$PATH" "$repo/new-repo.sh" demo > "$work/newrepo2.log"
! grep -q 'repo create' "$work/gh.log" || fail "a second run created the repository again"
grep -qx 'api -X PUT repos/harry/demo/rulesets/7 --input -' "$work/gh.log" || fail "a second run did not update the ruleset in place"
grep -q 'already has commits' "$work/newrepo2.log" || fail "a second run pushed the baseline files again"
ok "new-repo.sh run again updates settings in place and leaves the code alone"

if command -v actionlint >/dev/null 2>&1 && command -v zizmor >/dev/null 2>&1; then
  actionlint "$repo/templates/repo/.github/workflows/ci.yml" || fail "actionlint on the template workflow"
  zizmor -q --offline "$repo/templates/repo" || fail "zizmor on the template workflow"
  ok "the template workflow passes actionlint and zizmor"
else
  printf 'skip: actionlint or zizmor not installed, template workflow not linted\n'
fi

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$repo/new-repo.sh" "$repo/install.sh" "$repo/cloud/setup.sh" "$repo/cloud/bootstrap.sh" "$repo/tests/test.sh" "$hook" "$repo/tests/hook-contract.sh" "$repo/tests/jit-backtest.sh" || fail "shellcheck"
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
    PATH="/opt/oldnode/bin:$PATH" command -v pnpm >/dev/null
    shellcheck /opt/claude-setup/install.sh /opt/claude-setup/cloud/setup.sh /opt/claude-setup/cloud/bootstrap.sh /opt/claude-setup/tests/test.sh
    echo "vm: shellcheck clean, pnpm on PATH, no setup warnings"
    echo "vm: setup.sh ran as root and installed /root/.claude/CLAUDE.md"
    # The guard: a node that is still not 26 after the install is a warning, not a success.
    mkdir -p /tmp/oldnode
    printf "#!/bin/sh\necho v22.0.0\n" > /tmp/oldnode/node
    chmod +x /tmp/oldnode/node
    PATH="/tmp/oldnode:/tmp/bin:$PATH" bash /opt/claude-setup/cloud/setup.sh > /tmp/guard.log 2>&1 || true
    grep -q "^warning: node 26 is not the default node.*node is v22.0.0" /root/.claude/claude-setup.status || { cat /tmp/guard.log; exit 1; }
    echo "vm: a node that is not 26 after the install is a warning"
    # A plugin that fails to install is a warning in the status file, not a failed setup:
    # a failing setup script stops every session in the environment from starting.
    printf "#!/usr/bin/env bash\n[ \"\$2\" = install ] && exit 1; exit 0\n" > /tmp/bin/claude
    PATH="/tmp/bin:/opt/oldnode/bin:$PATH" bash /opt/claude-setup/cloud/setup.sh > /tmp/plugfail.log 2>&1 || { cat /tmp/plugfail.log; echo "setup.sh failed because a plugin failed"; exit 1; }
    grep -q "^warning: .*plugin" /root/.claude/claude-setup.status || { cat /root/.claude/claude-setup.status; exit 1; }
    echo "vm: a plugin that fails to install is a warning, and setup still finishes"
  ' || fail "cloud/setup.sh in ubuntu:24.04"
  ok "cloud/setup.sh works in a fresh ubuntu:24.04 container"
  # JiT's VM run: each vm test gets a fresh root container with its revision at /repo. Side effects
  # of one run (here, a marker under /root) never reach the next.
  printf '{"tests":[{"id":"vmroot","risk":"r","file":"t/vmroot.sh","cmd":"bash t/vmroot.sh","vm":true},{"id":"vmnew","risk":"n","file":"t/vmnew.sh","cmd":"bash t/vmnew.sh","vm":true}]}' > "$vw/tests.json"
  # shellcheck disable=SC2016 # literal shell for the container
  printf '[ "$(id -u)" = 0 ] && grep -q "24.04" /etc/os-release && [ -f /repo/cloud/setup.sh ] && [ ! -e /root/marker ] && touch /root/marker && command -v node git >/dev/null\n' > "$vw/tests/t/vmroot.sh"
  printf 'grep -q "echo six" cloud/setup.sh\n' > "$vw/tests/t/vmnew.sh"
  out="$(cd "$work/vmr" && HOME="$work/vmhome" node "$jit" run | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{for(const r of JSON.parse(s).results)console.log(r.id+"="+r.P+"/"+r.R+"/"+r.decision)})' | tr '\n' ' ')"
  [ "$out" = "vmroot=pass/pass/discard vmnew=fail/pass/land " ] || fail "JiT's VM run gave $out"
  ok "JiT runs vm tests as root in a fresh Ubuntu 24.04 container per run, at each revision"
fi

printf '%d checks passed\n' "$pass"
