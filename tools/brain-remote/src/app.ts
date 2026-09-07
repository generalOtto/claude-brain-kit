import express from "express";
import type { NextFunction, Request, Response } from "express";
import { createHash, timingSafeEqual } from "node:crypto";
import { toNodeHandler } from "@modelcontextprotocol/node";
import type { BrainFetcher } from "./gh.js";
import { makeHandler } from "./server.js";
import type { WriteNote, AppendNote } from "./server.js";

const sha = (s: string) => createHash("sha256").update(s).digest();
const safeEqual = (a: string, b: string) => timingSafeEqual(sha(a), sha(b));

export function makeApp(opts: {
  fetchFile: BrainFetcher;
  pathSecret: string;
  headerToken?: string;
  writeNote?: WriteNote;
  appendNote?: AppendNote;
}) {
  const app = express();
  app.disable("x-powered-by");
  app.use(express.json({ limit: "1mb" }));
  // A malformed or oversized body makes express.json() throw before the
  // /mcp/:secret route's auth check ever runs (SyntaxError for bad JSON,
  // PayloadTooLargeError for anything over the 1mb limit, etc). Without this
  // handler that throw falls through to Express's default error page (400/413
  // + stack trace with local filesystem paths), bypassing the "wrong path
  // secret -> bare 404, no body" contract and fingerprinting the parser.
  // This middleware sits directly after express.json() with nothing else
  // between them, so every error reaching it is a body-parse failure of some
  // kind — treat all of them as untrusted input and answer bare 404, same as
  // a bad secret, regardless of path.
  app.use((_err: unknown, _req: Request, res: Response, _next: NextFunction) => {
    res.status(404).end();
  });
  const node = toNodeHandler(makeHandler(opts.fetchFile, opts.writeNote, opts.appendNote));

  app.get("/healthz", (_req, res) => { res.status(200).send("ok"); });

  app.all("/mcp/:secret", (req, res) => {
    if (!safeEqual(req.params.secret, opts.pathSecret)) { res.status(404).end(); return; }
    if (opts.headerToken !== undefined) {
      const auth = req.headers.authorization ?? "";
      if (!auth.startsWith("Bearer ") || !safeEqual(auth.slice(7), opts.headerToken)) {
        res.status(404).end();
        return;
      }
    }
    void node(req, res, req.body);
  });

  app.use((_req, res) => { res.status(404).end(); });
  return app;
}
