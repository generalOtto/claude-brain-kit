#!/usr/bin/env bash
# brain-session-start.sh — Claude Code SessionStart hook.
# Freshens the brain clone and prints ONE status line; stdout lands in Claude's
# context at session start. Installed into ~/.claude/settings.json by setup.sh
# (matcher: startup|clear). See docs/how-it-works.md, "Session start: the clone
# freshens itself".
#
# Invariants:
#   - ALWAYS exits 0 — a brain problem must never break session start.
#   - Never hangs — no terminal prompts, bounded ssh connect, hard timeout where
#     coreutils provides one (macOS without coreutils degrades to the ssh bounds).
#   - Report-only beyond the ff-pull — never runs sync, never touches worktrees.

BRAIN="${BRAIN_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

git -C "$BRAIN" rev-parse --git-dir >/dev/null 2>&1 || {
  echo "brain: clone at $BRAIN is missing or broken — brain may be stale"
  exit 0
}

export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="ssh -oBatchMode=yes -oConnectTimeout=5"
TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"

before=$(git -C "$BRAIN" rev-parse HEAD 2>/dev/null)
pull_ok=false
if [ -n "$TIMEOUT_BIN" ]; then
  "$TIMEOUT_BIN" 15 git -C "$BRAIN" pull --ff-only --quiet >/dev/null 2>&1 && pull_ok=true
else
  git -C "$BRAIN" pull --ff-only --quiet >/dev/null 2>&1 && pull_ok=true
fi

if $pull_ok; then
  after=$(git -C "$BRAIN" rev-parse HEAD 2>/dev/null)
  if [ "$before" = "$after" ]; then
    status="fresh"
  else
    status="pulled $(git -C "$BRAIN" rev-list --count "$before..$after" 2>/dev/null || echo '?') new commit(s)"
  fi
else
  status="pull FAILED (offline or diverged) — clone may be STALE"
fi

# Offline writes waiting for a push? (local main ahead, or parked pending-sync/*)
ahead=$(git -C "$BRAIN" rev-list --count origin/main..main 2>/dev/null || echo 0)
pending=$(git -C "$BRAIN" for-each-ref 'refs/heads/pending-sync/*' | wc -l | tr -d '[:space:]')
suffix=""
if [ "${ahead:-0}" -gt 0 ] || [ "${pending:-0}" -gt 0 ]; then
  suffix=" | UNPUSHED writes waiting (${ahead} on local main, ${pending} pending-sync) — run tools/brain-write.sh sync"
fi

echo "brain: ${status}${suffix}"
exit 0
