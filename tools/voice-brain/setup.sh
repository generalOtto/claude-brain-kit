#!/usr/bin/env bash
# voice-brain-mcp — zero-copy-paste first-time setup for Cloudflare Workers.
#
#   bash setup.sh                 # do everything; safe to re-run (existing
#                                 # secrets and subdomain are left untouched)
#   bash setup.sh --rotate-secret # force a fresh MCP_PATH_SECRET (breaks the
#                                 # old connector URL — update it after)
#   bash setup.sh --set-token     # re-prompt for the GitHub PAT even if set
#   bash setup.sh --skip-token    # don't prompt for a PAT (testing/CI)
#   bash setup.sh --name <worker> # deploy under a different worker name
#   bash setup.sh --config <file> # use an alternate wrangler config
#
# What it derives so you never paste it: the Cloudflare account ID (from
# wrangler's own session), the workers.dev subdomain (auto-generated and
# registered if the account has none), the MCP path secret (generated here),
# and the brain repo itself (from this repo's git remote — this directory
# normally lives INSIDE your brain repo). The ONE thing you provide is the
# GitHub fine-grained PAT — and the script validates it against GitHub before
# storing, so a bad paste is caught on the spot, not in production.
#
# Lessons baked in: verify-then-store for every secret, diagnose paste
# failures by length/shape (never by value), and no hand-copying of long
# strings out of UI fields.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

say()  { printf '%s\n' "$*"; }
step() { printf '\n── %s\n' "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# The brain repo this server fronts ("owner/name"). Precedence: an explicit
# $BRAIN_REPO env > the value already stored on the worker > derived from this
# repo's git remote. In the kit layout this directory lives inside your brain
# repo, so the remote IS the brain repo — you never type it. Deploying from
# somewhere that is NOT your brain repo? Set BRAIN_REPO=owner/name explicitly.
derive_repo_from_git() {
  local url path
  url="$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || true)"
  [ -n "$url" ] || return 1
  # git@host:owner/name(.git) | https://host/owner/name(.git) | ssh://git@host/owner/name(.git)
  path="$(printf '%s\n' "$url" | sed -E -e 's#^[a-zA-Z+]+://[^/]+/##' -e 's#^[^@/]+@[^:]+:##' -e 's#\.git$##' -e 's#/+$##')"
  case "$path" in
    */*/*|/*|*:*) return 1 ;;  # not a plain owner/name (local path, subgroup, …)
    */*)          printf '%s\n' "$path" ;;
    *)            return 1 ;;
  esac
}

BRAIN_REPO_SOURCE="derived"
if [ -n "${BRAIN_REPO:-}" ]; then
  BRAIN_REPO_SOURCE="env"
  case "$BRAIN_REPO" in
    */*/*|/*|*:*) die "BRAIN_REPO must be \"owner/name\", got \"$BRAIN_REPO\"" ;;
    */*) : ;;
    *)   die "BRAIN_REPO must be \"owner/name\", got \"$BRAIN_REPO\"" ;;
  esac
else
  BRAIN_REPO="$(derive_repo_from_git || true)"
fi

ROTATE_SECRET="no"; SET_TOKEN="no"; SKIP_TOKEN="no"; WORKER_NAME=""; CONFIG_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --rotate-secret) ROTATE_SECRET="yes" ;;
    --set-token)     SET_TOKEN="yes" ;;
    --skip-token)    SKIP_TOKEN="yes" ;;
    --name)          [ $# -ge 2 ] || die "--name needs a value"; shift; WORKER_NAME="$1" ;;
    --config)        [ $# -ge 2 ] || die "--config needs a value"; shift; CONFIG_FILE="$1" ;;
    *) die "Unknown option: $1" ;;
  esac
  shift
done

WRANGLER() { npx wrangler "$@"; }
NAME_ARGS=()
[ -n "$WORKER_NAME" ] && NAME_ARGS=(--name "$WORKER_NAME")
[ -n "$CONFIG_FILE" ] && NAME_ARGS=(${NAME_ARGS[@]+"${NAME_ARGS[@]}"} --config "$CONFIG_FILE")

# JSON field extraction without assuming python — node is guaranteed (we need
# npm anyway). Walks a dot-path on stdin's JSON; prints "" on unparseable input.
json_get() { node -e 'let j;try{j=JSON.parse(require("fs").readFileSync(0,"utf8"))}catch{process.exit(0)};for(const k of process.argv[1].split(".").filter(Boolean))j=j?.[k];console.log(j==null?"":String(j))' "$1"; }

# ── 0. Dependencies ────────────────────────────────────────────────────────────
step "Dependencies"
command -v npm >/dev/null 2>&1 || die "npm not found — install Node.js first (https://nodejs.org)"
[ -d node_modules ] || { say "Installing packages (one-time)…"; npm install --silent; }
say "✓ node + packages ready"

# ── 0b. The brain repo ─────────────────────────────────────────────────────────
step "Brain repo"
if [ "$BRAIN_REPO_SOURCE" = "env" ]; then
  say "✓ $BRAIN_REPO (from \$BRAIN_REPO — will be stored on the worker)"
elif [ -n "$BRAIN_REPO" ]; then
  say "✓ $BRAIN_REPO (derived from this repo's git remote)"
else
  say "· no git remote to derive from — will keep whatever the worker already has stored"
fi

# ── 1. Cloudflare login ────────────────────────────────────────────────────────
step "Cloudflare account"
if ! WRANGLER whoami 2>/dev/null | grep -q "You are logged in"; then
  say "A browser window will open — log in to (or create) your free Cloudflare account."
  WRANGLER login
fi
WHOAMI="$(WRANGLER whoami 2>/dev/null)"
# Account ID: the 32-hex cell in whoami's account table — derived, never pasted.
ACCOUNT_ID="$(printf '%s\n' "$WHOAMI" | grep -oE '\b[0-9a-f]{32}\b' | head -1)"
[ -n "$ACCOUNT_ID" ] || die "could not read the account ID from 'wrangler whoami' — run 'npx wrangler login' and retry"
say "✓ logged in (account ${ACCOUNT_ID:0:6}…)"

# Wrangler's OAuth session token, for the one API call wrangler has no
# non-interactive command for (workers.dev subdomain registration). Running
# whoami above refreshed it. Location varies by OS.
oauth_token() {
  local f
  for f in "${WRANGLER_HOME:-}/config/default.toml" \
           "$HOME/Library/Preferences/.wrangler/config/default.toml" \
           "${XDG_CONFIG_HOME:-$HOME/.config}/.wrangler/config/default.toml" \
           "$HOME/.wrangler/config/default.toml"; do
    [ -f "$f" ] && grep -m1 '^oauth_token' "$f" | sed 's/^oauth_token *= *"\(.*\)"/\1/' && return 0
  done
  return 1
}

# ── 2. workers.dev subdomain (auto-generated — you are not asked) ─────────────
step "workers.dev subdomain"
CF_API="https://api.cloudflare.com/client/v4"
TOKEN="$(oauth_token || true)"
SUBDOMAIN=""
if [ -n "$TOKEN" ]; then
  SUBDOMAIN="$(curl -s -H "Authorization: Bearer $TOKEN" "$CF_API/accounts/$ACCOUNT_ID/workers/subdomain" \
    | json_get 'result.subdomain')"
fi
if [ -n "$SUBDOMAIN" ]; then
  say "✓ account already has a subdomain: $SUBDOMAIN.workers.dev"
elif [ -n "$TOKEN" ]; then
  for _try in 1 2 3 4 5; do
    CANDIDATE="brain-$(openssl rand -hex 4)"
    OK="$(curl -s -X PUT -H "Authorization: Bearer $TOKEN" -H 'content-type: application/json' \
      -d "{\"subdomain\":\"$CANDIDATE\"}" "$CF_API/accounts/$ACCOUNT_ID/workers/subdomain" \
      | json_get 'success')"
    if [ "$OK" = "true" ]; then SUBDOMAIN="$CANDIDATE"; say "✓ registered $SUBDOMAIN.workers.dev (auto-generated)"; break; fi
  done
fi
if [ -z "$SUBDOMAIN" ]; then
  say "· could not auto-register a subdomain — if the deploy below prompts you"
  say "  for one, accept and pick any name."
fi

# ── 3. Deploy the Worker ───────────────────────────────────────────────────────
# Streamed via tee (not captured in a command substitution) so that if wrangler
# ever needs to prompt — e.g. the subdomain fallback above — you can see and
# answer it.
step "Deploy"
DEPLOY_LOG="$(mktemp)"
if ! WRANGLER deploy ${NAME_ARGS[@]+"${NAME_ARGS[@]}"} 2>&1 | tee "$DEPLOY_LOG"; then
  rm -f "$DEPLOY_LOG"
  die "deploy failed (output above)"
fi
WORKER_URL="$(grep -oE 'https://[a-z0-9.-]+\.workers\.dev' "$DEPLOY_LOG" | head -1 || true)"
rm -f "$DEPLOY_LOG"
[ -n "$WORKER_URL" ] || { [ -n "$SUBDOMAIN" ] && WORKER_URL="https://${WORKER_NAME:-voice-brain-mcp}.$SUBDOMAIN.workers.dev"; }
[ -n "$WORKER_URL" ] || die "no workers.dev URL — register a subdomain (re-run me) and retry"
say "✓ deployed: $WORKER_URL"

# ── 4. Secrets (verify-then-store; existing values are never touched) ─────────
step "Secrets"
# A failed listing must NOT read as "no secrets" — that would regenerate the
# path secret on a re-run and break the live connector URL. Fail hard instead.
LIST_OUT="$(WRANGLER secret list ${NAME_ARGS[@]+"${NAME_ARGS[@]}"} 2>/dev/null)" \
  || die "could not list the worker's secrets (nothing was changed) — re-run me in a moment"
EXISTING="$(printf '%s' "$LIST_OUT" | node -e 'let j;try{j=JSON.parse(require("fs").readFileSync(0,"utf8"))}catch{console.error("unparseable secret list");process.exit(1)};console.log(j.map(s=>s.name).join(" "))')"

PATH_SECRET=""
if printf '%s' "$EXISTING" | grep -q "MCP_PATH_SECRET" && [ "$ROTATE_SECRET" = "no" ]; then
  say "✓ MCP_PATH_SECRET already set — kept (use --rotate-secret to replace)"
else
  PATH_SECRET="$(openssl rand -base64 48 | tr '+/' '-_' | tr -d '=\n')"
  printf '%s' "$PATH_SECRET" | WRANGLER secret put MCP_PATH_SECRET ${NAME_ARGS[@]+"${NAME_ARGS[@]}"} >/dev/null
  say "✓ MCP_PATH_SECRET generated (${#PATH_SECRET} chars) and stored"
fi

# BRAIN_REPO rides the worker as a secret (pragmatic persistent env — survives
# every later deploy). Env is authoritative; a stored value is kept otherwise.
if [ "$BRAIN_REPO_SOURCE" = "env" ]; then
  printf '%s' "$BRAIN_REPO" | WRANGLER secret put BRAIN_REPO ${NAME_ARGS[@]+"${NAME_ARGS[@]}"} >/dev/null
  say "✓ BRAIN_REPO stored: $BRAIN_REPO (from \$BRAIN_REPO)"
elif printf '%s' "$EXISTING" | grep -q "BRAIN_REPO"; then
  say "✓ BRAIN_REPO already stored — kept (re-run with BRAIN_REPO=owner/name to replace)"
elif [ -n "$BRAIN_REPO" ]; then
  printf '%s' "$BRAIN_REPO" | WRANGLER secret put BRAIN_REPO ${NAME_ARGS[@]+"${NAME_ARGS[@]}"} >/dev/null
  say "✓ BRAIN_REPO stored: $BRAIN_REPO (derived from this repo's git remote)"
else
  die "could not determine your brain repo (no BRAIN_REPO env, nothing stored, no git remote) — re-run as: BRAIN_REPO=owner/name bash setup.sh"
fi

if [ "$SKIP_TOKEN" = "yes" ]; then
  say "· GitHub PAT skipped (--skip-token)"
elif printf '%s' "$EXISTING" | grep -q "GITHUB_TOKEN" && [ "$SET_TOKEN" = "no" ]; then
  say "✓ GITHUB_TOKEN already set — kept (use --set-token to replace)"
else
  [ -n "$BRAIN_REPO" ] || die "need the brain repo name to verify a PAT against — re-run as: BRAIN_REPO=owner/name bash setup.sh"
  say ""
  say "The one thing I need from you: a GitHub fine-grained PAT for your brain repo."
  say "  1. Open  https://github.com/settings/personal-access-tokens/new"
  say "  2. Repository access: Only select repositories → ${BRAIN_REPO#*/}"
  say "  3. Permissions → Contents: Read and write"
  say "  4. Generate, then copy the VALUE (starts with github_pat_, ~90+ chars)"
  say ""
  TOKEN_OK="no"
  for _try in 1 2 3; do
    IFS= read -rs -p "Paste the PAT (input hidden): " PAT; echo
    if [ ${#PAT} -eq 36 ] && case "$PAT" in *-*-*-*-*) true;; *) false;; esac; then
      say "  ✗ that's a 36-char ID (a UUID), not the token — copy the token VALUE"; continue
    fi
    case "$PAT" in github_pat_*|ghp_*) : ;; *) say "  · unusual prefix (${PAT:0:10}…, ${#PAT} chars) — checking anyway";; esac
    CODE="$(curl -s -o /dev/null -w "%{http_code}" -H "authorization: Bearer $PAT" \
      -H "x-github-api-version: 2026-03-10" "https://api.github.com/repos/$BRAIN_REPO/contents/CLAUDE.md")"
    if [ "$CODE" = "200" ]; then
      printf '%s' "$PAT" | WRANGLER secret put GITHUB_TOKEN ${NAME_ARGS[@]+"${NAME_ARGS[@]}"} >/dev/null
      say "  ✓ PAT verified against $BRAIN_REPO and stored"; TOKEN_OK="yes"; break
    fi
    say "  ✗ GitHub says $CODE for $BRAIN_REPO — wrong value, wrong repo selection, or missing Contents permission"
  done
  unset PAT
  [ "$TOKEN_OK" = "yes" ] || die "no working PAT after 3 tries — re-run me when you have one"
fi

# ── 5. Self-test ───────────────────────────────────────────────────────────────
step "Self-test"
HZ=""
for _try in 1 2 3 4 5 6; do
  HZ="$(curl -s --connect-timeout 8 "$WORKER_URL/healthz" 2>/dev/null || true)"
  [ -n "$HZ" ] && break
  say "  … waiting for DNS ($_try/6)"; sleep 20
done
case "$HZ" in
  ok) say "✓ healthz ok" ;;
  *misconfigured*) say "· healthz: secrets missing (expected only with --skip-token)" ;;
  "") say "· healthz unreachable yet — new subdomains can take a few minutes; the URL below will still be right" ;;
  *) say "· healthz said: $HZ" ;;
esac
if [ -n "$PATH_SECRET" ] && [ "$SKIP_TOKEN" = "no" ]; then
  PROBE="$(curl -s --connect-timeout 8 -X POST "$WORKER_URL/mcp/$PATH_SECRET" \
    -H 'content-type: application/json' -H 'accept: application/json, text/event-stream' \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"brain_index","arguments":{}}}' | head -c 40 || true)"
  case "$PROBE" in *event:*|*jsonrpc*) say "✓ end-to-end probe: brain reachable through the Worker" ;;
                   *) say "· probe inconclusive (${PROBE:-empty}) — try again in a few minutes" ;; esac
fi

# ── 6. The connector URL ───────────────────────────────────────────────────────
copy_clip() {
  if   command -v pbcopy   >/dev/null 2>&1; then pbcopy
  elif command -v wl-copy  >/dev/null 2>&1; then wl-copy
  elif command -v xclip    >/dev/null 2>&1; then xclip -selection clipboard
  elif command -v clip.exe >/dev/null 2>&1; then clip.exe
  else return 1; fi
}
step "Done"
if [ -n "$PATH_SECRET" ]; then
  CONNECTOR_URL="$WORKER_URL/mcp/$PATH_SECRET"
  say "Your connector URL (add it on claude.ai → Settings → Connectors → Add custom connector):"
  say ""
  say "  $CONNECTOR_URL"
  say ""
  if printf '%s' "$CONNECTOR_URL" | copy_clip 2>/dev/null; then say "(already copied to your clipboard)"; fi
  say "Store the secret part in your password manager too — copy the VALUE field back"
  say "out later, never the entry's ID, and never drag-select it."
else
  say "Secrets unchanged — your existing connector URL keeps working as-is."
fi
