#!/usr/bin/env bash
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
run_hook() { bash "$HOOK" "$@" 2>&1; }
# Git Bash turns `ln -s` on a directory into a COPY, so brain-link is a distinct clone
# there; the test therefore points BRAIN_DIR at brain-link itself on every platform.
wire() { printf '@~/brain-link/CLAUDE.md\n' > "$HOME/.claude/CLAUDE.md"; ln -s "$SB/brain" "$HOME/brain-link" 2>/dev/null || cp -r "$SB/brain" "$HOME/brain-link"; export BRAIN_DIR="$HOME/brain-link"; }
retention() { printf '{ "cleanupPeriodDays": %s }\n' "$1" > "$HOME/.claude/settings.json"; }

t_setup; retention 3650
out=$(run_hook); assert_contains "$out" "brain: fresh" "fresh clone"
assert_contains "$out" "not wired: run /brain:setup" "unwired nudge"
assert_eq "$(printf '%s' "$out" | wc -l | tr -d ' ')" "0" "exactly one line"
t_teardown

t_setup; retention 3650; other_push 2
out=$(run_hook); assert_contains "$out" "pulled 2 new commit(s)" "pulled N"
t_teardown

t_setup; retention 3650; go_offline
out=$(run_hook); assert_contains "$out" "STALE" "offline is STALE"
t_teardown

t_setup; retention 3650; echo x > "$SB/brain/local.md"; git -C "$SB/brain" add -A; git -C "$SB/brain" commit -qm local; go_offline
out=$(run_hook); assert_contains "$out" "UNPUSHED writes waiting (1 on local main" "unpushed suffix"
assert_contains "$out" "run brain-write.sh sync" "sync hint has no tools/ prefix"
t_teardown

t_setup; retention 3650; wire
out=$(run_hook); assert_lacks "$out" "not wired" "wired via @~ line"
run_hook --check-wired >/dev/null; assert_rc $? 0 "--check-wired exit 0"
printf '@~/brain-link/CLAUDE.md\r\n' > "$HOME/.claude/CLAUDE.md"
run_hook --check-wired >/dev/null; assert_rc $? 0 "CRLF import line still wired"
t_teardown

t_setup; retention 3650
run_hook --check-wired >/dev/null; assert_rc $? 1 "--check-wired exit 1 when unwired"
if ! is_windows; then
  ln -s "$SB/brain/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
  out=$(run_hook); assert_lacks "$out" "not wired" "wired via symlink"
  rm "$HOME/.claude/CLAUDE.md"; ln -s "$SB/other/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
  out=$(run_hook --check-wired); assert_contains "$out" "symlink to" "foreign symlink reported"
fi
t_teardown

t_setup; rm -f "$HOME/.claude/settings.json"
out=$(run_hook); assert_contains "$out" "transcripts expire in 30d: run /brain:setup" "absent retention key"
retention 90;   out=$(run_hook); assert_contains "$out" "transcripts expire in 90d" "low retention"
retention 3650; out=$(run_hook); assert_lacks "$out" "transcripts expire" "retention ok"
t_teardown

t_setup; retention 3650
unset BRAIN_DIR
export CLAUDE_PLUGIN_OPTION_BRAIN_DIR="$SB/brain"; assert_eq "$(run_hook --resolve)" "$SB/brain" "resolve via plugin option"
unset CLAUDE_PLUGIN_OPTION_BRAIN_DIR
printf '{\n  "cleanupPeriodDays": 3650,\n  "pluginConfigs": { "brain@claude-brain-kit": { "options": { "brain_dir": "%s" } } }\n}\n' "$SB/brain" > "$HOME/.claude/settings.json"
assert_eq "$(run_hook --resolve)" "$SB/brain" "resolve via settings.json pluginConfigs"
retention 3650; mkdir -p "$HOME/claude-brain"; git -C "$HOME/claude-brain" init -q
assert_eq "$(run_hook --resolve)" "$HOME/claude-brain" "resolve via ~/claude-brain default"
rm -rf "$HOME/claude-brain"
out=$(run_hook); assert_contains "$out" "brain: no clone found" "no clone → one line, still exit 0"; run_hook >/dev/null; assert_rc $? 0 "status mode always exits 0"
run_hook --resolve >/dev/null; assert_rc $? 1 "--resolve exits 1 when none"
t_teardown

t_setup; retention 3650
# shellcheck disable=SC2088  # the literal ~ is what the script must expand
assert_eq "$(BRAIN_DIR='~/brain-tilde' bash -c 'mkdir -p ~/brain-tilde; git -C ~/brain-tilde init -q; bash "$0" --resolve' "$HOOK")" "$HOME/brain-tilde" "tilde expansion"
t_teardown

# pending-sync branch counts as unpushed
t_setup; retention 3650; git -C "$SB/brain" branch pending-sync/20260101T000000Z-1 >/dev/null
out=$(run_hook); assert_contains "$out" "1 pending-sync" "pending-sync branch counted"
t_teardown

# settings.json scrape: scoped to this plugin, survives garbage
t_setup; unset BRAIN_DIR
printf '{\n  "pluginConfigs": {\n    "other@x": { "options": { "brain_dir": "/wrong" } },\n    "brain@claude-brain-kit": { "options": { "brain_dir": "%s" } }\n  },\n  "cleanupPeriodDays": 3650\n}\n' "$SB/brain" > "$HOME/.claude/settings.json"
assert_eq "$(run_hook --resolve)" "$SB/brain" "brain_dir scoped to this plugin's key"
printf 'not json at all {{{ "brain_dir": ' > "$HOME/.claude/settings.json"
export BRAIN_DIR="$SB/brain"; out=$(run_hook); assert_contains "$out" "brain: fresh" "garbage settings.json still yields a status line"; run_hook >/dev/null; assert_rc $? 0 "garbage settings.json exits 0"
t_teardown

# concurrency: two hooks on one clone — a second session, or the legacy settings.json
# hook next to the plugin — must not report STALE; `git pull` did (interleaved FETCH_HEAD).
t_setup; retention 3650; other_push 2
out=$( (run_hook | sed 's/^/A /') & (run_hook | sed 's/^/B /') & wait )
assert_lacks "$out" "STALE" "two hooks at once: no false STALE"
assert_contains "$out" "pulled 2 new commit(s)" "two hooks at once: one of them pulled"
t_teardown

# lock races are retried once: a transient index.lock (fast-forward) and a transient ref lock (fetch)
t_setup; retention 3650; other_push 1
touch "$SB/brain/.git/index.lock"; (sleep 0.5; rm -f "$SB/brain/.git/index.lock") &
out=$(run_hook); assert_contains "$out" "pulled 1 new commit(s)" "transient index.lock: retry pulls"
wait
other_push 1; mkdir -p "$SB/brain/.git/refs/remotes/origin"
touch "$SB/brain/.git/refs/remotes/origin/main.lock"; (sleep 0.5; rm -f "$SB/brain/.git/refs/remotes/origin/main.lock") &
out=$(run_hook); assert_contains "$out" "pulled 1 new commit(s)" "transient ref lock: fetch retry pulls"
wait
t_teardown

# diverged (local commit + remote commit) is still reported, never merged
t_setup; retention 3650; echo y > "$SB/brain/mine.md"; git -C "$SB/brain" add -A; git -C "$SB/brain" commit -qm mine; other_push 1
out=$(run_hook); assert_contains "$out" "STALE" "diverged is STALE"
assert_eq "$(git -C "$SB/brain" rev-list --count HEAD)" "2" "diverged clone left untouched"
t_teardown

# missing remote-tracking ref → ladder still fast-forwards (no false STALE)
t_setup; retention 3650; other_push 1; git -C "$SB/brain" update-ref -d refs/remotes/origin/main
out=$(run_hook); assert_contains "$out" "pulled 1 new commit(s)" "missing origin/main ref recovers"
t_teardown

# detached HEAD → report-only: HEAD must not move
t_setup; retention 3650; other_push 1; git -C "$SB/brain" checkout -q --detach HEAD; h=$(git -C "$SB/brain" rev-parse HEAD)
out=$(run_hook); assert_contains "$out" "pull skipped" "detached HEAD skips ff"; assert_eq "$(git -C "$SB/brain" rev-parse HEAD)" "$h" "detached HEAD unchanged"
t_teardown

# paused rebase → report-only
t_setup; retention 3650; other_push 1; mkdir -p "$SB/brain/.git/rebase-merge"; h=$(git -C "$SB/brain" rev-parse HEAD)
out=$(run_hook); assert_contains "$out" "pull skipped" "rebase in progress skips ff"; assert_eq "$(git -C "$SB/brain" rev-parse HEAD)" "$h" "HEAD unchanged during rebase"
rm -rf "$SB/brain/.git/rebase-merge"; t_teardown

# non-upstream branch → report-only, local main untouched
t_setup; retention 3650; other_push 1; git -C "$SB/brain" checkout -q -b feature; m=$(git -C "$SB/brain" rev-parse main)
out=$(run_hook); assert_contains "$out" "pull skipped (clone on 'feature'" "feature branch skips ff"; assert_eq "$(git -C "$SB/brain" rev-parse main)" "$m" "main untouched"
t_teardown

# local branch named differently from its upstream still fast-forwards
t_setup; retention 3650; git -C "$SB/brain" checkout -q -b brain; git -C "$SB/brain" branch -q -u origin/main; other_push 1
out=$(run_hook); assert_contains "$out" "pulled 1 new commit(s)" "tracking branch with a different name fast-forwards"
t_teardown

# a clone-level core.sshCommand is honoured (deploy-key setups)
t_setup; retention 3650
printf '#!/usr/bin/env bash\necho marker > "%s/ssh-marker"\nexec ssh "$@"\n' "$SB" > "$SB/myssh"; chmod +x "$SB/myssh"
git -C "$SB/brain" config core.sshCommand "$SB/myssh"; git -C "$SB/brain" remote set-url origin "ssh://127.0.0.1:1/nonexistent.git"
run_hook >/dev/null; assert_eq "$([ -f "$SB/ssh-marker" ] && echo yes)" "yes" "core.sshCommand wrapper invoked"
t_teardown

# real-world settings.json layout: enabledPlugins block (with the plugin key) precedes pluginConfigs
t_setup; retention 3650; unset BRAIN_DIR
printf '{\n  "enabledPlugins": {\n    "brain@claude-brain-kit": true\n  },\n  "cleanupPeriodDays": 3650,\n  "pluginConfigs": {\n    "brain@claude-brain-kit": {\n      "options": {\n        "brain_dir": "%s"\n      }\n    }\n  }\n}\n' "$SB/brain" > "$HOME/.claude/settings.json"
assert_eq "$(run_hook --resolve)" "$SB/brain" "enabledPlugins-first layout resolves"
t_teardown

t_report
