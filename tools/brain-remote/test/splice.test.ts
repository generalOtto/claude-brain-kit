import { describe, expect, it } from "vitest";
import { spliceAppend } from "../src/splice.js";

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
      .toEqual({ ok: true, content: "# Note\n\nbody\n\nnew line\n" });
  });

  it("inserts at the end of a named section, before the next ## heading", () => {
    const r = spliceAppend(FILE, "### New item\n- x", "Active");
    if (!r.ok) throw new Error(r.reason);
    expect(r.content).toContain("- body\n\n### New item\n- x\n\n## Muted");
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
      .toEqual({ ok: true, content: "# T\n\n## Last\n\nitem\n\nfrag\n" });
  });

  it("appends into an empty section", () => {
    expect(spliceAppend("## A\n## B\n", "frag", "A"))
      .toEqual({ ok: true, content: "## A\n\nfrag\n\n## B\n" });
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
      .toEqual({ ok: true, content: "a\n\nfrag\n" });
  });

  it("collapses a multi-blank-line section tail to one seam line", () => {
    const r = spliceAppend("## A\n\nitem\n\n\n\n## B\n", "frag", "A");
    if (!r.ok) throw new Error(r.reason);
    expect(r.content).toBe("## A\n\nitem\n\nfrag\n\n## B\n");
  });

  it("adds the trailing newline when the source file lacks one", () => {
    expect(spliceAppend("## A\nitem\n## B", "frag", "A"))
      .toEqual({ ok: true, content: "## A\nitem\n\nfrag\n\n## B\n" });
  });
});
