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

# fake_claude — a `claude` on PATH that records whatever reaches its stdin, then
# answers like the real ping.
fake_claude() {
  export STDIN_SEEN="$SB/stdin-seen"
  cat > "$SB/stubbin/claude" <<'EOF'
#!/usr/bin/env bash
cat > "$STDIN_SEEN"
echo OK
EOF
  chmod +x "$SB/stubbin/claude"
}

# native_claude [dir] — a `claude` where the native installer puts it (~/.local/bin by
# default), on the installing shell's PATH but in no system directory. It answers
# like the real ping and needs nothing from the environment, so it still works under
# the bare environment a systemd --user manager gives the service.
native_claude() {
  NATIVE_BIN="${1:-$HOME/.local/bin}"
  mkdir -p "$NATIVE_BIN"
  printf '#!/bin/sh\necho OK\n' > "$NATIVE_BIN/claude"
  chmod +x "$NATIVE_BIN/claude"
  export PATH="$NATIVE_BIN:$PATH"
}

SCRIPT_FILE_REL=".config/claude-brain/claude-keepalive.sh"
WRAPPER_REL=".config/claude-brain/claude-keepalive.cmd"
LOG_REL=".config/claude-brain/claude-keepalive.log"
PLIST_REL="Library/LaunchAgents/com.claude-brain.keepalive.plist"
SERVICE_REL=".config/systemd/user/claude-brain-keepalive.service"
TIMER_REL=".config/systemd/user/claude-brain-keepalive.timer"

# The wrapper switches its console to UTF-8 (chcp 65001), and a console keeps its code
# page after the cmd.exe that set it exits. On Windows, remember the caller's so a
# test that depends on it can put it back first, and so the suite leaves it as found.
ORIG_CP=""
if is_windows; then ORIG_CP=$(cmd.exe //c chcp 2>/dev/null | tr -cd '0-9'); fi
restore_cp() { [ -z "$ORIG_CP" ] || cmd.exe //c chcp "$ORIG_CP" >/dev/null 2>&1; }

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
  MINGW*|MSYS*|CYGWIN*)
    # 1. the real thing, with the real cygpath: install, then run the wrapper through
    # cmd.exe on a scheduler-like PATH — the fake claude plus the Windows system
    # directories, no Git directories — so a wrapper naming a bare `bash` could not
    # reach Git Bash. ORIGINAL_PATH is dropped because Git Bash's login profile would
    # otherwise rebuild PATH from the caller's copy and lose the fake claude.
    keepalive_setup
    fake_claude
    out=$(K)
    wrapper="$HOME/$WRAPPER_REL"
    assert_eq "$([ -f "$wrapper" ] && echo yes)" "yes" "windows: .cmd wrapper written beside the keepalive script"
    bash_exe=$(sed -n 's/^"\([^"]*\)" -lc .*/\1/p' "$wrapper" | tr -d '\r')
    assert_eq "$([ -f "$bash_exe" ] && echo yes)" "yes" "windows: wrapper names a bash.exe that exists"
    wrapper_win=$(cygpath -w "$wrapper")
    assert_contains "$out" "$wrapper_win" "windows: schtasks command points at the wrapper"
    winroot=$(cygpath -u "$SYSTEMROOT")
    echo "data-from-the-caller" | (
      unset ORIGINAL_PATH
      PATH="$SB/stubbin:$winroot/System32:$winroot" cmd.exe //c "$wrapper_win"
    ) >/dev/null 2>&1
    assert_contains "$(cat "$HOME/$LOG_REL" 2>/dev/null)" "OK" "windows: wrapper run through cmd.exe reaches claude"
    assert_eq "$([ -f "$STDIN_SEEN" ] && echo yes)" "yes" "windows: ... and it was the fake claude that ran"
    assert_eq "$(cat "$STDIN_SEEN" 2>/dev/null)" "" "windows: claude reads /dev/null, not the task's stdin"
    t_teardown
    ;;
  *)
    # 1. install writes the keepalive script + systemd unit/timer and enables it
    keepalive_setup
    native_claude
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
    native_claude
    K >/dev/null; rc1=$?
    K >/dev/null; rc2=$?
    assert_rc "$rc1" 0 "linux: first install exits 0"
    assert_rc "$rc2" 0 "linux: second install exits 0 (idempotent)"
    assert_eq "$([ -f "$HOME/$TIMER_REL" ] && echo yes)" "yes" "linux: timer still present after re-install"
    t_teardown

    # 3. uninstall removes everything
    keepalive_setup
    native_claude
    K >/dev/null
    K --uninstall >/dev/null
    assert_eq "$([ -f "$HOME/$SERVICE_REL" ] || echo gone)" "gone" "linux: uninstall removes service"
    assert_eq "$([ -f "$HOME/$TIMER_REL" ] || echo gone)" "gone" "linux: uninstall removes timer"
    assert_eq "$([ -f "$HOME/$SCRIPT_FILE_REL" ] || echo gone)" "gone" "linux: uninstall removes keepalive script"
    assert_contains "$(cat "$STUB_LOG")" "systemctl --user disable --now" "linux: uninstall disables the timer"
    t_teardown

    # 4. the systemd --user manager's PATH has no ~/.local/bin, where the native
    # installer puts claude: the service carries its own PATH, starting with the
    # directory claude was found in at install time. The keepalive script then runs
    # with exactly that PATH in an otherwise empty environment, as systemd runs it
    # (no Environment= line -> the bare system PATH, which can't reach claude).
    keepalive_setup
    native_claude
    K >/dev/null
    unit_path=$(sed -n 's/^Environment="PATH=\(.*\)"$/\1/p' "$HOME/$SERVICE_REL")
    assert_eq "$unit_path" "$NATIVE_BIN:/usr/local/bin:/usr/bin:/bin" "linux: service PATH starts with claude's install-time directory"
    env -i HOME="$HOME" PATH="${unit_path:-/usr/local/bin:/usr/bin:/bin}" "$BASH" "$HOME/$SCRIPT_FILE_REL"
    log=$(cat "$HOME/$LOG_REL" 2>/dev/null)
    assert_contains "$log" "OK" "linux: keepalive run with the service's PATH reaches claude"
    assert_lacks "$log" "not found" "linux: ... and never logs claude CLI not found"
    t_teardown

    # 5. a claude directory with a space and a %: quoted for systemd's word splitting,
    # % doubled so systemd doesn't read it as a specifier
    keepalive_setup
    native_claude "$HOME/odd dir%/bin"
    K >/dev/null
    assert_contains "$(cat "$HOME/$SERVICE_REL")" "Environment=\"PATH=$HOME/odd dir%%/bin:/usr/local/bin:/usr/bin:/bin\"" "linux: service PATH quoted, % escaped"
    t_teardown

    # 5b. claude as a script (an npm install) with node in a version manager's
    # directory: node's directory comes along, claude's first, nothing twice
    keepalive_setup
    native_claude "$HOME/npm/bin"
    printf '#!/usr/bin/env node\n' > "$NATIVE_BIN/claude"
    mkdir -p "$HOME/fnm/bin"; printf '#!/bin/sh\n' > "$HOME/fnm/bin/node"; chmod +x "$HOME/fnm/bin/node"
    PATH="$HOME/fnm/bin:$PATH" K >/dev/null
    assert_contains "$(cat "$HOME/$SERVICE_REL")" "Environment=\"PATH=$HOME/npm/bin:$HOME/fnm/bin:/usr/local/bin:/usr/bin:/bin\"" "linux: script claude brings node's directory"
    t_teardown

    # 5c. claude already in a system directory: the PATH lists it once (checked on
    # the helper itself — the test can't put a claude in the real /usr/bin)
    keepalive_setup
    assert_eq "$(bash -c 'source <(sed -n "/^dedupe_path()/,/^}/p" "$1"); dedupe_path "/usr/bin:/usr/local/bin:/usr/bin:/bin:/a*b:/a*b"' _ "$KEEPALIVE")" "/usr/bin:/usr/local/bin:/bin:/a*b" "linux: PATH dedupe keeps the first occurrence"
    t_teardown

    # 6. no claude at install time: a clear message, non-zero exit, nothing installed
    # (a service with no way to reach claude would only log failures every week).
    # PATH keeps just the stubs and the system directories, so a claude installed on
    # the machine running the tests can't leak in.
    keepalive_setup
    if PATH=/usr/bin:/bin command -v claude >/dev/null 2>&1; then
      echo "  SKIP linux: no-claude case (a claude in /usr/bin or /bin on this machine)"
    else
      out=$(PATH="$SB/stubbin:/usr/bin:/bin" K 2>&1); rc=$?
      assert_rc "$rc" 1 "linux: no claude -> exit 1"
      assert_contains "$out" "claude CLI not found" "linux: no claude -> says so"
      assert_eq "$([ -e "$HOME/$SERVICE_REL" ] || echo none)" "none" "linux: no claude -> no service written"
      assert_lacks "$(cat "$STUB_LOG")" "enable --now" "linux: no claude -> timer not enabled"
    fi
    t_teardown
    ;;
esac

# --- every platform: the keepalive script itself -----------------------------------
# claude's stdin is /dev/null, not the scheduler's: an un-redirected `claude -p` waits
# 3s for stdin data and logs a warning on every scheduled run.
keepalive_setup
fake_claude
K >/dev/null
echo "data-from-the-caller" | bash "$HOME/$SCRIPT_FILE_REL"
assert_contains "$(cat "$HOME/$LOG_REL" 2>/dev/null)" "OK" "keepalive: the reply is logged"
assert_eq "$([ -f "$STDIN_SEEN" ] && echo yes)" "yes" "keepalive: the fake claude ran"
assert_eq "$(cat "$STDIN_SEEN" 2>/dev/null)" "" "keepalive: claude reads /dev/null, not the caller's stdin"
t_teardown

# --- the Windows branch, on every platform ------------------------------------------
# A fake uname puts the installer on Windows and a fake cygpath answers for Git Bash,
# so CI (Linux) covers the branch too.
win_setup() {
  keepalive_setup
  mkdir -p "$SB/winstub"
  cat > "$SB/winstub/uname" <<'EOF'
#!/usr/bin/env bash
echo MINGW64_NT-10.0-19045
EOF
  cat > "$SB/winstub/cygpath" <<'EOF'
#!/usr/bin/env bash
# fake cygpath: `-w /` prints $FAKE_GIT_ROOT plus the trailing backslash the real one
# prints; `-w <path>` prints <path> on C: with backslashes, minus the sandbox prefix
# ($CYG_STRIP) so the result never depends on where the sandbox lives.
[ "$1" = "-w" ] || exit 1
if [ "$2" = "/" ]; then
  printf '%s\134\n' "$FAKE_GIT_ROOT"
else
  printf 'C:%s\n' "$(printf '%s' "${2#"$CYG_STRIP"}" | tr / '\134')"
fi
EOF
  chmod +x "$SB/winstub/uname" "$SB/winstub/cygpath"
  export CYG_STRIP="$SB"
}
KW() { PATH="$SB/winstub:$PATH" bash "$KEEPALIVE" "$@"; }
win_path() { printf 'C:%s' "$(printf '%s' "${1#"$SB"}" | tr / '\134')"; }   # what the fake cygpath -w prints
count() { tr -cd "$1" | wc -c | tr -d ' '; }

# W1. Git for Windows layout (<root>\bin\bash.exe exists): the wrapper calls that
# launcher by full path, and schtasks runs the wrapper — never a bare `bash`
win_setup
export FAKE_GIT_ROOT="$SB/Fake Git"
# the installer tests "<root>\bin\bash.exe": a path on Windows, one odd file name elsewhere
mkdir -p "$SB/Fake Git/bin"; : > "$SB/Fake Git\bin\bash.exe"
out=$(KW)
wrapper="$HOME/$WRAPPER_REL"
assert_eq "$([ -x "$HOME/$SCRIPT_FILE_REL" ] && echo yes)" "yes" "windows: keepalive script written + executable"
assert_eq "$([ -f "$wrapper" ] && echo yes)" "yes" "windows: .cmd wrapper written beside it"
assert_contains "$(cat "$wrapper")" "\"$SB/Fake Git\bin\bash.exe\" -lc \"~/.config/claude-brain/claude-keepalive.sh\"" "windows: wrapper calls Git Bash by full path"
assert_eq "$(grep -E 'chcp 65001|" -lc "' "$wrapper" | head -1 | grep -c 'chcp 65001')" "1" "windows: wrapper switches cmd to UTF-8 before the bash line"
assert_eq "$(count '\r' < "$wrapper")" "$(count '\n' < "$wrapper")" "windows: every wrapper line ends CRLF"
assert_contains "$out" "schtasks /Create /SC WEEKLY /D MON /ST 09:15 /TN \"claude-brain-keepalive\" /TR \"C:\home\.config\claude-brain\claude-keepalive.cmd\" /F" "windows: schtasks runs the wrapper"
assert_lacks "$out" "bash -lc" "windows: no bare bash in the scheduled command"
t_teardown

# W2. no <root>\bin\bash.exe (MSYS2, Cygwin): falls back to the running shell's bash
win_setup
export FAKE_GIT_ROOT="$SB/msys64"
KW >/dev/null
assert_contains "$(cat "$HOME/$WRAPPER_REL")" "\"$(win_path "$(command -v bash)")\" -lc \"~/.config/claude-brain/claude-keepalive.sh\"" "windows: wrapper falls back to this shell's bash, by full path"
t_teardown

# W3. a home directory with a space: /TR quotes the wrapper path for schtasks
win_setup
export FAKE_GIT_ROOT="$SB/msys64"
out=$(HOME="$SB/home dir" KW)
assert_contains "$out" "/TR \"'C:\home dir\.config\claude-brain\claude-keepalive.cmd'\" /F" "windows: spaced wrapper path is single-quoted inside /TR"
assert_contains "$out" "Command Prompt or PowerShell" "windows: that form runs in either shell"
t_teardown

# W3b. a space AND an apostrophe: single quotes would end at the apostrophe (schtasks
# registers a broken task without complaint), so /TR gets \"...\" — a form only cmd parses
win_setup
export FAKE_GIT_ROOT="$SB/msys64"
out=$(HOME="$SB/o'brien home" KW)
assert_contains "$out" "/TR \"\\\"C:\o'brien home\.config\claude-brain\claude-keepalive.cmd\\\"\" /F" "windows: space + apostrophe path gets escaped double quotes"
assert_contains "$out" "Command Prompt (not PowerShell)" "windows: ... and the instruction says cmd only"
t_teardown

# W4. idempotent, and uninstall removes both files and says how to drop the task
win_setup
export FAKE_GIT_ROOT="$SB/msys64"
KW >/dev/null; rc1=$?
KW >/dev/null; rc2=$?
assert_rc "$rc1" 0 "windows: first run exits 0"
assert_rc "$rc2" 0 "windows: second run exits 0 (idempotent)"
out=$(KW --uninstall)
assert_eq "$([ -f "$HOME/$SCRIPT_FILE_REL" ] || echo gone)" "gone" "windows: uninstall removes keepalive script"
assert_eq "$([ -f "$HOME/$WRAPPER_REL" ] || echo gone)" "gone" "windows: uninstall removes the wrapper"
assert_contains "$out" "schtasks /Delete /TN \"claude-brain-keepalive\" /F" "windows: uninstall says how to remove the task"
t_teardown

# W5 (real Windows only). A Git root outside ASCII — a per-user install under a
# profile name with an umlaut: cmd.exe must still find the bash.exe the wrapper
# names. The fake cygpath reports such a root; an exe that echoes its arguments
# stands in for bash.
if is_windows; then
  win_setup
  umlaut_root="$SB/J"$'\xc3\xb6'"rg"
  mkdir -p "$umlaut_root/bin"
  cp /usr/bin/echo.exe "$umlaut_root/bin/bash.exe"
  FAKE_GIT_ROOT=$(cygpath -w "$umlaut_root"); export FAKE_GIT_ROOT
  KW >/dev/null
  restore_cp   # an earlier wrapper run left this console in UTF-8, which would hide a missing chcp
  out=$(cmd.exe //c "$(cygpath -w "$HOME/$WRAPPER_REL")" 2>&1)
  assert_contains "$out" "-lc ~/.config/claude-brain/claude-keepalive.sh" "windows: cmd finds a bash.exe under a non-ASCII path"
  t_teardown
fi

restore_cp

t_report
