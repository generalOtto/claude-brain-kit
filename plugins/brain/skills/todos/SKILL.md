---
name: todos
description: The brain's to-do list (TODO.md). Use when the user says "todos", "remind me to …", or answers a digest item (go / later / mute / done / add), and once a day — after the user's actual request is handled, never instead of it — to surface due items.
argument-hint: "[go|later|mute|done|add …]"
---

# /brain:todos $ARGUMENTS

Clone: `${user_config.brain_dir}`. Read `TODO.md` and `conventions/todo-list.md` there —
the convention is the rulebook (item format, the daily check, responses, the
hard-deadline bridge); this skill only adds the Claude Code mechanics:

- **No argument / "todos"** → show the list compactly (Active items: one line each).
- **Daily check** → only when `TODO.md`'s `last-surfaced` < today and the session is
  not urgent: list due items (`next:` ≤ today; judgment on `when:` for uncached items),
  then stamp `last-surfaced` via the write skill.
- **go [item]** → real work runs in a **subagent** that reports back; the main session
  does the bookkeeping (`last:`, `next:`, done log). Trivial items skip the subagent.
- **later / mute / done / add …** → edit the item per the convention.
- **"Remind me to X"** anywhere = **add** (offer the calendar/scheduled-agent bridge if
  it smells hard-deadline).

Every mutation publishes through the `brain:write` skill (worktree flow). Reply briefly.
