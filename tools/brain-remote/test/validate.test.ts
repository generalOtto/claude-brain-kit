import { describe, expect, it } from "vitest";
import { validateWrite, validateAppend, validateEdit, secretInWindow } from "../src/validate.js";

const FM = "---\nname: x\ndescription: y\ntype: reference\n---\n\n# X\nbody\n";

describe("validateWrite", () => {
  it("accepts a frontmattered note in an allowlisted folder", () => {
    expect(validateWrite("knowledge/some-note.md", FM)).toEqual({ ok: true, clean: "knowledge/some-note.md" });
  });

  it("strips leading slashes", () => {
    expect(validateWrite("/journal/2026-08-17-x.md", FM)).toEqual({ ok: true, clean: "journal/2026-08-17-x.md" });
  });

  it("accepts TODO.md without frontmatter", () => {
    expect(validateWrite("TODO.md", "# TODO\n- item\n").ok).toBe(true);
  });

  it("refuses unknown roots", () => {
    const r = validateWrite("archive/x.md", FM);
    expect(r.ok).toBe(false);
    expect((r as any).reason).toMatch(/not writable/i);
  });

  it("refuses non-markdown", () => {
    expect(validateWrite("knowledge/script.txt", "x").ok).toBe(false);
  });

  it.each([
    "tools/evil.md", ".github/workflows/x.md", "knowledge/run.sh",
    ".gitignore", "projects/projects.base", "CLAUDE.md",
  ])("denylist blocks %s", (p) => {
    expect(validateWrite(p, FM).ok).toBe(false);
  });

  it("refuses path traversal segments", () => {
    expect(validateWrite("knowledge/../tools/x.md", FM).ok).toBe(false);
  });

  it("requires frontmatter in note folders", () => {
    const r = validateWrite("knowledge/bare.md", "# no frontmatter\n");
    expect(r.ok).toBe(false);
    expect((r as any).reason).toMatch(/frontmatter/i);
  });

  it.each([
    'token = "ghp_' + "A".repeat(30) + '"',
    "github_pat_" + "A1_".repeat(10),
    "key: AKIAIOSFODNN7EXAMPLE",
    "-----BEGIN RSA PRIVATE KEY-----",
    'api_key = "' + "f0e1d2c3".repeat(4) + '"',
  ])("refuses secret-shaped content: %s", (s) => {
    const r = validateWrite("knowledge/leak.md", FM + s);
    expect(r.ok).toBe(false);
    expect((r as any).reason).toMatch(/pointer/i);
  });

  it("refuses content over 100k chars", () => {
    expect(validateWrite("knowledge/big.md", FM + "a".repeat(100_001)).ok).toBe(false);
  });

  it.each([
    "knowledge/my note.md",
    "knowledge/note(2).md",
    "knowledge/..\\evil.md",
    "knowledge/50%.md",
  ])("refuses paths with characters outside the safe set: %s", (p) => {
    const r = validateWrite(p, FM);
    expect(r.ok).toBe(false);
    expect((r as any).reason).toMatch(/characters outside the safe set/i);
  });

  it("still accepts ordinary valid paths after the charset gate", () => {
    expect(validateWrite("knowledge/some-note.md", FM).ok).toBe(true);
    expect(validateWrite("journal/2026-08-17-x.md", FM).ok).toBe(true);
    expect(validateWrite("TODO.md", "# TODO\n- item\n").ok).toBe(true);
  });

  it.each(["INDEX.md", "journal/INDEX.md", "knowledge/INDEX.md"])(
    "refuses %s — INDEX.md is a catalog the server maintains, at any depth",
    (p) => {
      const r = validateWrite(p, FM);
      expect(r.ok).toBe(false);
      if (!r.ok) expect(r.reason).toMatch(/catalog the server maintains/i);
    },
  );

  it("still accepts a note that merely contains INDEX in its name", () => {
    expect(validateWrite("knowledge/index-notes.md", FM).ok).toBe(true);
  });
});

describe("path charset tightening (v1.2)", () => {
  it("rejects doubled slashes", () => {
    const r = validateWrite("knowledge//x.md", FM);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.reason).toMatch(/empty or "\." segments/);
  });

  it("rejects . segments", () => {
    expect(validateWrite("knowledge/./x.md", FM).ok).toBe(false);
  });

  it("still accepts normal paths after tightening", () => {
    expect(validateWrite("knowledge/x.md", FM).ok).toBe(true);
  });
});

describe("validateAppend", () => {
  it("accepts a fragment without frontmatter", () => {
    expect(validateAppend("TODO.md", "### New item\n- **what:** x", "Active"))
      .toEqual({ ok: true, clean: "TODO.md" });
  });

  it("applies the same path gate as write", () => {
    const r = validateAppend("tools/x.md", "text", undefined);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.reason).toMatch(/protected directory/);
  });

  it("refuses empty and whitespace-only fragments", () => {
    const r = validateAppend("TODO.md", "   \n\n", undefined);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.reason).toMatch(/empty/i);
  });

  it("refuses secret-shaped fragments", () => {
    expect(validateAppend("TODO.md", "token ghp_" + "a".repeat(30), undefined).ok).toBe(false);
  });

  it("refuses h1/h2 headings in the fragment when a section is given", () => {
    expect(validateAppend("TODO.md", "## Sneaky\ntext", "Active").ok).toBe(false);
    expect(validateAppend("TODO.md", "# Sneaky\ntext", "Active").ok).toBe(false);
  });

  it("allows h3 headings in a section append (TODO items are h3)", () => {
    expect(validateAppend("TODO.md", "### Item\n- x", "Active").ok).toBe(true);
  });

  it("allows h2 headings in a plain EOF append", () => {
    expect(validateAppend("journal/2026-08-18-x.md", "## Later\ntext", undefined).ok).toBe(true);
  });

  it("refuses journal/INDEX.md — it is a catalog the server maintains", () => {
    const r = validateAppend("journal/INDEX.md", "x");
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.reason).toMatch(/catalog the server maintains/i);
  });

  it("refuses indented and tab-separated h2 headings when a section is given", () => {
    expect(validateAppend("TODO.md", "  ## Sneaky\ntext", "Active").ok).toBe(false);
    expect(validateAppend("TODO.md", "##\tSneaky\ntext", "Active").ok).toBe(false);
  });

  it("still allows indented h3 and 4-space-indented (code block) h2", () => {
    expect(validateAppend("TODO.md", "   ### Item\n- x", "Active").ok).toBe(true);
    expect(validateAppend("TODO.md", "    ## code sample\n", "Active").ok).toBe(true);
  });
});

describe("validateEdit", () => {
  it("accepts an allowed path with a non-empty find", () => {
    expect(validateEdit("TODO.md", "old", "new")).toEqual({ ok: true, clean: "TODO.md" });
    expect(validateEdit("/knowledge/x.md", "old", "")).toEqual({ ok: true, clean: "knowledge/x.md" });
  });

  it("refuses an empty find", () => {
    const r = validateEdit("TODO.md", "", "new");
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.reason).toContain("empty");
  });

  it("applies the path gate — INDEX.md and CLAUDE.md are not editable", () => {
    expect(validateEdit("INDEX.md", "a", "b").ok).toBe(false);
    expect(validateEdit("CLAUDE.md", "a", "b").ok).toBe(false);
    expect(validateEdit("tools/x.md", "a", "b").ok).toBe(false);
  });

  it("scans the replacement for secrets", () => {
    const r = validateEdit("knowledge/x.md", "a", "token = ghp_" + "A".repeat(30));
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.reason).toContain("GitHub token");
  });

  it("refuses journal/INDEX.md — it is a catalog the server maintains", () => {
    const r = validateEdit("journal/INDEX.md", "a", "b");
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.reason).toMatch(/catalog the server maintains/i);
  });
});

describe("secretInWindow", () => {
  const SECRET = "ghp_" + "B".repeat(25); // 29 chars, matches the GitHub-token pattern

  it("does not report a secret entirely outside the 80-char margin", () => {
    const content = SECRET + "z".repeat(300); // secret spans [0, 29)
    // window = slice(max(0, 310-80), 310+0+80) = slice(230, 390) — starts well past the secret
    expect(secretInWindow(content, 310, 0)).toBeNull();
  });

  it("reports a secret that overlaps the 80-char margin", () => {
    const content = "z".repeat(50) + SECRET + "z".repeat(300); // secret spans [50, 79)
    // window = slice(max(0, 100-80), 100+0+80) = slice(20, 180) — fully contains the secret
    const leak = secretInWindow(content, 100, 0);
    expect(leak).not.toBeNull();
    expect(leak).toMatch(/GitHub token/);
  });

  it("covers the inserted span itself, not just its margins", () => {
    const content = "z".repeat(50) + SECRET + "z".repeat(50);
    const leak = secretInWindow(content, 50, SECRET.length);
    expect(leak).not.toBeNull();
  });
});
