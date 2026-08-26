import { describe, expect, it } from "vitest";
import { BrainFileNotFound } from "../src/gh.js";
import { brainIndex, brainRead } from "../src/tools.js";

const fetcherOf = (files: Record<string, string>) => async (path: string) => {
  if (path in files) return files[path];
  throw new BrainFileNotFound(`No such file in the brain: ${path}`);
};

describe("brainIndex", () => {
  it("returns one text part with both files under separators", async () => {
    const r = await brainIndex(fetcherOf({ "CLAUDE.md": "BOOT", "INDEX.md": "CATALOG" }));
    expect(r.content).toHaveLength(1);
    expect(r.content[0].type).toBe("text");
    expect(r.content[0].text).toContain("== CLAUDE.md ==\n\nBOOT");
    expect(r.content[0].text).toContain("== INDEX.md ==\n\nCATALOG");
  });

  it("degrades to a text error, never throws", async () => {
    const r = await brainIndex(async () => { throw new Error("ECONNREFUSED"); });
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
