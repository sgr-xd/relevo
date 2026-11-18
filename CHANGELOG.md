# Changelog

All notable changes to Relevo. Versions follow `version` in `plugin/.claude-plugin/plugin.json`.

## [Unreleased]

Version 0.2.0. Breaking: the slash commands moved.

### Changed

- `/switch <name>` is now `/relevo switch <name>`, and `/account` is now `/relevo account`.
  Relevo registers only `/relevo`, so a future Claude Code built-in can never clash with
  one of its commands. There are no bare aliases.
- `relevo help` and `/relevo help` list commands in two groups, "Inside Claude Code" and "In
  a terminal", on one screen. Inside a session the inside group comes first, and
  terminal-only commands are marked. The longer explanation moved to `relevo help --more`.

### Fixed

- `/relevo switch` takes exactly one account name. Extra words or anything starting with `-`
  get the usage line and never reach the CLI. Before, `/switch bob --anyway` skipped the
  usage-limit question and closed the session; only the person's "Switch anyway" adds it now.
- The parallel-check test no longer depends on timing: the three checks must meet at a barrier.

### Added

- Tests: only `/relevo` is registered; the plugin's in-session allowlist equals the CLI's
  list; the help's inside group is exactly that list. The release check fails on a bare
  `/switch` or `/account` in shipped files.

## [0.1.3] - 2026-11-18

### Fixed

- The note under the table for a full window read "until in 18h12m, seen 29m ago" when the
  reset came from the status line. It now says "(resets in 18h12m, seen 29m ago)", and
  "(resets Nov 19 9:29am)" for a live answer.

## [0.1.2] - 2026-11-18

### Fixed

- `relevo list` and `/account` stopped with "unbound variable" in a UTF-8 terminal on
  macOS's bash 3.2, which read `$foot⚠` as one variable name. Variables before non-ASCII text
  are now braced; a static check and a run under a UTF-8 locale guard it.

## [0.1.1] - 2026-11-18

### Changed

- `/account` and `relevo list` show one table: a row per account with login days left, a
  10-step bar and percentage per usage window (5-hour, weekly, per-model weekly) and when the
  fullest window resets. Anything that needs a person (a full window, a login about to expire,
  a signed-out account) is listed under the table with what to do.
- README: the comparison table says Relevo is public (since 2026-11-18).
- The release check runs trufflehog offline (`--no-verification`), so no candidate string
  is ever sent to another service to be checked.

### Added

- Contributing guide, code of conduct, security policy, issue and pull-request templates,
  CODEOWNERS and Dependabot for GitHub Actions. CI actions are pinned to commit SHAs.

## [0.1.0] - 2026-11-18

### Added

- `relevo` CLI: `add` (Claude Code's own sign-in for a new profile), `list` and `account`
  (login expiry, live 5-hour and weekly usage from Claude Code's `/usage`), `rename`,
  `names`, `new`, `fix`, `install`, and the session wrapper behind `/switch`.
- Plugin: `/switch`, `/account` and `/relevo`, answered without a model turn; a usage-limit
  notice that names the account with the most room and never switches by itself.
- `relevo statusline` segment, release checklist and CI on Linux and macOS.
