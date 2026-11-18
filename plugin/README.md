# Relevo plugin

Named profiles for several Claude accounts (work, personal, client organisations), each signed in
once in its own `CLAUDE_CONFIG_DIR` folder, with settings, plugins and session history shared.
`/switch <name>` closes the session and reopens the same conversation on another account in the
same terminal; `/account` lists your accounts with login expiry and 5-hour / weekly usage. The
commands answer without a model turn and never handle passwords or tokens.

After installing, run `/relevo install` once to put the `relevo` command on your PATH.
Full documentation: [README](../README.md) and [docs/USAGE.md](../docs/USAGE.md). License: Apache-2.0.
