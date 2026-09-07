import { makeBrainFetcher } from "./gh.js";
import { makeBrainWriter, makeBrainAppender } from "./writeflow.js";
import { makeGitData } from "./gitdata.js";
import { makeWorkerFetch } from "./workerApp.js";

// Cloudflare Workers entry. Same wiring as index.ts (the Node entry), with
// env bindings instead of process.env: secrets arrive per-request on `env`,
// so the app is built lazily on first request and cached for the isolate's
// lifetime (a secret rotation redeploys, which resets isolates).
export interface Env {
  GITHUB_TOKEN?: string;
  MCP_PATH_SECRET?: string;
  BRAIN_REPO?: string; // "owner/name" of the brain repo — set by setup.sh
  AUTH_HEADER_TOKEN?: string;
  GITHUB_API_BASE?: string;
}

let cached: ((request: Request) => Promise<Response>) | null = null;

function build(env: Env): (request: Request) => Promise<Response> {
  const token = env.GITHUB_TOKEN!;
  const repo = env.BRAIN_REPO!;
  const apiBase = env.GITHUB_API_BASE;
  const fetchFile = makeBrainFetcher({ token, repo, apiBase });
  // Same invariant as index.ts: the write path must never round-trip a
  // truncated INDEX back into a commit — writers get truncation disabled.
  const fetchFileForWrites = makeBrainFetcher({ token, repo, apiBase, truncate: false });
  const writeDeps = {
    gitdata: makeGitData({ token, repo, apiBase }),
    fetchFile: fetchFileForWrites,
  };
  return makeWorkerFetch({
    fetchFile,
    pathSecret: env.MCP_PATH_SECRET!,
    headerToken: env.AUTH_HEADER_TOKEN || undefined,
    writeNote: makeBrainWriter(writeDeps),
    appendNote: makeBrainAppender(writeDeps),
  });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (!env.GITHUB_TOKEN || !env.MCP_PATH_SECRET || !env.BRAIN_REPO) {
      // Fail closed with the public bare-404 posture; /healthz alone says
      // enough to diagnose a missing-secrets deploy.
      if (new URL(request.url).pathname === "/healthz") {
        return new Response("misconfigured: missing secrets", { status: 500 });
      }
      return new Response(null, { status: 404 });
    }
    cached ??= build(env);
    return cached(request);
  },
};
