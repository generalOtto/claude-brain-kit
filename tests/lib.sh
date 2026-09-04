#!/usr/bin/env bash
# tests/lib.sh — shared helpers for the plugin's bash tests.
# Every test runs in a throwaway sandbox: its own $HOME, a bare git origin,
# a "brain" clone wired to it, and an "other" clone that plays a second device.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN="$ROOT/plugins/brain"
# shellcheck disable=SC2034  # used by the sourcing *.test.sh files
HOOK="$PLUGIN/hooks/session-start"
# shellcheck disable=SC2034
WRITE="$PLUGIN/bin/brain-write.sh"
BASE_TMP="${TMPDIR:-/tmp}"   # captured ONCE — t_setup overrides TMPDIR per sandbox
pass=0; fail=0

t_setup() {
  SB=$(mktemp -d "$BASE_TMP/brain-test.XXXXXX")
  export HOME="$SB/home"; mkdir -p "$HOME/.claude"
  export TMPDIR="$SB/tmp"; mkdir -p "$TMPDIR"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 GIT_EDITOR=true
  git init --quiet --bare -b main "$SB/origin.git"
  git -c init.defaultBranch=main clone --quiet "$SB/origin.git" "$SB/brain" 2>/dev/null
  printf -- '---\nname: index\n---\n# INDEX\n' > "$SB/brain/INDEX.md"
  printf '# bootloader\n' > "$SB/brain/CLAUDE.md"
  git -C "$SB/brain" add -A && git -C "$SB/brain" commit --quiet -m init
  git -C "$SB/brain" push --quiet -u origin main 2>/dev/null
  git -c init.defaultBranch=main clone --quiet "$SB/origin.git" "$SB/other" 2>/dev/null
  export BRAIN_DIR="$SB/brain"
  unset CLAUDE_PLUGIN_OPTION_BRAIN_DIR
}
t_teardown() { cd / && rm -rf "$SB"; }

# other device pushes N commits
other_push() { local n=${1:-1} i; for i in $(seq "$n"); do echo "$RANDOM" >> "$SB/other/note-$i.md"; git -C "$SB/other" add -A; git -C "$SB/other" commit --quiet -m "other $i"; done; git -C "$SB/other" push --quiet origin main 2>/dev/null; }
go_offline() { git -C "$SB/brain" remote set-url origin "$SB/nowhere.git"; }
go_online()  { git -C "$SB/brain" remote set-url origin "$SB/origin.git"; }

assert_eq()       { if [ "$1" = "$2" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  FAIL $3: expected [$2] got [$1]"; fi; }
assert_contains() { case "$1" in *"$2"*) pass=$((pass+1));; *) fail=$((fail+1)); echo "  FAIL $3: [$1] lacks [$2]";; esac; }
assert_lacks()    { case "$1" in *"$2"*) fail=$((fail+1)); echo "  FAIL $3: [$1] contains [$2]";; *) pass=$((pass+1));; esac; }
assert_rc()       { if [ "$1" -eq "$2" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  FAIL $3: exit $1, expected $2"; fi; }
t_report() { echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ]; }
is_windows() { case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) return 0;; *) return 1;; esac; }
