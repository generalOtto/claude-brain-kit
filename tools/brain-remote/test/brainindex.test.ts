import { describe, expect, it } from "vitest";
import { updateIndex, indexFileFor, isIndexed, indexLineFor } from "../src/brainindex.js";

const INDEX = `# INDEX — the brain's catalog

intro text

## knowledge/ — dense durable facts & gotchas
- [Existing note](knowledge/existing.md) — old description
- [Another](knowledge/another.md) — words

## journal/ — what we did together
- [2026-01-05 — Example day](journal/2026-01-05-example-day.md) — example things
`;

const note = (name: string, desc: string, h1: string) =>
  `---\nname: ${name}\ndescription: "${desc}"\ntype: reference\n---\n\n# ${h1}\n\nbody\n`;

const updated = (r: ReturnType<typeof updateIndex>): string => {
  if (r.kind !== "updated") throw new Error(`expected updated, got ${r.kind}`);
  return r.content;
};

describe("updateIndex", () => {
  it("appends a new line at the end of the right section", () => {
    const out = updated(updateIndex(INDEX, "knowledge/new-note.md", note("new-note", "fresh fact", "New Note")));
    const lines = out.split("\n");
    const i = lines.findIndex((l) => l.includes("](knowledge/new-note.md)"));
    expect(lines[i]).toBe("- [New Note](knowledge/new-note.md) — fresh fact");
    expect(i).toBe(lines.findIndex((l) => l.includes("](knowledge/another.md)")) + 1);
  });

  it("replaces the existing line for the path in place", () => {
    const out = updated(updateIndex(INDEX, "knowledge/existing.md", note("existing", "NEW description", "Existing note")));
    expect(out).toContain("- [Existing note](knowledge/existing.md) — NEW description");
    expect(out).not.toContain("old description");
    expect(out.match(/existing\.md/g)!.length).toBe(1);
  });

  it("uses the H1 as title, frontmatter name as fallback", () => {
    const noH1 = `---\nname: fallback-name\ndescription: "d"\ntype: reference\n---\n\nbody without heading\n`;
    const out = updated(updateIndex(INDEX, "knowledge/x.md", noH1));
    expect(out).toContain("- [fallback-name](knowledge/x.md) — d");
  });

  it("returns unmapped for ideas/ and TODO.md", () => {
    expect(updateIndex(INDEX, "ideas/apps/x.md", note("x", "d", "X"))).toEqual({ kind: "unmapped" });
    expect(updateIndex(INDEX, "TODO.md", "# TODO\n")).toEqual({ kind: "unmapped" });
  });

  it("returns section-missing (naming the section) when the header is absent", () => {
    expect(updateIndex(INDEX, "devices/new-box.md", note("new-box", "d", "New Box")))
      .toEqual({ kind: "section-missing", section: "## devices/" });
  });

  it("appends into journal/ with the entry's own H1 (date-titled)", () => {
    const out = updated(updateIndex(INDEX, "journal/2026-08-17-thing.md", note("j", "the arc", "2026-08-17 — the thing")));
    expect(out).toContain("- [2026-08-17 — the thing](journal/2026-08-17-thing.md) — the arc");
  });

  it("strips surrounding quotes from the frontmatter description", () => {
    const out = updated(updateIndex(INDEX, "knowledge/q.md", note("q", "quoted desc", "Q")));
    expect(out).toContain("— quoted desc");
    expect(out).not.toContain('"quoted desc"');
  });
});

describe("indexFileFor / isIndexed / indexLineFor", () => {
  it("routes journal notes to the sub-index and everything else to the root", () => {
    expect(indexFileFor("journal/2026-09-10-x.md")).toBe("journal/INDEX.md");
    expect(indexFileFor("knowledge/x.md")).toBe("INDEX.md");
    expect(indexFileFor("TODO.md")).toBe("INDEX.md");
  });

  it("isIndexed follows the section map", () => {
    expect(isIndexed("knowledge/x.md")).toBe(true);
    expect(isIndexed("journal/x.md")).toBe(true);
    expect(isIndexed("ideas/apps/x.md")).toBe(false);
    expect(isIndexed("TODO.md")).toBe(false);
  });

  it("indexLineFor prefers the H1, then frontmatter name, then the path", () => {
    expect(indexLineFor("knowledge/a.md", note("a", "desc", "Title A"))).toBe("- [Title A](knowledge/a.md) — desc");
    expect(indexLineFor("knowledge/a.md", "---\nname: a\ndescription: d\ntype: reference\n---\nbody\n")).toBe("- [a](knowledge/a.md) — d");
    expect(indexLineFor("knowledge/a.md", "body only\n")).toBe("- [knowledge/a.md](knowledge/a.md) — ");
  });
});
