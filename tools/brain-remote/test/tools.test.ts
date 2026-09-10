import { describe, expect, it } from "vitest";
import { BrainFileNotFound } from "../src/gh.js";
import { brainIndex, brainRead } from "../src/tools.js";

const fetcherOf = (files: Record<string, string>) => async (path: string) => {
  if (path in files) return files[path];
  throw new BrainFileNotFound(`No such file in the brain: ${path}`);
};

describe("brainIndex", () => {
  const files = {
    "CLAUDE.md": "BOOT",
    "INDEX.md": "# INDEX\n\n## knowledge/\n- [N](knowledge/n.md) — " + "word ".repeat(60).trim() + "\n",
  };

  it("bootloader: true returns both files under separators, catalog compacted", async () => {
    const r = await brainIndex(fetcherOf(files), { bootloader: true });
    expect(r.content).toHaveLength(1);
    expect(r.content[0].type).toBe("text");
    expect(r.content[0].text).toContain("== CLAUDE.md ==\n\nBOOT");
    expect(r.content[0].text).toContain("== INDEX.md ==\n\n# INDEX");
    expect(r.content[0].text).toContain("…");
    expect(r.content[0].text).not.toContain("word ".repeat(30));
  });

  it("bootloader: false returns the catalog only, with the omitted-bootloader note", async () => {
    const r = await brainIndex(fetcherOf(files), { bootloader: false });
    expect(r.content[0].text).not.toContain("BOOT");
    expect(r.content[0].text).not.toContain("== CLAUDE.md ==");
    expect(r.content[0].text).toMatch(/^Bootloader \(CLAUDE\.md\) omitted/);
    expect(r.content[0].text).toContain("pass bootloader: true");
    expect(r.content[0].text).toContain("== INDEX.md ==\n\n# INDEX");
  });

  it("bootloader: false never fetches CLAUDE.md", async () => {
    const seen: string[] = [];
    const f = async (p: string) => { seen.push(p); return files[p as keyof typeof files]; };
    await brainIndex(f, { bootloader: false });
    expect(seen).toEqual(["INDEX.md"]);
  });

  it("degrades to a text error, never throws", async () => {
    const r = await brainIndex(async () => { throw new Error("ECONNREFUSED"); }, { bootloader: true });
    expect(r.content[0].type).toBe("text");
    expect(r.content[0].text).toMatch(/could not be reached/);
  });
});

describe("brainRead", () => {
  it("returns the file body as one text part", async () => {
    const r = await brainRead(fetcherOf({ "identity/about-me.md": "ME" }), "identity/about-me.md");
    expect(r.content).toEqual([{ type: "text", text: "ME" }]);
  });

  it("turns not-found into helpful text, never throws", async () => {
    const r = await brainRead(fetcherOf({}), "ghost.md");
    expect(r.content[0].text).toContain("No such file in the brain: ghost.md");
    expect(r.content[0].text).toContain("INDEX.md");
  });
});
