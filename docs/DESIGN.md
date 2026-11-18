# Relevo design (D0) — WIP, paused

**Status: paused on 2026-11-18 by the orchestrator.** The existence check returned DROP (many
existing account switchers, e.g. claude-swap, ccs, hatswap; Anthropic's `CLAUDE_CONFIG_DIR` docs
already suggest one config folder per account). The owner decides whether to drop or build anyway.
This file holds what D0 had established when it stopped. It does not yet propose milestones S1…

## How the spikes ran

Claude Code 2.1.327 (native Mach-O build), macOS arm64. Every run used `env -i` with a throwaway
`HOME` and throwaway `CLAUDE_CONFIG_DIR` folders under a temp dir. `ANTHROPIC_BASE_URL` pointed at a
local fake Messages API (`docs/spikes/fake-api.mjs`, 127.0.0.1 only), with a dummy API key string
that is not a credential. No login, no Keychain, no real `~/.claude` was involved. Hooks were
recorded by `docs/spikes/hook.sh`. A stand-in "main" folder held settings, CLAUDE.md, skills,
agents, commands, plugins and projects, and two profiles linked to it with symlinks.

## Verified by experiment

| # | Finding | Consequence |
|---|---|---|
| 1 | The same session resumed in two profiles at once was **not detected**. Both processes appended to one transcript. The second one added a synthetic `No response requested.` reply after the first one's pending turn, and the first profile's real reply ended up on an orphaned branch. The JSON was not corrupted, but the conversation diverged silently. | Concurrent resume must be prevented. Detecting it afterwards is not enough. |
| 2 | `--resume <id> --fork-session` creates a new session id and a new file with the full history copied. The original file is untouched. SessionStart reports `source: "fork"`. | The handoff should fork by default, so two writers never share one file. |
| 3 | Running sessions register in `<config>/sessions/<pid>.json` (`sessionId`, `cwd`, `procStart`, …). This is per config folder, removed on exit, and undocumented. | Relevo can scan every profile's `sessions/` for best-effort detection. It must not depend on that format. |
| 4 | `--resume <id>` works from any cwd and appends to the original file, but the new turns record the new cwd. | The handoff command must `cd` to the session's original cwd. |
| 5 | Hook `transcript_path` uses the literal `CLAUDE_CONFIG_DIR` prefix (the profile path, not the link target). The hook environment carries `CLAUDE_CONFIG_DIR`, custom variables such as `RELEVO_PROFILE`, and `CLAUDE_CODE_CHILD_SESSION=1`. SessionStart gets a `CLAUDE_ENV_FILE` under `<config>/session-env/<sid>/`. | The profile can be identified from the environment, or from `transcript_path` when the environment is scrubbed. |
| 6 | A skill line `` !`relevo account --session ${CLAUDE_SESSION_ID}` `` with `allowed-tools: Bash(relevo account:*)` received the real session id, `CLAUDE_CONFIG_DIR`, `RELEVO_PROFILE`, variables exported through `CLAUDE_ENV_FILE`, and PWD set to the session cwd. A `!` command that contains `$VAR` is refused ("A variable in this command can't be checked before it runs"). | `/account` is feasible: pass the session id as an argument and let the CLI read the environment. |
| 7 | StopFailure fires on HTTP 429 with error `rate_limit`. Its input is `session_id, prompt_id, transcript_path, cwd, effort, error, last_assistant_message`. HTTP 500 gives `server_error`. In `-p` mode the hook process was cut off at exit: a shell `printf` finished, but a Node child did not. Tested with API-key auth only, and not in interactive mode. | The StopFailure handler must be near-instant. This favours a native binary. |
| 8 | `claude plugin marketplace add/install/disable` through a profile wrote through a symlinked `settings.json`. The link survived. | Symlinks work for shared files on macOS. |
| 9 | A **hard-linked** `settings.json` was replaced on its first write (new inode, link count 1), so the profiles silently diverged. | Hard links are ruled out, including as a Windows fallback. |
| 10 | `installed_plugins.json` records `installPath` under the profile path when a profile installs. The main profile still loaded the plugin from its own plugins root after the profile folder was removed (git-sourced plugin). | Deleting a profile does not break the main profile's plugins (2.1.327). |
| 11 | Nothing was written outside `CLAUDE_CONFIG_DIR` in the fake HOME. Per-profile files Claude created: `.claude.json`, `backups/`, `session-env/`, `sessions/`. `projects/<p>/memory/` appears in the shared projects folder. | The list of things to share and things to keep per profile is known. |
| 12 | **Inconclusive:** neither a symlinked nor an `@import` user CLAUDE.md appeared in the API request in this harness. The cause was not found. | Re-test before relying on either form. |

## From the docs (not run)

- `CLAUDE_CONFIG_DIR` docs suggest `alias claude-work='CLAUDE_CONFIG_DIR=~/.claude-work claude'`
  for multiple accounts.
- `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` removes `CLAUDE_CONFIG_DIR` from hook and Bash environments.
- `CLAUDE_CODE_PLUGIN_CACHE_DIR` relocates the plugins root.
- Plugins cannot set `statusLine`, and `${CLAUDE_PLUGIN_ROOT}` changes on every plugin update, so a
  status-line segment must call a CLI on PATH. A plugin's `bin/` is on the Bash tool's PATH only.
- On Windows, hooks and status lines run in Git Bash, or in PowerShell when Git Bash is absent.
  `CLAUDE_ENV_FILE` is not available to PowerShell hooks.
- `rate_limits` is present only for Pro/Max/Ultra subscribers, and only after the first API
  response in a session.
- The native installer ships a standalone binary (confirmed locally), so Node is not guaranteed.

## Where each open point stood

| Open point | Leaning | Evidence still missing |
|---|---|---|
| Language and distribution | A Go static binary (stdlib only). The plugin stays thin and calls `relevo` on PATH. | Binary sizes, Windows and Linux runs |
| Links on Windows | Directories: junctions. Files: symlinks (needs Developer Mode), since hard links are ruled out (#9). Fallback could be `--settings`. | Every Windows claim is unverified |
| Same session in two profiles | Fork on handoff (#2). Best-effort live check across profiles' `sessions/` (#3). Possibly a UserPromptSubmit block. | Interactive-mode test |
| What `/account` can know | Session id, profile, cwd: all available (#5, #6) | Status-line environment in interactive mode |

Not started: milestones S1… with acceptance criteria.
