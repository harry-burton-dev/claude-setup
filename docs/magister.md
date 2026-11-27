# Magister

Magister is a background second perspective for Harry. At design, UI and decision moments, Claude can run it without being asked, and it never interrupts. It advises Harry, not the session: a finding is written for him, and the session that launched it gets only the link (`Finding filed: <link>`, or `Nothing material to add.`). The `guard` hook refuses the session, and any agent but Magister, reads of `~/.magister/` and OneDrive `Claude/magister/`. This page is the contract for the viewer that reads its log, and for its evals. How it fits the workflow is in `docs/workflow.md`.

## The log

Everything lives in OneDrive, in `Claude/magister/`, one level deep. Writers never change a file once it is written, so nothing needs locking.

| File | What it is |
|---|---|
| `<YYYY-MM-DD>-<topic-slug>.md` | One finding. It always has a YAML header |
| `<finding-name>--<variant>.<ext>` | Something Magister built for that finding, such as an HTML variant of a UI. It is listed in the finding's `attachments` |
| `<finding-name>.rating.yaml` | Harry's rating of the finding, written by the viewer |

The finding's header, with every string quoted and every list written as a block list:

```yaml
date: "2026-11-27T15:40:53Z"        # ISO 8601
session: "https://claude.ai/code/session_…" # or "none"
repo: "claude-setup"                # or "none"
scope: "OUT-123"                    # a Linear issue, project or initiative, or "none"
lenses:                             # one or more of: research, analysis, support, alternatives
  - "analysis"
topic: "One line"
confidence: "high"                  # high | medium | low
sources:
  - "https://…"
attachments:                        # the saved names of built variants
  - "2026-11-27-settings-page--two-column.html"
```

For the viewer:

- **List the folder's children, and cache each file by item id and `eTag`.** Don't use Graph's `delta` API: on this OneDrive for Business drive it only works on the drive root, and it leaves out `cTag`.
- **A finding is a `.md` file whose header has a `topic`.** An attachment is a file that some finding lists in `attachments`. Anything else is an orphan. Pair files through `attachments`, never by name: an upload that clashes gets renamed (`x 1.md`).
- **Collapse duplicates on `date`, `session` and `topic`.** A retried upload can leave two copies of a finding.

## Ratings

The viewer writes one sidecar file per rated finding, `<finding-name>.rating.yaml`, and never edits the finding itself:

```yaml
rating: "acted-on"                  # acted-on | useful | noise | wrong
note: "Used the retry budget idea"  # optional
rated_at: "2026-11-28T09:00:00Z"
```

- **acted-on:** it changed what Harry did.
- **useful:** worth reading, but it changed nothing.
- **noise:** neither right nor wrong, and not worth the attention.
- **wrong:** a factual or judgment error.

The ratings are the ground truth. The numbers to watch are the share that is acted-on or useful, and the share that is noise or wrong. A reviewer that is asked to find problems will always find something, so a rising noise rate is the warning sign.

## Evals

`tests/evals/magister/` holds 20 planted cases (`cases/*.json`):

- 8 designs with a planted flaw, which Magister must name;
- 5 sound designs, where it must support the design or add nothing, and must not invent a blocker;
- 4 rules followed against their intent, which it must name;
- 3 UI briefs, where it must build a variant.

Every case also checks that Magister returned only the link or "Nothing material to add.", none of the finding.

`grade.js` scores each run by code. `node tests/evals/magister/grade.test.js` tests the grader on fixtures, with no model.

```bash
node tests/evals/magister/run.js
```

That runs every case: Magister headless, a throwaway repo and outbox for each case, nothing uploaded. Pass case ids to run only those. Results go to `.work/evals/`, with each run's cost and working folder, so you can read the transcripts. Run it again when the agent's brief, the model or the lenses change, and compare.

Next, once ratings have built up:

- Turn findings rated `noise` or `wrong` into new cases, since cases drawn from real failures are the best ones.
- Label a sample of past prompts as "moment" or "not a moment", to measure whether the hook and Claude's choice to run Magister trigger at the right times.
