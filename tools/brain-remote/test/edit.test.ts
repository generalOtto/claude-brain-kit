import { describe, expect, it } from "vitest";
import { spliceEdit } from "../src/edit.js";

const FILE = "- **next:** 2026-09-14 · **last:** 2026-09-07\n- other line\n";

describe("spliceEdit", () => {
  it("replaces the single occurrence and leaves everything else byte-identical", () => {
    const r = spliceEdit(FILE, "**next:** 2026-09-14", "**next:** 2026-09-21");
    expect(r).toEqual({ ok: true, content: "- **next:** 2026-09-21 · **last:** 2026-09-07\n- other line\n", at: 2, length: 20 });
  });

  it("empty replace deletes the matched span", () => {
    const r = spliceEdit(FILE, "- other line\n", "");
    expect(r).toEqual({ ok: true, content: "- **next:** 2026-09-14 · **last:** 2026-09-07\n", at: 46, length: 0 });
  });

  it("at points at the start of the original match; length matches the replacement", () => {
    const r = spliceEdit(FILE, "**next:** 2026-09-14", "**next:** 2026-09-21");
    if (!r.ok) throw new Error(r.reason);
    expect(r.content.slice(r.at, r.at + r.length)).toBe("**next:** 2026-09-21");
  });

  it("refuses when the text is not found, telling the caller to copy it verbatim", () => {
    const r = spliceEdit(FILE, "next: 2026-09-14", "x");
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.reason).toMatch(/^Not found — /);
    if (!r.ok) expect(r.reason).toContain("brain_read");
  });

  it("refuses when the text occurs more than once, stating the count", () => {
    const r = spliceEdit("a b a b a\n", "a", "z");
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.reason).toBe("Found 3 times — include more surrounding text so it matches exactly once.");
  });

  it("matching is whitespace-exact", () => {
    const r = spliceEdit("line one\n", "line  one", "x");
    expect(r.ok).toBe(false);
  });

  it("is a plain substring match, not a regex", () => {
    const r = spliceEdit("cost (2026).\n", "(2026).", "(2027).");
    expect(r).toEqual({ ok: true, content: "cost (2027).\n", at: 5, length: 7 });
  });

  it("counts overlapping occurrences", () => {
    const r = spliceEdit("aaa", "aa", "z");
    expect(r).toEqual({ ok: false, reason: "Found 2 times — include more surrounding text so it matches exactly once." });
  });

  it("refuses a repetitive span that overlaps itself", () => {
    const r = spliceEdit("09-09-09\n", "09-09", "X");
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.reason).toMatch(/^Found 2 times/);
  });

  it("find equal to the whole file replaces everything", () => {
    expect(spliceEdit("whole\n", "whole\n", "new\n")).toEqual({ ok: true, content: "new\n", at: 0, length: 4 });
  });
});
