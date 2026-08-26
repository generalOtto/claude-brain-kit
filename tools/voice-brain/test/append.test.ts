import { describe, expect, it } from "vitest";
import { makeBrainAppender } from "../src/writeflow.js";
import { BrainFileNotFound, TRUNCATION_NOTICE } from "../src/gh.js";
import type { GitData } from "../src/gitdata.js";

const TODO = `# TODO

## Active

### Old item
- body

## Muted

*(nothing)*
`;

function fakeDeps(opts: { races?: number; files?: Record<string, string> } = {}) {
  let races = opts.races ?? 0;
  const files = opts.files ?? { "TODO.md": TODO };
  const committed: any[] = [];
  let headN = 0;
  const gitdata: GitData = {
    async getHead() { headN++; return { commitSha: `head${headN}`, treeSha: `tree${headN}` }; },
    async commitFiles(args) { committed.push(args); return `commit${headN}`; },
    async updateRef() { if (races > 0) { races--; return "race"; } return "ok"; },
  };
  const fetchFile = async (path: string, _ref?: string) => {
    if (path in files) return files[path];
    throw new BrainFileNotFound(`No such file in the brain: ${path}`);
  };
  return { gitdata, fetchFile, committed };
}

describe("makeBrainAppender", () => {
  it("appends into a section and commits exactly the target file", async () => {
    const d = fakeDeps();
    const out = await makeBrainAppender(d)("TODO.md", "### New\n- x", "Active", "add todo");
    expect(out).toMatch(/committed/i);
    expect(out).toContain("commit1");
    expect(out).toContain('appended to TODO.md (section "Active")');
    expect(d.committed).toHaveLength(1);
    expect(d.committed[0].files.map((f: any) => f.path)).toEqual(["TODO.md"]);
    expect(d.committed[0].files[0].content).toContain("- body\n\n### New\n- x\n\n## Muted");
    expect(d.committed[0].message).toBe("add todo");
  });

  it("appends at EOF when no section is given", async () => {
    const d = fakeDeps({ files: { "journal/x.md": "# J\n\nentry\n" } });
    const out = await makeBrainAppender(d)("journal/x.md", "more", undefined, "extend");
    expect(out).toContain("appended to journal/x.md");
    expect(out).not.toContain("section");
    expect(d.committed[0].files[0].content).toBe("# J\n\nentry\n\nmore\n");
  });

  it("refuses a missing file, pointing at brain_write, committing nothing", async () => {
    const d = fakeDeps();
    const out = await makeBrainAppender(d)("knowledge/ghost.md", "x", undefined, "m");
    expect(out).toContain("No such file in the brain: knowledge/ghost.md");
    expect(out).toMatch(/brain_write/);
    expect(d.committed).toHaveLength(0);
  });

  it("refuses a missing section with the file's headings, committing nothing", async () => {
    const d = fakeDeps();
    const out = await makeBrainAppender(d)("TODO.md", "x", "Done log", "m");
    expect(out).toContain('"Active"');
    expect(out).toContain('"Muted"');
    expect(d.committed).toHaveLength(0);
  });

  it("validation refusals surface without touching git", async () => {
    const d = fakeDeps();
    const out = await makeBrainAppender(d)("tools/x.md", "x", undefined, "m");
    expect(out).toMatch(/protected directory/);
    expect(d.committed).toHaveLength(0);
  });

  it("refuses when the fetched file carries the truncation notice", async () => {
    const d = fakeDeps({ files: { "TODO.md": "big" + TRUNCATION_NOTICE } });
    const out = await makeBrainAppender(d)("TODO.md", "x", undefined, "m");
    expect(out).toMatch(/too large/i);
    expect(d.committed).toHaveLength(0);
  });

  it("refuses when the spliced result would exceed the cap", async () => {
    const d = fakeDeps({ files: { "TODO.md": "x".repeat(99_990) } });
    const out = await makeBrainAppender(d)("TODO.md", "y".repeat(50), undefined, "m");
    expect(out).toMatch(/cap/i);
    expect(d.committed).toHaveLength(0);
  });

  it("lost race: refetches and retries against the new head", async () => {
    const d = fakeDeps({ races: 1 });
    const out = await makeBrainAppender(d)("TODO.md", "### N\n- x", "Active", "m");
    expect(out).toMatch(/committed/i);
    expect(d.committed).toHaveLength(2);
    expect(d.committed[1].parentCommitSha).toBe("head2");
  });

  it("unexpected errors degrade to text", async () => {
    const d = fakeDeps();
    d.gitdata.getHead = async () => { throw new Error("GitHub returned 500"); };
    const out = await makeBrainAppender(d)("TODO.md", "x", undefined, "m");
    expect(out).toMatch(/failed/i);
    expect(out).toContain("500");
  });
});
