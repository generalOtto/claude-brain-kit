const SECTION_PREFIX: Record<string, string> = {
  "identity/": "## identity/",
  "projects/": "## projects/",
  "devices/": "## devices/",
  "knowledge/": "## knowledge/",
  "infrastructure/": "## infrastructure/",
  "playbooks/": "## playbooks/",
  "designs/": "## designs/",
  "conventions/": "## conventions/",
  "pointers/": "## pointers/",
  "journal/": "## journal/",
};

function frontmatterField(content: string, field: string): string | null {
  const fm = content.match(/^---\n([\s\S]*?)\n---/);
  if (!fm) return null;
  const m = fm[1].match(new RegExp(`^${field}:\\s*(.+)$`, "m"));
  if (!m) return null;
  return m[1].trim().replace(/^["']|["']$/g, "");
}

export type IndexUpdate =
  | { kind: "updated"; content: string }
  | { kind: "unmapped" }
  | { kind: "section-missing"; section: string };

export function updateIndex(
  indexContent: string,
  notePath: string,
  noteContent: string,
): IndexUpdate {
  const folder = Object.keys(SECTION_PREFIX).find((f) => notePath.startsWith(f));
  if (!folder) return { kind: "unmapped" }; // ideas/, TODO.md, anything unmapped: no INDEX line by design

  const h1 = noteContent.match(/^# (.+)$/m)?.[1].trim();
  const title = h1 ?? frontmatterField(noteContent, "name") ?? notePath;
  const desc = frontmatterField(noteContent, "description") ?? "";
  const newLine = `- [${title}](${notePath}) — ${desc}`;

  const lines = indexContent.split("\n");
  const existing = lines.findIndex((l) => l.includes(`](${notePath})`));
  if (existing !== -1) {
    lines[existing] = newLine;
    return { kind: "updated", content: lines.join("\n") };
  }

  const header = lines.findIndex((l) => l.startsWith(SECTION_PREFIX[folder]));
  if (header === -1) return { kind: "section-missing", section: SECTION_PREFIX[folder] };

  let end = lines.length;
  for (let i = header + 1; i < lines.length; i++) {
    if (lines[i].startsWith("## ")) { end = i; break; }
  }
  let insertAt = header + 1;
  for (let i = header + 1; i < end; i++) {
    if (lines[i].startsWith("- [")) insertAt = i + 1;
  }
  lines.splice(insertAt, 0, newLine);
  return { kind: "updated", content: lines.join("\n") };
}
