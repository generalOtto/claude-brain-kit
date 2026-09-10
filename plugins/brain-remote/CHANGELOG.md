# brain-remote plugin — changelog

## 1.5.0 — 2026-09-10
Token diet, paired with server 1.5.0. The plugin now sends `x-brain-surface: claude-code`, so
`brain_index` returns the catalog only (the bootloader is already in context via CLAUDE.md);
pass `bootloader: true` on a surface that lacks it. Catalog descriptions are capped at 120
chars server-side. New `brain_edit` tool (exact single-match find/replace on one existing
file, INDEX line refreshed when title/description change). `brain_append` section names now
match a heading's leading words ("Known dead weight" finds "## Known dead weight (pending …)").
Journal notes index into `journal/INDEX.md` when the brain keeps that sub-index.

## 1.0.0 — 2026-09-07
Renamed from `brain-voice` (shipped 2026-09-04, never installed anywhere). The plugin registers
the brain's remote MCP server — index, read and guarded writes over HTTP for any Claude Code
session without a local clone; "voice" only described where the server was first needed.
Config key `voice_brain_url` → `brain_remote_url`, server key `voice-brain` → `brain-remote`.
