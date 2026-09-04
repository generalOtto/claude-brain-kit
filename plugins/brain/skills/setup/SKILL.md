---
name: setup
description: Wire this machine to the brain — import stub in ~/.claude/CLAUDE.md, transcript retention, optional gitleaks pre-commit hook, template placeholders. Run once per machine after installing the brain plugin; safe to re-run.
disable-model-invocation: true
allowed-tools: Bash, Read, Edit, Write
---

# /brain:setup — wire this machine to the brain

Brain clone: the path printed by `"${CLAUDE_PLUGIN_ROOT}/hooks/session-start" --resolve` (it reads the plugin's `brain_dir` option; run it first and use that path everywhere below).
Shared checks: `"${CLAUDE_PLUGIN_ROOT}/hooks/session-start" --resolve` prints the clone
path the hook will use; `… --check-wired` says whether the bootloader is wired.
Run every step, report each as `✓ done` / `· already fine` / `⚠ needs you`, never
delete files or notes, touch only the settings.json keys named below, and never store a secret.

1. **Resolve the clone.** Run `--resolve`. If it fails, stop: tell the user to clone
   their brain (default `~/claude-brain`) or fix the plugin's `brain_dir` option
   (`/plugin` → brain → configure), then re-run.
2. **Privacy check.** `gh repo view --json visibility -q .visibility` inside the clone
   (skip silently if `gh` is missing). If `PUBLIC`: warn loudly and SHOW (do not run) the fix
   `gh repo edit --visibility private --accept-visibility-change-consequences`.
3. **Placeholders.** `grep -rl '{{YOUR_NAME}}' --include='*.md' <clone>`. If any hit:
   ask the user's name (default `git config user.name`), replace in every hit
   through the worktree flow (`wt=$(brain-write.sh open)` → sed inside `$wt` →
   `brain-write.sh publish "$wt" "brain: personalize placeholders"`).
4. **Wire the bootloader.** Run `--check-wired`.
   - `wired …` → already fine.
   - `not wired: … is a symlink to <target>` → do NOT edit through the symlink; tell
     the user to add the import line to `<target>` themselves and show the line.
   - otherwise: compose the stub — `@~/<path-under-home>/CLAUDE.md` when the clone is
     under `$HOME`, else `@<absolute path with forward slashes>/CLAUDE.md` — and
     append it to `~/.claude/CLAUDE.md` (create the file if missing; keep existing
     content). Re-run `--check-wired` and confirm `wired`.
5. **Transcript retention.** Read `~/.claude/settings.json` (create `{}` if missing).
   If `cleanupPeriodDays` is absent or < 3650, set it to 3650 with the Edit tool
   (valid JSON, keep every other key). Claude Code deletes idle transcripts after
   this many days — recall depends on them surviving.
6. **Legacy hook.** If `settings.json` has a `SessionStart` hook whose command contains
   `brain-session-start.sh`, remove that hook entry (the plugin's hook replaces it;
   two hooks = two pulls and two status lines). Leave every other hook alone.
7. **gitleaks pre-commit hook (optional).** If `command -v gitleaks` succeeds and
   `<clone>/.git/hooks/pre-commit` does not exist, offer to install:
   ```bash
   printf '#!/usr/bin/env bash\nexec gitleaks protect --staged --config "$(git rev-parse --show-toplevel)/.gitleaks.toml"\n' > <clone>/.git/hooks/pre-commit && chmod +x <clone>/.git/hooks/pre-commit
   ```
   If gitleaks is missing, say so once (`brew install gitleaks` / see docs/security.md)
   — CI still scans every push.
8. **Finish.** Summarize the report and tell the user to start a new session: the
   bootloader loads, and on a brand-new brain Claude offers the first-run interview.
