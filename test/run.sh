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
line()  { printf '%s\n' "$1" | grep -qE -- "$2"; }                         # some line matches the regex
lines_with() { printf '%s\n' "$1" | grep -F -- "$2"; }                    # the lines containing text
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
check "main is listed by its name, signed in" line "$out" '^me +\(main\) +signed in · login expires in 20 days'
check "expiry shown as days and date" has "$out" "login expires in 20 days ($(in_days 20 | cut -c1-10))"
check "under 5 days is flagged" has "$out" "login expires in 3 days ($(in_days 3 | cut -c1-10))  ← sign in again soon"
check "20 days is not flagged" hasnt "$(lines_with "$out" 'in 20 days')" "sign in again soon"
check "signed-out profile" has "$out" "NOT signed in"
check "expired login says how to sign in again" has "$out" "login expired $(in_days -2 | cut -c1-10)  ← sign in again: relevo old, then /login"
check "unreadable status" has "$out" "status unknown"
out="$(EXTRA=RELEVO_WARN_DAYS=25 r list)"
check "warning threshold is configurable" has "$(lines_with "$out" 'in 20 days')" "sign in again soon"
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

# --- R2: usage, status line, limits ------------------------------------------------------------
usage() { printf '%b\n' "$2" > "$1/fake-usage"; }               # dir, lines (\n-separated)
calls() { grep -c "^usage cfg=$1 " "$T/claude.log"; }           # how many /usage checks ran for a cfg
seen_json() {  # dir-target, 5h %, 5h reset in seconds from now, 7d %, 7d reset, seen seconds ago
  local now; now=$(date +%s); mkdir -p "$B/.usage"
  printf '{"seen": %s, "five_hour": {"used_percentage": %s, "resets_at": %s}, "seven_day": {"used_percentage": %s, "resets_at": %s}}\n' \
    $(( now - $6 )) "$2" $(( now + $3 )) "$4" $(( now + $5 )) > "$B/.usage/$1.json"
}

setup "usage: live"
auth "$H/.claude" "me@home.example $(in_days 20)"
profile acc2 "jane@work.example $(in_days 20)"
profile acc3 "bob@client.example $(in_days 20)"
profile acc4 "out"
r names > /dev/null
usage "$H/.claude" "Current session: 12% used · resets 3pm (Europe/Paris)\nCurrent week (all models): 40% used · resets Nov 22 at 6:30am\nLast 24h: 3 sessions, 2% used\nTop model: Opus 50% used\nEstimated cost: \$0"
usage "$B/acc2" "Current session: 100% used · resets 4pm (Europe/Paris)\nCurrent week (all models): 71% used · resets Nov 22"
usage "$B/acc3" "  Current session: 5% used · resets 5pm\n  Current week (\"Fable\"): 9% used"
for d in "$H/.claude" "$B/acc2" "$B/acc3"; do echo 2 > "$d/fake-usage-delay"; done
start=$SECONDS; out="$(r list)"; took=$(( SECONDS - start ))
check "live lines under each signed-in account" has "$out" "Current week (all models): 71% used · resets Nov 22"
check "indented under the account" line "$out" '^ {30,}Current session: 12% used · resets 3pm \(Europe/Paris\)$'
check "'Last …' and 'Top …' lines are dropped" hasnt "$out" "Top model"
check "escaped quotes come through" has "$out" 'Current week ("Fable"): 9% used'
check "no check for a signed-out account" [ "$(calls "$B/acc4")" = 0 ]
check "checks run in parallel (3 × 2 s in under 5 s)" [ "$took" -lt 5 ]
check "main is checked with CLAUDE_CONFIG_DIR unset" [ "$(calls UNSET)" = 1 ]
check "checks skip shared hooks, plugins and MCP servers" has "$(log)" "args=--output-format json --no-session-persistence --setting-sources project --strict-mcp-config"
check "checks run in an empty temp folder, not the project" hasnt "$(grep '^usage ' "$T/claude.log")" "pwd=$T/proj"
r list > /dev/null
check "a second list within 60 s reuses the results" [ "$(calls "$B/acc2")" = 1 ]
f="$B/.usage/acc2.live"; { echo $(( $(date +%s) - 120 )); tail -n +2 "$f"; } > "$f.x" && mv "$f.x" "$f"
r list > /dev/null
check "an older result is checked again" [ "$(calls "$B/acc2")" = 2 ]
rm -f "$B/.usage/"*.live; out="$(r list --cached)"
check "--cached runs no check" [ "$(calls "$B/acc2")" = 2 ]
check "--cached falls back to the last-seen line" has "$out" "usage: not seen yet"
check "live results are private" [ "$(mode "$B/.usage")" = 700 ]
cleanup

setup "usage: timeout and last-seen fallback"
auth "$H/.claude" "me@home.example $(in_days 20)"
profile acc2 "jane@work.example $(in_days 20)"
r names > /dev/null
usage "$B/acc2" "Current session: 50% used"; echo 30 > "$B/acc2/fake-usage-delay"
seen_json acc2 12.4 7530 40 274000 300
start=$SECONDS; out="$(EXTRA=RELEVO_USAGE_TIMEOUT=2 r list)"; took=$(( SECONDS - start ))
check "a slow account is stopped at the timeout" [ "$took" -lt 6 ]
check "its check was cut off" hasnt "$(log)" "usage-done cfg=$B/acc2"
check "it shows what the status line last saw" has "$out" "usage: 5h 12% used, resets in 2h05m · 7d 40% used, resets in 3d4h   (seen 5 min ago)"
seen_json acc2 100 -60 40 274000 7300
out="$(r list --cached)"
check "a window whose reset has passed says so" has "$out" "usage: 5h reset since · 7d 40% used"
check "old sightings in hours" has "$out" "(seen 2 h ago)"
cleanup

setup "usage: a check that ran a model turn is not trusted"
auth "$H/.claude" "me@home.example $(in_days 20)"
usage "$H/.claude" "Current session: 12% used"; echo 1 > "$H/.claude/fake-usage-turns"
out="$(r list)"
check "says so" has "$out" "ran a model turn, which it never should"
check "and does not show it" hasnt "$out" "Current session: 12% used"
cleanup

setup "status line"
auth "$H/.claude" "me@home.example $(in_days 20)"
profile acc2 "jane@work.example $(in_days 20)"
profile acc3 "bob@client.example $(in_days 20)"
r names > /dev/null
now=$(date +%s)
J="{\"session_id\":\"$SID\",\"transcript_path\":\"$B/acc2/projects/p/$SID.jsonl\",\"model\":{\"id\":\"claude-opus-5-5\",\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$T/proj\"},\"rate_limits\":{\"five_hour\":{\"used_percentage\":12.4,\"resets_at\":$(( now + 3600 ))},\"seven_day\":{\"used_percentage\":40,\"resets_at\":$(( now + 90000 ))}}}"
sl() { printf '%s' "$2" | (cd "$T/proj" && env -i HOME="$H" PATH="$ROOT/test/fake:/usr/bin:/bin" FAKE_LOG="$T/claude.log" \
        FAKE_PLAN="$T/plan" $1 "$SH" "$CLI" statusline 2>&1); }
put_login() { mkdir -p "$B/.usage"; echo "$(date +%s) $2 in" > "$B/.usage/$1.login"; }
put_login acc2 $(( now + 20 * 86400 )); put_login acc3 $(( now + 20 * 86400 )); : > "$T/claude.log"
out="$(sl "CLAUDE_CONFIG_DIR=$B/acc2" "$J")"
check "name · 5h · 7d · model" [ "$out" = "jane · 5h 12% · 7d 40% · Opus" ]
check "remembers the usage for relevo list" grep -q '"used_percentage":12.4' "$B/.usage/acc2.json"
check "the cache is private" [ "$(mode "$B/.usage/acc2.json")" = 600 ]
check "starts no claude when the login cache is fresh" [ "$(grep -c '^status ' "$T/claude.log")" = 0 ]
out="$(sl "RELEVO_PROFILE=acc3" "$J")"; check "RELEVO_PROFILE wins" [ "${out%% *}" = bob ]
out="$(sl "" "$J")"; check "with the environment scrubbed, the transcript path tells" [ "${out%% *}" = jane ]
out="$(sl "" "{\"transcript_path\":\"$H/.claude/projects/p/x.jsonl\",\"model\":{\"display_name\":\"Opus\"}}")"
check "main, with no rate limits yet" [ "$out" = "me · Opus" ]
cp "$B/.usage/acc2.json" "$T/before"
sl "CLAUDE_CONFIG_DIR=$B/acc2" "{\"model\":{\"display_name\":\"Opus\"}}" > /dev/null
check "input without rate limits leaves the cache alone" cmp -s "$T/before" "$B/.usage/acc2.json"
put_login acc2 $(( now + 3 * 86400 + 3600 )); out="$(sl "CLAUDE_CONFIG_DIR=$B/acc2" "$J")"
check "login under the warning days" [ "$out" = "jane · 5h 12% · 7d 40% · Opus · login expires in 3d" ]
put_login acc2 $(( now - 60 )); out="$(sl "CLAUDE_CONFIG_DIR=$B/acc2" "$J")"
check "expired login" has "$out" "· login expired"
rm "$B/.usage/acc3.login"; sl "RELEVO_PROFILE=acc3" "$J" > /dev/null
for i in 1 2 3 4 5 6 7 8 9 10; do [ -f "$B/.usage/acc3.login" ] && break; sleep 0.3; done
check "a missing login cache is refreshed in the background" grep -q ' in$' "$B/.usage/acc3.login"
out="$(sl "CLAUDE_CONFIG_DIR=$B/acc2" "{\"model\":{\"display_name\":\"\$(touch $T/pwned)\"}}")"
check "input is shown, never run" [ ! -e "$T/pwned" ]
out="$(sl "CLAUDE_CONFIG_DIR=/somewhere/else" "$J")"
check "a config folder outside relevo shows its folder name, caches nothing" [ "${out%% *}" = else ]
cleanup

setup "switch to an account at its limit"
auth "$H/.claude" "me@home.example $(in_days 20)"
profile acc2 "jane@work.example $(in_days 20)"
profile acc3 "bob@client.example $(in_days 20)"
r names > /dev/null
usage "$B/acc3" "Current session: 100% used · resets 4pm (Europe/Paris)\nCurrent week (all models): 30% used"
printf 'switch bob\nswitch bob --anyway\nexit 0\n' > "$T/plan"
r jane > /dev/null; L="$(log)"
check "warns with what Claude Code said, and when it resets" has "$L" "switch-exit=4 out=bob is at a usage limit: Current session: 100% used · resets 4pm (Europe/Paris)"
check "does not switch on its own" [ "$(grep -c '^run ' "$T/claude.log")" = 1 ]
: > "$T/claude.log"; r jane > /dev/null; L="$(log)"
check "--anyway switches" has "$L" "run cfg=$B/acc3 profile=acc3"
rm -f "$B/acc3/fake-usage" "$B/.usage/acc3.live" "$T/plan.n"; : > "$T/claude.log"
seen_json acc3 100 3630 30 90000 600
printf 'switch bob\n' > "$T/plan"; r jane > /dev/null
check "without a live answer, the last-seen 100% warns too" has "$(log)" "switch-exit=4 out=bob is at a usage limit: 5h 100% used, resets in 1h00m (last seen)"
seen_json acc3 100 -60 30 90000 600; rm -f "$T/plan.n"; : > "$T/claude.log"
printf 'switch bob\nexit 0\n' > "$T/plan"; r jane > /dev/null
check "a limit that has reset since does not warn" has "$(log)" "switch-exit=0 out=Switching to bob"
cleanup

setup "rate-limit stop"
auth "$H/.claude" "me@home.example $(in_days 20)"
profile acc2 "jane@work.example $(in_days 20)"
profile acc3 "bob@client.example $(in_days 20)"
profile acc4 "out"
profile acc5 "full@client.example $(in_days 20)"
r names > /dev/null
usage "$H/.claude" "Current session: 80% used"
usage "$B/acc3" "Current session: 30% used · resets 5pm"
usage "$B/acc5" "Current session: 100% used"
ENVS="RELEVO_PROFILE=acc2 CLAUDE_CODE_SESSION_ID=$SID CLAUDE_PROJECT_DIR=$T/proj"
out="$(EXTRA="$ENVS RELEVO_WRAPPER=$$" r _limited)"
check "suggests the account with the most room" [ "$out" = "Usage limit reached on jane. To continue this conversation on bob:  /switch bob   (Current session: 30% used · resets 5pm)" ]
check "records the stop" [ -f "$B/.usage/acc2.limited" ]
check "never switches by itself" no_request
out="$(EXTRA="$ENVS" r _limited)"
check "outside relevo it gives the command" has "$out" "exit, then run:  cd $T/proj && relevo bob --resume $SID"
usage "$B/acc3" "Current session: 100% used"; usage "$H/.claude" "Current week (all models): 100% used"; rm -f "$B/.usage/"*.live
out="$(EXTRA="$ENVS RELEVO_WRAPPER=$$" r _limited)"
check "says when no account has room" has "$out" "No other signed-in account has room right now"
cleanup

setup "account"
auth "$H/.claude" "me@home.example $(in_days 20)"
profile acc2 "jane@work.example $(in_days 20)"
profile acc3 "bob@client.example $(in_days 20)"
r names > /dev/null
usage "$B/acc2" "Current session: 100% used · resets 4pm"; usage "$B/acc3" "Current session: 10% used"
out="$(EXTRA=RELEVO_PROFILE=acc2 r account)"
check "marks this session's account" line "$out" '^▶ jane +\(acc2\)'
check "the others are not marked" line "$out" '^  bob +\(acc3\)'
check "says where to continue when at a limit" has "$out" "This session runs on jane. It is at a usage limit; to continue this conversation on bob:  /switch bob"
usage "$B/acc2" "Current session: 10% used"; rm -f "$B/.usage/"*.live
out="$(EXTRA=RELEVO_PROFILE=acc2 r account)"
check "no suggestion when there is room" [ "$(printf '%s\n' "$out" | tail -1)" = "This session runs on jane." ]
cleanup

setup "plugin settings reach the terminal"
auth "$H/.claude" "me@home.example $(in_days 20)"
r new acc2 > /dev/null
EXTRA=RELEVO_WARN_DAYS=25 r _sync
check "_sync saves the warning days" [ "$(cat "$B/.prefs")" = "warn_days=25" ]
out="$(r list --cached)"
check "the terminal CLI uses them" has "$(lines_with "$out" 'in 20 days')" "sign in again soon"
cleanup

# ---------------------------------------------------------------------------------------------
printf '\n%d passed, %d failed%b\n' "$PASS" "$FAIL" "$FAILED"
[ "$FAIL" = 0 ]
