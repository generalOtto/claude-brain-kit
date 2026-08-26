import { describe, expect, it } from "vitest";
import { makeBrainWriter } from "../src/writeflow.js";
import { TRUNCATION_NOTICE, BrainFileNotFound } from "../src/gh.js";
import type { GitData } from "../src/gitdata.js";

const FM = "---\nname: n\ndescription: d\ntype: reference\n---\n\n# N\nbody\n";
const INDEX = "# INDEX\n\n## knowledge/ — facts\n- [Old](knowledge/old.md) — o\n";

function fakeDeps(opts: { races?: number; todo?: string } = {}) {
  let races = opts.races ?? 0;
  const committed: any[] = [];
  let headN = 0;
  const gitdata: GitData = {
    async getHead() { headN++; return { commitSha: `head${headN}`, treeSha: `tree${headN}` }; },
    async commitFiles(args) { committed.push(args); return `commit${headN}`; },
    async updateRef() { if (races > 0) { races--; return "race"; } return "ok"; },
  };
  const fetchFile = async (path: string, ref?: string) => {
    if (path === "INDEX.md") return INDEX;
    if (path === "TODO.md" && opts.todo !== undefined) return opts.todo;
    throw new Error(`unexpected read: ${path}@${ref}`);
  };
  return { gitdata, fetchFile, committed };
}

describe("makeBrainWriter", () => {
  it("happy path: one commit with note + updated INDEX, success text with sha", async () => {
    const d = fakeDeps();
    const write = makeBrainWriter(d);
    const out = await write("knowledge/new.md", FM, "add note");
    expect(out).toMatch(/committed/i);
    expect(out).toContain("commit1");
    expect(d.committed).toHaveLength(1);
    expect(d.committed[0].files.map((f: any) => f.path)).toEqual(["knowledge/new.md", "INDEX.md"]);
    expect(d.committed[0].files[1].content).toContain("](knowledge/new.md)");
    expect(d.committed[0].parentCommitSha).toBe("head1");
  });

  it("no INDEX file in the commit when the path takes no line (ideas/)", async () => {
    const d = fakeDeps();
    const out = await makeBrainWriter(d)("ideas/apps/x.md", FM, "idea");
    expect(out).toMatch(/committed/i);
    expect(d.committed[0].files.map((f: any) => f.path)).toEqual(["ideas/apps/x.md"]);
  });

  it("refusals return text without touching git", async () => {
    const d = fakeDeps();
    const out = await makeBrainWriter(d)("tools/x.md", FM, "nope");
    expect(out).toMatch(/protected directory/);
    expect(d.committed).toHaveLength(0);
  });

  it("lost race: refetches head, rebuilds INDEX, retries, succeeds", async () => {
    const d = fakeDeps({ races: 1 });
    const out = await makeBrainWriter(d)("knowledge/new.md", FM, "add");
    expect(out).toMatch(/committed/i);
    expect(d.committed).toHaveLength(2);
    expect(d.committed[1].parentCommitSha).toBe("head2");
  });

  it("three lost races: gives up with retry-later text, never throws", async () => {
    const d = fakeDeps({ races: 3 });
    const out = await makeBrainWriter(d)("knowledge/new.md", FM, "add");
    expect(out).toMatch(/try again/i);
    expect(d.committed).toHaveLength(3);
  });

  it("unexpected errors degrade to text", async () => {
    const d = fakeDeps();
    d.gitdata.getHead = async () => { throw new Error("GitHub returned 500"); };
    const out = await makeBrainWriter(d)("knowledge/new.md", FM, "add");
    expect(out).toMatch(/could not|failed/i);
    expect(out).toContain("500");
  });

  it("refuses to write when the fetched INDEX is truncated, commits nothing", async () => {
    const d = fakeDeps();
    d.fetchFile = async (path: string) => {
      if (path === "INDEX.md") return "# INDEX\n\n## knowledge/ — facts\n" + TRUNCATION_NOTICE;
      throw new Error(`unexpected read: ${path}`);
    };
    const out = await makeBrainWriter(d)("knowledge/new.md", FM, "add");
    expect(out).toMatch(/too large/i);
    expect(d.committed).toHaveLength(0);
  });

  it("commits but says so when the INDEX section header is missing", async () => {
    const d = fakeDeps();
    const out = await makeBrainWriter(d)("devices/new-box.md", FM, "add device");
    expect(out).toMatch(/committed/i);
    expect(out).toContain('INDEX has no "## devices/" section');
    expect(d.committed[0].files.map((f: any) => f.path)).toEqual(["devices/new-box.md"]);
  });

  it("refuses a TODO.md replacement under half the current size", async () => {
    const d = fakeDeps({ todo: "x".repeat(100) });
    const out = await makeBrainWriter(d)("TODO.md", "y".repeat(49), "trim");
    expect(out).toMatch(/shrink TODO\.md/);
    expect(out).toContain("100");
    expect(out).toContain("49");
    expect(out).toMatch(/brain_append/);
    expect(d.committed).toHaveLength(0);
  });

  it("allows a TODO.md replacement at half the current size or more", async () => {
    const d = fakeDeps({ todo: "x".repeat(100) });
    const out = await makeBrainWriter(d)("TODO.md", "y".repeat(50), "reorganize");
    expect(out).toMatch(/committed/i);
    expect(d.committed).toHaveLength(1);
  });

  it("treats a missing TODO.md as creation — no guard", async () => {
    const d = fakeDeps();
    d.fetchFile = async (path: string) => {
      if (path === "INDEX.md") return INDEX;
      throw new BrainFileNotFound(`No such file in the brain: ${path}`);
    };
    const out = await makeBrainWriter(d)("TODO.md", "# TODO\n", "seed");
    expect(out).toMatch(/committed/i);
  });
});
