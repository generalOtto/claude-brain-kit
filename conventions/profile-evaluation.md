---
name: profile-evaluation
description: "The profile evaluation mechanism — event-driven capture of hard evidence about {{YOUR_NAME}} into profile.md's evidence log with a mandatory one-line 'profiled →' announce; facts only in-session, deductions only in the ~10-entry consolidation pass; includes the evidence rules"
type: feedback
---

# Profile evaluation (the evidence-based living profile)

**Why it exists.** A profile written once goes dormant — accurate the day it was
written, stale after. This mechanism keeps `identity/profile.md` current through normal
use: sessions that happen anyway are the sensor, exactly as the [[todo-list]] replaced
a scheduler with conversations. Purpose: speak to {{YOUR_NAME}} at the right level,
ground anything written *about* them (a resume, a bio) so they're neither under- nor
over-represented, and keep an accurate baseline to improve from.

## The capture loop (any session, any surface that can write)

When {{YOUR_NAME}}'s **words, decisions, or credentials** in a session constitute hard
evidence about who they are, how they work, or what they know — per the evidence rules
below — do both, immediately:

1. Append a dated one-liner to the `## Evidence log` in `identity/profile.md` via the
   write protocol. **Facts only, no trait language**: what they said / decided / hold,
   with the evidence kind in parentheses. Newest first.
2. Reply with **one line**: `profiled → <what was noted>`. The announce is mandatory —
   it's {{YOUR_NAME}}'s transparency check, and their veto point: if they object,
   remove the entry in the same session.

The bar is *durably worth noting* — not session trivia, not anything the repo already
records. When in doubt, skip; the portrait's value is curation.

## The evidence rules

- **Valid evidence for deductions:** which ideas/projects they choose to pursue and
  kill; hard facts (documents, credentials, their statements and quoted words); design
  decisions certainly theirs.
- **Invalid evidence: implementation.** Code structure, doc structure/phrasing,
  architecture detail, craft qualities of artifacts — that layer is mostly Claude's
  authorship; reading it as {{YOUR_NAME}}'s character is circular.
- **Invalid evidence: Claude-supplied knowledge** (the knowledge-provenance exclusion).
  When judging their knowledge or skill level, three more things are NOT evidence:
  things Claude explained to them; what they later echo back from those explanations
  (echoing ≠ independent knowledge — the same circularity, applied to knowledge); and
  what anyone knows from ordinary human experience (too universal to signal anything).
- When deducing from valid evidence, say so and show the evidence. When {{YOUR_NAME}}
  self-describes, quote and attribute.

## The consolidation trigger (condition-based, no scheduler)

Every append **counts the log**. At **~10 entries**, offer the consolidation pass in
the same breath as the announce ("log is ripe — run the consolidation pass?"). Track it
as a `TODO.md` item so it isn't lost; it runs like any **go** — with {{YOUR_NAME}} in
the conversation, since deductions are curation.

**The pass:** distill log entries into the portrait sections of `identity/profile.md` ·
make or update *deduced characteristics* (only here, each claim citing its evidence) ·
route collaboration-style findings toward `identity/how-we-work.md` and biographical
facts toward `identity/about-me.md` · collapse the processed entries out of the log
(additive: distilled, then removed).

## Honest limitations

Coverage is probabilistic — evidence in sessions that never touch the brain goes
unrecorded, and judgment can misfire in both directions (the announce catches false
positives; false negatives just wait for the evidence to recur). The log is
human-readable at all times; {{YOUR_NAME}} can read or edit the profile directly
whenever they want.
