# Changelog

All notable changes to Relevo. Versions follow `version` in `plugin/.claude-plugin/plugin.json`.

## [Unreleased]

### Added

- Contributing guide, code of conduct, security policy, issue and pull-request templates,
  CODEOWNERS and Dependabot for GitHub Actions. CI actions are pinned to commit SHAs.

### Changed

- The release check runs trufflehog offline (`--no-verification`), so no candidate string
  is ever sent to another service to be checked.

## [0.1.0] - 2026-11-18

### Added

- `relevo` CLI: `add` (Claude Code's own sign-in for a new profile), `list` and `account`
  (login expiry, live 5-hour and weekly usage from Claude Code's `/usage`), `rename`,
  `names`, `new`, `fix`, `install`, and the session wrapper behind `/switch`.
- Plugin: `/switch`, `/account` and `/relevo`, answered without a model turn; a usage-limit
  notice that names the account with the most room and never switches by itself.
- `relevo statusline` segment, release checklist and CI on Linux and macOS.
