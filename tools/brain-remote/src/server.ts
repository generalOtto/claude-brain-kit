import { createMcpHandler, McpServer } from "@modelcontextprotocol/server";
import { z } from "zod";
import type { BrainFetcher } from "./gh.js";
import { brainIndex, brainRead } from "./tools.js";

export type WriteNote = (path: string, content: string, message: string) => Promise<string>;
export type AppendNote = (path: string, content: string, section: string | undefined, message: string) => Promise<string>;
export type EditNote = (path: string, find: string, replace: string, message: string) => Promise<string>;

export const SURFACE_HEADER = "x-brain-surface";
export const SURFACE_CLAUDE_CODE = "claude-code";

export function makeHandler(fetchFile: BrainFetcher, writeNote?: WriteNote, appendNote?: AppendNote, editNote?: EditNote) {
  return createMcpHandler((ctx) => {
    // The plugin's .mcp.json marks Claude Code callers; there the bootloader is
    // already in context via the symlinked CLAUDE.md, so it is dead weight.
    // Every claude.ai connector sends no header and keeps today's full result.
    const surface = ctx.requestInfo?.headers.get(SURFACE_HEADER) ?? "";
    const defaultBootloader = surface !== SURFACE_CLAUDE_CODE;
    const server = new McpServer(
      { name: "brain-remote", version: "1.5.1" },
      {
        instructions:
          "This server is the user's brain (their private notes repo). Voice etiquette, " +
          "binding whenever this conversation is spoken aloud: finish your spoken " +
          "sentence BEFORE invoking any tool, stay silent while a call is in flight, " +
          "and resume speaking only once the result has arrived — never talk over an " +
          "in-flight call. Recall protocol: call brain_index first, then brain_read " +
          "the smallest set of notes that covers the task.",
      },
    );
    server.registerTool(
      "brain_index",
      {
        description:
          "Call this FIRST, before reading anything else. Returns INDEX.md, the catalog of every " +
          "brain note with one-line descriptions, plus — unless this surface already has it — the " +
          "brain bootloader (CLAUDE.md: who the user is, how recall works). If the brain bootloader " +
          "is not already in your context, pass bootloader: true; if it already is (e.g. Claude Code " +
          "with CLAUDE.md loaded), pass bootloader: false. Use the catalog to pick which " +
          "notes to read. Voice sessions: never speak while a tool call is running — finish your " +
          "sentence, call, then continue.",
        inputSchema: z.object({
          bootloader: z.boolean().optional().describe(
            "Include CLAUDE.md. Default: yes for connector surfaces, no for Claude Code callers " +
            "(they already have it). Set true if the bootloader is not in your context.",
          ),
        }),
      },
      async ({ bootloader }) => brainIndex(fetchFile, { bootloader: bootloader ?? defaultBootloader }),
    );
    server.registerTool(
      "brain_read",
      {
        description:
          "Read ONE brain note by its repo-relative path (e.g. knowledge/some-gotcha.md), " +
          "after brain_index has shown which notes match the task. Read the smallest set of " +
          "notes that covers the task.",
        inputSchema: z.object({
          path: z.string().describe("Repo-relative file path, e.g. identity/about-me.md"),
        }),
      },
      async ({ path }) => brainRead(fetchFile, path),
    );
    if (writeNote) {
      server.registerTool(
        "brain_write",
        {
          description:
            "Write ONE brain note (create or fully replace) the protocol-true way: the server " +
            "commits the note AND its INDEX.md line atomically to main. Server-enforced: markdown-only " +
            "paths in an allow/deny-listed directory set, required frontmatter (name/description/type), " +
            "no secret-shaped content, a size cap, a TODO.md wipe guard (replacing it with under half its " +
            "size refuses), atomic INDEX line update. Yours to follow: one fact " +
            "per file, kebab-case filename, update an existing note rather than duplicating it, and " +
            "brain_read it first before replacing. Refusals come back as text explaining what to fix.",
          inputSchema: z.object({
            path: z.string().describe("Repo-relative path, e.g. ideas/apps/overlay.md or knowledge/some-gotcha.md"),
            content: z.string().describe("Full file content including frontmatter"),
            message: z.string().describe("Commit message, imperative and specific"),
          }),
        },
        async ({ path, content, message }) => ({
          content: [{ type: "text", text: await writeNote(path, content, message) }],
        }),
      );
    }
    if (appendNote) {
      server.registerTool(
        "brain_append",
        {
          description:
            "Append a fragment to ONE existing brain file without rewriting it — the fit for " +
            "adding an item to a list or a line to a note. With section (e.g. \"Active\"), the " +
            "fragment lands at the end of that \"## \" section — the name may be the heading's " +
            "leading words, so \"Known dead weight\" finds \"## Known dead weight (pending Otto)\"; " +
            "without it, at the end of the file. " +
            "The headline case: adding a to-do = path TODO.md, section \"Active\", fragment shaped " +
            "like the file's existing items (brain_read it first if unsure). Server-enforced: the " +
            "file must already exist (create notes with brain_write), no secret-shaped content, no " +
            "new \"# \"/\"## \" headings inside a section append, 100k result cap. Refusals come " +
            "back as text explaining what to fix.",
          inputSchema: z.object({
            path: z.string().describe("Repo-relative path of an EXISTING file, e.g. TODO.md"),
            content: z.string().describe("The fragment to append — not a whole file, no frontmatter"),
            section: z.string().optional().describe("Optional \"## \" section to append inside, e.g. \"Active\""),
            message: z.string().describe("Commit message, imperative and specific"),
          }),
        },
        async ({ path, content, section, message }) => ({
          content: [{ type: "text", text: await appendNote(path, content, section, message) }],
        }),
      );
    }
    if (editNote) {
      server.registerTool(
        "brain_edit",
        {
          description:
            "Replace ONE exact piece of text in ONE existing brain file — the fit for small changes " +
            "(flip a to-do's next date, fix a line, update a status) that must not cost a full-file " +
            "brain_write. `find` must occur exactly once in the file, matched verbatim (whitespace " +
            "and punctuation included, no regex): brain_read the file first and copy the text. " +
            "`replace` may be empty to delete the span. If the edit changes a note's title or " +
            "description, its INDEX line is refreshed in the same commit. Server-enforced: the file " +
            "must exist (create notes with brain_write), same path rules as brain_write, no " +
            "secret-shaped content, 100k result cap, TODO.md wipe guard. For adding items use brain_append. Refusals " +
            "come back as text explaining what to fix.",
          inputSchema: z.object({
            path: z.string().describe("Repo-relative path of an EXISTING file, e.g. TODO.md or knowledge/some-gotcha.md"),
            find: z.string().describe("The exact text to replace — must occur exactly once"),
            replace: z.string().describe("The replacement text; empty string deletes the matched text"),
            message: z.string().describe("Commit message, imperative and specific"),
          }),
        },
        async ({ path, find, replace, message }) => ({
          content: [{ type: "text", text: await editNote(path, find, replace, message) }],
        }),
      );
    }
    return server;
  });
}
