---
name: todo-list
description: "The to-do list mechanism — AI-mediated replacement for schedulers: TODO.md item format, once-a-day digest surfacing, go/later/mute/done/add responses, execute-where-capable, hard-deadline bridge"
type: feedback
---

# The to-do list mechanism (standing chores & reminders)

**Why it exists.** Claude can't run on a schedule without an always-on machine, and this
brain runs no servers — so intermittent tasks ride on conversations that already happen.
`TODO.md` (repo root) is {{YOUR_NAME}}'s **single to-do list**: recurring maintenance
chores, one-shot reminders, follow-ups. Surfacing is **probabilistic by design** — fine
for everything soft; the bridge (below) covers the few hard deadlines. All
timing/relevance judgment is AI-mediated; there is no scheduler logic anywhere.

## Item format

Items live under `## Active`; status is section membership (`## Muted`, `## Done log`) —
no status field.

- `what:` one line (+ link to a note if a procedure exists)
- `when:` the **source** of due-ness, freeform: a date ("2027-03-01"), a cadence
  ("~monthly"), or a condition ("~20 unfiled ideas accumulated")
- `next:` the **cache** — a concrete date Claude maintains on every add/run/snooze. The
  session check compares dates only and **never runs tools**; conditions are verified
  only when a chore actually executes. `—` plus a parked note = never surfaces.
- `last:` last run/done date · `priority:` low | normal | high — feeds judgment, never
  raises the noise cap
- `needs:` what "go" requires (a specific machine, a connector, "none — telling
  {{YOUR_NAME}} is the task", …)
- `hard: yes → bridged: …` — backed by a real alarm (see bridge) · `queued: <date,
  surface>` — set when {{YOUR_NAME}} says go somewhere that can't run it · optional
  `notes:` for running context

## The daily check

Every session where the bootloader loads, on any surface: **after** handling what
{{YOUR_NAME}} actually asked — never instead of it, and skipped entirely when the
session is clearly urgent or deeply focused — read `TODO.md`. If frontmatter
`last-surfaced` < today (the shipped initial value `never` always counts as due)
**and** anything is due (`next:` ≤ today; judgment on `when:` for uncached items),
append a compact digest — **all** due items, one line each
(name · why due · priority) — and set `last-surfaced:` to today via the write protocol.
Strictly once a day, with one narrow exception: a `hard:` item inside its final window
may be repeated.

- **"todos"** from {{YOUR_NAME}} opens the full list any time, digest or not, no stamp
  implications.
- Low-priority items surface only in relaxed sessions — never wedge a nag into an
  urgent one.
- `queued:` items open the next capable session ("you queued X — run it now?") and
  bypass the daily throttle — they're invited, not nagging.
- On a surface that can't push to `main`, show the digest and skip the stamp — an
  occasional double-digest is the accepted cost.

## Responses

- **go [item]** → execute where capable, per `needs:`. On Claude Code, real work runs in
  a **subagent** (the main conversation stays clean) which reports back; the main
  session does the bookkeeping (`last:`, `next:`, done log) and publishes. Trivial
  items — the task is telling {{YOUR_NAME}} something — skip the subagent. On connector
  surfaces, chat/connector-doable items run inline; anything else gets a `queued:` mark.
- **later [hint]** → write a new `next:` (compute it from the hint, or propose one).
- **mute** → move to `## Muted` with date + reason.
- **done** → {{YOUR_NAME}} did it themselves; the line moves to the done log.
- **add …** → new Active item; Claude fills the fields. **"Remind me to X", said
  anywhere on any surface, IS an add** — draft the item inline, offer the bridge if it
  smells hard-deadline.

## Hard-deadline bridge

The mechanism never guarantees timing. An item that must not slip gets `hard: yes`, and
**at creation** Claude offers to back it with a real alarm: a **calendar event** when
{{YOUR_NAME}} is the actor (the event text points back — "from the brain's TODO.md;
tell Claude 'todos'"), or a **scheduled cloud agent** when Claude is the actor (it
proposes and nudges only — it never mutates the brain unattended). The alarm is the
bell; `TODO.md` stays the registry. Record the bridge on the item.

## Writes

Every mutation — stamp, snooze, mute, done, add, run bookkeeping — publishes via the
worktree write protocol, like any brain write. All edits happen with {{YOUR_NAME}} in
the conversation, which keeps the brain human-curated by construction.

## Honest limitations

A day with no conversation surfaces nothing — that's what the bridge is for.
Judgment-based surfacing can misfire in both directions; the list stays human-readable
and "todos" always works.
