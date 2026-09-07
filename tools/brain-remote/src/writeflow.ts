import { updateIndex } from "./brainindex.js";
import { validateWrite, validateAppend, MAX_CHARS } from "./validate.js";
import { spliceAppend } from "./splice.js";
import { TRUNCATION_NOTICE, BrainFileNotFound } from "./gh.js";
import type { BrainFetcher } from "./gh.js";
import type { GitData } from "./gitdata.js";

const MAX_ATTEMPTS = 3;

type Head = { commitSha: string; treeSha: string };
type BuildOutcome =
  | { files: { path: string; content: string }[]; message: string; success: (shortSha: string) => string }
  | { refuse: string };

// Shared CAS loop: fetch head, let the flow build its commit against exactly that
// head, commit, non-force ref update; a lost race rebuilds on the winner's head.
// Both brain_write and brain_append ride this one loop so retry semantics can't drift.
async function withCasRetry(gitdata: GitData, build: (head: Head) => Promise<BuildOutcome>): Promise<string> {
  try {
    for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
      const head = await gitdata.getHead();
      const b = await build(head);
      if ("refuse" in b) return b.refuse;
      const sha = await gitdata.commitFiles({
        files: b.files,
        message: b.message,
        parentCommitSha: head.commitSha,
        baseTreeSha: head.treeSha,
      });
      if ((await gitdata.updateRef(sha)) === "ok") return b.success(sha.slice(0, 7));
    }
    return "The brain is busy (another write landed each time I tried). Nothing was changed — try again in a moment.";
  } catch (err) {
    const detail = err instanceof Error ? err.message : "unknown error";
    return `The write failed (${detail}). Nothing may have been committed — read the note back to check, or retry from a text session.`;
  }
}

export function makeBrainWriter(deps: { gitdata: GitData; fetchFile: BrainFetcher }) {
  const { gitdata, fetchFile } = deps;

  return async (path: string, content: string, message: string): Promise<string> => {
    const v = validateWrite(path, content);
    if (!v.ok) return v.reason;

    return withCasRetry(gitdata, async (head) => {
      if (v.clean === "TODO.md") {
        let current: string | null = null;
        try {
          current = await fetchFile("TODO.md", head.commitSha);
        } catch (err) {
          if (!(err instanceof BrainFileNotFound)) throw err;
        }
        if (current !== null && content.length * 2 < current.length) {
          return {
            refuse:
              `That would shrink TODO.md from ${current.length} to ${content.length} chars — ` +
              `to add items use brain_append; a real restructure belongs in a text session.`,
          };
        }
      }

      const currentIndex = await fetchFile("INDEX.md", head.commitSha);
      if (currentIndex.endsWith(TRUNCATION_NOTICE)) {
        return { refuse: "INDEX too large to update safely from here — write it from a text session." };
      }
      const files = [{ path: v.clean, content }];
      const idx = updateIndex(currentIndex, v.clean, content);
      if (idx.kind === "updated") files.push({ path: "INDEX.md", content: idx.content });

      return {
        files,
        message,
        success: (s) => {
          if (idx.kind === "updated") return `Committed ${s}: ${v.clean} (+ INDEX line updated).`;
          if (idx.kind === "section-missing") {
            return `Committed ${s}: ${v.clean} — INDEX has no "${idx.section}" section, so its line was not added; add it from a text session.`;
          }
          return `Committed ${s}: ${v.clean}.`;
        },
      };
    });
  };
}

export function makeBrainAppender(deps: { gitdata: GitData; fetchFile: BrainFetcher }) {
  const { gitdata, fetchFile } = deps;

  return async (path: string, content: string, section: string | undefined, message: string): Promise<string> => {
    const v = validateAppend(path, content, section);
    if (!v.ok) return v.reason;

    return withCasRetry(gitdata, async (head) => {
      let current: string;
      try {
        current = await fetchFile(v.clean, head.commitSha);
      } catch (err) {
        if (err instanceof BrainFileNotFound) {
          return { refuse: `No such file in the brain: ${v.clean} — brain_append only appends to existing files; create it with brain_write.` };
        }
        throw err;
      }
      if (current.endsWith(TRUNCATION_NOTICE)) {
        return { refuse: `${v.clean} is too large to append to safely from here — do it from a text session.` };
      }
      const s = spliceAppend(current, content, section);
      if (!s.ok) return { refuse: s.reason };
      if (s.content.length > MAX_CHARS) {
        return { refuse: `Appending would grow ${v.clean} to ${s.content.length} chars; the cap is ${MAX_CHARS}.` };
      }
      return {
        files: [{ path: v.clean, content: s.content }],
        message,
        success: (sha) =>
          `Committed ${sha}: appended to ${v.clean}${section !== undefined ? ` (section "${section}")` : ""}.`,
      };
    });
  };
}
