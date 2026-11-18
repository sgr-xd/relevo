# Relevo — working rules

Relevo is an open-source Claude Code plugin plus a small CLI for people with
several Claude subscription accounts (work, personal, client orgs): named profiles, one-command
switching, and continuing the same conversation on another account. Read `docs/BRIEF.md` first.

## Hard safety rules

- **Never touch the owner's real logins.** Tests and experiments use throwaway `CLAUDE_CONFIG_DIR`
  folders under a temp dir. Never run `claude auth login|logout` or `claude setup-token` against
  the default profile, never modify `~/.claude`, `~/.claude.json` or Keychain entries.
- **Never read, print, log or copy credentials**: no Keychain secret reads (`security
  find-generic-password -w`), no reading `.credentials.json`, no OAuth tokens in env vars,
  argv, files or test output. The design must keep credentials where Claude Code puts them.
- **No auto-rotation.** The tool suggests a switch; a person always runs it. Never market or
  build "get around usage limits" behaviour — this is multi-account / multi-org profiles.
- No calls to undocumented Anthropic endpoints. Remaining-limit data comes only from Claude Code
  itself: its status-line `rate_limits` input, or its own `/usage` command run headless
  (`claude -p "/usage" --no-session-persistence`, no model call). Relevo never calls an
  Anthropic endpoint directly.
- Name: Relevo (Spanish for relay handoff). "Claude" must never be part of the product name (Anthropic trademark). The name
  lives in one place so a rename is cheap.

## Engineering

- Cross-platform (macOS, Linux, Windows). Tests use real processes and real temp folders; the
  only fake is a stub `claude` binary for flows that would need a login.
- Every security-relevant behaviour gets a negative test. Never claim a pass without running it;
  check each gate step's exit code explicitly (no `set -e` reliance).
- Few, well-known dependencies; justify each in the commit message.

## Git

- Identity and push credentials are configured repo-locally; do not change git config.
- Milestone branches `r<N>-<slug>`; merge to `main` only after the orchestrator approves.
- No GitHub remote yet — commit locally, do not create repos or push.
- End commit messages with: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
