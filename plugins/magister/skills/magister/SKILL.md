---
name: magister
description: Launch Magister - Harry's background second perspective (research, analysis of intent and assumptions, support for sound choices, alternatives and built variants) - and pass on its note. Use at design, UI and decision moments when it would add something, without being asked and without waiting; also to upload findings left in ~/.magister/outbox/.
---

Magister makes Harry's work better by feeding him information: it never interrupts and never asks. Its findings are a log of his own, kept in OneDrive under `Claude/magister/`, not part of any project.

Magister advises Harry, not this session. The finding in OneDrive is the whole output, and it is for him. This session gets only its link: don't read a finding (in OneDrive or `~/.magister/`), don't summarise it, and don't change the work because Magister ran. A hook refuses those reads. If Harry acts on a finding, he'll say so.

## When

At a design, UI or decision moment, if a second perspective would add something: research on how others do it, a check of intent and assumptions, confirmation that a choice is sound, or an alternative. Not for routine edits, and not twice on the same question. There is no cap: a run of real decisions can warrant several runs.

## Launch it

Start the `magister:magister` agent with the Agent tool, **in the background**, and carry on with the work. Its brief stands alone, since it hasn't seen this conversation:

- what is being worked on, and the goal behind it, in Harry's words where possible
- the decision or design at hand, and what has been chosen so far
- the files to read, by absolute path
- the repository name, the Linear scope if any, this session's link, and the current date and time (it has no clock of its own)

## Pass on its link

When it reports `Finding filed: <link>`, add `Magister: <link>` at the end of your next reply, and nothing more. If it said "Nothing material to add", say nothing. Never stop work, ask a question, or change course because of it.

## Upload

Magister uploads its own findings. When session start reports findings left in `~/.magister/outbox/`, launch `magister:magister` in the background with the brief "Upload the findings left in `~/.magister/outbox/`; nothing else", and pass on the links it returns as above. Don't upload them from this session, since that means reading them.

How Magister uploads a finding in the outbox and its built variants beside it, with the Microsoft 365 connector:

1. Find the drive: `read_resource` with `drive:///users/me`; use the drive named `OneDrive`.
2. Find the folder: `read_resource` with `file:///<driveId>/Claude` lists its children, with `magister`'s item id in its URI. If `Claude` or `magister` is missing, create it with `sharepoint_create_folder` (one level per call).
3. Upload with `sharepoint_upload_file` into that folder (`parentItemId`), using `content` for text and `conflictBehavior: "rename"`, so nothing is overwritten. Upload variants before the finding, and put the names they were saved under in its `attachments`.
4. A hook removes the finding from the outbox once its upload succeeds. If it fails, leave it: the next session start flags it.

Write only inside `Claude/magister/`.
