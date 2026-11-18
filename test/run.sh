#!/bin/bash
# Relevo CLI tests. Each test gets a fresh temp HOME and a fake `claude` (test/fake/claude) first
# on PATH; nothing touches the real ~/.claude, a real login or the network.
#   test/run.sh [bash]    run the CLI under that bash (default /bin/bash: 3.2 on macOS)
# Exit code: 0 when every check passes, 1 otherwise.
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
CLI="${RELEVO_CLI:-$ROOT/plugin/bin/relevo}"   # RELEVO_CLI: run against another copy (mutation checks)
SH="${1:-/bin/bash}"
SID=0a1b2c3d-1111-4222-8333-444455556666
PASS=0 FAIL=0 FAILED=""

check() {  # description, then a command that must succeed
  local d="$1"; shift
  if "$@"; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); FAILED="$FAILED\n  ✘ $CASE: $d"; fi
}
has()   { printf '%s' "$1" | grep -qF -- "$2"; }
hasnt() { ! printf '%s' "$1" | grep -qF -- "$2"; }

epoch_iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%S.000Z; }
in_days() { epoch_iso $(( $(date +%s) + $1 * 86400 + 3600 )); }   # +1h so "N days" reads N

setup() {  # fresh HOME with a stand-in ~/.claude
  CASE="$1"
  T="$(mktemp -d "${TMPDIR:-/tmp}/relevo-test.XXXXXX")"; T="$(cd -P "$T" && pwd -P)"
  H="$T/home"; B="$H/.claude-profiles"
  mkdir -p "$H/.claude/agents" "$H/.claude/commands" "$H/.claude/skills" "$H/.claude/plugins" \
           "$H/.claude/projects" "$T/proj"
  echo '{}' > "$H/.claude/settings.json"; echo '# shared' > "$H/.claude/CLAUDE.md"
  : > "$T/claude.log"; : > "$T/plan"
}
cleanup() { rm -rf "$T"; }
# run the CLI the way a person's shell would, with only the fake claude on PATH
r() {
  (cd "${CWD:-$T/proj}" && env -i HOME="$H" PATH="$ROOT/test/fake:/usr/bin:/bin" TERM=dumb \
    FAKE_LOG="$T/claude.log" FAKE_PLAN="$T/plan" FAKE_SID="$SID" FAKE_RELEVO="$SH $CLI" \
    FAKE_EXPIRY="$(in_days 30)" ${EXTRA:-} "$SH" "$CLI" "$@" 2>&1)
}
auth() { mkdir -p "$1"; printf '%s\n' "$2" > "$1/fake-auth"; }   # dir, "email expiry" | out | garbage
profile() { r new "$1" > /dev/null; auth "$B/$1" "$2"; }
log() { cat "$T/claude.log"; }
mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }   # GNU first: BSD stat -c fails, GNU stat -f means something else
no_request() { [ ! -d "$B/.switch" ] || [ -z "$(ls -A "$B/.switch")" ]; }

# ---------------------------------------------------------------------------------------------
setup "bash version"
v="$("$SH" -c 'echo "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"')"
echo "CLI runs under bash $v ($SH)"
check "static: no bash-4-only syntax" \
  bash -c "! grep -nE 'declare -A|local -n|mapfile|readarray|coproc|\\\$\\{[a-zA-Z_]+(,,|\\^\\^)|\\|&' '$CLI'"
check "static: the CLI never reads credentials or runs logout / setup-token" \
  bash -c "! grep -nE '\\.credentials|security (find|dump|delete)|auth logout|setup-token|keychain' '$CLI'"
cleanup

setup "list"
auth "$H/.claude" "me@home.example $(in_days 20)"
profile acc2 "jane.doe@work.example $(in_days 3)"
profile acc3 "out"
profile acc4 "old@client.example $(in_days -2)"
profile acc5 "garbage"
r names > /dev/null
out="$(r list)"
check "main is listed by its name, signed in" bash -c "printf '%s\\n' '$out' | grep -qE '^me +\\(main\\) +signed in · login expires in 20 days'"
check "expiry shown as days and date" has "$out" "login expires in 20 days ($(in_days 20 | cut -c1-10))"
check "under 5 days is flagged" has "$out" "login expires in 3 days ($(in_days 3 | cut -c1-10))  ← sign in again soon"
check "20 days is not flagged" bash -c "printf '%s' '$out' | grep 'in 20 days' | grep -vqF 'sign in again soon'"
check "signed-out profile" has "$out" "NOT signed in"
check "expired login says how to sign in again" has "$out" "login expired $(in_days -2 | cut -c1-10)  ← sign in again: relevo old, then /login"
check "unreadable status" has "$out" "status unknown"
out="$(EXTRA=RELEVO_WARN_DAYS=25 r list)"
check "warning threshold is configurable" bash -c "printf '%s' '$out' | grep 'in 20 days' | grep -qF 'sign in again soon'"
cleanup

setup "names"
auth "$H/.claude" "Sam@home.example $(in_days 20)"
profile acc2 "sam@work.example $(in_days 20)"
profile acc3 "Sam+Client@other.example $(in_days 20)"
profile acc4 "list@x.example $(in_days 20)"
profile acc5 "out"
out="$(r names)"
check "names from the email's local part, lower-cased" grep -qx 'sam main' "$B/.names"
check "duplicate gets -2" grep -qx 'sam-2 acc2' "$B/.names"
check "invalid characters become -" grep -qx 'sam-client acc3' "$B/.names"
check "a command word is never a name" grep -qx 'list-2 acc4' "$B/.names"
check "signed-out profile left unnamed" has "$out" "acc5     not signed in, left unnamed"
check "names file is private" [ "$(mode "$B/.names")" = 600 ]
out="$(r rename sam-2 work)"
check "rename" grep -qx 'work acc2' "$B/.names"
out="$(r rename work sam)"; check "rename refuses a taken name" has "$out" "'sam' is already taken"
out="$(r rename work list)"; check "rename refuses a command word" has "$out" "'list' is already taken"
cleanup

setup "run by name"
auth "$H/.claude" "me@home.example $(in_days 20)"
profile acc2 "jane@work.example $(in_days 20)"
r names > /dev/null
echo "exit 7" > "$T/plan"
out="$(r jane --model x)"; code=$?
check "profile runs with its own CLAUDE_CONFIG_DIR" has "$(log)" "run cfg=$B/acc2 profile=acc2"
check "claude args are passed through" has "$(log)" "args=--model x"
check "claude's exit code is kept" [ "$code" = 7 ]
: > "$T/claude.log"; rm -f "$T/plan.n"; : > "$T/plan"
r me > /dev/null
check "the default profile runs with CLAUDE_CONFIG_DIR unset" has "$(log)" "run cfg=UNSET profile=main"
: > "$T/claude.log"
r run acc2 > /dev/null
check "run <folder> works too" has "$(log)" "run cfg=$B/acc2"
out="$(r nobody)"; code=$?
check "unknown name is refused" has "$out" "no account named 'nobody'"
check "unknown name exits 1" [ "$code" = 1 ]
out="$(r ../acc2)"; check "path-like names are refused" has "$out" "names use a-z"
check "nothing ran for refused names" bash -c "[ \$(grep -c '^run ' '$T/claude.log') = 1 ]"
cleanup

setup "switch loop"
auth "$H/.claude" "me@home.example $(in_days 20)"
profile acc2 "jane@work.example $(in_days 20)"
profile acc3 "bob@client.example $(in_days 20)"
r names > /dev/null
mkdir -p "$T/proj/sub"
printf 'switch bob\nswitch me\nexit 0\n' > "$T/plan"
out="$(CWD="$T/proj/sub" EXTRA="FAKE_PROJECT=$T/proj" r jane)"; code=$?
L="$(log)"
check "first session on jane" has "$L" "run cfg=$B/acc2 profile=acc2 pwd=$T/proj/sub args="
check "switch accepted" has "$L" "switch-exit=0 out=Switching to bob"
check "reopened on bob with the same conversation" has "$L" "run cfg=$B/acc3 profile=acc3 pwd=$T/proj args=--resume $SID"
check "then on main, CLAUDE_CONFIG_DIR unset" has "$L" "run cfg=UNSET profile=main pwd=$T/proj args=--resume $SID"
check "three sessions in turn, never two at once" [ "$(grep -c '^run ' "$T/claude.log")" = 3 ]
check "tells the person" has "$out" "↪ continuing this conversation as bob"
check "exit code of the last session" [ "$code" = 0 ]
check "request removed afterwards" [ -z "$(ls -A "$B/.switch")" ]
cleanup

setup "switch refusals"
auth "$H/.claude" "me@home.example $(in_days 20)"
profile acc2 "jane@work.example $(in_days 20)"
profile acc3 "out"
profile acc4 "old@client.example $(in_days -1)"
r names > /dev/null; r rename acc3 nologin > /dev/null
printf 'switch nobody\nswitch jane\nswitch nologin\nswitch old\nswitch \nswitch a/b\n' > "$T/plan"
for i in 1 2 3 4 5 6; do r jane > /dev/null; done
L="$(log)"
check "unknown name" has "$L" "switch-exit=3 out=No account named 'nobody'"
check "same account" has "$L" "switch-exit=3 out=Already on jane."
check "signed-out account" has "$L" "switch-exit=3 out=nologin is not signed in. Sign in again: relevo nologin, then /login"
check "expired login" has "$L" "switch-exit=3 out=old is not signed in (login expired $(in_days -1 | cut -c1-10)). Sign in again: relevo old, then /login"
check "no name" has "$L" "switch-exit=3 out=usage: /switch <name>"
check "path in name" has "$L" "switch-exit=3 out=No account named 'a/b'"
check "no session reopened after a refusal" [ "$(grep -c '^run ' "$T/claude.log")" = 6 ]
check "no request left behind" [ -z "$(ls -A "$B/.switch")" ]
cleanup

setup "not started via relevo"
auth "$H/.claude" "me@home.example $(in_days 20)"
profile acc2 "jane@work.example $(in_days 20)"
r names > /dev/null
out="$(EXTRA="CLAUDE_CODE_SESSION_ID=$SID CLAUDE_PROJECT_DIR=$T/proj" r _switch jane)"; code=$?
check "prints the manual command" has "$out" "Exit, then run:  cd $T/proj && relevo jane --resume $SID"
check "exits 3 (nothing to close)" [ "$code" = 3 ]
out="$(EXTRA="CLAUDE_CODE_SESSION_ID=$SID RELEVO_WRAPPER=999999" r _switch jane)"
check "a wrapper that is gone counts as not started via relevo" has "$out" "was not started with relevo"
out="$(EXTRA="CLAUDE_CODE_SESSION_ID=nope RELEVO_WRAPPER=$$" r _switch jane)"; code=$?
check "outside a Claude Code session" has "$out" "doesn't look like a Claude Code session"
check "no request written" no_request
cleanup

setup "tampered switch request"
auth "$H/.claude" "me@home.example $(in_days 20)"
profile acc2 "jane@work.example $(in_days 20)"
r names > /dev/null
printf 'inject ../../etc\\n%s\\n\n' "$SID" > "$T/plan"
out="$(r jane)"; code=$?
check "target outside the profiles is refused" has "$out" "no profile '../../etc' in switch request"
printf 'inject acc2\\n$(touch %s/pwned)\\n\n' "$T" > "$T/plan"; rm -f "$T/plan.n"
out="$(r jane)"
check "bad session id is refused" has "$out" "bad session id in switch request"
check "nothing relaunched" [ "$(grep -c '^run ' "$T/claude.log")" = 2 ]
check "the request's text is never run" [ ! -e "$T/pwned" ]
cleanup

setup "add"
auth "$H/.claude" "me@home.example $(in_days 20)"
out="$(r add Jane.Doe@work.example)"; code=$?
check "creates acc2 and names it from the email" grep -qx 'jane.doe acc2' "$B/.names"
check "runs Claude Code's own sign-in for that folder" has "$(log)" "login cfg=$B/acc2 args=--claudeai --email Jane.Doe@work.example"
check "reports success" has "$out" "Signed in. Start it with:  relevo jane.doe"
check "exit 0" [ "$code" = 0 ]
out="$(r add jane.doe@client.example --sso)"
check "duplicate name gets -2" grep -qx 'jane.doe-2 acc3' "$B/.names"
check "--sso is passed through" has "$(log)" "login cfg=$B/acc3 args=--claudeai --email jane.doe@client.example --sso"
out="$(r add x@client.example --name acme)"
check "--name sets the name" grep -qx 'acme acc4' "$B/.names"
out="$(EXTRA=FAKE_LOGIN_AS=bob@other.example r add alice@client.example)"
check "another account signed in: renamed to its email" grep -qx 'bob acc5' "$B/.names"
check "with a notice" has "$out" "Notice: this profile signed in as bob@other.example, not alice@client.example, so it is named bob."
check "the folder is kept" [ -d "$B/acc5" ]
out="$(EXTRA=FAKE_LOGIN_AS=carol@other.example r add dan@client.example --name dan)"
check "with --name the name stays, with a notice" has "$out" "It keeps the name dan."
out="$(EXTRA=FAKE_LOGIN_FAIL=1 r add eve@client.example)"; code=$?
check "failed sign-in keeps the profile and says how to finish" has "$out" "finish later with:  relevo eve   then /login"
check "failed sign-in exits 1" [ "$code" = 1 ]
out="$(r add acme@x.example --name acme)"; check "--name refuses a taken name" has "$out" "'acme' is already taken"
out="$(r add not-an-email)"; check "refuses a non-email" has "$out" "usage: relevo add <email>"
check "never signs in on the default profile" hasnt "$(log)" "FORBIDDEN"
check "login file stays per profile (not linked)" [ ! -L "$B/acc2/.claude.json" ]
cleanup

setup "new and fix"
out="$(r new acc2)"
check "shared items are links to ~/.claude" [ "$(readlink "$B/acc2/settings.json")" = "$H/.claude/settings.json" ]
check "projects are shared (resume across accounts)" [ "$(readlink "$B/acc2/projects")" = "$H/.claude/projects" ]
check "no .claude.json or .credentials.json linked" bash -c "[ ! -e '$B/acc2/.claude.json' ] && [ ! -e '$B/acc2/.credentials.json' ]"
check "profile folder is private" [ "$(mode "$B/acc2")" = 700 ]
out="$(r new acc2)"; check "refuses an existing profile" has "$out" "'acc2' is already taken"
out="$(r new main)"; check "refuses main" has "$out" "'main' is a relevo command or the default profile"
rm "$B/acc2/settings.json"; echo '{"replaced":1}' > "$B/acc2/settings.json"
out="$(r fix acc2)"; check "fix keeps a real file and says so" has "$out" "kept settings.json"
rm "$B/acc2/settings.json"; r fix acc2 > /dev/null
check "fix restores the link" [ -L "$B/acc2/settings.json" ]
cleanup

setup "install and sync"
out="$(r install)"
check "links ~/.local/bin/relevo to the stable copy" [ "$(readlink "$H/.local/bin/relevo")" = "$B/.bin/relevo" ]
check "the copy is the CLI" cmp -s "$CLI" "$B/.bin/relevo"
check "PATH hint" has "$out" "~/.local/bin is not on your PATH yet"
echo "# old version" > "$B/.bin/relevo"
r _sync; check "_sync refreshes an installed copy" cmp -s "$CLI" "$B/.bin/relevo"
rm -rf "$B/.bin"; r _sync; check "_sync installs nothing on its own" [ ! -e "$B/.bin" ]
rm "$H/.local/bin/relevo"; echo other > "$H/.local/bin/relevo"
out="$(r install)"; check "never overwrites someone else's file" has "$out" "already exists and is not relevo's link"
cleanup

setup "help"
out="$(r help)"
check "help lists the commands" has "$out" "relevo add <email> [--sso] [--name <name>]"
check "help mentions /switch" has "$out" "/switch <name>"
cleanup

# ---------------------------------------------------------------------------------------------
printf '\n%d passed, %d failed%b\n' "$PASS" "$FAIL" "$FAILED"
[ "$FAIL" = 0 ]
