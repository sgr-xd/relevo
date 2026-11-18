# Relevo brief

> Historical: the brief D0 started from. What was built and why is in [DESIGN.md](DESIGN.md).

## Problem

People with more than one Claude subscription account (work + personal, several client orgs)
must log out and sign in again to switch, losing their place in the conversation.

## Idea

1. **Profiles**: each account is a separate `CLAUDE_CONFIG_DIR`, signed in once. Everything except
   the login is shared with the main profile by links: settings, plugins, skills, agents,
   commands, memory, `projects/` (session history). `.claude.json` stays per profile — it holds the
   account.
2. **CLI**: `add <name>`, `list`, `remove <name>`, `run <name> [--resume <session-id>] [-- claude args]`,
   `status` (last-seen remaining 5-hour / weekly % per profile), `doctor`.
3. **Plugin**: `/relevo account` (active profile + every profile's last-seen %, and the exact command to
   continue this conversation on another profile); a status-line segment; a `StopFailure` hook
   (matcher `rate_limit`) that records the event and notifies — it never switches by itself.

## Verified facts (orchestrator spike, Claude Code 2.1.327, macOS)

- A fresh `CLAUDE_CONFIG_DIR` reports `loggedIn: false` while the default stays logged in: logins
  are per config folder. With the variable set, `.claude.json` lives inside that folder.
- Status-line input carries `rate_limits` with `five_hour` / `seven_day` (`used_percentage`,
  `resets_at`).
- Hook event `StopFailure`: "fires instead of Stop when an API error (rate limit, auth failure,
  etc.) ended the turn. Fire-and-forget — hook output and exit codes are ignored." Matcher values
  include rate_limit.
- Each session is its own file under `projects/`, so different sessions never write the same file.
- Linux/Windows: credentials are a file inside the config folder (per docs; not yet tested).

## Open (resolve in D0)

- Language and distribution: one artifact that runs on macOS/Linux/Windows from a plugin
  (Node single-file vs Go binaries vs portable shell). Recommend with evidence.
- How links behave on Windows (junctions vs symlinks vs copies) and on plugin updates.
- Whether shared `projects/` is safe if the SAME session is resumed in two profiles at once
  (must be prevented or detected).
- What `/relevo account` can know about the running session's profile and session id.
- An independent existence check of competing tools is running in the orchestrator; if it finds
  this already exists natively in Claude Code, the project stops.

## Milestones

| # | Slug | Delivers |
|---|---|---|
| D0 | design | `docs/DESIGN.md` answering every open point above with spikes in temp folders; proposed milestones S1… with acceptance criteria. No product code yet. |

Further milestones are defined from D0 after review.

## Reporting

After each milestone: commit on the branch, then SendMessage to the Claude session named
`innovation`: branch, commit, what was verified and how, gaps, questions. Wait for review.

## Name

**Relevo** — Spanish for a relay handoff / changing of the guard: another account takes over and carries on the same conversation. Command: `relevo`. Never hard-code the local folder name: it may change.
