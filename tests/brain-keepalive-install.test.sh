#!/usr/bin/env bash
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
KEEPALIVE="$PLUGIN/bin/brain-keepalive-install"
K() { bash "$KEEPALIVE" "$@"; }

# every test gets its own sandbox ($HOME from t_setup) plus a stubbed
# launchctl/systemctl on PATH so nothing touches the real machine.
keepalive_setup() {
  t_setup
  mkdir -p "$SB/stubbin"
  STUB_LOG="$SB/stub.log"; : > "$STUB_LOG"
  export STUB_LOG
  cat > "$SB/stubbin/launchctl" <<EOF
#!/usr/bin/env bash
echo "launchctl \$*" >> "$STUB_LOG"
exit 0
EOF
  cat > "$SB/stubbin/systemctl" <<EOF
#!/usr/bin/env bash
echo "systemctl \$*" >> "$STUB_LOG"
exit 0
EOF
  chmod +x "$SB/stubbin/launchctl" "$SB/stubbin/systemctl"
  export PATH="$SB/stubbin:$PATH"
}

SCRIPT_FILE_REL=".config/claude-brain/claude-keepalive.sh"
PLIST_REL="Library/LaunchAgents/com.claude-brain.keepalive.plist"
SERVICE_REL=".config/systemd/user/claude-brain-keepalive.service"
TIMER_REL=".config/systemd/user/claude-brain-keepalive.timer"

case "$(uname -s)" in
  Darwin)
    # 1. install writes the keepalive script + LaunchAgent and bootstraps it
    keepalive_setup
    K >/dev/null
    assert_eq "$([ -x "$HOME/$SCRIPT_FILE_REL" ] && echo yes)" "yes" "macOS: keepalive script written + executable"
    assert_contains "$(cat "$HOME/$SCRIPT_FILE_REL")" "Reply with the single word OK." "macOS: keepalive script pings claude"
    assert_eq "$([ -f "$HOME/$PLIST_REL" ] && echo yes)" "yes" "macOS: LaunchAgent plist written"
    assert_contains "$(cat "$HOME/$PLIST_REL")" "com.claude-brain.keepalive" "macOS: plist has the right label"
    assert_contains "$(cat "$STUB_LOG")" "launchctl bootstrap" "macOS: bootstraps the agent"
    t_teardown

    # 2. idempotent: re-running boots out the old agent before bootstrapping again
    keepalive_setup
    K >/dev/null; K >/dev/null
    log=$(cat "$STUB_LOG")
    assert_eq "$(printf '%s\n' "$log" | grep -c 'launchctl bootstrap')" "2" "macOS: two installs -> two bootstraps"
    assert_eq "$(printf '%s\n' "$log" | grep -c 'launchctl bootout')" "2" "macOS: bootout-first each time (idempotent)"
    assert_eq "$([ -f "$HOME/$PLIST_REL" ] && echo yes)" "yes" "macOS: plist still present after re-install"
    t_teardown

    # 3. uninstall removes everything
    keepalive_setup
    K >/dev/null
    K --uninstall >/dev/null
    assert_eq "$([ -f "$HOME/$PLIST_REL" ] || echo gone)" "gone" "macOS: uninstall removes plist"
    assert_eq "$([ -f "$HOME/$SCRIPT_FILE_REL" ] || echo gone)" "gone" "macOS: uninstall removes keepalive script"
    assert_contains "$(cat "$STUB_LOG")" "launchctl bootout" "macOS: uninstall boots the agent out"
    t_teardown
    ;;
  *)
    # 1. install writes the keepalive script + systemd unit/timer and enables it
    keepalive_setup
    K >/dev/null
    assert_eq "$([ -x "$HOME/$SCRIPT_FILE_REL" ] && echo yes)" "yes" "linux: keepalive script written + executable"
    assert_contains "$(cat "$HOME/$SCRIPT_FILE_REL")" "Reply with the single word OK." "linux: keepalive script pings claude"
    assert_eq "$([ -f "$HOME/$SERVICE_REL" ] && echo yes)" "yes" "linux: systemd service written"
    assert_eq "$([ -f "$HOME/$TIMER_REL" ] && echo yes)" "yes" "linux: systemd timer written"
    assert_contains "$(cat "$HOME/$TIMER_REL")" "OnCalendar=Mon" "linux: timer runs weekly on Monday"
    assert_contains "$(cat "$STUB_LOG")" "systemctl --user enable --now claude-brain-keepalive.timer" "linux: enables the timer"
    t_teardown

    # 2. idempotent: re-running is a clean re-install, no errors, files still there
    keepalive_setup
    K >/dev/null; rc1=$?
    K >/dev/null; rc2=$?
    assert_rc "$rc1" 0 "linux: first install exits 0"
    assert_rc "$rc2" 0 "linux: second install exits 0 (idempotent)"
    assert_eq "$([ -f "$HOME/$TIMER_REL" ] && echo yes)" "yes" "linux: timer still present after re-install"
    t_teardown

    # 3. uninstall removes everything
    keepalive_setup
    K >/dev/null
    K --uninstall >/dev/null
    assert_eq "$([ -f "$HOME/$SERVICE_REL" ] || echo gone)" "gone" "linux: uninstall removes service"
    assert_eq "$([ -f "$HOME/$TIMER_REL" ] || echo gone)" "gone" "linux: uninstall removes timer"
    assert_eq "$([ -f "$HOME/$SCRIPT_FILE_REL" ] || echo gone)" "gone" "linux: uninstall removes keepalive script"
    assert_contains "$(cat "$STUB_LOG")" "systemctl --user disable --now" "linux: uninstall disables the timer"
    t_teardown
    ;;
esac

t_report
