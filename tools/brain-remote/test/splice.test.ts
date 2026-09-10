import { describe, expect, it } from "vitest";
import { spliceAppend, findSection } from "../src/splice.js";

const FILE = `---
name: todo
---

# TODO

## Active

### Old item
- body

## Muted

*(nothing)*
`;

describe("spliceAppend", () => {
  it("appends at EOF with exactly one blank line seam", () => {
    expect(spliceAppend("# Note\n\nbody\n", "new line"))
      .toEqual({ ok: true, content: "# Note\n\nbody\n\nnew line\n", at: 14, length: 8 });
  });

  it("inserts at the end of a named section, before the next ## heading", () => {
    const r = spliceAppend(FILE, "### New item\n- x", "Active");
    if (!r.ok) throw new Error(r.reason);
    expect(r.content).toContain("- body\n\n### New item\n- x\n\n## Muted");
  });

  it("at/length point exactly at the inserted fragment for an EOF append", () => {
    const r = spliceAppend("# Note\n\nbody\n", "new line");
    if (!r.ok) throw new Error(r.reason);
    expect(r.content.slice(r.at, r.at + r.length)).toBe("new line");
  });

  it("at/length point exactly at the inserted fragment for a section append", () => {
    const r = spliceAppend(FILE, "### New item\n- x", "Active");
    if (!r.ok) throw new Error(r.reason);
    expect(r.content.slice(r.at, r.at + r.length)).toBe("### New item\n- x");
  });

  it("matches sections case-insensitively, ## prefix optional", () => {
    expect(spliceAppend(FILE, "x", "## aCtIvE").ok).toBe(true);
    expect(spliceAppend(FILE, "x", "muted").ok).toBe(true);
  });

  it("first match wins when headings repeat", () => {
    const twice = "## A\n\none\n\n## B\n\n## A\n\ntwo\n";
    const r = spliceAppend(twice, "frag", "A");
    if (!r.ok) throw new Error(r.reason);
    expect(r.content.indexOf("frag")).toBeLessThan(r.content.indexOf("## B"));
  });

  it("appends into a section that ends the file", () => {
    expect(spliceAppend("# T\n\n## Last\n\nitem\n", "frag", "Last"))
      .toEqual({ ok: true, content: "# T\n\n## Last\n\nitem\n\nfrag\n", at: 20, length: 4 });
  });

  it("appends into an empty section", () => {
    expect(spliceAppend("## A\n## B\n", "frag", "A"))
      .toEqual({ ok: true, content: "## A\n\nfrag\n\n## B\n", at: 6, length: 4 });
  });

  it("missing section refuses and lists the real headings", () => {
    const r = spliceAppend(FILE, "x", "Done log");
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.reason).toContain('"Active"');
    expect(r.reason).toContain('"Muted"');
    expect(r.reason).toMatch(/omit section/i);
  });

  it("file with no ## sections at all gives the omit-section hint", () => {
    const r = spliceAppend("just text\n", "x", "Active");
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.reason).toMatch(/no "## " sections/);
  });

  it("normalizes messy fragment edges to single blank lines", () => {
    expect(spliceAppend("a\n", "\n\nfrag\n\n\n"))
      .toEqual({ ok: true, content: "a\n\nfrag\n", at: 3, length: 4 });
  });

  it("collapses a multi-blank-line section tail to one seam line", () => {
    const r = spliceAppend("## A\n\nitem\n\n\n\n## B\n", "frag", "A");
    if (!r.ok) throw new Error(r.reason);
    expect(r.content).toBe("## A\n\nitem\n\nfrag\n\n## B\n");
  });

  it("adds the trailing newline when the source file lacks one", () => {
    expect(spliceAppend("## A\nitem\n## B", "frag", "A"))
      .toEqual({ ok: true, content: "## A\nitem\n\nfrag\n\n## B\n", at: 11, length: 4 });
  });
});

const HEADINGS = `# Note

## Known dead weight (pending Otto)
- a

## v1.2.1 — voice etiquette (2026-08-18)
- b

## v1.2 — brain_append
- c

## Active
- d

## Active items — later
- e
`.split("\n");

describe("findSection", () => {
  const idx = (s: string) => { const r = findSection(HEADINGS, s); if (!r.ok) throw new Error(r.reason); return HEADINGS[r.index]; };

  it("exact match still works, case-insensitive, ## optional", () => {
    expect(idx("active")).toBe("## Active");
    expect(idx("## Active")).toBe("## Active");
  });

  it("matches a heading that continues with a parenthetical", () => {
    expect(idx("Known dead weight")).toBe("## Known dead weight (pending Otto)");
  });

  it("matches a heading that continues with an em-dash", () => {
    expect(idx("v1.2.1")).toBe("## v1.2.1 — voice etiquette (2026-08-18)");
  });

  it("does not treat a shorter version number as a prefix of a longer one", () => {
    expect(idx("v1.2")).toBe("## v1.2 — brain_append");
  });

  it("exact match wins over prefix matches", () => {
    expect(idx("Active")).toBe("## Active");
  });

  it("refuses when several headings share the prefix, listing them", () => {
    const lines = ["## Notes — 2026", "## Notes — 2025", "body"];
    const r = findSection(lines, "Notes");
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.reason).toContain("2 sections");
      expect(r.reason).toContain('"Notes — 2026"');
      expect(r.reason).toContain('"Notes — 2025"');
    }
  });

  it("matches a heading that continues with an en-dash (U+2013)", () => {
    const lines = ["## Notes – 2026", "x"];
    const r = findSection(lines, "Notes");
    expect(r.ok).toBe(true);
    if (r.ok) expect(lines[r.index]).toBe("## Notes – 2026");
  });

  it("does not match mid-word prefixes", () => {
    const r = findSection(["## Activewear", "x"], "Active");
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.reason).toContain('No section matching "Active"');
  });

  it("empty section string is a no-match, not a match-everything", () => {
    const r = findSection(HEADINGS, "   ");
    expect(r.ok).toBe(false);
  });
});

describe("spliceAppend with prefix sections", () => {
  it("appends into a prefix-matched section", () => {
    const r = spliceAppend(HEADINGS.join("\n"), "- new", "Known dead weight");
    if (!r.ok) throw new Error(r.reason);
    expect(r.content).toContain("- a\n\n- new\n\n## v1.2.1");
  });
});
