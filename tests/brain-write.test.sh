#!/usr/bin/env bash
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
W() { bash "$WRITE" "$@"; }
origin_log() { git --git-dir="$SB/origin.git" log --format=%s main; }

# 1. open → detached worktree on the newest main
t_setup
wt=$(W open); assert_eq "$([ -d "$wt" ] && echo yes)" "yes" "open creates worktree"
assert_eq "$(git -C "$wt" rev-parse HEAD)" "$(git -C "$SB/brain" rev-parse origin/main)" "worktree at origin/main"
# 2. publish online → on origin, worktree gone, clone fast-forwarded
echo hi > "$wt/a.md"; W publish "$wt" "add a" 2>/dev/null
assert_contains "$(origin_log)" "add a" "published to origin"
assert_eq "$([ -d "$wt" ] || echo gone)" "gone" "worktree removed"
assert_eq "$(git -C "$SB/brain" rev-parse HEAD)" "$(git -C "$SB/brain" rev-parse origin/main)" "clone fast-forwarded"
t_teardown

# 3. lost push race → replayed with rebase, both commits land
t_setup
wt=$(W open); echo mine > "$wt/mine.md"; other_push 1
W publish "$wt" "mine" 2>/dev/null
assert_contains "$(origin_log)" "mine" "race: mine landed"; assert_contains "$(origin_log)" "other 1" "race: theirs kept"
t_teardown

# 4. offline + idle clone → lands on local main
t_setup
wt=$(W open); echo off > "$wt/off.md"; go_offline
msg=$(W publish "$wt" "offline write" 2>&1); assert_contains "$msg" "offline: saved to local main" "offline idle message"
assert_contains "$msg" "run 'brain-write.sh sync'" "sync hint uses bare name"
assert_eq "$(git -C "$SB/brain" rev-list --count origin/main..main)" "1" "local main ahead by 1"
# 5. sync when back online
go_online; out=$(W sync 2>&1); assert_contains "$out" "synced local main -> origin/main" "sync local main"
assert_contains "$(origin_log)" "offline write" "offline write reached origin"
t_teardown

# 6. offline + busy clone → parked on pending-sync/*, then synced
t_setup
wt=$(W open); echo p > "$wt/p.md"; go_offline; echo dirty > "$SB/brain/dirty.md"
msg=$(W publish "$wt" "parked" 2>&1); assert_contains "$msg" "parked on a pending-sync/" "offline busy message"
assert_eq "$(git -C "$SB/brain" for-each-ref 'refs/heads/pending-sync/*' | wc -l | tr -d ' ')" "1" "one pending branch"
rm "$SB/brain/dirty.md"; go_online; out=$(W sync 2>&1); assert_contains "$out" "synced pending-sync/" "pending branch synced"
assert_eq "$(git -C "$SB/brain" for-each-ref 'refs/heads/pending-sync/*' | wc -l | tr -d ' ')" "0" "pending branch deleted"
t_teardown

# 7. sync conflict → instructions, no crash
t_setup
wt=$(W open); echo A > "$wt/same.md"; go_offline; echo dirty > "$SB/brain/dirty.md"; W publish "$wt" "A" 2>/dev/null
echo B > "$SB/other/same.md"; git -C "$SB/other" add -A; git -C "$SB/other" commit -qm B; git -C "$SB/other" push -q origin main 2>/dev/null
rm "$SB/brain/dirty.md"; go_online; out=$(W sync 2>&1); rc=$?
assert_contains "$out" "conflict syncing pending-sync/" "conflict reported with instructions"; assert_rc $rc 0 "sync continues past a conflict"
t_teardown

# still offline
t_setup; go_offline; W sync >/dev/null 2>&1; assert_rc $? 1 "sync offline exits 1"; t_teardown

# resolution ladder + usage
t_setup; unset BRAIN_DIR
W open >/dev/null 2>&1; assert_rc $? 1 "no clone → exit 1"
export CLAUDE_PLUGIN_OPTION_BRAIN_DIR="$SB/brain"; wt=$(W open); assert_eq "$([ -d "$wt" ] && echo yes)" "yes" "resolve via plugin option"; W publish "$wt" "noop" 2>/dev/null
t_teardown
t_setup; W bogus >/dev/null 2>&1; assert_rc $? 2 "usage exit 2"; t_teardown

t_report
