# brain-remote plugin — changelog

## 1.0.0 — 2026-09-07
Renamed from `brain-voice` (shipped 2026-09-04, never installed anywhere). The plugin registers
the brain's remote MCP server — index, read and guarded writes over HTTP for any Claude Code
session without a local clone; "voice" only described where the server was first needed.
Config key `voice_brain_url` → `brain_remote_url`, server key `voice-brain` → `brain-remote`.
