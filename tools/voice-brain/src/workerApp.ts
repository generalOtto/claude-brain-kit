import type { BrainFetcher } from "./gh.js";
import { makeHandler } from "./server.js";
import type { WriteNote, AppendNote } from "./server.js";

// Mirror express.json({ limit: "1mb" }) — the bytes library parses "1mb" as
// 1024 * 1024, and the limit is enforced on byte length.
const BODY_LIMIT_BYTES = 1024 * 1024;

const sha256 = async (s: string) =>
  new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)));

// Constant-time equality over fixed-length SHA-256 digests — the web-runtime
// equivalent of app.ts's hash-then-timingSafeEqual (no node:crypto on workerd).
async function safeEqual(a: string, b: string): Promise<boolean> {
  const [da, db] = await Promise.all([sha256(a), sha256(b)]);
  let diff = 0;
  for (let i = 0; i < da.length; i++) diff |= da[i]! ^ db[i]!;
  return diff === 0;
}

// Fetch-native twin of app.ts's makeApp: same options, same routing, same
// "wrong secret / malformed / oversized body -> bare 404, no body" contract.
// app.ts wraps the SDK handler for Node/Express; this serves its web-standard
// face directly, which is all a Cloudflare Worker needs.
export function makeWorkerFetch(opts: {
  fetchFile: BrainFetcher;
  pathSecret: string;
  headerToken?: string;
  writeNote?: WriteNote;
  appendNote?: AppendNote;
}): (request: Request) => Promise<Response> {
  const handler = makeHandler(opts.fetchFile, opts.writeNote, opts.appendNote);
  const notFound = () => new Response(null, { status: 404 });

  return async (request: Request): Promise<Response> => {
    const url = new URL(request.url);

    if (url.pathname === "/healthz" && request.method === "GET") {
      return new Response("ok", { status: 200 });
    }

    const m = url.pathname.match(/^\/mcp\/([^/]+)$/);
    if (!m) return notFound();
    if (!(await safeEqual(decodeURIComponent(m[1]!), opts.pathSecret))) return notFound();
    if (opts.headerToken !== undefined) {
      const auth = request.headers.get("authorization") ?? "";
      if (!auth.startsWith("Bearer ") || !(await safeEqual(auth.slice(7), opts.headerToken))) {
        return notFound();
      }
    }

    // Body gate — the worker-side stand-in for express.json() + the bare-404
    // error middleware in app.ts: an oversized or unparseable JSON body must
    // answer an empty 404 (any other answer fingerprints the parser). Express
    // only parses bodies whose content-type is JSON; mirror that so the SDK
    // handler sees the same inputs it would behind Express.
    let toServe = request;
    if (request.method === "POST" || request.method === "PUT") {
      const declared = Number(request.headers.get("content-length") ?? "0");
      if (declared > BODY_LIMIT_BYTES) return notFound();
      let text: string;
      try {
        text = await request.text();
      } catch {
        return notFound();
      }
      if (new TextEncoder().encode(text).byteLength > BODY_LIMIT_BYTES) return notFound();
      const contentType = request.headers.get("content-type") ?? "";
      if (contentType.includes("json") && text.length > 0) {
        try {
          JSON.parse(text);
        } catch {
          return notFound();
        }
      }
      toServe = new Request(request.url, {
        method: request.method,
        headers: request.headers,
        body: text.length > 0 ? text : undefined,
      });
    }

    // The SDK answers protocol-level errors itself; anything that still throws
    // here is unexpected — fail closed to the same bare 404.
    try {
      return await handler.fetch(toServe);
    } catch {
      return notFound();
    }
  };
}
