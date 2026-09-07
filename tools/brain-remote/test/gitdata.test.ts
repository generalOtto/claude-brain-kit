import { describe, expect, it } from "vitest";
import { makeGitData } from "../src/gitdata.js";
import { GITHUB_API_VERSION } from "../src/gh.js";

const REPO = "octocat/second-brain";

type Call = { url: string; method: string; body: any; headers: Record<string, string> };
const fakeApi = (respond: (c: Call) => { status: number; json: any }) => {
  const calls: Call[] = [];
  const impl = (async (url: any, init: any) => {
    const c = {
      url: String(url),
      method: init?.method ?? "GET",
      body: init?.body ? JSON.parse(init.body) : null,
      headers: init?.headers ?? {},
    };
    calls.push(c);
    const r = respond(c);
    return new Response(JSON.stringify(r.json), { status: r.status });
  }) as typeof fetch;
  return { impl, calls };
};

describe("makeGitData", () => {
  it("getHead resolves ref then commit tree", async () => {
    const { impl, calls } = fakeApi((c) =>
      c.url.includes("/git/ref/") ? { status: 200, json: { object: { sha: "headsha" } } }
      : { status: 200, json: { sha: "headsha", tree: { sha: "treesha" } } });
    const gd = makeGitData({ token: "t", repo: REPO, fetchImpl: impl });
    expect(await gd.getHead()).toEqual({ commitSha: "headsha", treeSha: "treesha" });
    expect(calls[0].url).toContain(`/repos/${REPO}/git/ref/heads/main`);
    expect(calls[1].url).toContain("/git/commits/headsha");
    expect(calls[0].headers["x-github-api-version"]).toBe(GITHUB_API_VERSION);
  });

  it("commitFiles posts blobs, one tree on the base, one commit on the parent", async () => {
    const { impl, calls } = fakeApi((c) => {
      if (c.url.endsWith("/git/blobs")) return { status: 201, json: { sha: `blob${c.body.content.length}` } };
      if (c.url.endsWith("/git/trees")) return { status: 201, json: { sha: "newtree" } };
      if (c.url.endsWith("/git/commits")) return { status: 201, json: { sha: "newcommit" } };
      return { status: 500, json: {} };
    });
    const gd = makeGitData({ token: "t", repo: REPO, fetchImpl: impl });
    const sha = await gd.commitFiles({
      files: [{ path: "knowledge/a.md", content: "A" }, { path: "INDEX.md", content: "II" }],
      message: "msg", parentCommitSha: "p", baseTreeSha: "b",
    });
    expect(sha).toBe("newcommit");
    const tree = calls.find((c) => c.url.endsWith("/git/trees"))!.body;
    expect(tree.base_tree).toBe("b");
    expect(tree.tree).toEqual([
      { path: "knowledge/a.md", mode: "100644", type: "blob", sha: "blob1" },
      { path: "INDEX.md", mode: "100644", type: "blob", sha: "blob2" },
    ]);
    const commit = calls.find((c) => c.url.endsWith("/git/commits"))!.body;
    expect(commit.parents).toEqual(["p"]);
    expect(commit.message).toBe("msg\n\nvia brain-remote-mcp");
  });

  it("updateRef returns ok on 200 and race on 422, never force", async () => {
    let status = 200;
    const { impl, calls } = fakeApi(() => ({ status, json: {} }));
    const gd = makeGitData({ token: "t", repo: REPO, fetchImpl: impl });
    expect(await gd.updateRef("sha1")).toBe("ok");
    status = 422;
    expect(await gd.updateRef("sha2")).toBe("race");
    for (const c of calls) expect(c.body.force ?? false).toBe(false);
    expect(calls[0].url).toContain("/git/refs/heads/main");
    expect(calls[0].method).toBe("PATCH");
  });

  it("non-race API failures throw with status, no token in message", async () => {
    const { impl } = fakeApi(() => ({ status: 500, json: {} }));
    const gd = makeGitData({ token: "sekret", repo: REPO, fetchImpl: impl });
    await expect(gd.getHead()).rejects.toThrow(/500/);
    await expect(gd.getHead()).rejects.not.toThrow(/sekret/);
  });

  it("passes an abort signal and translates timeouts into a friendly Error", async () => {
    const inits: any[] = [];
    let firstInit: any;
    const impl = (async (_url: any, init: any) => {
      firstInit = firstInit ?? init;
      inits.push(init);
      throw new DOMException("The operation timed out", "TimeoutError");
    }) as typeof fetch;
    const gd = makeGitData({ token: "t", repo: REPO, fetchImpl: impl });
    await expect(gd.getHead()).rejects.toThrow(/timed out after 15s/);
    expect(firstInit.signal).toBeInstanceOf(AbortSignal);
  });
});
