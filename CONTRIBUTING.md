# Contributing to Relevo

Thank you for helping. Relevo has one maintainer, [@sgr-xd](https://github.com/sgr-xd), and
welcomes issues and pull requests.

## Before you start

- **Bugs and ideas:** open an issue first for anything bigger than a small fix, so we agree on
  the approach before you spend time on it.
- **Security problems:** never in a public issue. See [SECURITY.md](SECURITY.md).
- **Conduct:** this project follows the [Code of Conduct](CODE_OF_CONDUCT.md).

## Making a change

1. Fork the repository and branch from `main`.
2. Set up: No build step. You need bash, git and a POSIX userland; macOS's own bash 3.2 must keep working.
3. Run the checks before you push:

   ```sh
   test/run.sh /bin/bash          # the CLI suite: temp HOME, fake claude, no network
   test/gate.sh                   # also claude plugin validate / test (needs Claude Code)
   ```

4. Keep one change per pull request. New behaviour needs tests.
5. Add a line to `CHANGELOG.md` under **Unreleased**.
6. Open a pull request against `main`. `main` takes changes only through pull requests whose
   checks pass: no direct pushes, no force pushes, linear history.

## Rules this project keeps

- Never read, print or copy a credential, token or Keychain secret, and never sign in or out on someone's default profile. Tests use a temporary HOME and the fake `claude` in `test/fake/`.
- Never switch an account on the person's behalf. Relevo suggests; a person runs `/switch`.
- Usage data comes only from Claude Code itself (its status line or its `/usage` command), never from a direct call to an Anthropic endpoint.
- Every security-relevant behaviour gets a negative test.
- Few dependencies; justify any new one in the pull request.

## License

By contributing, you agree that your contribution is licensed under the
[Apache License 2.0](LICENSE), the license of this project.
