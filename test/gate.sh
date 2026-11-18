#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The Relevo authors
# The release gate. Each step's exit code is checked on its own (no set -e).
#   test/gate.sh            CLAUDE_BIN=<path> picks the claude used for plugin checks (default: claude)
# Linux runs in a debian:12-slim container when Docker is up; otherwise that step says SKIPPED.
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
failed=0

step() {  # name, command...
  local name="$1" code; shift
  "$@" > "${TMPDIR:-/tmp}/relevo-gate.out" 2>&1
  code=$?
  if [ "$code" = 0 ]; then echo "PASS  $name"
  else echo "FAIL  $name (exit $code)"; tail -15 "${TMPDIR:-/tmp}/relevo-gate.out" | sed 's/^/      /'; failed=1; fi
}

step "CLI tests, macOS/system bash ($(/bin/bash -c 'echo $BASH_VERSION'))" "$ROOT/test/run.sh" /bin/bash
step "plugin manifest and module validate" "$CLAUDE_BIN" plugin validate "$ROOT/plugin"
step "plugin module tests" "$CLAUDE_BIN" plugin test "$ROOT/plugin"
if docker info > /dev/null 2>&1; then
  step "CLI tests, Linux (debian:12-slim, GNU coreutils)" \
    docker run --rm --network none -v "$ROOT":/src:ro debian:12-slim bash /src/test/run.sh /bin/bash
else
  echo "SKIPPED  CLI tests, Linux (Docker is not running)"
fi

[ "$failed" = 0 ] && echo "gate: all steps passed" || echo "gate: FAILED"
exit "$failed"
