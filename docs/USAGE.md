# Using Relevo

## Set up

1. **Install the plugin** in Claude Code:
   ```text
   /plugin marketplace add sgr-xd/relevo
   /plugin install relevo@relevo
   ```
   From a shell: `claude plugin install relevo --marketplace sgr-xd/relevo`.
2. **Put `relevo` on your PATH.** A plugin can't do this by itself: its own commands reach only
   Claude's tools, not your shell. Run this once, inside Claude Code:
   ```text
   /relevo install
   ```
   It copies the CLI to `~/.claude-profiles/.bin/relevo` and links `~/.local/bin/relevo` to it.
   Each session start refreshes that copy, so plugin updates reach the command too. If
   `~/.local/bin` is not on your PATH yet, add it in your shell profile. Claude Code's own
   installer uses the same folder.
3. **Add an account:**
   ```sh
   relevo add jane.doe@work.example          # --sso for single sign-on, --name to pick the name
   ```
   This creates a profile folder (`~/.claude-profiles/acc2`, `acc3`, …), links everything except
   the login to `~/.claude`, and opens Claude Code's own sign-in page. Afterwards, Relevo checks
   which account actually signed in. If it's a different email, the profile is named after that
   email and you get a notice.
4. **Name existing profiles** (if you made some by hand): `relevo names` names every profile
   after the part of its email before the @. `relevo rename <name> <new>` changes one.
5. **Status line (optional, one manual step).** A plugin can't set the status line, so put this
   in `~/.claude/settings.json`, replacing any `statusLine` you have:
   ```json
   "statusLine": { "type": "command", "command": "relevo statusline" }
   ```
   It shows `jane.doe · 5h 12% · 7d 40% · Opus`, adds a warning when the login expires soon,
   and remembers the usage it sees for `relevo list`.
6. **Start every session through Relevo (optional, recommended).** Add this line to your shell
   profile (`~/.zshrc` or `~/.bashrc`), then open a new terminal:
   ```sh
   command -v relevo > /dev/null && claude() { relevo start "$@"; }
   ```
   Plain `claude` then opens the default account (the one you last switched to), and every
   session can `/relevo switch` in place. Claude Code's own tools are unaffected: a `claude` run
   from inside a session keeps that session's account. `command claude` skips Relevo.

**Coming from a hand-made setup?** If you have a personal `~/.claude/commands/switch.md`,
delete it after installing: Relevo's command is `/relevo switch`, and the old one would run
your old script. Profile folders and `.names` in `~/.claude-profiles` keep working as they are.
Never rename a profile folder: Claude Code ties the login to the folder's path.

## Everyday use

| In a terminal | Does |
|---|---|
| `relevo <name> [claude args]` | Start Claude Code as that account. `relevo run <name>` is the same, for a name that matches a command |
| `relevo start [claude args]` | Start Claude Code as the default account: the one you last switched to (main until then) |
| `relevo default [<name>]` | Show or set the default account |
| `relevo list` | Every account: login expiry, and its 5-hour and weekly usage, live from Claude Code's `/usage` |
| `relevo list --cached` | The same without the live check: what the status line last saw |
| `relevo add <email> [--sso] [--name <n>]` | Add an account through Claude Code's sign-in page |
| `relevo rename <name> <new>`, `relevo names` | Change names (`names` replaces renames with email-based names) |
| `relevo new <folder>`, `relevo fix <name>` | Empty profile without signing in; re-create shared links |

| In a Claude Code session | Does |
|---|---|
| `/relevo switch <name>` | Close this session and reopen the same conversation on that account, in this terminal |
| `/relevo account` | The account table, with this session's account marked |
| `/relevo default [<name>]` | Show or set the account new sessions open as |
| `/relevo list`, `/relevo install`, … | The CLI commands that are safe inside a session |

None of these slash commands starts a model turn. Their output is for you and is not sent to
the model.

### How /relevo switch works

`relevo <name>` starts Claude Code inside a small wrapper. `/relevo switch bob` checks that `bob` is
signed in, the login hasn't expired, and it isn't at a usage limit. It then leaves a note for
the wrapper and closes the session the normal way (`/exit`). The wrapper reopens the same
conversation with `claude --resume <id>` on bob's profile, from the project folder.

- If `bob` is at 100% of a limit, `/relevo switch` shows Claude Code's own line, with the reset time,
  and asks "Switch anyway?". Nothing happens unless you say so.
- If `bob`'s login has expired, it says: `Sign in again: relevo bob, then /login`.
- `bob` becomes the default account: `relevo start` (and plain `claude`, with the shell line
  from step 6) opens bob from then on. `relevo <name>` never changes the default.
- In a session started with plain `claude` (without that line), it can't reopen itself. It
  prints the command instead, `cd <project> && relevo bob --resume <id>`, and still makes bob
  the default.
- The reopened session gets only `--resume`; other flags from the first start (such as
  `--model`) are not carried over.

### When an account stops on its limit

When a turn ends on a rate limit, Relevo posts a notice in the session, plus a desktop
notification. It says which signed-in account has the most room and gives the exact `/relevo switch`
line. It never switches by itself.

## Limits and caveats

- **macOS and Linux only.** Windows is planned, not built.
- **Logins last about 30 days** from sign-in. `relevo list`, `/relevo account` and the status line
  show the expiry and warn when fewer than 5 days are left (change it with the plugin's
  "Login warning (days)" setting). **We do not know whether using an account extends its
  login**; we have not been able to test it without real logins. To renew: `relevo <name>`,
  then `/login`.
- **One conversation, one account at a time.** Opening the same conversation in two accounts at
  once (a second terminal with `claude --resume`, or a second `relevo`) is not detected by
  Claude Code. Both sessions write into the same transcript and the conversation forks: one
  account's replies silently drop out of it. `/relevo switch` never does this, because it closes the
  session before reopening it.
- **Usage checks start Claude Code** once per account, all at once, from an empty temporary
  folder, with only project settings. So your hooks, plugins and MCP servers don't run for
  them. Each check stops after 20 seconds (`RELEVO_USAGE_TIMEOUT`), and results are reused
  for 60 seconds. Usage numbers exist only for Pro, Max and Ultra subscriptions (per Claude
  Code's docs).
- **Plugin API.** The commands use Claude Code's hooks-module API, which is marked early
  access; a Claude Code update may need a Relevo update. Tested on Claude Code 2.1.327.
- **Not about limits.** Relevo keeps separate accounts apart and lets a conversation move to
  the account it belongs on. Use each account within its organisation's rules and Anthropic's
  terms.

## What Relevo touches

| Path | What |
|---|---|
| `~/.claude-profiles/<folder>/` | One profile per account. Its login stays here, written by Claude Code; everything else links to `~/.claude` |
| `~/.claude-profiles/.names` | `name folder` pairs |
| `~/.claude-profiles/.default` | The default account's folder (`main` for `~/.claude`) |
| `~/.claude-profiles/.switch/` | Short-lived notes from `/relevo switch` to the wrapper |
| `~/.claude-profiles/.usage/` | Last-seen usage, live results, login-expiry cache |
| `~/.claude-profiles/.bin/relevo`, `~/.local/bin/relevo` | The CLI copy and its link (`relevo install`) |
| `~/.claude-profiles/.prefs` | The plugin's warning-days setting, for the terminal |

Relevo never reads a password, token or credential file. It never signs in or out on your
default account. It never calls an Anthropic server itself: login dates come from
`claude auth status --json`, and usage from Claude Code's status line and `/usage`.

## Troubleshooting

- **`relevo: command not found`**: run `/relevo install` in Claude Code, and check that
  `~/.local/bin` is on your PATH.
- **`/relevo switch` says the session was not started with relevo**: exit and run the command it
  printed. To stop seeing this, add the shell line from step 6 of setup.
- **A new `claude` opens the wrong account**: `relevo default` says which one it opens;
  `relevo default <name>` changes it. Without the shell line from step 6, plain `claude` always
  opens your first account.
- **A setting you changed in one account didn't stick**: something replaced that profile's
  shared link with a real file. Run `relevo fix <name>`; it says which item it is.
