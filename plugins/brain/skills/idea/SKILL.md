---
name: idea
description: File an idea into the brain the moment the user drops one — "idea: …" or just describing something they might build. Zero ceremony, one-line confirmation.
argument-hint: "<the idea, in the user's words>"
---

# /brain:idea $ARGUMENTS

Clone: `${user_config.brain_dir}`. Follow `conventions/idea-capture.md` there:
`ideas/<category>/<kebab-slug>.md` with frontmatter `name` / `description` /
`type: idea`, body in the user's own words, existing category when one fits
(new categories: propose first — a new category also gets its one INDEX.md line; an idea never does) — published through the
`brain:write` skill. Reply with exactly one line: `filed → ideas/<category>/<slug>`.
