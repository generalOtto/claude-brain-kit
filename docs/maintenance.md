# Keeping the brain healthy

A brain that's written to and never tended drifts: duplicate notes, stale facts, an
index that lies. The good news — because everything is small markdown files, hygiene
is minutes, not projects. Most of it Claude does for you if the protocols hold.

## The habits that matter

**One fact per file.** The unit of memory is a note that answers one question. When a
note starts covering two things, split it. Small notes are what make index-first
recall work.

**The index never lies.** Every note has exactly one line in `INDEX.md`, and the
description is what recall runs on — write it as *"when would someone need this?"*,
not a vague title. New note without an index line = invisible note.

**Update, don't duplicate.** Before writing a note, check whether one already covers
it. The write protocol says update in place; git history preserves the old version,
so editing is never lossy.

**Delete what's wrong.** A wrong note is worse than no note — Claude will act on it.
Deleting is safe (git remembers) and keeps trust in the brain absolute.

**Journal the days that mattered.** Not every session — milestones, big decisions,
good days. The journal is where the *relationship* accumulates, not just the facts.

## Periodic consolidation (monthly-ish, or when it feels cluttered)

Ask Claude, in a session with the brain loaded:

> Do a consolidation pass on the brain: find duplicate or overlapping notes and merge
> them, flag facts that look stale so I can confirm, fix INDEX.md drift (missing
> entries, dead entries, descriptions that no longer match), and delete the starter
> example notes if any are still around. Commit as you go, one concern per commit.

Review the commits; revert anything you disagree with. That's the whole ceremony.

## What NOT to store (the anti-bloat rules)

- **Anything a repo already records** — code, file listings, architecture that's in
  the README, bug-fix history that's in git log. Store the *why* and the *gotcha*,
  link to the rest.
- **Session narration** — "we ran the tests and they passed" is noise. The distilled
  outcome is the note.
- **Speculation** — the brain stores facts and decisions, not maybes. (Open questions
  belong in a project note's "open questions" line, clearly marked.)
- **Secret values** — never. See [security.md](security.md).

## Watch the bootloader's weight

`CLAUDE.md` loads into *every* session — its length is a per-session tax. Keep it a
bootloader (who + how to remember), never a knowledge dump; knowledge belongs in
notes behind the index. If you add sections, ask whether every session needs them.
The same goes for `identity/` notes: always-loaded means always-paid-for.

## Trust but verify (occasionally)

Once in a while, ask a fresh session *"what do you know about me?"* and skim the
answer. If something's wrong or missing, that's a note to fix — and the fastest
possible audit of whether the brain is doing its job.
