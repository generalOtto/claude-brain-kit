#!/usr/bin/env bash
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
SETUP="$ROOT/tools/brain-remote/setup.sh"

# Canaries stand in for the three credentials setup.sh handles — long, so an assertion
# can't match by accident, and shaped like no real token. Digit-free on purpose: with
# a digit in it, gitleaks' generic-api-key rule would flag the OAuth one.
OAUTH_CANARY=xtrace-canary-wrangler-oauth-that-must-never-be-printed
PAT_CANARY=github_pat_xtrace-canary-that-must-never-be-printed
PATH_CANARY=xtrace-canary-path-secret-shown-only-in-the-connector-url

# A sandbox where setup.sh runs start to finish without touching the network or the
# machine: a fake on PATH for every external command it runs, and a wrangler config
# holding the OAuth canary. The fakes are plain bash that tolerates `set -eu` — under
# an exported SHELLOPTS they inherit the shell options of the script under test.
setup_sandbox() {
  t_setup
  mkdir -p "$SB/bin" "$SB/seen" "$SB/wrangler/config"
  export SEEN="$SB/seen" PATH_CANARY
  export WRANGLER_HOME="$SB/wrangler" BRAIN_REPO=canary-owner/canary-brain
  # A host BASH_ENV file must not run — and be traced — inside the script under test.
  unset BASH_ENV
  printf 'oauth_token = "%s"\n' "$OAUTH_CANARY" > "$WRANGLER_HOME/config/default.toml"
  cat > "$SB/bin/npx" <<'EOF'
#!/usr/bin/env bash
# Fake `npx wrangler …`: a logged-in account and a worker with no secrets stored yet.
# Every `secret put` value arrives on stdin and is kept in $SEEN/put-<NAME>. The deploy
# URL's subdomain is longer than a DNS label can be, so it is nobody's real worker.
[ "${1:-}" = wrangler ] || exit 64
case "${2:-}" in
  whoami) printf 'You are logged in\n| Account ID | 00000000000000000000000000000000 |\n' ;;
  deploy) echo "https://brain-remote-mcp.a-label-longer-than-sixty-three-characters-can-never-exist-in-dns.workers.dev" ;;
  secret)
    case "${3:-}" in
      list) echo '[]' ;;
      put)  cat > "$SEEN/put-$4" ;;
    esac ;;
  *) exit 64 ;;
esac
EOF
  cat > "$SB/bin/curl" <<'EOF'
#!/usr/bin/env bash
# Fake curl: answers by URL, and keeps what it was handed — each bearer token, the
# probe URL — in $SEEN, so a test can prove the credential still reached the request.
url="" bearer=""
for a in "$@"; do
  case "$a" in
    [Aa]uthorization:\ Bearer\ *) bearer=${a#*Bearer } ;;
    http*) url=$a ;;
  esac
done
case "$url" in
  */workers/subdomain)      printf '%s\n' "$bearer" >> "$SEEN/cloudflare-bearer"; echo '{"success":true,"result":{}}' ;;
  https://api.github.com/*) printf '%s\n' "$bearer" >> "$SEEN/github-bearer"; printf 200 ;;
  */healthz)                printf ok ;;
  */mcp/*)                  printf '%s\n' "$url" >> "$SEEN/probe-url"; echo '{"jsonrpc":"2.0","id":1,"result":{}}' ;;
esac
EOF
  cat > "$SB/bin/node" <<'EOF'
#!/usr/bin/env bash
# Fake node: setup.sh only runs `node -e <script> [dot.path]` to pick a field out of
# the JSON on stdin. Answers by dot-path: the account has no subdomain yet, registering
# one succeeds, and (no path) the worker's secret list is empty.
cat > /dev/null
case "${3:-}" in
  success) echo true ;;
  *)       echo ;;
esac
EOF
  cat > "$SB/bin/openssl" <<'EOF'
#!/usr/bin/env bash
# Fake openssl: `rand -hex 4` names the subdomain, `rand -base64 48` is the path secret.
case "${2:-}" in
  -hex)    echo cafe ;;
  -base64) echo "$PATH_CANARY" ;;
esac
EOF
  # npm passes the dependency check, sleep never stalls a run, and pbcopy — the first
  # clipboard tool setup.sh tries — keeps the canary URL off the real clipboard.
  printf '#!/usr/bin/env bash\n' > "$SB/bin/npm"
  printf '#!/usr/bin/env bash\n' > "$SB/bin/sleep"
  printf '#!/usr/bin/env bash\ncat > /dev/null\n' > "$SB/bin/pbcopy"
  chmod +x "$SB/bin"/*
  export PATH="$SB/bin:$PATH"
}

# 1. xtrace must never trace a credential. Under `bash -x` — or an xtrace inherited
# through an exported SHELLOPTS — bash would print the Wrangler OAuth token and the
# pasted GitHub PAT as it assigns them and hands them to curl and wrangler. The path
# secret is the one value setup.sh shows on purpose: once, inside the connector URL on
# stdout, never in a trace. Each route also proves it was live: the trace of the
# script's own `set +x` shows xtrace was on at startup, and the fakes show every
# credential still arrived where it was going.
setup_sandbox
for route in "bash -x" "env SHELLOPTS=xtrace bash"; do   # word-split on purpose below
  rm -f "$SEEN"/*
  printf '%s\n' "$PAT_CANARY" | $route "$SETUP" > "$SB/out" 2> "$SB/err"; rc=$?
  out=$(cat "$SB/out"); err=$(cat "$SB/err")
  assert_rc "$rc" 0 "$route: setup runs to the end"
  assert_contains "$err" "set +x" "$route: xtrace was on when the script started"
  assert_eq "$(cat "$SEEN/cloudflare-bearer")" "$OAUTH_CANARY"$'\n'"$OAUTH_CANARY" "$route: both Cloudflare calls still carry the OAuth token"
  assert_eq "$(cat "$SEEN/github-bearer")" "$PAT_CANARY" "$route: GitHub still gets the PAT to verify"
  assert_eq "$(cat "$SEEN/put-GITHUB_TOKEN")" "$PAT_CANARY" "$route: the PAT is still stored on the worker"
  assert_eq "$(cat "$SEEN/put-MCP_PATH_SECRET")" "$PATH_CANARY" "$route: the path secret is still stored on the worker"
  assert_contains "$(cat "$SEEN/probe-url")" "/mcp/$PATH_CANARY" "$route: the probe still uses the path secret"
  assert_contains "$out" "/mcp/$PATH_CANARY" "$route: the connector URL is still shown"
  assert_lacks "$out$err" "$OAUTH_CANARY" "$route: never prints the OAuth token"
  assert_lacks "$out$err" "$PAT_CANARY" "$route: never prints the PAT"
  assert_lacks "$err" "$PATH_CANARY" "$route: never traces the path secret"
done
t_teardown

t_report
