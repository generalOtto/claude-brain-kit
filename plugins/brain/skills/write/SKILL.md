---
name: write
description: Record something durable in the brain — a fact about the user, a decision, a project's state, a gotcha, a preference — or when the user says "remember this". Publishes through the concurrency-safe worktree flow; never edits the clone directly.
---

# Brain write (the worktree flow)

Clone: `${user_config.brain_dir}` (the plugin puts `brain-write.sh` on PATH).

1. Decide the note: update an existing one when it exists (grep `INDEX.md` and the
   folder first — no near-duplicates), else create `<folder>/<kebab-slug>.md` with
   frontmatter `name`, `description`, `type` (`user`|`feedback`|`project`|`reference`|`idea`).
   One fact per file; link related notes with `[[slug]]`. Don't record what a repo,
   codebase or git history already captures.
2. `wt=$(brain-write.sh open)` — edit ONLY inside `$wt`. Add or update the note's one
   line in `$wt/INDEX.md`.
3. `brain-write.sh publish "$wt" "<short message>"` — commits in isolation and pushes to
   remote `main`. On `offline: …` the write is safe locally; run `brain-write.sh sync`
   later. On a rebase conflict: resolve inside `$wt`, `git -C "$wt" rebase --continue`,
   re-run publish.
4. Reply in one line with what was written and where.

Notable session → consider a dated `journal/YYYY-MM-DD-<slug>.md` entry the same way.
