const MAX_CHARS = 100_000;
export const TRUNCATION_NOTICE = "\n\n[truncated — file continues beyond 100 KB]";
// Git database endpoints (git/blobs, git/trees, git/commits, git/refs) on private
// repos require this version or newer — verified empirically 2026-08-17 (403/404
// on 2022-11-28, 200 on 2026-03-10 with the same fine-grained PAT). The contents
// API behaves identically under the new version too, so both clients share it.
export const GITHUB_API_VERSION = "2026-03-10";

export const GITHUB_TIMEOUT_MS = 15_000;

// One fetch wrapper for both GitHub clients: enforces the outbound timeout and
// translates the abort (a DOMException, which is NOT instanceof Error — the
// error paths downstream would degrade to "unknown error") into a plain Error.
export async function githubFetch(
  fetchImpl: typeof fetch,
  url: string,
  init: RequestInit,
  what: string,
): Promise<Response> {
  try {
    return await fetchImpl(url, { ...init, signal: AbortSignal.timeout(GITHUB_TIMEOUT_MS) });
  } catch (err) {
    const name = (err as { name?: string } | null)?.name;
    if (name === "TimeoutError" || name === "AbortError") {
      throw new Error(`GitHub timed out after 15s on ${what}`);
    }
    throw err;
  }
}

export class BrainFileNotFound extends Error {}

export type BrainFetcher = (path: string, ref?: string) => Promise<string>;

export function makeBrainFetcher(opts: {
  token: string;
  repo: string; // the brain repo this server fronts, as "owner/name"
  apiBase?: string;
  fetchImpl?: typeof fetch;
  truncate?: boolean;
}): BrainFetcher {
  const { token, repo, apiBase = "https://api.github.com", fetchImpl = fetch, truncate = true } = opts;
  return async (path: string, ref = "main") => {
    const clean = path.replace(/^\/+/, "");
    const res = await githubFetch(
      fetchImpl,
      `${apiBase}/repos/${repo}/contents/${encodeURI(clean)}?ref=${ref}`,
      {
        headers: {
          accept: "application/vnd.github.raw+json",
          authorization: `Bearer ${token}`,
          "x-github-api-version": GITHUB_API_VERSION,
          "user-agent": "voice-brain-mcp",
        },
      },
      `GET ${clean}`,
    );
    if (res.status === 404) throw new BrainFileNotFound(`No such file in the brain: ${clean}`);
    if (!res.ok) throw new Error(`GitHub returned ${res.status} for ${clean}`);
    const text = await res.text();
    if (!truncate) return text;
    return text.length > MAX_CHARS ? text.slice(0, MAX_CHARS) + TRUNCATION_NOTICE : text;
  };
}
