import { BrainFileNotFound, type BrainFetcher } from "./gh.js";
import { compactCatalog } from "./catalog.js";

export type TextResult = { content: [{ type: "text"; text: string }] };
const text = (t: string): TextResult => ({ content: [{ type: "text", text: t }] });

export const BOOTLOADER_OMITTED =
  "Bootloader (CLAUDE.md) omitted — it is already in your context on this surface; " +
  "pass bootloader: true if it is not.";

export async function brainIndex(
  fetchFile: BrainFetcher,
  opts: { bootloader: boolean },
): Promise<TextResult> {
  try {
    if (!opts.bootloader) {
      const indexMd = await fetchFile("INDEX.md");
      return text(`${BOOTLOADER_OMITTED}\n\n== INDEX.md ==\n\n${compactCatalog(indexMd)}`);
    }
    const [claudeMd, indexMd] = await Promise.all([
      fetchFile("CLAUDE.md"),
      fetchFile("INDEX.md"),
    ]);
    return text(`== CLAUDE.md ==\n\n${claudeMd}\n\n== INDEX.md ==\n\n${compactCatalog(indexMd)}`);
  } catch (err) {
    return text(errorText(err));
  }
}

export async function brainRead(fetchFile: BrainFetcher, path: string): Promise<TextResult> {
  try {
    return text(await fetchFile(path));
  } catch (err) {
    return text(errorText(err));
  }
}

function errorText(err: unknown): string {
  if (err instanceof BrainFileNotFound) {
    return `${err.message} — check the path against INDEX.md (via brain_index).`;
  }
  const detail = err instanceof Error ? err.message : "unknown error";
  return `The brain could not be reached right now (${detail}). Try again, or mention it so it can be looked into from a text session.`;
}
