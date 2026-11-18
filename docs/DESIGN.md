# Relevo design

**Status (2026-11-18):** D0 was paused after a DROP verdict, then resumed with a narrower scope:
package the owner's working prototype (`cc-as`) as the Relevo plugin. What sets it apart from
claude-swap, ccs and hatswap is an in-session `/relevo switch <name>`: the session closes and the same
conversation reopens on another account, in the same terminal, without touching tokens or
Keychain entries. Milestones R1 (package), R2 (/relevo account, usage, status line), R3 (docs).
macOS and Linux only for v0.1.

## R1 decisions

| Question | Decision | Evidence |
|---|---|---|
| `/relevo switch` without a model turn | A plugin hooks module (`plugin/hooks/register.ts`) registers one command, `/relevo`, with `$.command.register` (since 0.2.0; earlier versions also registered bare switch and account commands, which a future Claude Code built-in could clash with). Its `command.run` hook answers `{ text, isTextDisplayOnly }` with no `next`, so no model turn starts. | `claude -p "/switch p2"`: `num_turns 0`, zero API requests, even with no login and no API key |
| How the session closes | The mod queues `/exit` via `$.clock.after(300)`. A `command.run` hook may not call `$.command.run` itself (host check: "it would wait on the turn this hook is holding"). If `/exit` is refused, it falls back to SIGTERM on `CLAUDE_PID`. | pty run: SessionEnd `prompt_input_exit`, then the wrapper resumed the same session id on the other profile |
| Session id and Claude's PID | `$.process.hookEnv()` gives `CLAUDE_CODE_SESSION_ID`, `CLAUDE_PID`, `CLAUDE_PROJECT_DIR`. The host environment (`RELEVO_WRAPPER`, `RELEVO_PROFILE`, `CLAUDE_CONFIG_DIR`) is inherited. | spike log |
| Name clash with a user `commands/switch.md` (the prototype) | Before 0.2.0 the module's switch command ran, not the user command (`-p` test). Since 0.2.0 there is no clash: the module's command is `/relevo` | `-p` test |
| CLI language | Bash, 3.2-compatible, with no python/node/jq: coreutils, sed, awk and BSD-or-GNU `date` only | suite passes on macOS bash 3.2 and Debian bash 5.2 |
| CLI on PATH | A plugin cannot put a command on the shell's PATH: its `bin/` reaches only Claude's Bash tool. One step instead: `/relevo install` (in a session, no model turn) copies the CLI to `~/.claude-profiles/.bin/relevo` and links `~/.local/bin/relevo` to it. Each session start runs `relevo _sync`, which refreshes that copy, so plugin updates reach the PATH command. | real-binary `-p` run |
| Same session open in two profiles | Prevented by order: the wrapper reopens only after the first session has exited (D0 finding #1 shows the harm otherwise) | switch-loop tests |
| Tokens | None. No `user_config` secrets and no setup-token. `relevo add <email>` runs Claude Code's own `claude auth login --claudeai --email …` for the new profile folder, then checks `claude auth status`. | fake-claude tests |
| Login expiry | From `loginExpiresAt` in `claude auth status --json`, with a warning under `warn_days` (plugin option, default 5). `/relevo switch` to a signed-out or expired profile is refused. Whether using a profile extends its expiry is **unknown** (not testable without real logins). | tests |
| New profile folders | Neutral `acc<N>` names, because a folder can never be renamed (the login is tied to its path). Names live in `.names` and can change freely. | — |

## R2 decisions

| Question | Decision | Evidence |
|---|---|---|
| Live usage | `claude -p "/usage" --output-format json --no-session-persistence`, run per account in parallel, each stopped after 20 s (`RELEVO_USAGE_TIMEOUT`). Results are reused for 60 s. Kept: lines containing `% used`, except those starting `Last ` or `Top `. A result with `num_turns > 0` is flagged and not used. Allowed by the amended working rule (owner, 2026-11-18). | CLI tests: parallel (3 × 2 s in under 5 s), timeout, cache, model-turn guard |
| Hook noise from the checks | Run from an empty temp folder with `--setting-sources project --strict-mcp-config`, so the shared settings' hooks, plugins and MCP servers do not start. | throwaway profile: SessionStart/SessionEnd stopped firing, about 1.0 s down to 0.8 s. **Not verified:** that OAuth `/usage` still answers with these flags (needs a real login) |
| Fallback | `relevo statusline` writes `~/.claude-profiles/.usage/<target>.json` (0600, atomic), in the same shape the prototype's status line used | status-line tests |
| Status-line segment | `"statusLine": {"type": "command", "command": "relevo statusline"}`. A plugin cannot set it. Shows `name · 5h N% · 7d N% · model`, plus a login warning under `warn_days`. The profile comes from `RELEVO_PROFILE`, else `CLAUDE_CONFIG_DIR`, else `transcript_path` (for scrubbed environments). Login expiry comes from a cache refreshed in the background every 6 h, so a refresh never starts claude in the foreground. | pty: `jane · Opus 5.5` from real input |
| 100% on /relevo switch | `_switch` checks the target (live, or last seen if no live answer). At a limit it exits 4 with Claude Code's own line, reset time included. The mod then asks "Switch anyway?" (`$.ui.ask`). Stay, a closed question, or `-p` all mean no switch. | module + CLI tests |
| Rate-limit stop | The mod hooks `classic.StopFailure` (`error: rate_limit`) and runs `relevo _limited`. That records the stop and names the signed-in account with the most room. The suggestion goes out as a transcript notice (`$.ui.log`, not sent to the model) and a notification (`$.ui.notify`). Never switches. | pty with a fake 429: notice shown. The notification itself was not observed |
| Plugin settings in the terminal | `_sync` at session start writes `warn_days` to `~/.claude-profiles/.prefs`, which the terminal CLI and status line read | CLI test |

## D0 findings (kept for reference)

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
| 6 | A skill line `` !`relevo account --session ${CLAUDE_SESSION_ID}` `` with `allowed-tools: Bash(relevo account:*)` received the real session id, `CLAUDE_CONFIG_DIR`, `RELEVO_PROFILE`, variables exported through `CLAUDE_ENV_FILE`, and PWD set to the session cwd. A `!` command that contains `$VAR` is refused ("A variable in this command can't be checked before it runs"). | `/relevo account` is feasible: pass the session id as an argument and let the CLI read the environment. |
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
| What `/relevo account` can know | Session id, profile, cwd: all available (#5, #6) | Status-line environment in interactive mode |

Not started: milestones S1… with acceptance criteria.
