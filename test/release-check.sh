#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The Relevo authors
# Checks before the repository goes public. Each check's exit code is taken on its own.
#   RELEVO_PRIVATE_TERMS="name1|name2" test/release-check.sh
# RELEVO_PRIVATE_TERMS: extra words that must not appear (your user name, employer, real
# emails). They are passed in, never written into the repository.
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$ROOT" || exit 1
failed=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | head -10 | sed 's/^/      /'; failed=1; }

files="$(git ls-files)"
# this script names the patterns it looks for, so it is the one file not scanned
tracked() { printf '%s\n' "$files" | grep -vE '^(LICENSE|test/release-check\.sh)$' | tr '\n' '\0' | xargs -0 grep -nIE "$@" 2>/dev/null; }

hits="$(tracked '/Users/[A-Za-z0-9._-]+|/home/[a-z][a-z0-9_-]+/|/private/(tmp|var)/|C:\\\\Users\\\\')"
[ -z "$hits" ] && pass "no personal home or temp paths" || fail "personal home or temp paths" "$hits"

hits="$(tracked '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' \
  | grep -vE '@([a-z0-9-]+\.)*example(\.[a-z]+)?|noreply@anthropic\.com|users\.noreply\.github\.com|@(v[0-9]|latest)\b')"
[ -z "$hits" ] && pass "no real email addresses (only example.* and noreply)" || fail "email addresses" "$hits"

if [ -n "${RELEVO_PRIVATE_TERMS:-}" ]; then
  hits="$(tracked -i "$RELEVO_PRIVATE_TERMS")"
  log="$(git log --format='%an %ae %s %b' | grep -iE "$RELEVO_PRIVATE_TERMS")"
  [ -z "$hits$log" ] && pass "no private terms in files or history" || fail "private terms" "$hits$log"
else
  echo "SKIP  private terms (set RELEVO_PRIVATE_TERMS)"
fi

missing=""
for f in $(printf '%s\n' "$files" | grep -E '\.(sh|ts|mjs|yml)$|^plugin/bin/|^test/fake/'); do
  head -3 "$f" | grep -q 'SPDX-License-Identifier: Apache-2.0' || missing="$missing $f"
done
[ -z "$missing" ] && pass "every source file has an SPDX header" || fail "SPDX header missing:$missing"
grep -q '"license": "Apache-2.0"' plugin/.claude-plugin/plugin.json && head -2 LICENSE | grep -q 'Apache License' \
  && pass "LICENSE and plugin.json agree (Apache-2.0)" || fail "license mismatch"

hits="$(tracked -i 'switchyard')"   # the working folder's name, which may change: never shipped
[ -z "$hits" ] && pass "the local folder name is not hard-coded" || fail "local folder name in shipped files" "$hits"

hits="$(tracked 'TODO|FIXME|link needed')"
[ -z "$hits" ] && pass "no TODO, FIXME or 'link needed' left" || fail "unfinished text" "$hits"

if command -v gitleaks > /dev/null; then
  out="$(gitleaks git --no-banner --redact . 2>&1)"; code=$?
  [ "$code" = 0 ] && pass "gitleaks: no secrets in history" || fail "gitleaks found something (exit $code)" "$out"
else echo "SKIP  gitleaks not installed"; fi
if command -v trufflehog > /dev/null; then
  out="$(trufflehog git "file://$ROOT" --no-update --no-verification --fail --json 2> /dev/null)"; code=$?
  [ "$code" = 0 ] && pass "trufflehog: no candidate secrets (checked offline)" || fail "trufflehog found something (exit $code)" "$out"
else echo "SKIP  trufflehog not installed"; fi

[ -z "$(git status --porcelain)" ] && pass "working tree clean (what is checked is what is committed)" \
  || fail "uncommitted changes: commit, then run again" "$(git status --short)"

[ "$failed" = 0 ] && echo "release check: all passed" || echo "release check: FAILED"
exit "$failed"
