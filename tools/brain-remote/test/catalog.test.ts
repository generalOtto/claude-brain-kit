import { describe, expect, it } from "vitest";
import { compactCatalog, DESC_CAP } from "../src/catalog.js";

const long = "word ".repeat(60).trim(); // 299 chars
const entry = (desc: string) => `- [Some note](knowledge/some-note.md) — ${desc}`;

describe("compactCatalog", () => {
  it("leaves short descriptions untouched", () => {
    const line = entry("a short description");
    expect(compactCatalog(line)).toBe(line);
  });

  it("leaves a description of exactly the cap untouched, no ellipsis", () => {
    const desc = "x".repeat(DESC_CAP);
    expect(compactCatalog(entry(desc))).toBe(entry(desc));
  });

  it("cuts a long description at a word boundary and appends an ellipsis", () => {
    const out = compactCatalog(entry(long));
    const desc = out.slice("- [Some note](knowledge/some-note.md) — ".length);
    expect(desc.endsWith("…")).toBe(true);
    expect(desc.length).toBeLessThanOrEqual(DESC_CAP + 1);
    expect(desc).toBe("word ".repeat(24).trim() + "…"); // 24 words = 119 chars, next word would cross 120
  });

  it("does not leave trailing punctuation before the ellipsis", () => {
    const desc = "alpha beta gamma, " + "delta ".repeat(30);
    const out = compactCatalog(entry(desc));
    expect(out).not.toMatch(/[,;:—–-] …$/);
    expect(out).not.toMatch(/[,;:—–-]…$/);
  });

  it("passes headings, prose and pointer lines through untouched", () => {
    const text = [
      "# INDEX — the brain's catalog",
      "",
      "Skim this to find the right note. " + "x".repeat(200),
      "## knowledge/ — dense durable facts & gotchas " + "y".repeat(200),
      "- `archive/transcripts/` — scrubbed export " + "z".repeat(200),
      entry(long),
    ].join("\n");
    const out = compactCatalog(text).split("\n");
    expect(out.slice(0, 5)).toEqual(text.split("\n").slice(0, 5));
    expect(out[5].endsWith("…")).toBe(true);
  });

  it("preserves line count and a trailing newline", () => {
    const text = `${entry(long)}\n${entry("short")}\n`;
    const out = compactCatalog(text);
    expect(out.split("\n")).toHaveLength(3);
    expect(out.endsWith("\n")).toBe(true);
  });

  it("hard-cuts at 120 chars when description is one unbroken token", () => {
    const token = "x".repeat(200); // no spaces
    const out = compactCatalog(entry(token));
    const desc = out.slice("- [Some note](knowledge/some-note.md) — ".length);
    expect(desc).toBe("x".repeat(120) + "…");
  });

  it("cuts at early space when it's the only space in the window", () => {
    const token = "short " + "x".repeat(150);
    const out = compactCatalog(entry(token));
    const desc = out.slice("- [Some note](knowledge/some-note.md) — ".length);
    expect(desc).toBe("short…");
  });
});
