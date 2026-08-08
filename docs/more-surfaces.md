# More surfaces: second machine, Claude Code web, cloud sessions

## Another computer

**The one-sentence way** (recommended once the [GitHub MCP
connector](claude-ai-and-mobile.md) is set up — connectors are account-level, so
they're already on the new machine; verified mid-2026, and if the connector tools
don't appear in Claude Code there, the manual way below always works): open Claude
Code there and say

> *Bootstrap my brain: read `docs/bootstrap.md` from my `<your-brain-repo>` repo via
> the GitHub connector and follow it.*

Claude self-onboards — either **satellite** tier (connector-only, no git on the
device; right for casual boxes) or **full** tier (clone + repo-scoped deploy key).
Details: [bootstrap.md](bootstrap.md).

**The manual way** — the brain is just a repo, so a full setup is a two-liner
(assuming the machine already has GitHub auth):

```bash
git clone git@github.com:<you>/<your-brain-repo>.git ~/claude-brain
bash ~/claude-brain/setup.sh
```

`setup.sh` is idempotent and personalization is already done, so it just wires
`~/.claude/CLAUDE.md` and the retention setting. Every Claude Code session on that
machine now loads the brain. Keep machines honest with ordinary git: pull when you
sit down, push when memories get written.

## Claude Code web (claude.ai/code)

Add your brain repo to the session — alone or alongside the repos you're working on.
The brain's repo-root `CLAUDE.md` auto-loads, so recall works immediately.

Treat web sessions as **read-mostly**: cloud sessions typically land their commits on
`claude/…` branches rather than `main`, so if a web session writes memories, merge
that branch afterwards (or ask the session to open a PR). For heavy writing days,
prefer desktop.

## Cloud/sandbox sessions (no git credentials)

Some cloud environments can't clone a private repo at all. If the GitHub MCP
connector is available there, use the same pattern as [claude.ai and
mobile](claude-ai-and-mobile.md): read `INDEX.md` first via the connector, open
matching notes, write memories as real commits.

## One brain, many surfaces — the mental model

Every surface is just a different transport to the same repo:

| Surface | Transport | Read | Write |
|---|---|---|---|
| Claude Code (desktop) | local clone + `~/.claude/CLAUDE.md` | full | full (commit + push) |
| Claude Code (satellite device) | GitHub MCP connector + [bootloader stub](bootstrap.md) | full | full (commits via connector) |
| claude.ai web + mobile | GitHub MCP connector | full | full (commits via connector) |
| Claude Code web | repo added to session | full | via `claude/` branches |
| Any browser, worst case | github.com itself | full | GitHub's editor |

Nothing here is a server you run. If any surface breaks, the others — and the repo —
are unaffected.
