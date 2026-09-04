#!/usr/bin/env bash
# brain-write.sh — concurrency-safe brain writes (shipped by the brain plugin, on PATH).
# See docs/how-it-works.md, "Why writes go through a worktree".
#
# Usage:
#   brain-write.sh open                  print path of a fresh worktree; make the edits there
#   brain-write.sh publish <wt> "<msg>"  commit the worktree, push straight to remote main, clean up
#   brain-write.sh sync                  push offline writes (local main ahead, pending-sync/* branches)
#
# Never edit the shared clone directly — two sessions on one device share it and can
# silently clobber each other's read-modify-write. Remote main is the serialization
# point: a push is an atomic ref update, a lost race is replayed with pull --rebase,
# and a genuine same-file collision surfaces as a rebase conflict instead of silent loss.
#
# Brain clone resolution (shared with hooks/session-start — keep identical):
#  $BRAIN_DIR → $CLAUDE_PLUGIN_OPTION_BRAIN_DIR → pluginConfigs["brain@claude-brain-kit"] brain_dir in
#  ~/.claude/settings.json → ~/claude-brain (if a git repo) → error.
#  (two-space indent on purpose: the usage printer only echoes `#   ` lines)
set -euo pipefail

normpath() {
  local p="$1"
  case "$p" in "~") p="$HOME" ;; "~/"*) p="$HOME/${p#\~/}" ;; esac
  if command -v cygpath >/dev/null 2>&1; then p=$(cygpath -u "$p" 2>/dev/null || printf '%s' "$p"); else p=${p//\\//}; fi
  printf '%s' "${p%/}"
}
resolve_brain() {
  local d="${BRAIN_DIR:-${CLAUDE_PLUGIN_OPTION_BRAIN_DIR:-}}" s="$HOME/.claude/settings.json"
  if [ -z "$d" ] && [ -f "$s" ]; then
    d=$(sed -n '/"brain@claude-brain-kit"/,/^[[:space:]]*}/ s/.*"brain_dir"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$s" | head -1 || true); d=${d//\\\\/\\}
  fi
  if [ -z "$d" ] && git -C "$HOME/claude-brain" rev-parse --git-dir >/dev/null 2>&1; then d="$HOME/claude-brain"; fi
  [ -n "$d" ] || return 1
  normpath "$d"
}
BRAIN=$(resolve_brain) || { echo "brain-write.sh: no brain clone found (looked at BRAIN_DIR, the plugin's brain_dir option, settings.json pluginConfigs, ~/claude-brain)" >&2; exit 1; }
[ -d "$BRAIN" ] || { echo "brain-write.sh: $BRAIN does not exist" >&2; exit 1; }
git -C "$BRAIN" rev-parse --git-dir >/dev/null 2>&1 || { echo "brain-write.sh: $BRAIN is not a git repo" >&2; exit 1; }

online()     { git -C "$BRAIN" ls-remote --exit-code origin main >/dev/null 2>&1; }
clone_idle() { [ "$(git -C "$BRAIN" symbolic-ref --short -q HEAD)" = main ] \
               && [ -z "$(git -C "$BRAIN" status --porcelain)" ]; }

case "${1:-}" in
  open)
    git -C "$BRAIN" worktree prune   # self-heal worktrees lost to /tmp wipes
    git -C "$BRAIN" fetch --quiet origin 2>/dev/null || true
    # base on the most advanced main — local main may be ahead after offline writes
    ref=origin/main
    git -C "$BRAIN" rev-parse --quiet --verify "$ref" >/dev/null || ref=main
    if [ "$ref" = origin/main ] \
       && git -C "$BRAIN" merge-base --is-ancestor origin/main main 2>/dev/null; then
      ref=main
    fi
    wt=$(mktemp -d "${TMPDIR:-/tmp}/brain-wt.XXXXXX")
    git -C "$BRAIN" worktree add --quiet --detach "$wt" "$ref"
    echo "$wt"
    ;;
  publish)
    wt=${2:?usage: brain-write.sh publish <worktree-path> "<commit message>"}
    msg=${3:?usage: brain-write.sh publish <worktree-path> "<commit message>"}
    git -C "$wt" add -A
    # empty status = retrying after a resolved rebase conflict; skip the commit
    [ -z "$(git -C "$wt" status --porcelain)" ] || git -C "$wt" commit --quiet -m "$msg"
    if ! git -C "$wt" push --quiet origin HEAD:main 2>/dev/null; then
      if online; then
        # lost a push race — replay on the winner's commit. A conflict here is a real
        # same-file collision: resolve it in $wt, `git rebase --continue`, re-run publish.
        git -C "$wt" pull --rebase --quiet origin main
        git -C "$wt" push --quiet origin HEAD:main
      elif clone_idle \
           && git -C "$BRAIN" merge --ff-only --quiet "$(git -C "$wt" rev-parse HEAD)" 2>/dev/null; then
        # offline: land the write on the clone's local main so it stays recallable here
        echo "offline: saved to local main — run 'brain-write.sh sync' when online" >&2
      else
        # offline AND the clone is busy — park the commit on a branch instead
        git -C "$wt" branch "pending-sync/$(date -u +%Y%m%dT%H%M%SZ)-$$"
        echo "offline: parked on a pending-sync/* branch — run 'brain-write.sh sync' when online" >&2
      fi
    fi
    git -C "$BRAIN" worktree remove "$wt"
    # fast-forward the shared clone only when it's idle
    if clone_idle; then
      git -C "$BRAIN" merge --ff-only --quiet origin/main 2>/dev/null || true
    fi
    ;;
  sync)
    online || { echo "still offline" >&2; exit 1; }
    git -C "$BRAIN" fetch --quiet origin
    # offline writes that landed on local main
    if ! git -C "$BRAIN" merge-base --is-ancestor main origin/main; then
      if ! git -C "$BRAIN" push --quiet origin main:main 2>/dev/null; then
        clone_idle || { echo "clone busy: cannot rebase local main — retry when idle" >&2; exit 1; }
        # conflict → resolve in the clone, `git rebase --continue`, re-run sync
        git -C "$BRAIN" pull --rebase --quiet origin main
        git -C "$BRAIN" push --quiet origin main:main
      fi
      echo "synced local main -> origin/main"
    fi
    # offline writes parked on branches
    git -C "$BRAIN" for-each-ref --format='%(refname:short)' 'refs/heads/pending-sync/*' |
    while read -r b; do
      if ! git -C "$BRAIN" push --quiet origin "$b:main" 2>/dev/null; then
        wt=$(mktemp -d "${TMPDIR:-/tmp}/brain-wt.XXXXXX")
        git -C "$BRAIN" worktree add --quiet "$wt" "$b"
        if ! git -C "$wt" pull --rebase --quiet origin main; then
          # a real same-file collision — finish it by hand, then clean up
          echo "conflict syncing $b: resolve in $wt, run 'git rebase --continue', then:" >&2
          echo "  git -C '$wt' push origin HEAD:main && git -C '$BRAIN' worktree remove '$wt' && git -C '$BRAIN' branch -D '$b'" >&2
          continue
        fi
        git -C "$wt" push --quiet origin HEAD:main
        git -C "$BRAIN" worktree remove "$wt"
      fi
      git -C "$BRAIN" branch -D "$b" >/dev/null
      echo "synced $b -> main"
    done
    ;;
  *)
    sed -n 's/^#   //p' "$0" >&2
    exit 2
    ;;
esac
