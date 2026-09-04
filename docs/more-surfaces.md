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

**The manual way** — the brain is just a repo, so a full setup is a two-liner plus
one command (assuming the machine already has GitHub auth):

```bash
git clone git@github.com:<you>/<your-brain-repo>.git ~/claude-brain
claude plugin marketplace add generalOtto/claude-brain-kit && claude plugin install brain@claude-brain-kit
```

Then run `/brain:setup` in a Claude Code session. It's idempotent and personalization
is already done, so it just wires `~/.claude/CLAUDE.md` and the retention setting;
the plugin's hook handles the session-start auto-sync.
Every Claude Code session on that machine now loads the brain *and* freshens the
clone on its own — writes push themselves the moment they're made, and sessions open
knowing whether the clone is fresh (the worktree flow + hook — see
[how-it-works.md](how-it-works.md)).

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

## Obsidian as a viewer (optional)

The brain doubles as a perfectly ordinary [Obsidian](https://obsidian.md) vault — the
notes use frontmatter and `[[wikilinks]]`, so opening the clone as a vault gives you
graph view, backlinks, and comfortable human reading for free. If you want to
hand-edit through it:

- **Open the clone as the vault** (e.g. `~/claude-brain`) — no copy, no export.
- **Use the community Obsidian Git plugin** (unrelated to the Claude Code plugin) for
  your hand-edits (commit-and-sync with rebase pull). That's the *human* edit path;
  Claude's writes keep going through the worktree flow, and the two coexist because
  both end in pushes to `main`.
- The kit's `.gitignore` already excludes the parts of `.obsidian/` that shouldn't
  sync (workspace state, plugin runtime data — plugin data files can hold tokens).
  Committing your `.obsidian` app settings and theme is fine if you want the same
  viewer everywhere.

Strictly optional — the brain never depends on it, and Claude never writes through it.

## One brain, many surfaces — the mental model

Every surface is just a different transport to the same repo:

| Surface | Transport | Read | Write |
|---|---|---|---|
| Claude Code (desktop) | local clone + brain plugin | full | full (worktree → push to main) |
| Claude Code (satellite device) | GitHub MCP connector + [bootloader stub](bootstrap.md) | full | full (commits via connector) |
| claude.ai web + mobile | GitHub MCP connector | full | full (commits via connector) |
| Claude Code web | repo added to session | full | via `claude/` branches |
| Any browser, worst case | github.com itself | full | GitHub's editor |

Nothing here is a server you run — one plugin, one repo. If any surface breaks, the
others — and the repo — are unaffected.
