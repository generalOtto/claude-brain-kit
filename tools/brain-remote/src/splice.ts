export type SpliceResult =
  | { ok: true; content: string; at: number; length: number }
  | { ok: false; reason: string };

const isH2 = (line: string) => line.startsWith("## ");

export type SectionMatch = { ok: true; index: number } | { ok: false; reason: string };

// A caller's string matches a "## " heading when it equals the heading text
// (case-insensitive, leading #s optional) or is a prefix of it followed by a
// boundary: space, em/en dash, hyphen, colon, open paren, or end of text. So
// "Known dead weight" finds "## Known dead weight (pending Otto)" but "v1.2"
// does not find "## v1.2.1 …". Exact beats prefix; several prefix hits refuse.
const BOUNDARY = /^[\s—–\-:(]/;

export function findSection(lines: string[], section: string): SectionMatch {
  const want = section.trim().replace(/^#+\s*/, "").toLowerCase();
  const headings = lines
    .map((l, index) => ({ index, text: l.slice(3).trim(), h2: isH2(l) }))
    .filter((h) => h.h2);
  const names = headings.map((h) => `"${h.text}"`);
  const noMatch = (): SectionMatch => ({
    ok: false,
    reason: names.length
      ? `No section matching "${section}" — this file's sections are: ${names.join(", ")}. Retry with one of those, or omit section to append at the end of the file.`
      : `This file has no "## " sections — omit section to append at the end of the file.`,
  });
  if (!want) return noMatch();

  const exact = headings.find((h) => h.text.toLowerCase() === want);
  if (exact) return { ok: true, index: exact.index };

  const prefix = headings.filter((h) => {
    const t = h.text.toLowerCase();
    return t.startsWith(want) && (t.length === want.length || BOUNDARY.test(t.slice(want.length)));
  });
  if (prefix.length === 1) return { ok: true, index: prefix[0].index };
  if (prefix.length > 1) {
    return {
      ok: false,
      reason: `"${section}" matches ${prefix.length} sections: ${prefix.map((h) => `"${h.text}"`).join(", ")}. Retry with the full heading text.`,
    };
  }
  return noMatch();
}

// Appends `fragment` to `file`: at EOF, or (when `section` names a "## " heading,
// case-insensitively, prefix optional) at the end of that section. Exactly one
// blank line lands on each side of the fragment; the result keeps a trailing
// newline. Pure string surgery — validation happens in validate.ts before this.
export function spliceAppend(file: string, fragment: string, section?: string): SpliceResult {
  const frag = fragment.replace(/^\s*\n/, "").replace(/\s+$/, "");

  if (section === undefined) {
    const before = file.replace(/\s+$/, "");
    return { ok: true, content: `${before}\n\n${frag}\n`, at: before.length + 2, length: frag.length };
  }

  const lines = file.split("\n");
  const found = findSection(lines, section);
  if (!found.ok) return { ok: false, reason: found.reason };
  const header = found.index;

  let end = lines.length;
  for (let i = header + 1; i < lines.length; i++) {
    if (isH2(lines[i])) { end = i; break; }
  }
  let insertAt = end;
  while (insertAt > header + 1 && lines[insertAt - 1].trim() === "") insertAt--;

  const before = lines.slice(0, insertAt).join("\n");
  const after = lines.slice(end);
  const at = before.length + 2;
  if (after.length) {
    const content = `${before}\n\n${frag}\n\n${after.join("\n")}`;
    return { ok: true, content: content.endsWith("\n") ? content : `${content}\n`, at, length: frag.length };
  }
  return { ok: true, content: `${before}\n\n${frag}\n`, at, length: frag.length };
}
