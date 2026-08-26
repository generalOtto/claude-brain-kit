import { describe, expect, it } from "vitest";
import { BrainFileNotFound, GITHUB_API_VERSION, makeBrainFetcher } from "../src/gh.js";

const REPO = "octocat/second-brain";

const fakeFetch = (status: number, body: string) => {
  const calls: { url: string; headers: Record<string, string> }[] = [];
  const impl = (async (url: any, init: any) => {
    calls.push({ url: String(url), headers: init.headers });
    return new Response(body, { status });
  }) as typeof fetch;
  return { impl, calls };
};

describe("makeBrainFetcher", () => {
  it("requests the raw media type from the configured repo/ref with auth", async () => {
    const { impl, calls } = fakeFetch(200, "# hello");
    const fetchFile = makeBrainFetcher({ token: "tkn", repo: REPO, fetchImpl: impl });
    expect(await fetchFile("INDEX.md")).toBe("# hello");
    expect(calls[0].url).toBe(
      `https://api.github.com/repos/${REPO}/contents/INDEX.md?ref=main`,
    );
    expect(calls[0].headers["accept"]).toBe("application/vnd.github.raw+json");
    expect(calls[0].headers["authorization"]).toBe("Bearer tkn");
    expect(calls[0].headers["x-github-api-version"]).toBe(GITHUB_API_VERSION);
  });

  it("strips leading slashes and URL-encodes the path", async () => {
    const { impl, calls } = fakeFetch(200, "x");
    await makeBrainFetcher({ token: "t", repo: REPO, fetchImpl: impl })("/a b/c.md");
    expect(calls[0].url).toContain("/contents/a%20b/c.md?ref=main");
  });

  it("throws BrainFileNotFound on 404", async () => {
    const { impl } = fakeFetch(404, "");
    await expect(makeBrainFetcher({ token: "t", repo: REPO, fetchImpl: impl })("nope.md"))
      .rejects.toBeInstanceOf(BrainFileNotFound);
  });

  it("throws a generic error (no token) on other failures", async () => {
    const { impl } = fakeFetch(500, "boom");
    await expect(makeBrainFetcher({ token: "sekret", repo: REPO, fetchImpl: impl })("x.md"))
      .rejects.toThrow(/GitHub returned 500/);
  });

  it("truncates at 100k chars with the notice", async () => {
    const { impl } = fakeFetch(200, "a".repeat(150_000));
    const out = await makeBrainFetcher({ token: "t", repo: REPO, fetchImpl: impl })("big.md");
    expect(out.length).toBe(100_000 + "\n\n[truncated — file continues beyond 100 KB]".length);
    expect(out.endsWith("[truncated — file continues beyond 100 KB]")).toBe(true);
  });

  it("fetches at an explicit ref when given", async () => {
    const { impl, calls } = fakeFetch(200, "x");
    await makeBrainFetcher({ token: "t", repo: REPO, fetchImpl: impl })("INDEX.md", "abc123");
    expect(calls[0].url).toContain("?ref=abc123");
  });

  it("with truncate: false, returns content over 100k chars intact", async () => {
    const { impl } = fakeFetch(200, "a".repeat(150_000));
    const out = await makeBrainFetcher({ token: "t", repo: REPO, fetchImpl: impl, truncate: false })("big.md");
    expect(out.length).toBe(150_000);
    expect(out.endsWith("[truncated — file continues beyond 100 KB]")).toBe(false);
  });

  it("passes an abort signal on every request", async () => {
    const inits: any[] = [];
    const impl = (async (_url: any, init: any) => { inits.push(init); return new Response("x", { status: 200 }); }) as typeof fetch;
    await makeBrainFetcher({ token: "t", repo: REPO, fetchImpl: impl })("x.md");
    expect(inits[0].signal).toBeInstanceOf(AbortSignal);
  });

  it("translates a timeout DOMException into a friendly Error", async () => {
    const impl = (async () => { throw new DOMException("The operation timed out", "TimeoutError"); }) as typeof fetch;
    await expect(makeBrainFetcher({ token: "t", repo: REPO, fetchImpl: impl })("slow.md"))
      .rejects.toThrow(/timed out after 15s/);
  });
});
