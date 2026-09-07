import { BrainFileNotFound, type BrainFetcher } from "./gh.js";

export type TextResult = { content: [{ type: "text"; text: string }] };
const text = (t: string): TextResult => ({ content: [{ type: "text", text: t }] });

export async function brainIndex(fetchFile: BrainFetcher): Promise<TextResult> {
  try {
    const [claudeMd, indexMd] = await Promise.all([
      fetchFile("CLAUDE.md"),
      fetchFile("INDEX.md"),
    ]);
    return text(`== CLAUDE.md ==\n\n${claudeMd}\n\n== INDEX.md ==\n\n${indexMd}`);
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
