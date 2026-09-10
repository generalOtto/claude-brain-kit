---
name: standing-decisions
description: "Pre-decided operational calls so Claude never asks — merge, push, tag, deploy, scratch resources, brainstorm defaults"
type: feedback
---

# Standing decisions — calls Claude should just make

**Why:** every "I need to check with you first" is a point of friction, and most of
them are on questions {{YOUR_NAME}} has already answered in principle — they just
haven't been written down. This file writes them down once so Claude stops asking.

**The rule:** when a situation below matches, do it — don't pause for confirmation.

- **Solo-repo merges.** After tests are green and a clean review, merge locally,
  push `main`, and delete the branch. No confirmation.
- **Releases.** After probing that the build/deploy actually works, tag and deploy
  without asking.
- **Scratch resources.** Anything prefixed `scratch-` (branches, cloud resources,
  temp files) can be created and cleaned up freely.
- **Brainstorms.** End with a recommendation and proceed on it unless {{YOUR_NAME}}
  objects — don't stall on "which do you want?" when there's a clear best answer.
- **Secrets.** Fetch with `brain-secret` before ever asking {{YOUR_NAME}} to paste a
  value. See `docs/zero-friction.md`.
- **Devices.** Try the remote path (wake it, reach it over the tunnel/API) before
  declaring "needs the human."
- **The daily digest stays human-triggered.** This is the one deliberate exception —
  it runs on "go," never on a schedule. See `conventions/todo-list.md`.

## What still comes back to you

- Destructive or public actions outside the rules above (force-push to a shared
  branch, deleting something that isn't `scratch-`, posting publicly).
- Real design forks — a genuine "which direction" choice with no clear best answer,
  not a brainstorm default.
- Physical-world acts (anything Claude can't do from a keyboard).
