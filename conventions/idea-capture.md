---
name: idea-capture
description: "Zero-friction idea filing: {{YOUR_NAME}} drops an idea on any surface → file it immediately to ideas/<category>/<kebab-slug>.md (type: idea) and confirm in one line; new categories propose-first"
type: feedback
---

# Idea capture — zero friction

{{YOUR_NAME}}'s cheapest entry point into the brain is dropping ideas. When they say
"idea: …" — or just describe one — **file it immediately**, no ceremony:

1. `ideas/<category>/<kebab-slug>.md` — pick the existing category that fits (see the
   folders under `ideas/`; e.g. `apps`, plus whatever categories have grown — and
   consider a `brain/` category for ideas about evolving this brain itself). Short
   slug; the idea's essence.
2. Frontmatter `name`/`description`/`type: idea`; body = **the idea in
   {{YOUR_NAME}}'s words** plus minimal context (what sparked it, constraints they
   mentioned).
3. Reply is ONE line: `filed → ideas/apps/overlay-translator`. No summaries, no
   questions unless genuinely ambiguous.

**Why:** capture must be cheaper than forgetting. Filing is Claude's job, not
{{YOUR_NAME}}'s.

**How to apply:**
- **New categories are propose-first** — curation stays with {{YOUR_NAME}}. Suggest the
  category in the confirm line ("new category `music/`?") rather than silently creating
  it.
- Claude Code surfaces use the worktree write flow; connector surfaces (claude.ai,
  phone) commit directly.
- `ideas/` is indexed **one line per category** in INDEX.md (never per idea, no
  counts) — a capture never needs an INDEX edit.
- When an idea becomes a real design or project, a project note takes over and the idea
  note moves to `ideas/graduated/` — the record that a seed became a thing.
