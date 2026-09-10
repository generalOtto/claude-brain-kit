# Zero-friction operations

## The principle

Every time Claude has to come back to you for something it could have handled
itself, that's friction — and friction compounds. The goal isn't "ask less often,"
it's **reduce the amount of things Claude needs you for toward zero**: fetch the
secret instead of asking for it, keep the login alive instead of hitting an expired
token mid-task, try the remote path before declaring "needs the human." This belongs
in the brain kit's core conventions, not something every user has to rediscover and
fix themselves.

Six root causes cover essentially every "needs the human" ask:

## 1. Secrets Claude didn't fetch

**Mechanism:** `brain-secret`, a thin wrapper around Bitwarden Secrets Manager's
`bws` CLI (`plugins/brain/bin/brain-secret`).

- `brain-secret list` — prints `id  KEY` for every secret. **Never values.**
- `brain-secret get <id-or-exact-key>` — prints the value alone, for
  `$(brain-secret get NAME)` inside a script. Claude never echoes the value it gets
  back — capture or pipe it, never paste it into chat or a committed file.
- Token file: `${BRAIN_SECRETS_TOKEN_FILE:-~/.config/claude-brain/bws-token}`, mode
  600 — a Bitwarden Secrets Manager machine-account access token, nothing else.
- No `bws`? `brew install bws` (or see the [bws docs](https://bitwarden.com/help/secrets-manager-cli/)).
  No token file? Create a Bitwarden Secrets Manager machine account, put its access
  token at the path above.

Per the brain's secrets policy ([pointers/secrets.md](../pointers/secrets.md)), the
brain itself still stores no secret values — `brain-secret` is what turns "the
password manager has it" into "Claude can reach it without asking you to paste it."

## 2. Expiring `claude` OAuth login

**Mechanism:** `brain-keepalive-install` installs a weekly job that runs
`claude -p 'Reply with the single word OK.' --output-format text` — just enough
activity that the OAuth token never lapses from inactivity.

- macOS: a LaunchAgent (`~/Library/LaunchAgents/com.claude-brain.keepalive.plist`),
  Mondays 09:15.
- Linux: a `systemd --user` service + timer (`claude-brain-keepalive.timer`), weekly.
- Windows (Git Bash): prints a `schtasks` one-liner for you to run once — Git Bash
  can't register a scheduled task for you.
- Idempotent (safe to re-run), `--uninstall` removes it, logs to
  `~/.config/claude-brain/claude-keepalive.log`.
- `/brain:setup` installs it and checks the reply; if it's not `OK`, it tells you to
  run `claude login` once.

## 3. Devices off or behind an interactive login

**Mechanism:** don't declare "needs the human" on first contact — try the remote
path first. A Cloudflare Access **service token** (client ID + secret, stored via
`brain-secret`) authenticates a machine-to-machine request the same way your browser
session does interactively; if the device itself is asleep, Wake-on-LAN (a magic
packet to its MAC address, which is worth recording as a `knowledge/` note) can bring
it up before you resort to asking someone to walk over and turn it on.

## 4. Dashboards with no API access

**Mechanism:** an API token for the dashboard, stored in the secret store like any
other credential and fetched with `brain-secret` — not clicked-through by a human
each time. **Never rotate a connector's path secret unless it's compromised** —
rotating a working credential just to "clean up" trades a small security gain for a
guaranteed round of re-auth friction across every surface that uses it.

## 5. Undecided standing calls

**Mechanism:** [`conventions/standing-decisions.md`](../conventions/standing-decisions.md)
— the calls that don't need a fresh decision every time (solo-repo merges, releases,
scratch resources, brainstorm defaults) are pre-decided once, in writing, so Claude
acts on them instead of asking.

## 6. Human-in-the-loop by design (kept, deliberately)

Not everything should be automatic. **The daily digest stays human-triggered** —
it surfaces due `TODO.md` items only after you say "go," never on a schedule. Running
chores unattended on a timer is a different (and riskier) feature than reminding you
they exist; this kit only does the latter. See
[`conventions/todo-list.md`](../conventions/todo-list.md).

## Gotcha: `*.workers.dev` and bot detection

If you're calling a Cloudflare Worker (e.g. the brain-remote MCP server) from a
script instead of a browser, a bare `curl` or default HTTP client User-Agent gets a
**403, Cloudflare error 1010** — `*.workers.dev` hosts silently reject requests that
don't look browser-like. Fix: send a real `User-Agent` header (a normal browser UA
string, or at minimum something that isn't empty/a bare library default).
