# Security policy

## Reporting a vulnerability

Report it privately, through GitHub: on this repository open **Security → Report a
vulnerability** ([direct link](https://github.com/sgr-xd/relevo/security/advisories/new)). Please do not open a public issue, pull request
or discussion about it.

Say what you found, how to reproduce it, and what it affects. This project has one maintainer,
who aims to answer within a week and will credit you in the fix unless you ask otherwise.

## In scope

Anything that could anything that could expose a login, token or credential; run a command taken from untrusted input; write outside `~/.claude-profiles` and `~/.local/bin/relevo`; or switch an account without the person asking.

## Supported versions

Only the latest release gets security fixes.
