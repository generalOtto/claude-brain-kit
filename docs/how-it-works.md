# How it works — and why it's just files

## The architecture, in one sentence

**The repo IS the brain**: markdown notes in a private git repo, a bootloader
(`CLAUDE.md`) that loads into every Claude Code session, and an index (`INDEX.md`)
that lets Claude find the right note without loading everything.

```mermaid
graph TD
    A[Private GitHub repo<br/>= the brain] -->|"@import stub"| B[~/.claude/CLAUDE.md<br/>loads every Claude Code session]
    A -->|GitHub MCP connector| C[claude.ai web + mobile app]
    A -->|git clone + plugin| D[Your other machines]
    B --> E[Recall: INDEX.md first,<br/>then only matching notes]
    B --> F[Writes: note + INDEX line<br/>own worktree → push to main]
```

There are three moving parts, and you operate none of them:

1. **The files** — markdown notes, one fact per file, with YAML frontmatter and
   `[[wikilinks]]`. Durable, versioned, offline-capable, greppable, restorable.
2. **The plugin** — client configuration installed by `claude plugin install`,
   versioned, and not a server: it runs one bash script at session start and puts
   one (`brain-write.sh`) on PATH. Its `/brain:setup` wires `~/.claude/CLAUDE.md`
   so the brain's bootloader loads into every session (user-scope memory is
   documented Claude Code behavior; the bootloader just happens to live in a repo).
3. **The protocols** — the bootloader tells Claude *how to remember*: recall =
   index-first and selective; writes = note + index line, committed in a throwaway
   worktree and pushed straight to `main`.

## Why not a memory database?

Every popular memory system for Claude adds infrastructure: a SQLite/vector store, an
embedding pipeline, a daemon, an MCP server, or a hosted service. Those solve recall
at scale — and cost you a dependency that can break, a service to operate, and a
store you can't read with your own eyes.

A personal brain doesn't have that scale problem. A year of dense, curated notes is a
few hundred kilobytes of markdown. Claude reads an index and opens three files faster
— and more transparently — than any retrieval pipeline. And because it's git:

- **History is free.** Every fact has a commit explaining when and why it changed.
- **Sync is free.** Push/pull replaces any sync service.
- **Durability is free.** GitHub is the backup; any clone is a full restore.
- **Portability is free.** It's markdown. It outlives any tool, including Claude.

If your brain ever grows a hundredfold, you can bolt retrieval on *top of the files*
then — the files stay the source of truth, so nothing is locked in.

## Why curation instead of auto-capture?

Auto-capture systems record everything and compress it later. That yields volume, not
memory: transcripts full of dead ends, wrong turns, and noise, with the load-bearing
facts buried. This system takes the opposite bet — **Claude writes memory the way a
person does: deciding, at the moment something matters, that it's worth keeping.**

The write protocol makes that cheap: one small note, one index line, one commit,
usually written mid-session while you're both looking at it. You curate by existing —
wrong notes get deleted, duplicates get merged, and the brain stays small enough that
all of it is *actually usable*.

## Why writes go through a worktree

The write protocol never edits the shared clone directly. Every write happens in a
throwaway git worktree and is pushed straight to remote `main` the moment it's made —
which is what `brain-write.sh` (on PATH while the plugin is enabled) automates, and
what the plugin's `brain:write` skill walks Claude through:

```bash
wt=$(brain-write.sh open)     # fresh worktree at origin/main
# ... Claude writes the note + index line inside $wt ...
brain-write.sh publish "$wt" "brain: what was learned"
```

Two reasons, both earned the hard way:

- **Parallel sessions share one clone.** Two Claude sessions on the same machine both
  touching `INDEX.md` is a silent read-modify-write race — last save wins, the other
  write vanishes with no error. Worktrees give each write an isolated checkout, and
  remote `main` becomes the serialization point: a push is an atomic ref update, a
  lost push race is replayed with `pull --rebase`, and a genuine same-file collision
  surfaces as a visible conflict instead of silent loss.
- **"Push when practical" goes stale.** With more than one device, an unpushed memory
  is a memory your other machines don't have. Publishing pushes immediately —
  connector surfaces (which read GitHub live) see every write the moment it lands,
  and other clones catch up at their next pull. Offline, the write lands on the
  clone's local `main` (so it's still recallable on this device) — or a
  `pending-sync/*` branch if the clone is busy — and `brain-write.sh sync` pushes
  it next time you're online.

Connector surfaces (claude.ai, the phone app, satellite devices) don't need any of
this: their writes are GitHub API commits, which are already atomic on the remote.

## Session start: the clone freshens itself

Writes push themselves the moment they're made — but *reads* need the clone to be
fresh, and "pull when you sit down" is a habit that fails silently. So the plugin
ships a Claude Code **SessionStart hook**: when a session starts, it fetches and
fast-forwards the clone and injects exactly one status line into Claude's context —

- `brain: fresh` / `brain: pulled N new commit(s)` — normal cases
- `brain: pull FAILED (offline or diverged) — clone may be STALE` — Claude knows not
  to trust the clone blindly (the same STALE flag appears when the clone sits on
  another branch or mid-rebase: the hook fetches but never moves HEAD then, reporting
  `brain: fetched, pull skipped (clone on '<branch>' or an operation in progress) —
  clone may be STALE`)
- `… UNPUSHED writes waiting … — run brain-write.sh sync` — offline writes are
  parked; sync once you're online
- `… not wired: run /brain:setup` — the bootloader isn't imported on this machine
- `… transcripts expire in Nd: run /brain:setup` — retention is still at the default

Design constraints, in case you're auditing it: it **always exits 0** (a brain problem
must never break session start), it **can't hang** (no terminal prompts, bounded ssh
connect, bounded timeouts — 15 s fetch, 5 s fast-forward; Claude Code's 30 s hook limit caps the whole run — where
coreutils provides one), it's **report-only** beyond the pull (never auto-syncs, never
touches worktrees), and it **never dumps note content**
into context — recall stays index-first. The hook matcher is `startup|clear`, not
`resume`, so resuming a session doesn't pay pull latency. The same script answers
`--resolve` (which clone path it will use) and `--check-wired` (is the bootloader
imported) — that's what `/brain:setup` and the skills call.

## Mechanisms that ride on conversations (still no scheduler)

Claude can't run on a schedule without an always-on machine — and this system runs no
servers. The kit's answer: intermittent behavior rides on sessions that already
happen. The conventions in `conventions/` are the source of truth on every surface;
on Claude Code they surface as the plugin's `brain:todos` / `brain:idea` /
`brain:profile` skills, loaded on demand instead of in every session. Three ship
enabled:

- **The to-do list** (`TODO.md` + `conventions/todo-list.md`) — one list for chores,
  reminders, and follow-ups. At most once a day, *after* handling what you actually
  asked, Claude surfaces a compact digest of what's due; "todos" opens the list any
  time, and "remind me to X" on any surface files an item. Hard deadlines get bridged
  to a real alarm — the mechanism is honest about being probabilistic.
- **Idea capture** (`ideas/` + `conventions/idea-capture.md`) — say "idea: …" on any
  surface and it's filed to `ideas/<category>/<slug>.md` in your words, confirmed in
  one line. Capture must be cheaper than forgetting.
- **The living profile** (`identity/profile.md` + `conventions/profile-evaluation.md`)
  — when a session produces hard evidence about who you are or how you work, Claude
  appends a dated one-liner to an evidence log and tells you (`profiled → …` — your
  veto point). Every ~10 entries it offers a consolidation pass that distills the log
  into a portrait. Strict evidence rules keep it honest: only your words, decisions,
  and credentials count — never how projects are implemented (that's mostly Claude's
  authorship), and never knowledge Claude itself explained to you.

Each is a couple of markdown files plus a skill — uninstall the plugin and delete the
files and the mechanism is gone, nothing else to uninstall.

## Zero-friction operations

The same logic extends to *why Claude needs you at all*: `brain-secret` fetches
credentials from Bitwarden Secrets Manager instead of asking you to paste them,
`brain-keepalive-install` keeps the `claude` OAuth login from lapsing, and
`conventions/standing-decisions.md` pre-answers the operational calls (merge, push,
tag, deploy, scratch resources, brainstorm defaults) that don't need a fresh
confirmation every time. One deliberate exception stays human-triggered: the daily
digest. Full writeup: [zero-friction.md](zero-friction.md).

## The recall discipline

The bootloader teaches Claude a strict order:

1. Identity essentials — always loaded (they're tiny).
2. Need more? **Skim `INDEX.md`** — one line per note.
3. Open **only** the notes whose descriptions match the task.

This is the token-economy trick that makes a growing brain sustainable: sessions pay
for an index and a handful of relevant notes, never the whole corpus. Guard it by
keeping descriptions honest and notes single-purpose — see
[maintenance.md](maintenance.md).

## What goes in the brain (and what doesn't)

**In:** who you are, how you like to work, standing conventions, per-project mission
control (state/decisions/links), hard-won gotchas, pointers to where external things
live, journal entries for the sessions that mattered.

**Out:** anything a repo already records (code, file structure, git history), session
noise, and — absolutely — **secret values** ([security.md](security.md)).
