#!/usr/bin/env bash
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
SECRET="$PLUGIN/bin/brain-secret"
S() { bash "$SECRET" "$@"; }

# every test gets its own sandbox: a fake bws on PATH, a JSON fixture, a token file
secret_setup() {
  t_setup
  mkdir -p "$SB/bin" "$SB/conf"
  cat > "$SB/bin/bws" <<'EOF'
#!/usr/bin/env bash
# Fake bws for tests: `bws --color no -o json secret list|get [id]`, reads
# $BWS_FIXTURE (a JSON array of {id,key,value,note} objects). Mirrors the real
# bws CLI's JSON output — never TSV/table, since values here contain tabs/newlines.
set -euo pipefail
shift 2  # --color no
shift 2  # -o json
cmd=$1; shift
case "$cmd" in
  secret)
    sub=$1; shift
    case "$sub" in
      list) cat "$BWS_FIXTURE" ;;
      get)
        id=$1
        python3 -c '
import json, sys
data = json.load(open(sys.argv[2]))
match = [s for s in data if s["id"] == sys.argv[1]]
if not match:
    sys.exit(1)
json.dump(match[0], sys.stdout)
' "$id" "$BWS_FIXTURE"
        ;;
    esac
    ;;
esac
EOF
  chmod +x "$SB/bin/bws"
  # ids are real UUIDs — brain-secret routes a UUID-shaped arg straight to `bws
  # secret get`, so the fixture must match that shape for the "get by id" tests to
  # exercise it. id-5 has a value containing embedded newlines and tabs — the exact
  # shape that broke the old TSV parser. id-6's value contains another secret's key
  # as a substring, to prove `list` never leaks value text.
  ID1=11111111-1111-4111-8111-111111111111
  ID2=22222222-2222-4222-8222-222222222222
  ID3=33333333-3333-4333-8333-333333333333
  ID4=44444444-4444-4444-8444-444444444444
  ID5=55555555-5555-4555-8555-555555555555
  ID6=66666666-6666-4666-8666-666666666666
  export ID1 ID2 ID3 ID4 ID5 ID6
  python3 -c '
import json, os
secrets = [
    {"id": os.environ["ID1"], "key": "FOO_KEY", "value": "foo-value", "note": ""},
    {"id": os.environ["ID2"], "key": "BAR_KEY", "value": "bar-value", "note": ""},
    {"id": os.environ["ID3"], "key": "DUP_KEY", "value": "dup-value-1", "note": ""},
    {"id": os.environ["ID4"], "key": "DUP_KEY", "value": "dup-value-2", "note": ""},
    {"id": os.environ["ID5"], "key": "MULTILINE_KEY", "value": "line one\nline\ttwo\nline three", "note": ""},
    {"id": os.environ["ID6"], "key": "REFERRING_KEY", "value": "contains FOO_KEY inside it", "note": ""},
]
print(json.dumps(secrets))
' > "$SB/fixture.json"
  export BWS_FIXTURE="$SB/fixture.json"
  echo tok > "$SB/conf/bws-token"; chmod 600 "$SB/conf/bws-token"
  export BRAIN_SECRETS_TOKEN_FILE="$SB/conf/bws-token"
  export PATH="$SB/bin:$PATH"
}

# 1. list: ids + keys, never values (including value fragments from other secrets)
secret_setup
out=$(S list)
assert_contains "$out" "$ID1	FOO_KEY" "list shows id + key"
assert_contains "$out" "$ID2	BAR_KEY" "list shows second id + key"
assert_lacks "$out" "foo-value" "list never prints values"
assert_lacks "$out" "line one" "list never prints multiline value text"
assert_lacks "$out" "contains FOO_KEY inside it" "list never prints value text that echoes another key"
t_teardown

# 2. get by exact key
secret_setup
out=$(S get FOO_KEY)
assert_eq "$out" "foo-value" "get by key returns the value"
t_teardown

# 3. get by id
secret_setup
out=$(S get "$ID2")
assert_eq "$out" "bar-value" "get by id returns the value"
t_teardown

# 4. multi-line/tab value: get by key and get by id must be byte-identical
secret_setup
by_key=$(S get MULTILINE_KEY | xxd)
by_id=$(S get "$ID5" | xxd)
assert_eq "$by_key" "$by_id" "multiline value identical whether fetched by key or id"
raw=$(S get MULTILINE_KEY)
assert_contains "$raw" "line one" "multiline value line 1 intact"
assert_contains "$raw" "line	two" "multiline value embedded tab intact"
assert_contains "$raw" "line three" "multiline value line 3 intact"
t_teardown

# 5. ambiguous key -> exit 2, friendly error, no value leaked
secret_setup
out=$(S get DUP_KEY 2>&1); rc=$?
assert_rc "$rc" 2 "ambiguous key exits 2"
assert_contains "$out" "ambiguous" "ambiguous key error message"
assert_lacks "$out" "dup-value" "ambiguous error never leaks a value"
t_teardown

# 6. unknown id/key -> exit 2, friendly error
secret_setup
out=$(S get NOPE 2>&1); rc=$?
assert_rc "$rc" 2 "unknown key exits 2"
assert_contains "$out" "no secret found" "unknown key error message"
t_teardown

# 7. missing bws -> exit 2, friendly error, mentions install
secret_setup
out=$(PATH="/usr/bin:/bin" S list 2>&1); rc=$?
assert_rc "$rc" 2 "missing bws exits 2"
assert_contains "$out" "bws not found" "missing bws error message"
assert_contains "$out" "brew install bws" "missing bws error suggests install"
t_teardown

# 8. missing token file -> exit 2, friendly error
secret_setup
out=$(BRAIN_SECRETS_TOKEN_FILE="$SB/conf/does-not-exist" S list 2>&1); rc=$?
assert_rc "$rc" 2 "missing token file exits 2"
assert_contains "$out" "no token file" "missing token file error message"
t_teardown

# 9. help / bogus usage
secret_setup
out=$(S help 2>&1); assert_contains "$out" "brain-secret list" "help prints usage"
S bogus >/dev/null 2>&1; assert_rc "$?" 2 "bogus subcommand exits 2"
t_teardown

t_report
