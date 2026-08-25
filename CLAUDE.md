# CLAUDE.md — {{YOUR_NAME}}'s Persistent Brain (bootloader)

This file is the entry point to **the brain**: a single, git-backed, cross-device
memory that persists everything {{YOUR_NAME}} and I (Claude) do together. It is wired
into `~/.claude/CLAUDE.md`, so it loads into **every** Claude Code session on every
machine. Read it as: *who I'm working with, and how to remember.*

## ⚠️ FIRST-RUN SETUP — Claude: delete this whole section when done

If `identity/about-me.md` still contains placeholder text ("REPLACE ME"), this brain
is brand new. Offer to set it up right now by interviewing your human:

1. Ask, conversationally and **one at a time** (not as a form):
   - Their name, and what they'd like you to call them
   - What they do (work, and what they build/care about outside it)
   - How they like to work with you (direct or chatty? big picture or detail?
     anything that annoys them about AI assistants?)
   - What they're currently working on (1–3 projects or ongoing threads)
2. Write what you learn:
   - `identity/about-me.md`      — who they are (facts, in their own words)
   - `identity/how-we-work.md`   — collaboration preferences
   - `projects/<name>.md`        — one short note per current project
3. Update `INDEX.md`: one line per note you wrote.
4. If any `{{PLACEHOLDER}}` tokens remain anywhere in the brain (setup.sh normally
   replaces them — check with a grep for `{{YOUR_NAME}}` across `*.md`), fill every
   hit with the name they gave you.
5. **Delete this entire "FIRST-RUN SETUP" section from CLAUDE.md.**
6. Commit everything: `git add -A && git commit -m "brain: first-run setup"`
   — and push if a remote is configured. (Committing directly is fine for this
   one-time setup; every write after it follows the Write protocol's worktree flow.)
7. Tell them their brain is live, and that from now on you'll remember.

Keep the interview light — 5 minutes, not an interrogation. They can always add
more later; the brain grows with use.

## Where the brain lives
- Canonical store: this git repo (a **private** GitHub repo), cloned locally.
- **Source of truth = the markdown files here.** Versioned in git → durable, offline-capable, restorable. No live service is required for the brain to work.
- Sync: a **SessionStart hook** (`tools/brain-session-start.sh`, installed by `setup.sh`) auto-pulls this clone when a session starts and injects a one-line status — a STALE warning means don't trust the clone blindly; an UNPUSHED-writes warning means run `tools/brain-write.sh sync`. Manual fallback: `git pull --ff-only`. The clone is a **read cache** — never edit files in it directly; every write publishes through the worktree flow in the Write protocol below.

## Who {{YOUR_NAME}} is (always-true essentials)
- See `identity/about-me.md` for who they are and `identity/how-we-work.md` for how we collaborate. Read both whenever the session is personal or strategic — they are small.
- This brain exists so I show up as the **same collaborator every time** — a long-term partner who remembers our history, not a stranger who resets each session.

## How the brain is organized
| Folder | What's in it | When to read |
|---|---|---|
| `identity/` | Who {{YOUR_NAME}} is, how we work together | Whenever context is personal/strategic — they're tiny |
| `projects/` | One mission-control note per initiative (state, decisions, links) | When working on that project |
| `knowledge/` | Dense, durable facts & gotchas (how-things-work) | Pull the specific note by relevance |
| `conventions/` | Standing preferences for how I should work | Honor these whenever they apply |
| `ideas/` | Idea seeds by category; `graduated/` = ones that became real | Capture per "Idea capture" below; browse when picking what to build |
| `pointers/` | Where external things live (other repos, vaults, secrets policy) | When you need something that isn't in the brain |
| `journal/` | Dated log of what we did together over time | For history/continuity; append notable sessions |
| `INDEX.md` | Catalog of every note + one-line descriptions | **Read this first when you need to find something and don't know which file** |
| `TODO.md` | The single to-do list — chores, reminders, follow-ups | Per "The to-do list" below; any time {{YOUR_NAME}} says **"todos"** |

## Recall protocol (use the brain without loading all of it)
1. Identity essentials come from `identity/` — two small files.
2. For anything deeper, **skim `INDEX.md`** and open only the notes whose descriptions match the task.
3. Prefer the **smallest set of notes** that covers the task. Do not dump the whole brain into context.

## Write protocol (how the brain grows)
When you learn something durable — a fact about {{YOUR_NAME}}, a decision, a project's state, a gotcha, a preference:
1. Write/update the right note. Frontmatter: `name`, `description`, `type` (`user`|`feedback`|`project`|`reference`|`idea`). **One fact per file**; link related notes with `[[name]]`.
2. Add/update its one-line entry in `INDEX.md`.
3. Publish via the **worktree flow — never edit the shared clone directly** (two sessions on one device silently clobber each other): `wt=$(~/claude-brain/tools/brain-write.sh open)` → make the edits inside `$wt` → `~/claude-brain/tools/brain-write.sh publish "$wt" "message"`. This commits in isolation and **pushes straight to remote `main` immediately** — connector surfaces see it live, other clones at their next pull; offline, the write lands on local `main` for `sync` to push later. (Clone devices only — connector surfaces commit via the GitHub API, which is already atomic.) Why + details: `docs/how-it-works.md`.
4. Don't record what a repo/codebase/git history already captures. Save what's **non-obvious and durable**.
5. Update existing notes instead of creating near-duplicates; delete notes that turn out to be wrong.
6. Big moments / end of a meaningful session → consider a dated `journal/` entry. This is how the relationship accumulates.

## The to-do list (standing chores & reminders)
- `TODO.md` (repo root) is {{YOUR_NAME}}'s **single to-do list** — recurring maintenance, one-shot reminders, follow-ups. Full mechanism: `conventions/todo-list.md`.
- **Once a day** (frontmatter `last-surfaced` < today): after handling what {{YOUR_NAME}} actually asked — never instead of it, and not when the session is clearly urgent — read `TODO.md`; if items are due (`next:` ≤ today; judgment on `when:` for uncached items), append a compact digest (all due items, one line each) and stamp `last-surfaced` via the write protocol. Saying **"todos"** opens the full list any time.
- Responses: **go** → execute where capable per the item's `needs:` · **later** → new `next:` hint · **mute** / **done** / **add …** → edit the note. "Remind me to X" anywhere = add.

## Idea capture (zero friction)
{{YOUR_NAME}} drops an idea on any surface — "idea: …" or just describing one — and Claude **files it immediately**: `ideas/<category>/<kebab-slug>.md`, frontmatter `name`/`description`/`type: idea`, body in their words. Reply is one line: "filed → ideas/apps/overlay-translator". New categories propose-first. Full protocol: `conventions/idea-capture.md`.

## Profile evaluation (the evidence-based living profile)
When {{YOUR_NAME}}'s **words, decisions, or credentials** in a session are hard evidence about who they are, how they work, or what they know (rules in `conventions/profile-evaluation.md`, incl. the knowledge-provenance exclusion — Claude-supplied knowledge never counts), append a dated one-liner to the `## Evidence log` in `identity/profile.md` (write protocol) and reply with one line: "profiled → <what was noted>". **Facts only in-session** — deductions happen solely in the consolidation pass (offered when the log hits ~10 entries).

## Secrets — NEVER store secret values here
- The brain stores **pointers only**: e.g. *"API key → password manager item 'Acme prod'"* or *"in the gitignored `.env` of that repo"*.
- Real secrets live in a password manager / gitignored `.env` files — never in this repo. See `pointers/secrets.md`.
- A brain leak must **never** be a credential leak. If you're about to write a token/key/password into a brain file — STOP and write a pointer instead. (`.gitignore` and gitleaks CI are backstops, not the policy.)
