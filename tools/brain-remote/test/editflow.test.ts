import { describe, expect, it } from "vitest";
import { makeBrainEditor } from "../src/writeflow.js";
import { BrainFileNotFound, TRUNCATION_NOTICE } from "../src/gh.js";
import type { GitData } from "../src/gitdata.js";

const NOTE = "---\nname: n\ndescription: old desc\ntype: reference\n---\n\n# N\n\nstatus: draft\n";
const INDEX = "# INDEX\n\n## knowledge/ — facts\n- [N](knowledge/n.md) — old desc\n";
const TODO = "# TODO\n\n## Active\n\n### Item\n- **next:** 2026-09-14\n" + "- filler\n".repeat(20);

function fakeDeps(opts: { races?: number; files?: Record<string, string> } = {}) {
  let races = opts.races ?? 0;
  const files = opts.files ?? { "knowledge/n.md": NOTE, "INDEX.md": INDEX, "TODO.md": TODO };
  const committed: any[] = [];
  const reads: string[] = [];
  let headN = 0;
  const gitdata: GitData = {
    async getHead() { headN++; return { commitSha: `head${headN}`, treeSha: `tree${headN}` }; },
    async commitFiles(args) { committed.push(args); return `commit${headN}`; },
    async updateRef() { if (races > 0) { races--; return "race"; } return "ok"; },
  };
  const fetchFile = async (path: string, _ref?: string) => {
    reads.push(path);
    if (path in files) return files[path];
    throw new BrainFileNotFound(`No such file in the brain: ${path}`);
  };
  return { gitdata, fetchFile, committed, reads };
}

describe("makeBrainEditor", () => {
  it("edits the body only: single-file commit, no INDEX read", async () => {
    const d = fakeDeps();
    const out = await makeBrainEditor(d)("knowledge/n.md", "status: draft", "status: final", "finalize");
    expect(out).toBe("Replaced 1 occurrence in knowledge/n.md — commit1.");
    expect(d.committed).toHaveLength(1);
    expect(d.committed[0].files.map((f: any) => f.path)).toEqual(["knowledge/n.md"]);
    expect(d.committed[0].files[0].content).toContain("status: final");
    expect(d.committed[0].message).toBe("finalize");
    expect(d.reads).toEqual(["knowledge/n.md"]);
  });

  it("refreshes the INDEX line in the same commit when the description changes", async () => {
    const d = fakeDeps();
    const out = await makeBrainEditor(d)("knowledge/n.md", "description: old desc", "description: new desc", "redescribe");
    expect(out).toBe("Replaced 1 occurrence in knowledge/n.md — commit1 (+ INDEX line updated).");
    expect(d.committed[0].files.map((f: any) => f.path)).toEqual(["knowledge/n.md", "INDEX.md"]);
    expect(d.committed[0].files[1].content).toContain("- [N](knowledge/n.md) — new desc");
  });

  it("refreshes the INDEX line when the H1 changes", async () => {
    const d = fakeDeps();
    const out = await makeBrainEditor(d)("knowledge/n.md", "# N\n", "# N renamed\n", "retitle");
    expect(out).toContain("INDEX line updated");
    expect(d.committed[0].files[1].content).toContain("- [N renamed](knowledge/n.md) — old desc");
  });

  it("TODO.md edits never touch the INDEX", async () => {
    const d = fakeDeps();
    const out = await makeBrainEditor(d)("TODO.md", "**next:** 2026-09-14", "**next:** 2026-09-21", "bump");
    expect(out).toBe("Replaced 1 occurrence in TODO.md — commit1.");
    expect(d.reads).toEqual(["TODO.md"]);
  });

  it("refuses a missing file, pointing at brain_write, and commits nothing", async () => {
    const d = fakeDeps();
    const out = await makeBrainEditor(d)("knowledge/ghost.md", "a", "b", "x");
    expect(out).toContain("No such file in the brain: knowledge/ghost.md");
    expect(out).toContain("brain_write");
    expect(d.committed).toHaveLength(0);
  });

  it("refuses zero and multiple matches without committing", async () => {
    const d = fakeDeps();
    expect(await makeBrainEditor(d)("knowledge/n.md", "nope", "b", "x")).toMatch(/^Not found/);
    expect(await makeBrainEditor(d)("TODO.md", "- filler", "- x", "x")).toBe("Found 20 times — include more surrounding text so it matches exactly once.");
    expect(d.committed).toHaveLength(0);
  });

  it("refuses when the result would exceed the cap", async () => {
    const d = fakeDeps();
    const out = await makeBrainEditor(d)("knowledge/n.md", "status: draft", "x".repeat(100_001), "big");
    expect(out).toMatch(/cap is 100000/);
    expect(d.committed).toHaveLength(0);
  });

  it("applies the TODO.md wipe guard to the result", async () => {
    const d = fakeDeps();
    const out = await makeBrainEditor(d)("TODO.md", "- filler\n".repeat(20), "", "gut");
    expect(out).toMatch(/would shrink TODO\.md/);
    expect(d.committed).toHaveLength(0);
  });

  it("refuses a truncated source file", async () => {
    const d = fakeDeps({ files: { "knowledge/n.md": NOTE + TRUNCATION_NOTICE } });
    const out = await makeBrainEditor(d)("knowledge/n.md", "status: draft", "x", "x");
    expect(out).toMatch(/too large to edit/);
    expect(d.committed).toHaveLength(0);
  });

  it("lost race: refetches at the new head and retries", async () => {
    const d = fakeDeps({ races: 1 });
    const out = await makeBrainEditor(d)("knowledge/n.md", "status: draft", "status: final", "x");
    expect(out).toContain("commit2");
    expect(d.committed).toHaveLength(2);
    expect(d.committed[1].parentCommitSha).toBe("head2");
  });

  it("validation refusals return text without touching git", async () => {
    const d = fakeDeps();
    expect(await makeBrainEditor(d)("INDEX.md", "a", "b", "x")).not.toMatch(/Replaced/);
    expect(await makeBrainEditor(d)("knowledge/n.md", "", "b", "x")).toContain("empty");
    expect(d.committed).toHaveLength(0);
  });

  // Unlike append, edit performs plain string surgery with no inserted seam —
  // `replace` lands exactly where `find` was. So a GitHub token can straddle
  // the boundary directly: the file already carries the token's first 10
  // chars, and the edit's replacement supplies the remaining 20.
  it("refuses when a GitHub token straddles the edit seam", async () => {
    const d = fakeDeps({ files: { "knowledge/n.md": "note: ghp_ABCDEFGHIJ@ end\n" } });
    const out = await makeBrainEditor(d)("knowledge/n.md", "@", "KLMNOPQRSTUVWXYZ0123", "x");
    expect(out).toMatch(/GitHub token/);
    expect(d.committed).toHaveLength(0);
  });

  it("still accepts an unrelated edit when a secret-shaped string sits far (>200 chars) from the seam", async () => {
    const farSecret = "ghp_" + "B".repeat(25);
    const d = fakeDeps({
      files: { "knowledge/n.md": `${farSecret}\n${"z".repeat(300)}\nOld line to edit\n` },
    });
    const out = await makeBrainEditor(d)("knowledge/n.md", "Old line to edit", "New line edited", "x");
    expect(out).toMatch(/^Replaced 1 occurrence/);
    expect(d.committed).toHaveLength(1);
  });
});
