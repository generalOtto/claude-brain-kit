const ALLOWED_ROOTS = [
  "knowledge/", "projects/", "conventions/", "ideas/", "designs/",
  "journal/", "devices/", "pointers/", "identity/", "infrastructure/",
];
const ROOT_FILES = ["TODO.md"];
export const MAX_CHARS = 100_000;

const SECRET_PATTERNS: [RegExp, string][] = [
  [/ghp_[A-Za-z0-9]{20,}/, "a GitHub token"],
  [/github_pat_[A-Za-z0-9_]{20,}/, "a GitHub fine-grained token"],
  [/AKIA[0-9A-Z]{16}/, "an AWS access key"],
  [/-----BEGIN [A-Z ]*PRIVATE KEY-----/, "a private key"],
  [/(?:api[_-]?key|token|secret|password)\s*[:=]\s*["']?[A-Za-z0-9+/_-]{24,}/i, "a credential assignment"],
];

export type ValidateResult = { ok: true; clean: string } | { ok: false; reason: string };

export function validatePath(path: string): ValidateResult {
  const clean = path.replace(/^\/+/, "");
  const no = (reason: string): ValidateResult => ({ ok: false, reason });

  if (!/^[A-Za-z0-9._/-]+$/.test(clean)) {
    return no(`Path "${clean}" contains characters outside the safe set (letters, digits, ".", "_", "-", "/").`);
  }
  const segments = clean.split("/");
  if (segments.includes("..")) return no(`Path "${clean}" contains traversal segments.`);
  if (segments.includes(".") || segments.includes("")) {
    return no(`Path "${clean}" contains empty or "." segments.`);
  }
  if (clean === "CLAUDE.md") return no("CLAUDE.md is the bootloader — edit it from a text session, never by connector write.");
  if (clean === "INDEX.md" || clean.endsWith("/INDEX.md")) return no(`${clean} is a catalog the server maintains — edit it from a text session, never by connector write.`);
  if (clean.startsWith("tools/") || clean.startsWith(".github/")) return no(`"${clean}" is under a protected directory (tools/, .github/) — not writable from a connector.`);
  if (clean.endsWith(".sh") || clean === ".gitignore" || clean.endsWith(".base")) return no(`"${clean}" is executable/config surface — not writable from a connector.`);
  if (!clean.endsWith(".md")) return no(`Only markdown files are writable; "${clean}" is not .md.`);

  const isRootFile = ROOT_FILES.includes(clean);
  const root = ALLOWED_ROOTS.find((r) => clean.startsWith(r));
  if (!isRootFile && !root) {
    return no(`"${clean}" is not writable — allowed: ${ALLOWED_ROOTS.join(" ")} and ${ROOT_FILES.join(" ")}.`);
  }
  return { ok: true, clean };
}

function findSecret(content: string): string | null {
  for (const [re, what] of SECRET_PATTERNS) {
    if (re.test(content)) return what;
  }
  return null;
}

const SECRET_REFUSAL = (what: string) =>
  `Content looks like it contains ${what} — the brain stores no secret values; store a pointer instead (see pointers/secrets.md).`;

export function validateWrite(path: string, content: string): ValidateResult {
  const p = validatePath(path);
  if (!p.ok) return p;
  const no = (reason: string): ValidateResult => ({ ok: false, reason });

  if (!ROOT_FILES.includes(p.clean)) {
    const fm = content.match(/^---\n([\s\S]*?)\n---/);
    const block = fm?.[1] ?? "";
    if (!fm || !/^name:/m.test(block) || !/^description:/m.test(block) || !/^type:/m.test(block)) {
      return no("Notes need frontmatter with name, description, and type — see the write protocol in CLAUDE.md.");
    }
  }

  const secret = findSecret(content);
  if (secret) return no(SECRET_REFUSAL(secret));

  if (content.length > MAX_CHARS) return no(`Content is ${content.length} chars; the cap is ${MAX_CHARS}.`);

  return { ok: true, clean: p.clean };
}

export function validateAppend(path: string, fragment: string, section?: string): ValidateResult {
  const p = validatePath(path);
  if (!p.ok) return p;
  const no = (reason: string): ValidateResult => ({ ok: false, reason });

  if (fragment.trim() === "") return no("Nothing to append — the fragment is empty.");
  if (section !== undefined && /^ {0,3}#{1,2}[ \t]/m.test(fragment)) {
    return no(`The fragment contains a "# "/"## " heading, which would break out of the "${section}" section — restructure with brain_write or from a text session instead.`);
  }

  const secret = findSecret(fragment);
  if (secret) return no(SECRET_REFUSAL(secret));

  return { ok: true, clean: p.clean };
}

export function validateEdit(path: string, find: string, replace: string): ValidateResult {
  const p = validatePath(path);
  if (!p.ok) return p;
  const no = (reason: string): ValidateResult => ({ ok: false, reason });

  if (find === "") return no("Nothing to find — `find` is empty; brain_read the file and copy the exact text to replace.");

  const secret = findSecret(replace);
  if (secret) return no(SECRET_REFUSAL(secret));

  return { ok: true, clean: p.clean };
}
