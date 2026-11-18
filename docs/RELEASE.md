# Release checklist

Before the repository goes public, and before each release after that. Every step is a command
whose exit code decides; nothing is "looked at".

1. **Gate:** `test/gate.sh` passes. It runs the CLI suite under the system bash (3.2 on
   macOS), `claude plugin validate`, the module tests, and the Linux suite in Docker when
   Docker runs. Once pushed, `.github/workflows/test.yml` runs the suite on `ubuntu-latest`
   and `macos-latest` as well.
2. **Release check:** `RELEVO_PRIVATE_TERMS="<your user name>|<employer>|<real email>" test/release-check.sh`
   passes. It fails on any of these:
   - a path inside someone's home folder or a system temp folder
   - email addresses other than `*.example` and noreply addresses
   - the private terms you pass, in files or in git history (never commit them)
   - a source file without its `SPDX-License-Identifier: Apache-2.0` header, or LICENSE and
     `plugin.json` disagreeing
   - unfinished-work markers (the script lists which) left anywhere
   - any finding from `gitleaks` or `trufflehog` over the whole history
   - uncommitted changes (what gets checked must be what gets pushed)
3. **Version:** bump `version` in `plugin/.claude-plugin/plugin.json`. Users stay on the
   version they have until it changes.
4. **Claude Code version:** if this release was tested on a newer Claude Code, update
   `engines.claude-code` in `plugin.json` and the version named in README and USAGE.
5. **Repository:** create it public only after steps 1 and 2 pass on the commit you push.
   Install from it once, on a machine other than the development one:
   `/plugin marketplace add <owner>/relevo`, `/plugin install relevo@relevo`, `/relevo install`,
   `relevo list`.
