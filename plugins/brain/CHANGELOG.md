# brain plugin — changelog

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
