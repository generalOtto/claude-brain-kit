#!/usr/bin/env bash
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
run_hook() { bash "$HOOK" 2>&1; }
retention() { printf '{ "cleanupPeriodDays": %s }\n' "$1" > "$HOME/.claude/settings.json"; }
write_profile() {                  # $1 = extra frontmatter lines (or ""), $2 = evidence log body lines
  mkdir -p "$SB/brain/identity"
  {
    printf -- '---\nname: profile\n'
    [ -n "$1" ] && printf '%s\n' "$1"
    printf -- '---\n# profile\n\n## Evidence log\n\n'
    printf '%s\n' "$2"
  } > "$SB/brain/identity/profile.md"
  git -C "$SB/brain" add -A && git -C "$SB/brain" commit --quiet -m profile
}

# 3 entries newer than last-consolidated → reported; an older entry is excluded from the count
t_setup; retention 3650
write_profile 'last-consolidated: 2026-09-06' \
'- 2026-09-10 (statement) said a thing
- 2026-09-08 (decision) chose a thing
- 2026-09-07 (statement) said another thing
- 2026-08-20 (statement) old, before last-consolidated'
out=$(run_hook); assert_contains "$out" "profile: 3 unconsolidated evidence entries — run the consolidation pass (see conventions/profile-evaluation.md)" "3 newer entries reported"
t_teardown

# all entries older than (or equal to) last-consolidated → no profile: text at all
t_setup; retention 3650
write_profile 'last-consolidated: 2026-09-10' \
'- 2026-09-10 (statement) same day as last-consolidated
- 2026-09-01 (statement) older'
out=$(run_hook); assert_lacks "$out" "profile:" "no unconsolidated entries → silent"
t_teardown

# no last-consolidated key at all + 2 entries → all count, treated as 0000-00-00
t_setup; retention 3650
write_profile "" \
'- 2026-09-05 (statement) said a thing
- 2026-09-01 (decision) chose a thing'
out=$(run_hook); assert_contains "$out" "profile: 2 unconsolidated evidence entries" "missing last-consolidated treated as 0000-00-00"
t_teardown

# no identity/profile.md at all → no profile: text, hook still exits 0
t_setup; retention 3650
out=$(run_hook); assert_lacks "$out" "profile:" "no profile note → silent"
run_hook >/dev/null; assert_rc $? 0 "still exits 0 with no profile note"
t_teardown

# last-consolidated == today, even with entries dated today → silent (the pass that ran
# today must not re-trigger on the very entries it just left behind)
t_setup; retention 3650
today=$(date +%Y-%m-%d)
write_profile "last-consolidated: ${today}" "- ${today} (statement) said a thing today"
out=$(run_hook); assert_lacks "$out" "profile:" "last-consolidated == today stays silent"
t_teardown

# quoted frontmatter value is parsed the same as bare
t_setup; retention 3650
write_profile 'last-consolidated: "2026-09-01"' '- 2026-09-05 (statement) said a thing'
out=$(run_hook); assert_contains "$out" "profile: 1 unconsolidated evidence entries" "quoted last-consolidated value parsed"
t_teardown

t_report
