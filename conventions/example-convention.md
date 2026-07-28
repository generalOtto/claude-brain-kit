---
name: example-convention
description: "EXAMPLE — the shape of a convention note: a standing preference with the why and how to apply it"
type: feedback
---

# Example: Commit messages say why, not what

> **EXAMPLE NOTE** — invented content showing the format. Conventions are standing
> instructions Claude should honor whenever they apply — the feedback you don't want
> to repeat. Replace with your real preferences and delete this one.

**The rule:** Commit messages lead with *why* the change exists, not a description of
the diff. "Fix sensor 2 offset (reads ~8% high)" — not "Update calibration.py".

**Why:** The diff already shows what changed. Six months later, only the why is
recoverable from the message.

**How to apply:** Before committing on my behalf, check the message answers "why did
this change need to happen?" If it only describes the code, rewrite it.
