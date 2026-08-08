# Extend to claude.ai and your phone

The desktop setup gives Claude Code a brain. This page gives the *same brain* to
claude.ai in the browser and the Claude iPhone/Android app — read **and write** — so
a chat on your phone can recall your notes and commit new ones.

> Verified July 2026. Connector features move fast; if a step doesn't match what you
> see, check Anthropic's connectors documentation and please open an issue.

## The one trap to avoid first

claude.ai has **two different GitHub features**. You want the second one:

| | What it is | Can it write? |
|---|---|---|
| "Add from GitHub" file sync | Built-in integration that syncs file contents into a chat/Project | **No — read-only** |
| **GitHub MCP connector** | GitHub's hosted MCP server (`https://api.githubcopilot.com/mcp/`) added as a connector | **Yes — real commits** |

If you set up the first one, recall sort-of works and writes silently don't. Set up
the connector.

## Setup (once, on claude.ai web)

1. **claude.ai → Settings → Connectors** → browse the connector directory → add
   **GitHub** (or add it as a custom connector pointing at
   `https://api.githubcopilot.com/mcp/`).
2. Complete the OAuth flow with your GitHub account and make sure access covers your
   private brain repo (see the troubleshooting section below — the default flow can
   silently under-grant).
3. Connect once on web — the connector is then available in the mobile apps too
   (the directory itself isn't browsable from mobile; do the setup on web/desktop).

Directory connectors are available on all plans including Free; *custom* connectors
require a paid plan.

## Teach claude.ai where the brain is (the memory seed)

claude.ai chats don't read `~/.claude/CLAUDE.md` — they need their own pointer.
Paste a paragraph like this into **Settings → Capabilities → memory** (and/or into a
Project's custom instructions, which survives memory-synthesis quirks better):

```
My persistent brain is the private GitHub repo <you>/<your-brain-repo>. In any chat:
read its INDEX.md via the GitHub connector first, and open only the notes matching
the topic; write durable facts back as commits following its CLAUDE.md write
protocol. Never store secret values in it — pointers only.
```

## Troubleshooting: the connector 404s on a repo that exists

The most common failure, and it's silent: the connector authenticates fine, lists
your **public** repos, but returns **404 on your private brain repo** — as if it
didn't exist. Cause: GitHub Apps separate *authorization* ("may act as you") from
*installation* ("may see these repos"). The connect flow sometimes completes only
the authorization half. Fix:

1. On GitHub: **Settings → Applications**. The connector's app (for claude.ai it's
   named like *"Claude Github MCP Connector"*) will be under **Authorized** GitHub
   Apps — but for private-repo access it must ALSO appear under **Installed** GitHub
   Apps.
2. If it's not installed: open the app's page (click its name, or
   `github.com/apps/<app-slug>`) → **Install** → your account → *Only select
   repositories* → your brain repo.
3. Installing from GitHub's side may end on an error page (e.g. `state: Field
   required`) — that's cosmetic; GitHub records the installation before the
   redirect. Just test again.

**Test it honestly.** Don't ask *"what do you know about me?"* — if you seeded the
memory paragraph, Claude will answer from that even while the connector fails, and
the break stays invisible (ask us how we know). A real test demands file content:

> *Fetch `INDEX.md` from my brain repo via the GitHub connector and quote its first
> heading line.*

## What it's like in practice

- **Recall:** ask anything that needs history — Claude fetches `INDEX.md`, picks the
  right note(s), and reads just those. Same discipline as on desktop, and worth
  keeping: MCP reads are per-file, so index-first is also the fast path.
- **Writes:** "remember this" in a phone chat becomes a real commit to the brain —
  which your desktop sessions see on their next `git pull`.

## Known limits

- The connector ecosystem is still young — expect occasional flakiness. The failure
  mode is inconvenience, never data loss: your repo and desktop path don't depend on
  it, and the GitHub mobile app can read/edit any note as a fallback.
- Tightest-scope option for auth: a fine-grained PAT restricted to the brain repo
  (if you use the custom-connector route) rather than broad OAuth.
