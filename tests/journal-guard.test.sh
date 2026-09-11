#!/usr/bin/env bash
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
GUARD="$PLUGIN/hooks/journal-guard"
run_guard() { printf '%s' "$1" | bash "$GUARD" 2>&1; }
stop_json() { printf '{"hook_event_name":"Stop","stop_hook_active":%s}' "${1:-false}"; }

today() { date +%Y-%m-%d; }
yesterday() { date -v-1d +%Y-%m-%d 2>/dev/null || date -d yesterday +%Y-%m-%d; }

# t_setup's own "init" commit lands with today's real date (no GIT_*_DATE set),
# which would make every sandbox start with "1 commit today" already. Push its
# date back to yesterday so tests start from a clean "no commits today" slate.
backdate_init() {
  local y; y=$(yesterday)
  GIT_COMMITTER_DATE="$y 12:00:00" GIT_AUTHOR_DATE="$y 12:00:00" \
    git -C "$SB/brain" commit --quiet --amend --no-edit
}
commit_today() {
  echo "$RANDOM" >> "$SB/brain/note-$RANDOM-$$.md"
  git -C "$SB/brain" add -A
  git -C "$SB/brain" commit --quiet -m "${1:-today}"
}

# no commits today → allow (silent, exit 0)
t_setup; backdate_init
out=$(run_guard "$(stop_json false)"); rc=$?
assert_eq "$out" "" "no commits today: silent"
assert_rc "$rc" 0 "no commits today: exit 0"
t_teardown

# commits today + no journal entry → block, reason names the date and count
t_setup; backdate_init; commit_today; commit_today
out=$(run_guard "$(stop_json false)"); rc=$?
assert_contains "$out" '"decision":"block"' "commits + no journal: blocks"
assert_contains "$out" "2 commit(s) today" "reason mentions count"
assert_contains "$out" "journal/$(today)-*.md" "reason mentions today's journal path"
assert_rc "$rc" 0 "block path still exits 0"
python3 -c 'import json,sys; json.loads(sys.argv[1])' "$out" >/dev/null 2>&1
assert_rc $? 0 "block output is valid JSON"
t_teardown

# commits today + today's journal entry present → allow
t_setup; backdate_init; commit_today
mkdir -p "$SB/brain/journal"
echo "# journal" > "$SB/brain/journal/$(today)-session.md"
git -C "$SB/brain" add -A; git -C "$SB/brain" commit --quiet -m journal
out=$(run_guard "$(stop_json false)")
assert_eq "$out" "" "journal present: silent allow"
t_teardown

# stop_hook_active: true → allow, never block twice
t_setup; backdate_init; commit_today
out=$(run_guard "$(stop_json true)")
assert_eq "$out" "" "stop_hook_active true: silent allow"
t_teardown

# BRAIN_JOURNAL_GUARD=off → allow regardless of state
t_setup; backdate_init; commit_today
out=$(BRAIN_JOURNAL_GUARD=off run_guard "$(stop_json false)")
assert_eq "$out" "" "opt-out env var: silent allow"
t_teardown

# no brain dir resolvable → allow
t_setup; unset BRAIN_DIR
out=$(run_guard "$(stop_json false)"); rc=$?
assert_eq "$out" "" "no brain dir: silent"
assert_rc "$rc" 0 "no brain dir: exit 0"
t_teardown

t_report
