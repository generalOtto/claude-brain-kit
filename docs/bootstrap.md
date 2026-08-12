# One-sentence device onboarding

Once your brain exists, adding a new device shouldn't mean copy-pasting setup
instructions between machines. It doesn't: the instructions live *in the brain*, and
every device with your Claude account can reach the brain through the GitHub MCP
connector ([set up once, on claude.ai](claude-ai-and-mobile.md) — connectors are
account-level, so they follow you to new devices automatically; verified mid-2026,
availability in Claude Code can vary by plan and client version — Full mode below
never depends on it).

So on any fresh machine, open Claude Code and say:

> **Bootstrap my brain: read `docs/bootstrap.md` from my `<your-brain-repo>` repo via
> the GitHub connector and follow it.**

That's the whole onboarding. The rest of this page is written for the Claude that
just got told that.

---

## Claude: you were pointed here on a new device

This repo is your human's persistent brain. Read the repo's `CLAUDE.md` first — it
holds the recall protocol, the write protocol, and the secrets policy. Then wire this
device using one of the two tiers below.

### Step 0 — pick the tier

- **Satellite** (default): secondary/casual machines — a gaming box, a family
  computer, a short-lived VM. No git, no keys, no clone; the GitHub MCP connector
  does everything.
- **Full**: primary work machines. Local clone + `setup.sh`. Choose when local
  search over the notes, offline access, or git-based workflows matter here.
  (Satellite upgrades to Full at any time — just do Full's steps later.)

When unsure, ask: "satellite or full?"

### Satellite mode (~1 minute, zero installs)

1. **Verify the connector.** Fetch `INDEX.md` from the brain repo via the GitHub MCP
   connector. If the tools are missing or the repo 404s, don't guess — see
   [Troubleshooting the connector](claude-ai-and-mobile.md#troubleshooting-the-connector-404s-on-a-repo-that-exists),
   or fall back to Full mode.
2. **Drop the bootloader stub.** If `~/.claude/CLAUDE.md` already exists and isn't
   this stub, STOP and show your human before touching it. Otherwise write (filling
   in the real name from `identity/about-me.md` and the real `owner/repo`):

   ```markdown
   # <Name>'s brain — satellite bootloader
   I work with <Name> — a long-term collaborator, not a stranger. Our shared memory
   ("the brain") is the private GitHub repo **<you>/<your-brain-repo>**.
   - **Recall:** via the GitHub MCP connector, read the repo's INDEX.md first, then
     open only the notes matching the task. Read its CLAUDE.md when protocol details
     matter. The brain wins over assumptions.
   - **Write:** when something durable is learned, commit it through the connector,
     following the repo CLAUDE.md write protocol (one small note + INDEX line).
   - **Secrets:** NEVER store secret values in the brain — pointers only.
   - This is a satellite device (no local clone). Full instructions: repo
     `docs/bootstrap.md`.
   ```

3. **Optional:** raise Claude Code's transcript retention on this device too — add
   `"cleanupPeriodDays": 3650` to `~/.claude/settings.json` (by default transcripts
   are deleted after ~30 idle days).
4. **Prove it.** Read `identity/about-me.md` through the connector and tell your
   human what you know about them. Consider a journal line or a small note recording
   that this device joined — per the write protocol.

### Full mode (~5 minutes, one GitHub click from your human)

1. Verify `git` and `python3` exist (on immutable OSes — SteamOS, Fedora Silverblue,
   etc. — prefer homebrew/flatpak over unlocking the root filesystem).
2. Generate a **dedicated** deploy key — don't reuse `~/.ssh/id_ed25519`: GitHub
   rejects a key that's already attached to any account or repo, and reusing a
   personal key would give this device account-wide access, defeating the point:
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/brain-deploy -N "" -C "<device-name>-brain"
   ```
   Then **print the PUBLIC key (`~/.ssh/brain-deploy.pub`) and pause.**
3. Your human adds it on GitHub: brain repo → Settings → **Deploy keys** → Add,
   ticking **Allow write access**. (A deploy key is scoped to this one repo — a
   casual device never gets account-wide GitHub access. See
   [Security](security.md).)
4. Clone with that key, and pin the clone to it:
   ```bash
   GIT_SSH_COMMAND="ssh -i ~/.ssh/brain-deploy -o IdentitiesOnly=yes" \
     git clone git@github.com:<you>/<your-brain-repo>.git ~/claude-brain
   git -C ~/claude-brain config core.sshCommand "ssh -i ~/.ssh/brain-deploy -o IdentitiesOnly=yes"
   bash ~/claude-brain/setup.sh
   ```
   (`setup.sh` is idempotent: `~/.claude/CLAUDE.md` stub/symlink + retention
   setting; personalization already happened on the first machine.)
5. Set the commit identity in that clone: `git config user.name` / `user.email` —
   ask your human (the name may be in `identity/about-me.md`; an email usually
   isn't).
6. **Prove it** — as in Satellite step 4, using local files this time.

### After bootstrap

Every future session on this device loads the brain automatically (stub or clone).
Keep honoring the write protocol — on full-tier devices every write publishes through
`tools/brain-write.sh` (own worktree → immediate push to `main`), so the remote — and
every connector surface — has each memory the moment it's made; other clones catch up
on their next pull.
