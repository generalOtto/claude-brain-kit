import { GITHUB_API_VERSION, githubFetch } from "./gh.js";

export type GitData = {
  getHead(): Promise<{ commitSha: string; treeSha: string }>;
  commitFiles(args: {
    files: { path: string; content: string }[];
    message: string;
    parentCommitSha: string;
    baseTreeSha: string;
  }): Promise<string>;
  updateRef(sha: string): Promise<"ok" | "race">;
};

export function makeGitData(opts: {
  token: string;
  repo: string; // the brain repo this server fronts, as "owner/name"
  apiBase?: string;
  fetchImpl?: typeof fetch;
}): GitData {
  const { token, repo, apiBase = "https://api.github.com", fetchImpl = fetch } = opts;
  const base = `${apiBase}/repos/${repo}/git`;
  const headers = {
    accept: "application/vnd.github+json",
    authorization: `Bearer ${token}`,
    "x-github-api-version": GITHUB_API_VERSION,
    "user-agent": "brain-remote-mcp",
    "content-type": "application/json",
  };

  async function call(method: string, url: string, body?: unknown): Promise<Response> {
    return githubFetch(
      fetchImpl,
      url,
      { method, headers, body: body === undefined ? undefined : JSON.stringify(body) },
      `${method} ${url.slice(base.length)}`,
    );
  }
  async function json(method: string, url: string, body?: unknown): Promise<any> {
    const res = await call(method, url, body);
    if (!res.ok) throw new Error(`GitHub returned ${res.status} on ${method} ${url.slice(base.length)}`);
    return res.json();
  }

  return {
    async getHead() {
      const ref = await json("GET", `${base}/ref/heads/main`);
      const commit = await json("GET", `${base}/commits/${ref.object.sha}`);
      return { commitSha: ref.object.sha, treeSha: commit.tree.sha };
    },
    async commitFiles({ files, message, parentCommitSha, baseTreeSha }) {
      const entries = [];
      for (const f of files) {
        const blob = await json("POST", `${base}/blobs`, { content: f.content, encoding: "utf-8" });
        entries.push({ path: f.path, mode: "100644", type: "blob", sha: blob.sha });
      }
      const tree = await json("POST", `${base}/trees`, { base_tree: baseTreeSha, tree: entries });
      const commit = await json("POST", `${base}/commits`, {
        message: `${message}\n\nvia brain-remote-mcp`,
        tree: tree.sha,
        parents: [parentCommitSha],
      });
      return commit.sha;
    },
    async updateRef(sha) {
      const res = await call("PATCH", `${base}/refs/heads/main`, { sha, force: false });
      if (res.ok) return "ok";
      if (res.status === 422 || res.status === 409) return "race";
      throw new Error(`GitHub returned ${res.status} updating refs/heads/main`);
    },
  };
}
