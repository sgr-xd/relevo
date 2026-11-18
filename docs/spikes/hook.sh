#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The Relevo authors
# Spike hook: records event input plus a few env facts. Never prints credentials:
# only names of env vars, plus CLAUDE_CONFIG_DIR / RELEVO_PROFILE values.
in=$(cat); printf "%s" "$in" > "$SPIKE_DIR/last-$1.json"; exec 2>>"$SPIKE_DIR/hook-stderr.txt"
node -e '
const [inp, log] = process.argv.slice(1);
const fs = require("fs");
let j; try { j = JSON.parse(inp); } catch { j = { raw: inp }; }
fs.appendFileSync(log, JSON.stringify({
  event: j.hook_event_name, input: j,
  env: { CLAUDE_CONFIG_DIR: process.env.CLAUDE_CONFIG_DIR ?? null,
         RELEVO_PROFILE: process.env.RELEVO_PROFILE ?? null,
         CLAUDE_ENV_FILE: process.env.CLAUDE_ENV_FILE ?? null,
         CLAUDE_CODE_CHILD_SESSION: process.env.CLAUDE_CODE_CHILD_SESSION ?? null,
         ppid: process.ppid }
}) + "\n");
' "$in" "$SPIKE_DIR/hooks.jsonl"
if [ "$1" = "SessionStart" ] && [ -n "$CLAUDE_ENV_FILE" ]; then
  sid=$(printf '%s' "$in" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).session_id))')
  echo "export RELEVO_SESSION_ID=$sid" >> "$CLAUDE_ENV_FILE"
fi
exit 0
