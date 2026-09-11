---
name: profile
description: Append a dated evidence one-liner to identity/profile.md when the user's own words, decisions or credentials in this session are hard evidence about who they are, how they work, or what they know. Facts only; never Claude-supplied knowledge.
user-invocable: false
---

# Profile evidence capture

Clone: run `"${CLAUDE_PLUGIN_ROOT}/hooks/session-start" --resolve` to get the path. Follow `conventions/profile-evaluation.md` there (the
evidence rules, incl. the knowledge-provenance exclusion). Append one dated line to the
`## Evidence log` in `identity/profile.md` through the `brain:write` skill and reply with
one line: `profiled → <what was noted>`. Deductions happen only in the daily
consolidation pass — never in-session; the session-start hook reports it (`profile: N
unconsolidated evidence entries`) at the start of the first session of any day the
evidence log holds entries newer than `last-consolidated`.
