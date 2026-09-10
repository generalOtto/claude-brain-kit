import { beforeAll, describe, expect, it } from "vitest";
import { makeWorkerFetch } from "../src/workerApp.js";
import workerEntry from "../src/worker.js";
import type { Env } from "../src/worker.js";

// Same fixtures and contract cases as app.test.ts, served through the
// worker's fetch face instead of Express — the two entries must be
// behaviorally identical from a client's point of view.

const SECRET = "a".repeat(32);
const BASE = "https://worker.test";

let handler: (request: Request) => Promise<Response>;

const rpc = (body: unknown, path = `/mcp/${SECRET}`, headers: Record<string, string> = {}) =>
  handler(
    new Request(`${BASE}${path}`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        accept: "application/json, text/event-stream",
        ...headers,
      },
      body: JSON.stringify(body),
    }),
  );

const toolsCall = (name: string, args: object, id = 1) => ({
  jsonrpc: "2.0", id, method: "tools/call", params: { name, arguments: args },
});

const rawPost = (rawBody: string, path: string) =>
  handler(
    new Request(`${BASE}${path}`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        accept: "application/json, text/event-stream",
      },
      body: rawBody,
    }),
  );

beforeAll(() => {
  handler = makeWorkerFetch({
    fetchFile: async (p) => (p === "CLAUDE.md" ? "BOOT" : p === "INDEX.md" ? "CATALOG" : `BODY:${p}`),
    pathSecret: SECRET,
    writeNote: async (path, _content, message) => `Committed abc1234: ${path} (+ INDEX line updated). [msg=${message}]`,
    appendNote: async (path, _content, section, message) =>
      `Committed def5678: appended to ${path}${section !== undefined ? ` (section "${section}")` : ""}. [msg=${message}]`,
  });
});

describe("auth gate", () => {
  it("404s a wrong path secret with no body", async () => {
    const res = await rpc(toolsCall("brain_read", { path: "x.md" }), `/mcp/${"b".repeat(32)}`);
    expect(res.status).toBe(404);
    expect(await res.text()).toBe("");
  });

  it("404s unknown routes", async () => {
    const res = await handler(new Request(`${BASE}/`, { method: "GET" }));
    expect(res.status).toBe(404);
    expect(await res.text()).toBe("");
  });

  it("404s malformed JSON to a wrong path secret, with no body", async () => {
    const res = await rawPost('{"broken', `/mcp/${"b".repeat(32)}`);
    expect(res.status).toBe(404);
    expect(await res.text()).toBe("");
  });

  it("404s malformed JSON to the correct path secret, with no body", async () => {
    const res = await rawPost('{"broken', `/mcp/${SECRET}`);
    expect(res.status).toBe(404);
    expect(await res.text()).toBe("");
  });

  it("404s an oversized body to a wrong path secret, with no body", async () => {
    const oversized = '{"a":"' + "x".repeat(1_100_000) + '"}';
    const res = await rawPost(oversized, `/mcp/${"b".repeat(32)}`);
    expect(res.status).toBe(404);
    expect(await res.text()).toBe("");
  });

  it("404s an oversized body to the correct path secret, with no body", async () => {
    const oversized = '{"a":"' + "x".repeat(1_100_000) + '"}';
    const res = await rawPost(oversized, `/mcp/${SECRET}`);
    expect(res.status).toBe(404);
    expect(await res.text()).toBe("");
  });

  it("enforces AUTH_HEADER_TOKEN when configured", async () => {
    const h2 = makeWorkerFetch({ fetchFile: async () => "x", pathSecret: SECRET, headerToken: "hdr" });
    const no = await h2(
      new Request(`${BASE}/mcp/${SECRET}`, {
        method: "POST",
        headers: { "content-type": "application/json", accept: "application/json, text/event-stream" },
        body: JSON.stringify(toolsCall("brain_read", { path: "x" })),
      }),
    );
    expect(no.status).toBe(404);
    const yes = await h2(
      new Request(`${BASE}/mcp/${SECRET}`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          accept: "application/json, text/event-stream",
          authorization: "Bearer hdr",
        },
        body: JSON.stringify(toolsCall("brain_read", { path: "x" })),
      }),
    );
    expect(yes.status).toBeLessThan(300);
  });
});

describe("MCP over streamable HTTP", () => {
  it("initialize carries the voice-etiquette server instructions", async () => {
    const res = await rpc({
      jsonrpc: "2.0", id: 0, method: "initialize",
      params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "t", version: "0" } },
    });
    const body = await res.text();
    expect(body).toContain('"instructions"');
    expect(body).toContain("never talk over an in-flight call");
  });

  it("lists all four tools", async () => {
    const res = await rpc({ jsonrpc: "2.0", id: 1, method: "tools/list" });
    const body = await res.text();
    expect(body).toContain("brain_index");
    expect(body).toContain("brain_read");
    expect(body).toContain("brain_write");
    expect(body).toContain("brain_append");
  });

  it("brain_read returns a plain text part with the file body", async () => {
    const res = await rpc(toolsCall("brain_read", { path: "knowledge/x.md" }));
    const body = await res.text();
    expect(body).toContain('"type":"text"');
    expect(body).toContain("BODY:knowledge/x.md");
    expect(body).not.toContain('"type":"resource"');
  });

  it("brain_index returns both files in one text part", async () => {
    const res = await rpc(toolsCall("brain_index", {}));
    const body = await res.text();
    expect(body).toContain("== CLAUDE.md ==");
    expect(body).toContain("CATALOG");
    expect(body).not.toContain('"type":"resource"');
  });

  it("brain_index omits the bootloader when the Claude Code surface header is present", async () => {
    const res = await rpc(toolsCall("brain_index", {}), undefined, { "x-brain-surface": "claude-code" });
    const body = await res.text();
    expect(body).not.toContain("BOOT");
    expect(body).toContain("Bootloader (CLAUDE.md) omitted");
    expect(body).toContain("CATALOG");
  });

  it("brain_index keeps the bootloader for an unknown surface header value", async () => {
    const res = await rpc(toolsCall("brain_index", {}), undefined, { "x-brain-surface": "something-else" });
    expect(await res.text()).toContain("BOOT");
  });

  it("bootloader: true beats the surface header", async () => {
    const res = await rpc(toolsCall("brain_index", { bootloader: true }), undefined, { "x-brain-surface": "claude-code" });
    expect(await res.text()).toContain("== CLAUDE.md ==");
  });

  it("bootloader: false beats the absent header", async () => {
    const res = await rpc(toolsCall("brain_index", { bootloader: false }));
    const body = await res.text();
    expect(body).not.toContain("BOOT");
    expect(body).toContain("CATALOG");
  });

  it("brain_index description teaches the bootloader override", async () => {
    const res = await rpc({ jsonrpc: "2.0", id: 1, method: "tools/list" });
    expect(await res.text()).toContain("pass bootloader: true");
  });

  it("brain_write returns the writer's text as a single text part", async () => {
    const res = await rpc(toolsCall("brain_write", {
      path: "knowledge/x.md",
      content: "---\nname: x\ndescription: d\ntype: reference\n---\n# X\n",
      message: "add x",
    }, 11));
    const body = await res.text();
    expect(body).toContain('"type":"text"');
    expect(body).toContain("Committed abc1234: knowledge/x.md");
  });

  it("brain_append passes section through", async () => {
    const res = await rpc(toolsCall("brain_append", {
      path: "TODO.md",
      content: "### New\n- x",
      section: "Active",
      message: "add item",
    }, 21));
    const body = await res.text();
    expect(body).toContain('appended to TODO.md (section \\"Active\\")');
  });

  it("healthz answers 200 without auth", async () => {
    const res = await handler(new Request(`${BASE}/healthz`, { method: "GET" }));
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("ok");
  });
});

describe("worker entry env handling", () => {
  it("fails closed (bare 404) when secrets are missing", async () => {
    const res = await workerEntry.fetch(
      new Request(`${BASE}/mcp/anything`, { method: "POST" }),
      {} as Env,
    );
    expect(res.status).toBe(404);
    expect(await res.text()).toBe("");
  });

  it("healthz reports misconfiguration when secrets are missing", async () => {
    const res = await workerEntry.fetch(new Request(`${BASE}/healthz`), {} as Env);
    expect(res.status).toBe(500);
    expect(await res.text()).toContain("misconfigured");
  });

  it("treats a missing BRAIN_REPO as misconfigured even with both secrets set", async () => {
    const env = { GITHUB_TOKEN: "t", MCP_PATH_SECRET: "s" } as Env;
    const res = await workerEntry.fetch(new Request(`${BASE}/healthz`), env);
    expect(res.status).toBe(500);
    expect(await res.text()).toContain("misconfigured");
  });
});
