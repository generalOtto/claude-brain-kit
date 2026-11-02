#!/usr/bin/env bash
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
KIT="$PLUGIN/bin/brain-kit-update"
run_hook() { bash "$HOOK" 2>&1; }
K() { bash "$KIT" "$@"; }
W() { bash "$WRITE" "$@"; }
retention() { printf '{ "cleanupPeriodDays": %s }\n' "$1" > "$HOME/.claude/settings.json"; }
stamp() { cat "$HOME/.config/claude-brain/kit-update-check" 2>/dev/null; }
rewind_stamp() { sed -i.bak 's/^probe_date .*/probe_date 2000-01-01/' "$HOME/.config/claude-brain/kit-update-check"; }
kit_head() { git --git-dir="$SB/kit.git" rev-parse main; }
origin_file() { git --git-dir="$SB/origin.git" show "main:$1" 2>/dev/null; }

# A fake template: bare $SB/kit.git + working clone $SB/kit, first shipped as version $1 at date $2.
# The brain sandbox's first commit is "now", so a kit dated 2020 is one the brain was made FROM
# (derived base) and a kit dated 2030 is one the brain predates (no base).
kit_setup() {
  git init --quiet --bare -b main "$SB/kit.git"
  git -c init.defaultBranch=main clone --quiet "$SB/kit.git" "$SB/kit" 2>/dev/null
  mkdir -p "$SB/kit/plugins/brain/.claude-plugin" "$SB/kit/conventions" "$SB/kit/docs"
  printf '{ "name": "brain", "version": "%s" }\n' "$1" > "$SB/kit/plugins/brain/.claude-plugin/plugin.json"
  printf '# brain plugin — changelog\n\n## %s — %s\nfirst.\n' "$1" "${2%%T*}" > "$SB/kit/plugins/brain/CHANGELOG.md"
  printf 'rule one\nrule two\n' > "$SB/kit/conventions/todo-list.md"
  printf 'doc v1\n' > "$SB/kit/docs/a.md"
  kit_commit "brain: ship $1" "$2"
  export BRAIN_KIT_REPO="$SB/kit.git"
}
kit_commit() { git -C "$SB/kit" add -A; GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" git -C "$SB/kit" commit --quiet -m "$1"; git -C "$SB/kit" push --quiet origin main 2>/dev/null; }
kit_ship() {   # bump the kit to version $1 at date $2: plugin.json, a CHANGELOG entry, a doc change, a new tool
  local f="$SB/kit/plugins/brain/CHANGELOG.md"
  printf '{ "name": "brain", "version": "%s" }\n' "$1" > "$SB/kit/plugins/brain/.claude-plugin/plugin.json"
  { printf '# brain plugin — changelog\n\n## %s — %s\nnew in %s.\n\n' "$1" "${2%%T*}" "$1"; tail -n +2 "$f"; } > "$f.new" && mv "$f.new" "$f"
  printf 'doc v2\n' > "$SB/kit/docs/a.md"
  mkdir -p "$SB/kit/plugins/brain/bin"; printf '#!/bin/sh\n' > "$SB/kit/plugins/brain/bin/new-tool"
  kit_commit "brain: ship $1" "$2"
}
# the brain starts as a copy of the kit (what "Use this template" produces)
brain_from_kit() { cp -r "$SB/kit/plugins" "$SB/kit/conventions" "$SB/kit/docs" "$SB/brain/"; git -C "$SB/brain" add -A; git -C "$SB/brain" commit -qm "from template"; git -C "$SB/brain" push -q origin main; }

# ---- hook: first run arms the check, then alerts only when the kit moves -------------
t_setup; retention 3650; kit_setup 1.0.0 2020-01-01T00:00:00Z
out=$(run_hook); assert_contains "$out" "kit: template update check is on" "first run nudges once"
assert_contains "$out" "run /brain:update once" "nudge names the skill"
assert_eq "$(printf '%s' "$out" | wc -l | tr -d ' ')" "0" "still exactly one line"
assert_contains "$(stamp)" "baseline $(kit_head)" "baseline recorded on this device"
out=$(run_hook); assert_lacks "$out" "kit:" "same day, same kit: quiet"
kit_ship 1.1.0 2030-01-01T00:00:00Z
out=$(run_hook); assert_lacks "$out" "kit:" "probe is cached for the day"
rewind_stamp
out=$(run_hook); assert_contains "$out" "kit: template updates available ($(kit_head | cut -c1-7))" "next day: kit moved → alert with sha"
assert_contains "$out" "offer /brain:update" "alert asks Claude to offer the skill"
assert_contains "$(stamp)" "probe_sha $(kit_head)" "probe refreshed"
rewind_stamp; out=$(run_hook); assert_contains "$out" "kit: template updates available" "alert persists until reviewed"
t_teardown

# ---- hook: a recorded review wins over the device baseline --------------------------
t_setup; retention 3650; kit_setup 1.0.0 2020-01-01T00:00:00Z
printf 'repo %s\nreviewed %s\n' "$SB/kit.git" "$(kit_head)" > "$SB/brain/.kit-upstream"
unset BRAIN_KIT_REPO                                  # url comes from the file
out=$(run_hook); assert_lacks "$out" "kit:" "reviewed at head: quiet, no nudge"
assert_contains "$(stamp)" "probe_sha $(kit_head)" "url read from .kit-upstream"
kit_ship 1.1.0 2030-01-01T00:00:00Z; rewind_stamp
out=$(run_hook); assert_contains "$out" "kit: template updates available" "kit moved past the reviewed commit"
printf 'repo %s\nreviewed %s\n' "$SB/kit.git" "$(kit_head)" > "$SB/brain/.kit-upstream"
out=$(run_hook); assert_lacks "$out" "kit:" "reviewed again (any device): quiet"
t_teardown

# ---- hook: off, offline, unreachable → silent, no stamp ----------------------------------
t_setup; retention 3650
printf 'repo off\n' > "$SB/brain/.kit-upstream"; unset BRAIN_KIT_REPO
out=$(run_hook); assert_lacks "$out" "kit:" "repo off: no check"; assert_eq "$(stamp)" "" "repo off: no stamp"
export BRAIN_KIT_REPO=off; out=$(run_hook); assert_lacks "$out" "kit:" "BRAIN_KIT_REPO=off: no check"
export BRAIN_KIT_REPO="$SB/nowhere.git"
out=$(run_hook); assert_contains "$out" "brain: fresh" "unreachable kit: status line intact"
assert_lacks "$out" "kit:" "unreachable kit: silent"; assert_eq "$(stamp)" "" "unreachable kit: no stamp"
run_hook >/dev/null; assert_rc $? 0 "unreachable kit: exit 0"
t_teardown

t_setup; retention 3650; kit_setup 1.0.0 2020-01-01T00:00:00Z; go_offline
out=$(run_hook); assert_contains "$out" "STALE" "offline"; assert_lacks "$out" "kit:" "offline: probe skipped"
assert_eq "$(stamp)" "" "offline: nothing cached, retried next session"
t_teardown

# ---- brain-kit-update: derived base, status/log/files ----------------------------------
t_setup; kit_setup 1.0.0 2020-01-01T00:00:00Z; brain_from_kit
kit_ship 1.1.0 2030-01-01T00:00:00Z
printf 'rule one\nrule two\nrule three\n' > "$SB/kit/conventions/todo-list.md"; kit_commit "conventions: rule three" 2030-01-02T00:00:00Z
st=$(K status); assert_contains "$st" "base_source derived" "base derived from the brain's first commit"
assert_contains "$st" "base $(git --git-dir="$SB/kit.git" rev-list --max-parents=0 main)" "derived base is the kit's ship 1.0.0"
assert_contains "$st" "behind 2" "two kit commits since"
assert_contains "$st" "plugin_kit 1.1.0" "kit version"; assert_contains "$st" "plugin_in_brain 1.0.0" "brain's template copy version"
assert_contains "$st" "plugin_installed $(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' "$PLUGIN/.claude-plugin/plugin.json")" "installed version from the plugin root"
assert_eq "$(git -C "$SB/brain" remote get-url kit)" "$SB/kit.git" "kit remote added to the clone"
lg=$(K log); assert_contains "$lg" "brain: ship 1.1.0" "log lists kit commits"; assert_contains "$lg" "new in 1.1.0" "log shows added CHANGELOG lines"
assert_lacks "$lg" "first." "log omits unchanged CHANGELOG lines"
fl=$(K files)
assert_contains "$fl" "$(printf 'kit\tM\tdocs/a.md')" "kit-owned modified"
assert_contains "$fl" "$(printf 'kit\tA\tplugins/brain/bin/new-tool')" "kit-owned added"
assert_contains "$fl" "$(printf 'yours\tM\tconventions/todo-list.md')" "user-owned tagged yours"
# ---- apply: kit paths taken, a personalized convention merges three-way --------------
printf 'rule one (mine)\nrule two\n' > "$SB/brain/conventions/todo-list.md"; git -C "$SB/brain" commit -qam "personalize"; git -C "$SB/brain" push -q origin main
wt=$(W open); out=$(K apply "$wt" plugins docs/ conventions/todo-list.md); rc=$?
assert_rc "$rc" 0 "apply exits 0"
assert_contains "$out" "applied: M docs/a.md" "doc applied"; assert_contains "$out" "applied: A plugins/brain/bin/new-tool" "new tool applied"
assert_contains "$out" "applied: M conventions/todo-list.md" "convention applied"
assert_eq "$(cat "$wt/docs/a.md")" "doc v2" "kit-owned file is the kit's"
assert_eq "$(cat "$wt/conventions/todo-list.md")" "$(printf 'rule one (mine)\nrule two\nrule three')" "three-way: my line kept, kit's line added"
assert_eq "$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' "$wt/plugins/brain/.claude-plugin/plugin.json")" "1.1.0" "template copy bumped"
out=$(K apply "$wt" docs/); assert_contains "$out" "nothing to apply" "re-apply is a no-op"
out=$(K mark "$wt"); assert_contains "$out" "marked: reviewed up to $(kit_head | cut -c1-7)" "mark reports"
assert_contains "$(cat "$wt/.kit-upstream")" "repo $SB/kit.git" "mark keeps the url"
W publish "$wt" "brain: pull kit updates" 2>/dev/null
assert_contains "$(origin_file .kit-upstream)" "reviewed $(kit_head)" "reviewed commit published"
assert_eq "$(origin_file docs/a.md)" "doc v2" "pulled file on origin main"
st=$(K status); assert_contains "$st" "base_source recorded" "base now recorded"; assert_contains "$st" "behind 0" "nothing behind"
retention 3650; out=$(run_hook); assert_lacks "$out" "kit:" "hook quiet after the review"
t_teardown

# ---- apply: a real collision leaves markers, exits 1, names the file ---------------------
t_setup; kit_setup 1.0.0 2020-01-01T00:00:00Z; brain_from_kit
printf 'rule one (kit)\nrule two\n' > "$SB/kit/conventions/todo-list.md"; kit_commit "conventions: reword" 2030-01-01T00:00:00Z
printf 'rule one (mine)\nrule two\n' > "$SB/brain/conventions/todo-list.md"; git -C "$SB/brain" commit -qam "personalize"; git -C "$SB/brain" push -q origin main
wt=$(W open); out=$(K apply "$wt" conventions/todo-list.md 2>/dev/null); rc=$?
assert_rc "$rc" 1 "conflict exits 1"; assert_contains "$out" "conflict: conventions/todo-list.md" "conflict named"
assert_lacks "$out" "applied: M conventions/todo-list.md" "conflicted file not reported as applied"
assert_contains "$(cat "$wt/conventions/todo-list.md")" "<<<<<<<" "markers left for resolution"
printf 'rule one (mine, kit-reworded)\nrule two\n' > "$wt/conventions/todo-list.md"; git -C "$wt" add conventions/todo-list.md
K mark "$wt" >/dev/null; W publish "$wt" "resolved" 2>/dev/null
assert_contains "$(origin_file conventions/todo-list.md)" "kit-reworded" "resolution published"
t_teardown

# ---- no base: brain predates the kit → kit-owned only, taken outright ----------------------
t_setup; kit_setup 1.0.0 2030-01-01T00:00:00Z
mkdir -p "$SB/brain/docs"; echo mine > "$SB/brain/docs/mine.md"   # this brain's own doc under a kit-owned path
git -C "$SB/brain" add -A; git -C "$SB/brain" commit -qm "my doc"; git -C "$SB/brain" push -q origin main
st=$(K status); assert_contains "$st" "base none" "no base"; assert_contains "$st" "base_source none" "source none"
assert_contains "$st" "behind unknown" "behind unknown"; assert_contains "$st" "plugin_in_brain none" "no template copy in the brain"
lg=$(K log); assert_contains "$lg" "no base" "log explains"; assert_contains "$lg" "brain: ship 1.0.0" "log shows latest kit commits"
fl=$(K files); assert_contains "$fl" "# no base" "files explains"; assert_contains "$fl" "$(printf 'kit\tA\tdocs/a.md')" "kit-only file is A"
assert_lacks "$fl" "INDEX.md" "no base: the brain's own notes are not listed as deleted"
assert_contains "$fl" "$(printf 'yours\tD\tdocs/mine.md')" "no base: a brain-only file under a kit path is tagged yours"
wt=$(W open)
out=$(K apply "$wt" conventions/todo-list.md 2>&1); rc=$?; assert_rc "$rc" 1 "no base: refuses a user-owned path"; assert_contains "$out" "is yours" "refusal explains"
out=$(K apply "$wt" docs plugins/); assert_contains "$out" "applied: A docs/a.md" "no base: kit-owned taken outright"
assert_lacks "$out" "docs/mine.md" "no base: the brain's own file is not reported"
assert_eq "$(cat "$wt/docs/a.md")" "doc v1" "kit content"
assert_eq "$(cat "$wt/docs/mine.md")" "mine" "no base: the brain's own file under docs/ survives"
out=$(K apply "$wt" docs/mine.md); assert_contains "$out" "nothing to apply" "no base: a brain-only path has nothing to take"
t_teardown

# ---- off → exit 3; bad worktree → exit 1 ---------------------------------------------------------
t_setup; kit_setup 1.0.0 2020-01-01T00:00:00Z
K status >/dev/null 2>&1; assert_rc $? 0 "status ok"
export BRAIN_KIT_REPO=off; K status >/dev/null 2>&1; assert_rc $? 3 "repo off exits 3"
export BRAIN_KIT_REPO="$SB/kit.git"
K apply "$SB/not-a-worktree" docs >/dev/null 2>&1; assert_rc $? 1 "apply refuses a non-worktree"
K bogus >/dev/null 2>&1; assert_rc $? 2 "usage exits 2"
t_teardown

t_report
