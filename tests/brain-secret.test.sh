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
# Fake bws for tests: `bws --color no -o json secret list|get [id]`. `list` prints
# $BWS_FIXTURE (a JSON array of {id,key,value,note} objects), `get` prints
# $BWS_FIXTURE_DIR/<id>.json. Mirrors the real bws CLI's JSON output — never
# TSV/table, since values here contain tabs/newlines. Plain bash on purpose: the
# parser-probe tests run it with a failing python3 on PATH.
set -euo pipefail
shift 2  # --color no
shift 2  # -o json
cmd=$1; shift
case "$cmd" in
  secret)
    sub=$1; shift
    case "$sub" in
      list) cat "$BWS_FIXTURE" ;;
      get)  cat "$BWS_FIXTURE_DIR/$1.json" 2>/dev/null || exit 1 ;;
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
  ID7=77777777-7777-4777-8777-777777777777
  ID8=88888888-8888-4888-8888-888888888888
  export ID1 ID2 ID3 ID4 ID5 ID6 ID7 ID8
  # The fixture is raw UTF-8 with LF line ends, like real bws output — written as
  # bytes so a native Windows python can't translate newlines or re-encode it. The
  # directory is passed as an argument so Git Bash hands that python a Windows path.
  # id-7's value is non-ASCII, to prove a value survives as the same UTF-8 bytes.
  # id-8's key starts with "/" (spelled in two pieces so Git Bash leaves the script
  # argument alone) — the shape Git Bash rewrites into a Windows path.
  mkdir -p "$SB/fixtures"
  python3 -c '
import json, os, sys
out = sys.argv[1]
secrets = [
    {"id": os.environ["ID1"], "key": "FOO_KEY", "value": "foo-value", "note": ""},
    {"id": os.environ["ID2"], "key": "BAR_KEY", "value": "bar-value", "note": ""},
    {"id": os.environ["ID3"], "key": "DUP_KEY", "value": "dup-value-1", "note": ""},
    {"id": os.environ["ID4"], "key": "DUP_KEY", "value": "dup-value-2", "note": ""},
    {"id": os.environ["ID5"], "key": "MULTILINE_KEY", "value": "line one\nline\ttwo\nline three", "note": ""},
    {"id": os.environ["ID6"], "key": "REFERRING_KEY", "value": "contains FOO_KEY inside it", "note": ""},
    {"id": os.environ["ID7"], "key": "UNICODE_KEY", "value": "p" + chr(0xe4) + "ss " + chr(0x2713), "note": ""},
    {"id": os.environ["ID8"], "key": "/" + "prod/db/password", "value": "slash-value", "note": ""},
]
def dump(name, obj):
    with open(os.path.join(out, name), "wb") as f:
        f.write(json.dumps(obj, ensure_ascii=False).encode("utf-8"))
dump("list.json", secrets)
for s in secrets:
    dump(s["id"] + ".json", s)
' "$SB/fixtures"
  export BWS_FIXTURE="$SB/fixtures/list.json" BWS_FIXTURE_DIR="$SB/fixtures"
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

# 4b. a value comes out as the exact bytes stored — a native Windows python writes
# \r\n for every \n in text mode, which corrupts multi-line values
secret_setup
want=$(printf 'line one\nline\ttwo\nline three' | xxd -p | tr -d '\n')
assert_eq "$(S get MULTILINE_KEY | xxd -p | tr -d '\n')" "$want" "multiline value is byte-exact (LF stays LF)"
assert_eq "$(S get UNICODE_KEY | xxd -p | tr -d '\n')" "70c3a4737320e29c93" "non-ASCII value is the same UTF-8 bytes"
assert_eq "$(S list | tr -cd '\r' | wc -c | tr -d ' ')" "0" "list output has no carriage returns"
t_teardown

# 4c. a key that starts with "/": on its way to a native Windows python or jq, Git
# Bash would rewrite the argument into a Windows path and the lookup would miss
secret_setup
assert_contains "$(S list)" "$ID8	/prod/db/password" "list shows a key that starts with /"
out=$(S get /prod/db/password 2>&1); rc=$?
assert_rc "$rc" 0 "get by a key that starts with / exits 0"
assert_eq "$out" "slash-value" "get by a key that starts with / returns the value"
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

# --- parser probe: an interpreter counts only if it actually runs -----------------
# store_stub <dir> <name>... — commands that are on PATH but fail when run, like the
# Microsoft Store app-execution alias Windows ships as python3.exe / python.exe:
# `command -v` finds it, running it prints "Python was not found" and exits 49.
store_stub() {
  local dir=$1 n; shift
  mkdir -p "$dir"
  for n in "$@"; do
    cat > "$dir/$n" <<'EOF'
#!/usr/bin/env bash
echo "Python was not found; run without arguments to install from the Microsoft Store, or disable this shortcut from Settings > Apps > Advanced app settings > App execution aliases." >&2
exit 49
EOF
    chmod +x "$dir/$n"
  done
}
# The interpreter binary itself (not a shim that might re-enter PATH), so the tests
# can offer it under another name while `python3` is a failing stub.
REAL_PY=$(python3 -c 'import sys; print(sys.executable)' | tr -d '\r')

# 10. python3 is a failing stub, `python` works -> falls through to python
secret_setup
store_stub "$SB/stub" python3
cat > "$SB/stub/python" <<EOF
#!/usr/bin/env bash
exec "$REAL_PY" "\$@"
EOF
chmod +x "$SB/stub/python"
out=$(PATH="$SB/stub:$PATH" S get FOO_KEY 2>&1); rc=$?
assert_rc "$rc" 0 "failing python3 stub: exits 0 via the next interpreter"
assert_eq "$out" "foo-value" "failing python3 stub: value still returned"
out=$(PATH="$SB/stub:$PATH" S list 2>&1)
assert_contains "$out" "$ID1	FOO_KEY" "failing python3 stub: list still works"
assert_lacks "$out" "Python was not found" "failing python3 stub: its message never surfaces"
t_teardown

# 11. python3 and python are failing stubs, the `py -3` launcher works
secret_setup
store_stub "$SB/stub" python3 python
cat > "$SB/stub/py" <<EOF
#!/usr/bin/env bash
[ "\$1" = "-3" ] || exit 64
shift
exec "$REAL_PY" "\$@"
EOF
chmod +x "$SB/stub/py"
out=$(PATH="$SB/stub:$PATH" S get "$ID2" 2>&1); rc=$?
assert_rc "$rc" 0 "py launcher fallback: exits 0"
assert_eq "$out" "bar-value" "py launcher fallback: value returned"
t_teardown

# 12. nothing on PATH actually runs -> exit 2 with an honest message, not the stub's
secret_setup
store_stub "$SB/stub" python3 python py jq
out=$(PATH="$SB/stub:$PATH" S list 2>&1); rc=$?
assert_rc "$rc" 2 "no working parser exits 2"
assert_contains "$out" "brain-secret: no working JSON parser" "no working parser: says what is wrong"
assert_contains "$out" "jq" "no working parser: names the jq alternative"
assert_lacks "$out" "Python was not found" "no working parser: the stub's message never surfaces"
t_teardown

# 13. no python at all, jq present -> jq parses (skipped where jq isn't installed)
if command -v jq >/dev/null 2>&1; then
  secret_setup
  store_stub "$SB/stub" python3 python py
  out=$(PATH="$SB/stub:$PATH" S list 2>&1)
  assert_contains "$out" "$ID1	FOO_KEY" "jq fallback: list works"
  assert_lacks "$out" "foo-value" "jq fallback: list never prints values"
  assert_eq "$(PATH="$SB/stub:$PATH" S get FOO_KEY 2>&1)" "foo-value" "jq fallback: get by key"
  want=$(printf 'line one\nline\ttwo\nline three' | xxd -p | tr -d '\n')
  assert_eq "$(PATH="$SB/stub:$PATH" S get "$ID5" | xxd -p | tr -d '\n')" "$want" "jq fallback: multiline value is byte-exact"
  t_teardown
fi

t_report
