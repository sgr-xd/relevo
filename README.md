# Relevo

Several Claude accounts, one Claude Code, and `/relevo switch` to carry a conversation from one account
to another in the same terminal.

Relevo is for people with more than one Claude subscription account that belong to different
places: a work account from an employer, a personal one, accounts in client organisations. Each
account is signed in once, in its own folder. Everything else (settings, plugins, skills, memory,
session history) is shared. When a conversation belongs on another account, type
`/relevo switch <name>`: the session closes and reopens on that account with the same conversation.

Relevo never handles passwords or tokens. Each login stays where Claude Code put it, and Relevo
never switches an account by itself.

```text
$ relevo list
Accounts

   Account    Login   5-hour            Week, all models   Resets
   me         25d     —                 ███████░░░  71%    Nov 22 6:30am
   jane.doe   27d     █░░░░░░░░░  12%   ████░░░░░░  40%    Nov 22 6:30am

$ relevo jane.doe          # Claude Code, signed in as jane.doe
> /relevo switch me        # same conversation, now on the "me" account
```

## Install

macOS or Linux, Claude Code 2.1.327 or later.

1. In Claude Code:
   ```text
   /plugin marketplace add sgr-xd/relevo
   /plugin install relevo@relevo
   ```
2. Still in Claude Code, put the `relevo` command on your PATH (a plugin cannot do this itself):
   ```text
   /relevo install
   ```
   This links `~/.local/bin/relevo`. Check it in a new terminal with `relevo list`.
3. Add your accounts: `relevo add you@work.example`. Claude Code's own sign-in page opens in
   the browser. Add `--sso` for single sign-on.

The rest of setup, every command and the status line are in [docs/USAGE.md](docs/USAGE.md).

## What to know before you rely on it

- **macOS and Linux only** for now.
- **Logins expire** about 30 days after sign-in. Relevo shows the date and warns 5 days ahead.
  We do not know whether using an account extends its login, and have not been able to test it.
- **Never open one conversation in two accounts at once** (for example `claude --resume` in a
  second terminal). Claude Code does not detect it: both write into one transcript, and one
  account's replies drop out of the conversation. `/relevo switch` avoids this by closing the session
  before it reopens it.
- **Usage numbers come only from Claude Code itself:** its status line, or its `/usage` command
  run in the background. Each check starts Claude Code once per account (no model call).
- **Use each account for what it is for.** Relevo is for keeping work, personal and client
  accounts apart, not for getting around anyone's limits. When an account stops on its limit,
  Relevo says which of your accounts has room. Whether to continue there is your decision,
  within your organisation's rules and Anthropic's terms.

## How it compares

All four are open source. Facts come from each project's own README and GitHub on 2026-11-18.

| | **Relevo** | [claude-swap](https://github.com/realiti4/claude-swap) | [ccs](https://github.com/kaitranntt/ccs) | [hatswap](https://github.com/orvi2014/hatswap) |
|---|---|---|---|---|
| Size and age | New: public since 2026-11-18 | 4,790 stars; since Jan 2026; last push Nov 15 | 2,907 stars; since Nov 2025; last push Nov 16 | 1 star, 28 commits; since Oct 11 2026; last push Oct 21 |
| How accounts are kept apart | One `CLAUDE_CONFIG_DIR` folder per account, as Claude Code's docs suggest. Logins never move | Copies the account's login into place on each switch (Keychain or credential files) and keeps backups of every login | Separate account folders by default (mechanism not described) | One `CLAUDE_CONFIG_DIR` folder per account. "No credentials are read, copied or modified" |
| Shared history, `--resume` across accounts | Yes | Yes (default) | Opt-in "shared context groups" | Yes (default); an account can keep its own private history |
| Move a running conversation to another account | `/relevo switch <name>` in the session; it reopens in the same terminal | `cswap switch` in any terminal; the running session picks up the new login | Not stated | `/switch` or `/handoff` in the session (after `hatswap install-command`); restarts Claude Code |
| Automatic switching | Never | Yes: `cswap auto` switches at a usage threshold (default 90%) | Not stated | Never |
| Usage source | Claude Code's status line, and its `/usage` command | "The usage endpoint" (not named); optional probe request | Not stated | "The same endpoint Claude's `/usage` reads"; its README says this is not a public API |
| Other providers | No | No | Yes: Gemini, Copilot and OpenRouter, through a proxy | OpenAI Codex |
| Platforms | macOS, Linux | macOS, Linux/WSL, Windows | macOS, Linux, Windows | macOS, Linux |
| Needs | bash | Python 3.12+ | npm | Python 3, bash 3.2+ |

Pick claude-swap if you need Windows or automatic switching, or ccs if you also route to other
providers. hatswap is closest to Relevo's design (a folder per account, an in-session switch command,
no automatic switching). It adds Codex and private per-account history, and it reads usage
from the endpoint behind `/usage` instead of running `/usage`. Pick Relevo if you want usage
only from Claude Code's own commands, a `/relevo switch` that asks before moving to a full account,
and no model turn for any of its commands.

## Contributing

Issues and pull requests are welcome: see [CONTRIBUTING.md](CONTRIBUTING.md). Report security
problems privately, as [SECURITY.md](SECURITY.md) describes.

## License

Apache-2.0. See [LICENSE](LICENSE). Relevo is not made by or affiliated with Anthropic.
