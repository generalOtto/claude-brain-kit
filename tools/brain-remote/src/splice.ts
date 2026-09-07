export type SpliceResult = { ok: true; content: string } | { ok: false; reason: string };

const isH2 = (line: string) => line.startsWith("## ");

// Appends `fragment` to `file`: at EOF, or (when `section` names a "## " heading,
// case-insensitively, prefix optional) at the end of that section. Exactly one
// blank line lands on each side of the fragment; the result keeps a trailing
// newline. Pure string surgery — validation happens in validate.ts before this.
export function spliceAppend(file: string, fragment: string, section?: string): SpliceResult {
  const frag = fragment.replace(/^\s*\n/, "").replace(/\s+$/, "");

  if (section === undefined) {
    return { ok: true, content: `${file.replace(/\s+$/, "")}\n\n${frag}\n` };
  }

  const lines = file.split("\n");
  const want = section.trim().replace(/^#+\s*/, "").toLowerCase();
  const header = lines.findIndex((l) => isH2(l) && l.slice(3).trim().toLowerCase() === want);
  if (header === -1) {
    const names = lines.filter(isH2).map((l) => `"${l.slice(3).trim()}"`);
    return {
      ok: false,
      reason: names.length
        ? `No section matching "${section}" — this file's sections are: ${names.join(", ")}. Retry with one of those, or omit section to append at the end of the file.`
        : `This file has no "## " sections — omit section to append at the end of the file.`,
    };
  }

  let end = lines.length;
  for (let i = header + 1; i < lines.length; i++) {
    if (isH2(lines[i])) { end = i; break; }
  }
  let insertAt = end;
  while (insertAt > header + 1 && lines[insertAt - 1].trim() === "") insertAt--;

  const before = lines.slice(0, insertAt).join("\n");
  const after = lines.slice(end);
  if (after.length) {
    const content = `${before}\n\n${frag}\n\n${after.join("\n")}`;
    return { ok: true, content: content.endsWith("\n") ? content : `${content}\n` };
  }
  return { ok: true, content: `${before}\n\n${frag}\n` };
}
