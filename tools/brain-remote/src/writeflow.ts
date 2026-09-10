import { updateIndex, indexFileFor, isIndexed, indexLineFor } from "./brainindex.js";
import type { IndexUpdate } from "./brainindex.js";
import { validateWrite, validateAppend, validateEdit, MAX_CHARS } from "./validate.js";
import { spliceAppend } from "./splice.js";
import { spliceEdit } from "./edit.js";
import { TRUNCATION_NOTICE, BrainFileNotFound } from "./gh.js";
import type { BrainFetcher } from "./gh.js";
import type { GitData } from "./gitdata.js";

const MAX_ATTEMPTS = 3;

type Head = { commitSha: string; treeSha: string };
type BuildOutcome =
  | { files: { path: string; content: string }[]; message: string; success: (shortSha: string) => string }
  | { refuse: string };

type IndexState = IndexUpdate | { kind: "index-missing"; file: string };
type IndexOutcome = { refuse: string } | { idx: IndexState; extra: { path: string; content: string }[] };

// One place decides which index file a note belongs to, fetches it at the
// commit's head, and produces the extra file for the commit. Shared by
// brain_write and brain_edit so the two cannot drift.
async function refreshIndex(
  fetchFile: BrainFetcher,
  commitSha: string,
  notePath: string,
  noteContent: string,
): Promise<IndexOutcome> {
  const indexPath = indexFileFor(notePath);
  let current: string;
  try {
    current = await fetchFile(indexPath, commitSha);
  } catch (err) {
    if (err instanceof BrainFileNotFound) return { idx: { kind: "index-missing", file: indexPath }, extra: [] };
    throw err;
  }
  if (current.endsWith(TRUNCATION_NOTICE)) {
    return { refuse: `${indexPath} too large to update safely from here — write it from a text session.` };
  }
  const idx = updateIndex(current, notePath, noteContent);
  return { idx, extra: idx.kind === "updated" ? [{ path: indexPath, content: idx.content }] : [] };
}

function indexSuffix(idx: IndexState): string {
  if (idx.kind === "updated") return " (+ INDEX line updated)";
  if (idx.kind === "section-missing") return ` — INDEX has no "${idx.section}" section, so its line was not added; add it from a text session`;
  if (idx.kind === "index-missing") return ` — ${idx.file} does not exist, so its line was not added; create it from a text session`;
  return "";
}

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

      const r = await refreshIndex(fetchFile, head.commitSha, v.clean, content);
      if ("refuse" in r) return r;
      return {
        files: [{ path: v.clean, content }, ...r.extra],
        message,
        success: (s) => `Committed ${s}: ${v.clean}${indexSuffix(r.idx)}.`,
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

export function makeBrainEditor(deps: { gitdata: GitData; fetchFile: BrainFetcher }) {
  const { gitdata, fetchFile } = deps;

  return async (path: string, find: string, replace: string, message: string): Promise<string> => {
    const v = validateEdit(path, find, replace);
    if (!v.ok) return v.reason;

    return withCasRetry(gitdata, async (head) => {
      let current: string;
      try {
        current = await fetchFile(v.clean, head.commitSha);
      } catch (err) {
        if (err instanceof BrainFileNotFound) {
          return { refuse: `No such file in the brain: ${v.clean} — brain_edit only edits existing files; create it with brain_write.` };
        }
        throw err;
      }
      if (current.endsWith(TRUNCATION_NOTICE)) {
        return { refuse: `${v.clean} is too large to edit safely from here — do it from a text session.` };
      }
      const e = spliceEdit(current, find, replace);
      if (!e.ok) return { refuse: e.reason };
      if (e.content.length > MAX_CHARS) {
        return { refuse: `The edit would grow ${v.clean} to ${e.content.length} chars; the cap is ${MAX_CHARS}.` };
      }
      if (v.clean === "TODO.md" && e.content.length * 2 < current.length) {
        return {
          refuse:
            `That would shrink TODO.md from ${current.length} to ${e.content.length} chars — ` +
            `a real restructure belongs in a text session.`,
        };
      }

      const files = [{ path: v.clean, content: e.content }];
      let suffix = "";
      if (isIndexed(v.clean) && indexLineFor(v.clean, current) !== indexLineFor(v.clean, e.content)) {
        const r = await refreshIndex(fetchFile, head.commitSha, v.clean, e.content);
        if ("refuse" in r) return r;
        files.push(...r.extra);
        suffix = indexSuffix(r.idx);
      }
      return {
        files,
        message,
        success: (s) => `Replaced 1 occurrence in ${v.clean} — ${s}${suffix}.`,
      };
    });
  };
}
