import { makeApp } from "./app.js";
import { makeBrainFetcher } from "./gh.js";
import { makeBrainWriter, makeBrainAppender, makeBrainEditor } from "./writeflow.js";
import { makeGitData } from "./gitdata.js";

function need(name: string): string {
  const v = process.env[name];
  if (!v) {
    console.error(`Missing required env var ${name}`);
    process.exit(1);
  }
  return v;
}

const token = need("GITHUB_TOKEN");
const repo = need("BRAIN_REPO");
const apiBase = process.env.GITHUB_API_BASE;
const fetchFile = makeBrainFetcher({ token, repo, apiBase });
// The writer must never round-trip a truncated INDEX back into a commit, so it
// gets its own fetcher with truncation disabled. Reads (brain_index/brain_read)
// keep the truncating one — truncation there is a display concern, not a hazard.
const fetchFileForWrites = makeBrainFetcher({ token, repo, apiBase, truncate: false });
const writeDeps = {
  gitdata: makeGitData({ token, repo, apiBase }),
  fetchFile: fetchFileForWrites,
};
const app = makeApp({
  fetchFile,
  pathSecret: need("MCP_PATH_SECRET"),
  headerToken: process.env.AUTH_HEADER_TOKEN || undefined,
  writeNote: makeBrainWriter(writeDeps),
  appendNote: makeBrainAppender(writeDeps),
  editNote: makeBrainEditor(writeDeps),
});

const port = Number(process.env.PORT ?? 3000);
app.listen(port, () => console.log(`brain-remote-mcp listening on :${port}`));
