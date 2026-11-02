---
name: update
description: Check the claude-brain-kit template for updates and pull them into this brain — plugin version, protocol and convention changes, docs, tests. Use when the session-start line says "kit: template updates available" (ask the user first), when the user asks to update the brain kit / template / plugin, or any time to check.
allowed-tools: Bash, Read, Edit, Write
---

# /brain:update — pull template updates into this brain

A brain is a copy of the kit made with "Use this template", so kit improvements never
reach it on their own. `brain-kit-update` (on PATH) bridges that: it fetches the kit as
the `kit` remote of the brain clone and applies `base..kit/main` as a three-way patch, so
files you personalized merge instead of being overwritten. Clone: the path printed by
`"${CLAUDE_PLUGIN_ROOT}/hooks/session-start" --resolve`.

**Nothing changes without a yes.** When the session-start line prompted this, first tell
the user in one line that the template has updates and ask whether to review them. Never
run step 4 or 5 on your own initiative.

1. **Status.** `brain-kit-update status` → `key value` lines. `behind 0` and
   `plugin_installed` = `plugin_kit` → say the brain is current and stop. Exit 3 means the
   check is off (`repo off` in `.kit-upstream`) — say so and stop. Exit 1 = offline; stop.
2. **What changed.** `brain-kit-update log` (commit subjects + the CHANGELOG entries added)
   and `brain-kit-update files` (`kit`/`yours` tag, status letter, path). Summarize in a
   few lines: what the new plugin version brings, which kit-owned paths move, and which of
   the user's own files (`yours`: `CLAUDE.md`, `conventions/`, …) the kit changed —
   those are protocol updates the user may want, merged three-way into their version.
   `base_source derived` → mention once that the base was inferred from the brain's first
   commit (the kit commit current when the template was used); `none` → the brain
   predates the kit's history, so only kit-owned paths can be pulled (taken outright);
   files that exist only in this brain under those paths show as `yours` with `D` and
   are never removed — don't offer them.
3. **Ask.** Default offer: pull every `kit` path, and the `yours` paths too when the
   changes are protocol/convention text (not personal content). Honor "skip X", or
   "nothing" — a no still ends with step 5 so the daily line goes quiet.
4. **Apply** (only what was agreed), through the worktree flow:
   ```bash
   wt=$(brain-write.sh open)
   brain-kit-update apply "$wt" <path> [<path>…]     # paths from `files`; directories allowed (plugins/ tests/ docs/)
   ```
   Each `applied: <S> <path>` line is in the worktree's index. `conflict: <path>` lines
   (exit 1) are real collisions: open the file in `$wt`, resolve the `<<<<<<<`/`>>>>>>>`
   markers keeping the user's content and the kit's intent, show the user anything
   non-obvious, then `git -C "$wt" add <path>`. Edit only inside `$wt`.
5. **Record and publish.** `brain-kit-update mark "$wt"` writes the reviewed kit commit
   into `$wt/.kit-upstream` (this is what silences the session-start line, on every
   device). Then `brain-write.sh publish "$wt" "brain: pull kit updates (plugin <plugin_kit>)"`
   — or `"brain: reviewed kit updates, none pulled"` after a no. `offline: …` is safe;
   `brain-write.sh sync` later.
6. **Plugin.** If `plugin_installed` < `plugin_kit`: run
   `claude plugin update brain@claude-brain-kit` and tell the user to start a new session
   so the updated hooks and skills load (the running session keeps the old ones). If the
   command fails, show it for the user to run themselves.
7. **Report** in a few lines: what was pulled, what was skipped, conflicts resolved, and
   whether a restart is needed.

Disable the check for good: set `repo off` in `.kit-upstream` (through the write skill).
A brain whose plugin source is customized should point `repo` at its own fork instead.
