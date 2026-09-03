# Voice Brain: your brain in voice mode (and first-class connector writes)

The [claude.ai + mobile guide](claude-ai-and-mobile.md) wires the brain into text
chats through the GitHub connector. This page covers the gap that connector cannot
close — **voice mode** — with a tiny MCP server of your own, deployed free on
Cloudflare Workers in one command: `tools/voice-brain/`.

> Verified August 2026 on a live daily-driver brain. Connector features move fast;
> if a step doesn't match what you see, please open an issue.

## Why this exists

- **Voice mode drops file bodies.** The GitHub connector returns file contents as
  *embedded resources*, and claude.ai's voice mode currently discards those — Claude
  hears that a file exists but not a word of what's in it. Voice Brain returns
  everything as plain text parts, which voice mode keeps. Recall works.
- **Writes worth trusting from any connector surface.** The GitHub connector can
  commit, but raw commits skip your brain's protocol. Voice Brain's `brain_write`
  commits the note **and its INDEX.md line in one atomic commit** (Git Data API,
  compare-and-swap with retries — parallel writers can't clobber each other), and
  `brain_append` adds an item to an existing file, section-aware (the "add a to-do
  from my phone" case). Server-enforced guardrails: markdown-only paths in an
  allowlisted directory set, required frontmatter, secret-shaped content refused,
  size caps, `CLAUDE.md` and `tools/` not writable at all. Every refusal comes back
  as plain text explaining what to fix.
- **Voice etiquette, baked in.** The server's instructions teach Claude to finish
  its spoken sentence before a tool call and stay silent while one is in flight, so
  speech doesn't shred around tool use.

## What you get

Four tools on every surface the connector is added to: `brain_index` (bootloader +
catalog), `brain_read` (one note), `brain_write` (create/replace, atomic with the
index), `brain_append` (add to an existing note or a `##` section of it). There is
deliberately **no delete** — voice plus irreversible is a bad mix; deletions stay
in text sessions.

## Setup (~5 minutes, $0)

You need: a free [Cloudflare account](https://dash.cloudflare.com/sign-up) (created
on the fly if you don't have one), and a claude.ai plan that allows **custom
connectors** (paid plans; the directory-connector tier isn't enough here).

```bash
cd ~/claude-brain/tools/voice-brain
bash setup.sh
```

The script derives everything it can instead of asking you to paste it: your
Cloudflare account ID (from wrangler's login session), a `workers.dev` subdomain
(auto-generated and registered if your account has none), the MCP path secret
(generated), and **your brain repo itself** — read from this repo's git remote,
since `tools/voice-brain/` lives inside your brain. The one thing you paste is a
GitHub fine-grained PAT (the script prints the exact settings: your brain repo
only, Contents read+write) — and it's **verified against GitHub before it's
stored**, so a bad paste fails on the spot, not in production.

At the end it prints (and, when a clipboard tool is available, copies) your
connector URL:

```
https://voice-brain-mcp.<subdomain>.workers.dev/mcp/<secret>
```

Add it on **claude.ai → Settings → Connectors → Add custom connector**. Done —
voice mode, text chats, and the mobile apps can now all use the four tools.
Re-running the script is safe: existing secrets and the subdomain are kept.

## Security posture

- **The URL is the credential.** The `<secret>` path segment (64+ random chars,
  compared in constant time) is the auth. Treat the connector URL like a password:
  store it in your password manager, never in the brain.
- **Everything else is a bare 404.** Wrong secret, malformed body, oversized body,
  unknown path — all get an empty 404. The one deliberate exception: `GET /healthz`
  answers `200 ok` without auth (setup's self-test, and yours if you want an uptime
  check) — it reveals that *a* worker exists, never what it fronts.
- **No request logging**, by design: Workers observability is off in
  `wrangler.jsonc` (keep it off — logs would record the secret-bearing URL of every
  request).
- **Blast radius = one repo.** The PAT is fine-grained and scoped to the brain repo
  only; it lives as a Worker secret, never in code or config. Rotate the path
  secret any time with `bash setup.sh --rotate-secret` (then update the connector
  URL); kill the whole thing with `npx wrangler delete`.
- **The server won't commit secrets.** Secret-shaped content (tokens, keys,
  credential assignments) is refused server-side — same policy as the rest of the
  kit: pointers, never values.

## Cost

$0. Cloudflare Workers' free tier allows 100,000 requests/day; personal brain
traffic is a rounding error against that. GitHub API usage is far below any limit.

## Known limits & flags

- **Fresh-account subdomain registration is the one path we could not live-test**
  (our account already had a `workers.dev` subdomain). If the auto-registration
  branch fails on your brand-new account, the deploy step may prompt you once to
  pick a subdomain (its output streams to your terminal, so you'll see it) —
  accept, and please open an issue telling us which of the two happened.
- **Custom domain (optional):** attach one to the worker in the Cloudflare
  dashboard (Workers & Pages → your worker → Settings → Domains & Routes). The
  config is deliberately routes-less — a dashboard/API-attached custom domain
  survives every later deploy (verified), so the same `wrangler.jsonc` works for
  everyone.
- **Cloudflare's official MCP server (optional):** add `https://mcp.cloudflare.com/mcp`
  (OAuth — no API token to mint) to Claude Code or claude.ai and Claude can do the
  dashboard/API steps above — custom domains, DNS records — for you. It's an
  account-wide grant, so add it where you do ops, not on every surface.
- **When Anthropic fixes voice resource-unwrapping**, reads could move back to the
  GitHub connector — but the write path (atomic, guarded, protocol-true) stays
  valuable on every connector surface regardless. Re-test occasionally: in voice,
  ask Claude to fetch a file via the *GitHub* connector and quote a line from it.
  Verbatim quote = fixed.
