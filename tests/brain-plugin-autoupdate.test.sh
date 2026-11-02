#!/usr/bin/env bash
# brain-plugin-autoupdate: status / on against a sandbox known_marketplaces.json, and the
# session-start nudge that rides on it.
cd "$(dirname "$0")" || exit 2
. ./lib.sh
B="$PWD/../plugins/brain/bin/brain-plugin-autoupdate"
H="$PWD/../plugins/brain/hooks/session-start"
A() { bash "$B" "$@"; }
km() { mkdir -p "$HOME/.claude/plugins"; cat > "$HOME/.claude/plugins/known_marketplaces.json"; }

t_setup
# ---- outside the plugin cache and without $BRAIN_MARKETPLACE the marketplace can't be told --------
unset BRAIN_MARKETPLACE
out=$(A status 2>&1); assert_rc $? 1 "no marketplace → exit 1"; assert_contains "$out" "which marketplace" "explains how to pass it"
export BRAIN_MARKETPLACE=my-kit

# ---- status: no file, registered-but-off behind a nested block, unknown name ---------------------
out=$(A status); assert_rc $? 2 "no file → exit 2"; assert_eq "$out" "not-registered" "no file reads as not-registered"
km <<'EOF'
{
  "claude-plugins-official": {
    "source": { "source": "github", "repo": "anthropics/claude-plugins-official" },
    "installLocation": "/x/plugins/marketplaces/claude-plugins-official",
    "lastUpdated": "2026-11-02T22:09:15.458Z"
  },
  "my-kit": {
    "source": {
      "source": "github",
      "repo": "someone/my-kit"
    },
    "installLocation": "/x/plugins/marketplaces/my-kit",
    "lastUpdated": "2026-11-02T22:49:24.664Z"
  }
}
EOF
out=$(A status); assert_rc $? 1 "off → exit 1"; assert_eq "$out" "off" "the nested source block does not end the entry early"
out=$(A status other); assert_rc $? 2 "unknown marketplace → exit 2"; assert_eq "$out" "not-registered" "unknown reads as not-registered"

# ---- on: sets exactly one field, valid JSON, idempotent --------------------------------------------
out=$(A on); assert_rc $? 0 "on → exit 0"; assert_contains "$out" "set now" "reports it set the flag"
out=$(A status); assert_rc $? 0 "status on → exit 0"; assert_eq "$out" "on" "status reads on"
python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1]))
ok = d["my-kit"]["autoUpdate"] is True and "autoUpdate" not in d["claude-plugins-official"] \
     and d["my-kit"]["source"]["repo"] == "someone/my-kit" and d["my-kit"]["lastUpdated"].endswith("Z")
sys.exit(0 if ok else 1)' "$HOME/.claude/plugins/known_marketplaces.json"; assert_rc $? 0 "file stays valid JSON; only my-kit gained the flag"
out=$(A on); assert_rc $? 0 "on again → exit 0"; assert_contains "$out" "already" "idempotent"
out=$(A on other 2>&1); assert_rc $? 2 "on for an unregistered marketplace → exit 2"; assert_contains "$out" "not registered" "says so"

# ---- hook nudge: off → one suffix; on or unknown → silent -----------------------------------------
km <<'EOF'
{
  "my-kit": {
    "source": { "source": "github", "repo": "someone/my-kit" },
    "installLocation": "/x",
    "lastUpdated": "2026-11-02T22:49:24.664Z"
  }
}
EOF
out=$(bash "$H" 2>&1); assert_contains "$out" "plugin auto-update is off" "hook nudges when off"
A on >/dev/null; out=$(bash "$H" 2>&1); assert_lacks "$out" "plugin auto-update" "hook silent once on"
unset BRAIN_MARKETPLACE
out=$(bash "$H" 2>&1); assert_lacks "$out" "plugin auto-update" "hook silent when the marketplace can't be told (dev checkout)"
t_teardown
t_report
