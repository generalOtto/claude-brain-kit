#!/usr/bin/env bash
# Runs every *.test.sh in this directory; exits non-zero if any fails.
cd "$(dirname "$0")" || exit 2
shopt -s nullglob
rc=0
for t in *.test.sh; do
  echo "== $t"
  bash "$t" || rc=1
done
exit $rc
