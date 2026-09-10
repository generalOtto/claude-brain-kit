export const DESC_CAP = 120;

// A catalog entry: "- [title](path) — description". Anything else (headings,
// prose, the archive pointer line) is not an entry and passes through as-is.
const ENTRY = /^(- \[[^\]]*\]\([^)]*\) — )(.*)$/;
const MIN_WORD_CUT = 60; // never cut so early that the description loses its meaning

// Cap every entry's description at DESC_CAP chars on a word boundary. The INDEX
// diet trims at the source; this is the safety net that keeps a long line from
// ever creeping back into every session's brain_index result.
export function compactCatalog(index: string): string {
  return index
    .split("\n")
    .map((line) => {
      const m = line.match(ENTRY);
      if (!m) return line;
      const [, head, desc] = m;
      if (desc.length <= DESC_CAP) return line;
      let cut = desc.slice(0, DESC_CAP);
      const space = cut.lastIndexOf(" ");
      if (space >= MIN_WORD_CUT) cut = cut.slice(0, space);
      cut = cut.replace(/[\s,;:—–-]+$/, "");
      return `${head}${cut}…`;
    })
    .join("\n");
}
