# More surfaces: second machine, Claude Code web, cloud sessions

## Another computer

The brain is just a repo — a new machine is a two-liner:

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
| claude.ai web + mobile | GitHub MCP connector | full | full (commits via connector) |
| Claude Code web | repo added to session | full | via `claude/` branches |
| Any browser, worst case | github.com itself | full | GitHub's editor |

Nothing here is a server you run. If any surface breaks, the others — and the repo —
are unaffected.
