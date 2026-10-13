# brain plugin — changelog

## 1.3.4 — 2026-10-13
The session-start hook's profile-consolidation nudge (`profile: N unconsolidated
evidence entries`) only counted evidence-log lines written as `- YYYY-MM-DD …`. A line
with the date in bold — `- **YYYY-MM-DD** — …`, which is how the capture loop tends to
write them — was silently skipped, so a log holding only bold-dated entries never
nudged: six such entries appended on 2026-10-07 went unreported until the pass was
run by hand.
- The date extraction now accepts an optional `**` in front of the date. Nothing else
  about the trigger changes — plain-dated lines count exactly as before.
- `tests/profile-trigger.test.sh` gains a mixed plain/bold case that fails on the old
  hook (counts 1) and passes on the new one (counts 3).

## 1.3.3 — 2026-10-03
`brain-secret` on Windows when `jq` is the parser (it is only used when no Python 3.6+
runs).
- A native Windows `jq.exe` run from Git Bash writes CRLF for every newline, so
  `brain-secret get` put a CR in front of each line break inside a multi-line value
  and `brain-secret list` lines ended in CR. `brain-secret` now checks how `jq` writes
  a newline and runs it with `-b` when that is what keeps the newline a plain LF.
- A native Windows `jq.exe` older than 1.7 has no `-b` and cannot return a multi-line
  value unchanged. It is no longer used at all: `brain-secret` stops with its "no
  working JSON parser" message — for `list` and single-line values too, which used
  to work — instead of handing back an altered value. Install jq 1.7 or newer, or a
  Python 3.6+.
- Linux and macOS are unchanged — `jq` already writes plain LF there and keeps being
  run without `-b` (jq 1.5 and 1.6 would reject it).

Found by running the `jq` path on Windows for the first time; where `jq` is installed
the tests now drive it on every platform through a stand-in `jq` that writes CRLF.

## 1.3.2 — 2026-10-03
`brain-secret` printed its Bitwarden access token when run under xtrace — `bash -x
brain-secret …`, or an xtrace inherited through an exported `SHELLOPTS` — because bash
traces the command-scoped assignment that hands the token to `bws`
(`+ BWS_ACCESS_TOKEN=…` on stderr). Every version since 1.1.0 did this. The script now
turns tracing off (`set +x`) as its first command, before anything reads the token
file; the test suite pins it on both routes with a canary token.
- **Were you exposed?** Only if `brain-secret` ever ran traced and that output went
  somewhere: terminal scrollback, a log, a Claude transcript. From 1.1.1 on, secret
  values were never part of the trace (they travel through pipes, not command lines);
  1.1.0 traced every value as well. Either way the token reads every secret its
  machine account can reach — revoke it and issue a new one, and if anyone else could
  have seen the trace, rotate those secrets too.
- **What the script cannot fix:** a caller that itself runs under `set -x` traces
  whatever it captures with `$(brain-secret get NAME)` and every command it then hands
  the value to. Keep xtrace off around the capture and every use of the value.

Also corrects the 1.3.1 notes below: where to re-run the keepalive installer.

## 1.3.1 — 2026-10-03
Windows (Git for Windows) fixes.
- `brain-keepalive-install` printed a `schtasks` command that ran a bare `bash`; from
  a scheduled task that is usually WSL's launcher, not Git Bash, so the keepalive
  never ran. It now writes `~/.config/claude-brain/claude-keepalive.cmd`, which calls
  Git Bash by full path, and the printed command points `/TR` at that wrapper
  (quoted for `schtasks` when the path has a space). `--uninstall` removes the
  wrapper too. **If you registered the task with an earlier version:** re-run
  `/brain:setup` (or ask Claude to run `brain-keepalive-install` — it is on PATH only
  inside Claude Code, not in your own terminal) and run the `schtasks` command it
  prints again — `/F` replaces the old task.
- The keepalive script runs `claude -p … < /dev/null`: with no stdin under a scheduler
  the CLI waited 3s and logged a warning on every run. Re-run `/brain:setup` (or ask
  Claude to run `brain-keepalive-install`) to pick this up (all platforms).
- `brain-secret` chose `python3` because it was on PATH; on Windows that can be the
  Microsoft Store alias, which only prints "Python was not found". It now runs each
  candidate (`python3`, `python`, `py -3`) and takes the first Python 3.6+ that
  works, then `jq`, and says plainly when none does.
- `brain-secret` under a native Windows python turned every newline in a value into
  CRLF and ended `list` lines with CR; values and lists are now written as bytes.
- `brain-secret get` missed a key that starts with `/` on Windows: Git Bash rewrote
  the argument into a Windows path before the parser saw it.

## 1.3.0 — 2026-09-11
The profile consolidation trigger is now daily instead of count-based: the pass runs
at the start of the first session of any day on which `identity/profile.md`'s
evidence log holds entries newer than its `last-consolidated` frontmatter date
(~10 entries was too slow in practice). The session-start hook now reports it in its
status line — `profile: N unconsolidated evidence entries — run the consolidation
pass (see conventions/profile-evaluation.md)` — silent when there's nothing to
consolidate, no `identity/profile.md`, or a pass already ran today. The consolidation
pass stamps `last-consolidated: <today>` when it runs. See `docs/how-it-works.md`,
"Session start: the clone freshens itself", and `conventions/profile-evaluation.md`.

## 1.2.0 — 2026-09-11
New **Stop hook** `journal-guard`: a session can no longer quietly end a day that
had brain commits without a same-day `journal/<today>-*.md` entry. It blocks the
stop once with a reason telling Claude to write the entry through the write
protocol, never blocks twice in a row, and always exits 0 (a brain problem must
never break a session's stop). Opt out per-session with `BRAIN_JOURNAL_GUARD=off`.
See `docs/how-it-works.md`, "Journal guard".

## 1.1.1 — 2026-09-10
brain-secret parsed bws columns and could print value fragments in `list`; now JSON-only.

## 1.1.0 — 2026-09-10
Zero-friction operations: reduce how often Claude needs to come back to you for
things it can just do. `brain-secret` (wraps Bitwarden Secrets Manager's `bws` CLI —
`list` prints ids/keys only, `get` prints a value for `$(brain-secret get NAME)`,
Claude never echoes it) and `brain-keepalive-install` (weekly LaunchAgent / systemd
timer / Windows `schtasks` one-liner that pings `claude` so the OAuth login never
lapses). `/brain:setup` now installs the keepalive and confirms secrets access.
New starter convention `conventions/standing-decisions.md` — pre-decided operational
calls (merge/push/tag/deploy, scratch resources, brainstorm defaults, secrets,
devices) so Claude doesn't ask for what's already decided. See `docs/zero-friction.md`.

## 1.0.0 — 2026-09-04
First release. SessionStart auto-pull hook (status line + setup nudges), `brain-write.sh`
on PATH, skills: `/brain:setup`, `/brain:todos`, `/brain:idea`, `write`, `profile`.
Replaces `setup.sh` and `tools/brain-*.sh`; Windows supported through the polyglot launcher.
