---
name: context-hygiene
description: "Keep tool output out of the main session: bulk brain reads and rewrites in a subagent, targeted edits over whole-file writes, shell output trimmed at the source"
type: feedback
---

# Context hygiene — tool output is the token bill, not the chat

Every tool round re-sends the whole context, so output that enters it once is paid for on
every later round. A short session can reach hundreds of thousands of tokens with under
5% of them conversation: notes read whole, a big file rewritten (read + replace, both
resident forever), a `$PATH` dump, a redirect URL carrying a token. Cutting what enters
context is worth more than any compaction afterwards — `/context` shows the live
breakdown; `/compact` is the fallback, not the plan.

## Rules (wherever Claude has subagents or a shell)
1. **Bulk brain work goes to a subagent.** Reading more than ~3 notes, or rewriting a
   large one (`TODO.md`, a mission-control note), runs in a subagent that returns a summary
   or the exact fragment — never the file bodies. The to-do "go" rule already does this
   for execution; apply it to reads too.
2. **Targeted edits over whole-file writes.** A one-line change to a big note must not
   cost the whole file twice. Append a dated line or edit in place (`brain_edit` /
   `brain_append` on connector surfaces; an in-place edit inside the worktree on Claude
   Code). This is also a **correctness** rule: a whole-file write from a stale read
   silently reverts the lines another session appended in between.
3. **Trim shell output at the source.** `head`/`tail`/`cut`/`grep` on every command whose
   output size is unknown. Never print `$PATH`, `env`, whole compose files or logs. Never
   print redirect URLs or headers from authenticated endpoints — they carry tokens
   (`curl -sI … | grep -i '^location' | cut -c1-80`) — and mask path secrets before
   showing MCP server URLs (`claude mcp list` prints them whole).
4. **Grep spilled tool results, don't read them.** When a result is saved to a file, grep
   it for what the task needs; a whole-file read goes to a subagent.
5. **Don't re-read what is already in context.** One `brain_index` per session; one read
   per note.

Related: [[todo-list]], [[persist-when-blocked]], [[evidence-before-claims]].
