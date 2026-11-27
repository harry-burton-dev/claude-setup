---
name: dream
description: Consolidate Harry's global memory in OneDrive Claude/memory/_global/ - merge pending proposals into topic files and the MEMORY.md index within its limits, keep history and an audit trail, and propose promoting lessons that recur across repositories. Run by the nightly scheduled task, or when Harry says "dream" or "consolidate global memory".
---

This is `outerpale-mem:dream` applied to `Claude/memory/_global/`. Follow that skill's steps, using the Microsoft 365 connector: lock, read, verify, consolidate, index, apply the file limit, version, mark, report, unlock. If `outerpale-mem` isn't installed, read the steps from https://github.com/harry-burton-dev/claude-setup/blob/main/plugins/outerpale-mem/skills/dream/SKILL.md. These differences apply:

- **Folder:** `Claude/memory/_global/` only.
- **Types:** `profile`, `preference`, `lesson`, `environment`, `pattern` and `reference`. Group the index by these.
- **Limits:** the index stays under **100 lines and 12 KB**, because every session loads it. The topic folder has the same 200-file rule.
- **Verify:** check against what can be checked (a documented fact, a tool's behaviour, a later memory that supersedes this one). A `profile` or `preference` memory is Harry's own word, so keep it unless a newer one contradicts it.
- **Promotion, after the merge:** read the topic files in each repository's `Claude/memory/<repo>/topics/`. If the same lesson appears in two or more repositories, write a proposal for it into `_global/log/` (type `lesson`, its `description` naming the repositories), so the next dream considers it. Never move or delete a repository's memories.
- **Report:** in `dreams/<YYYY-MM-DD>.md`, also list every `profile` and `preference` memory added or changed, so Harry can see what was kept about him.

Write only inside `Claude/memory/_global/`.
