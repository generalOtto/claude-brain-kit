# Security: a brain full of your life, kept safe

Your brain will end up containing your name, your projects, your preferences, your
history — a concentrated map of you. Two rules keep that safe: **the repo is
private**, and **it never contains secrets**. Everything else on this page serves
those two.

## Rule 1 — The repo is PRIVATE

When you click "Use this template", GitHub asks for visibility. Choose **Private**.
Verify right now if you're unsure:

```bash
gh repo view --json visibility -q .visibility
```

If it says `PUBLIC`, flip it before writing anything real:

```bash
gh repo edit --visibility private --accept-visibility-change-consequences
```

`setup.sh` checks this and warns loudly. Note that anything ever pushed to a public
repo should be considered leaked (forks and caches survive a visibility flip) — if
real personal content went public, treat it as exposed, don't just flip the switch.

Who can read a private repo: you, collaborators you add, and any app/connector you
grant access (the GitHub MCP connector acts *as you* under the access you gave it —
prefer the tightest scope offered, e.g. a fine-grained PAT limited to this repo).

**Secondary devices: prefer deploy keys over account auth.** When a casual machine
(gaming box, shared computer) gets a full clone, give it a **deploy key** — an SSH
key added under the brain repo's *Settings → Deploy keys* ("Allow write access" if
it should commit memories). A deploy key can touch exactly one repo; if that machine
is ever compromised, sold, or discarded without a wipe, your GitHub account and
every other repo stay untouched, and revoking is one click on one key. [bootstrap.md](bootstrap.md)
uses this pattern for its "full" tier.

## Rule 2 — Secrets are pointers, never values

Even in a private repo, no secret value ever gets written down here — not passwords,
tokens, API keys, private keys, recovery codes, or connection strings. Two reasons:

1. **Blast-radius:** the brain is the most-shared, most-synced, most-read-by-AI file
   set you own. If it leaks — a mis-scoped connector, a laptop, a wrong paste — a
   leak of *facts about you* is bad; a leak of *credentials* is catastrophic.
2. **It's never necessary:** a pointer is exactly as useful to future-you:

   > Grafana admin password → password manager item **"garden-dashboard admin"**

Real secrets live in a password manager or gitignored `.env` files in the projects
that use them. The policy note ships at [`pointers/secrets.md`](../pointers/secrets.md)
— fill in where *your* secrets actually live.

## The three enforcement layers (backstops, not the policy)

| Layer | What it catches | Ships as |
|---|---|---|
| `.gitignore` | whole secret files (`.env`, `*.pem`, keys) ever being tracked | on by default |
| gitleaks pre-commit hook | secret-shaped strings *before* they enter history | offered by `setup.sh` (needs `gitleaks` installed) |
| gitleaks CI (`gitleaks-action` v3) | anything that slips through, on every push — including writes from claude.ai/mobile surfaces that never ran your local hook | on by default |

The CI layer is free for personal-account repos (org-owned repos need a free license
key from gitleaks). GitHub's own push protection for private repos ("Secret
Protection") is a paid product — gitleaks covers you at $0; consider the paid layer
optional hardening.

**If a secret does land in history:** rotate the credential first (assume exposed),
then rewrite history if you care to (`git filter-repo`) — rotation is the part that
actually matters.

## Claude-specific notes

- The bootloader instructs Claude to STOP and write a pointer if it's ever about to
  record a secret — the policy is enforced at write time, not just scanned after.
- Journal entries quoting terminal output are the sneakiest leak path (a pasted
  `curl -H "Authorization: …"`). The pre-commit hook exists for exactly this.
- If you use the claude.ai connector, remember writes from your phone bypass your
  laptop's pre-commit hook — that's why CI scans every push.
