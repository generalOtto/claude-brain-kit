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
4. If any `{{PLACEHOLDER}}` tokens remain in this file or `INDEX.md` (setup.sh
   normally replaces them), fill them in with the name they gave you.
5. **Delete this entire "FIRST-RUN SETUP" section from CLAUDE.md.**
6. Commit everything: `git add -A && git commit -m "brain: first-run setup"`
   — and push if a remote is configured.
7. Tell them their brain is live, and that from now on you'll remember.

Keep the interview light — 5 minutes, not an interrogation. They can always add
more later; the brain grows with use.

## Where the brain lives
- Canonical store: this git repo (a **private** GitHub repo), cloned locally.
- **Source of truth = the markdown files here.** Versioned in git → durable, offline-capable, restorable. No live service is required for the brain to work.
- Sync: `git pull` in this repo at the start of a session when practical; commit + push after writing memories.

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
| `pointers/` | Where external things live (other repos, vaults, secrets policy) | When you need something that isn't in the brain |
| `journal/` | Dated log of what we did together over time | For history/continuity; append notable sessions |
| `INDEX.md` | Catalog of every note + one-line descriptions | **Read this first when you need to find something and don't know which file** |

## Recall protocol (use the brain without loading all of it)
1. Identity essentials come from `identity/` — two small files.
2. For anything deeper, **skim `INDEX.md`** and open only the notes whose descriptions match the task.
3. Prefer the **smallest set of notes** that covers the task. Do not dump the whole brain into context.

## Write protocol (how the brain grows)
When you learn something durable — a fact about {{YOUR_NAME}}, a decision, a project's state, a gotcha, a preference:
1. Write/update the right note. Frontmatter: `name`, `description`, `type` (`user`|`feedback`|`project`|`reference`). **One fact per file**; link related notes with `[[name]]`.
2. Add/update its one-line entry in `INDEX.md`.
3. Commit with a clear message — and push when practical.
4. Don't record what a repo/codebase/git history already captures. Save what's **non-obvious and durable**.
5. Update existing notes instead of creating near-duplicates; delete notes that turn out to be wrong.
6. Big moments / end of a meaningful session → consider a dated `journal/` entry. This is how the relationship accumulates.

## Secrets — NEVER store secret values here
- The brain stores **pointers only**: e.g. *"API key → password manager item 'Acme prod'"* or *"in the gitignored `.env` of that repo"*.
- Real secrets live in a password manager / gitignored `.env` files — never in this repo. See `pointers/secrets.md`.
- A brain leak must **never** be a credential leak. If you're about to write a token/key/password into a brain file — STOP and write a pointer instead. (`.gitignore` and gitleaks CI are backstops, not the policy.)
