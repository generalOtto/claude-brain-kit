#!/usr/bin/env bash
# brain-write.sh — concurrency-safe brain writes.
# See docs/how-it-works.md, "Why writes go through a worktree".
#
# Usage:
#   tools/brain-write.sh open                  print path of a fresh worktree; make the edits there
#   tools/brain-write.sh publish <wt> "<msg>"  commit the worktree, push straight to remote main, clean up
#   tools/brain-write.sh sync                  push offline writes (local main ahead, pending-sync/* branches)
#
# Never edit the shared clone directly — two sessions on one device share it and can
# silently clobber each other's read-modify-write. Remote main is the serialization
# point: a push is an atomic ref update, a lost race is replayed with pull --rebase,
# and a genuine same-file collision surfaces as a rebase conflict instead of silent loss.
set -euo pipefail
BRAIN="${BRAIN_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

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
        echo "offline: saved to local main — run '$0 sync' when online" >&2
      else
        # offline AND the clone is busy — park the commit on a branch instead
        git -C "$wt" branch "pending-sync/$(date -u +%Y%m%dT%H%M%SZ)-$$"
        echo "offline: parked on a pending-sync/* branch — run '$0 sync' when online" >&2
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
