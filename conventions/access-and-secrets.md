---
name: access-and-secrets
description: Every surface gets the same access; add connectors once on claude.ai; official OAuth connectors before raw keys, keys before asking
type: feedback
---

# Access & secrets — least friction, most permanence, no surface gating

## Rules
1. **One registration, every surface.** Add integrations as **claude.ai connectors** (custom or
   directory), not as per-device registrations: a connector mirrors into web, mobile, voice and
   every Claude Code session signed in with the account. Do not gate a surface on purpose.
   (The `brain-remote` plugin exists only for setups without connectors — `docs/zero-friction.md`.)
2. **The ladder — take the highest rung that exists:**
   1. Official MCP/connector with **OAuth** — permanent, permission-scoped at consent, nothing stored.
   2. A CLI's own OAuth login (`gh`, `wrangler`, `claude`) kept alive by the weekly keepalive.
   3. A key in your secret store (Bitwarden Secrets Manager), fetched blind with `brain-secret`,
      only when no OAuth path exists. Store new keys there the moment they are minted — never in
      chat, never in a note.
   4. Asking the human — last resort, only for the one-time act of granting rung 1–3.
3. **Recommend up the ladder.** Say which rung a task is on and whether an official connector
   would move it up. Prefer what still works next year without a human touch.
4. **Permanence over cleverness:** never rotate a connector's path secret unless compromised; no
   short-lived tokens where a standing grant exists; no device-local config a second machine
   would have to repeat.

**Why:** every "needs the human" is a UX defect. **How to apply:** before any credential handling
or any "add this to your machine" instruction, run the ladder — the answer is usually "add the
connector on claude.ai once".
