#!/usr/bin/env bash
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
SECRET="$PLUGIN/bin/brain-secret"
S() { bash "$SECRET" "$@"; }

# every test gets its own sandbox: a fake bws on PATH, a fixture, a token file
secret_setup() {
  t_setup
  mkdir -p "$SB/bin" "$SB/conf"
  cat > "$SB/bin/bws" <<'EOF'
#!/usr/bin/env bash
# Fake bws for tests: `bws --color no -o tsv secret list|get [id]`, reads $BWS_FIXTURE.
set -euo pipefail
shift 2  # --color no
shift 2  # -o tsv
shift    # secret
cmd=$1; shift
case "$cmd" in
  list)
    printf 'id\tkey\tvalue\n'
    cat "$BWS_FIXTURE"
    ;;
  get)
    id=$1
    printf 'id\tkey\tvalue\n'
    awk -F'\t' -v id="$id" '$1==id' "$BWS_FIXTURE"
    ;;
esac
EOF
  chmod +x "$SB/bin/bws"
  cat > "$SB/fixture.tsv" <<'EOF'
id-1	FOO_KEY	foo-value
id-2	BAR_KEY	bar-value
id-3	DUP_KEY	dup-value-1
id-4	DUP_KEY	dup-value-2
EOF
  export BWS_FIXTURE="$SB/fixture.tsv"
  echo tok > "$SB/conf/bws-token"; chmod 600 "$SB/conf/bws-token"
  export BRAIN_SECRETS_TOKEN_FILE="$SB/conf/bws-token"
  export PATH="$SB/bin:$PATH"
}

# 1. list: ids + keys, never values
secret_setup
out=$(S list)
assert_contains "$out" "id-1  FOO_KEY" "list shows id + key"
assert_contains "$out" "id-2  BAR_KEY" "list shows second id + key"
assert_lacks "$out" "foo-value" "list never prints values"
t_teardown

# 2. get by exact key
secret_setup
out=$(S get FOO_KEY)
assert_eq "$out" "foo-value" "get by key returns the value"
t_teardown

# 3. get by id
secret_setup
out=$(S get id-2)
assert_eq "$out" "bar-value" "get by id returns the value"
t_teardown

# 4. ambiguous key -> exit 2, friendly error, no value leaked
secret_setup
out=$(S get DUP_KEY 2>&1); rc=$?
assert_rc "$rc" 2 "ambiguous key exits 2"
assert_contains "$out" "ambiguous" "ambiguous key error message"
assert_lacks "$out" "dup-value" "ambiguous error never leaks a value"
t_teardown

# 5. unknown id/key -> exit 2, friendly error
secret_setup
out=$(S get NOPE 2>&1); rc=$?
assert_rc "$rc" 2 "unknown key exits 2"
assert_contains "$out" "no secret found" "unknown key error message"
t_teardown

# 6. missing bws -> exit 2, friendly error, mentions install
secret_setup
out=$(PATH="/usr/bin:/bin" S list 2>&1); rc=$?
assert_rc "$rc" 2 "missing bws exits 2"
assert_contains "$out" "bws not found" "missing bws error message"
assert_contains "$out" "brew install bws" "missing bws error suggests install"
t_teardown

# 7. missing token file -> exit 2, friendly error
secret_setup
out=$(BRAIN_SECRETS_TOKEN_FILE="$SB/conf/does-not-exist" S list 2>&1); rc=$?
assert_rc "$rc" 2 "missing token file exits 2"
assert_contains "$out" "no token file" "missing token file error message"
t_teardown

# 8. help / bogus usage
secret_setup
out=$(S help 2>&1); assert_contains "$out" "brain-secret list" "help prints usage"
S bogus >/dev/null 2>&1; assert_rc "$?" 2 "bogus subcommand exits 2"
t_teardown

t_report
