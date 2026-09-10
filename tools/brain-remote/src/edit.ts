export type EditResult = { ok: true; content: string } | { ok: false; reason: string };

// Exact, whitespace-sensitive, plain-substring find/replace that only proceeds
// when `find` occurs exactly once. Pure string surgery — path/secret gates run
// in validate.ts before this; size gates run in the flow after.
export function spliceEdit(file: string, find: string, replace: string): EditResult {
  let count = 0;
  let from = 0;
  for (;;) {
    const i = file.indexOf(find, from);
    if (i === -1) break;
    count++;
    from = i + find.length;
  }
  if (count === 0) {
    return {
      ok: false,
      reason: "Not found — the exact text does not occur in the file. brain_read it and copy the text verbatim, including whitespace and punctuation.",
    };
  }
  if (count > 1) {
    return { ok: false, reason: `Found ${count} times — include more surrounding text so it matches exactly once.` };
  }
  const i = file.indexOf(find);
  return { ok: true, content: file.slice(0, i) + replace + file.slice(i + find.length) };
}
