#!/bin/bash
# Runs both hooks against a throwaway HOME (never your real ~/.claude) and compares what they write and print
# with tests/hooks.expected.txt.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   tests/hooks.sh            run and compare
#   tests/hooks.sh --update   run and save the output as the new expected (after a change you meant)
# Needs python3, git, clang and perl. Takes about a minute: the permission hook is waited on in real time.
cd "$(dirname "$0")/.." || exit 1
REPO=$PWD
# git here ignores your personal git settings (signing, hooks, …), so the sample repo's commit always works.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
H="$REPO/hooks/whozmove-claude.py"
P="$REPO/hooks/whozmove-claude-permission.py"
# Whozmove's own folder and process name, taken from the app itself (AppDir in app/Files.m, CFBundleExecutable
# in app/Info.plist). The hooks spell both out separately, so if they ever disagree with the app, the tests fail
# here instead of the panel quietly showing nothing. The folder has a space in it, so it's always quoted.
APP_LINE='s|.*NSString \*base = \[Home() stringByAppendingPathComponent:@"'
APP_LINE+='\(Library/Application Support/[^"]*\)"].*|\1|p'
APPDIR=$(sed -n "$APP_LINE" "$REPO"/app/*.m | head -1)
EXE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$REPO/app/Info.plist")
[ -n "$APPDIR" ] && [ -n "$EXE" ] || { echo "Couldn't read the app's folder or process name"; exit 1; }
# Stops here if there's no temporary folder: an empty T would make the clean-up below delete this checkout.
T=$(mktemp -d "${TMPDIR:-/tmp}/whozmove-test.XXXXXX") || exit 1
T=$(cd "$T" && pwd -P) || exit 1
D="$T/$APPDIR"
# Stand-in processes are started detached, their pids kept in $T/pids so they're stopped however this ends.
trap 'kill $(cat "$T/pids" 2>/dev/null) 2>/dev/null; rm -rf "$T"' EXIT
detached() { local pid; pid=$("$@" >/dev/null 2>&1 & echo $!); echo $pid >> "$T/pids"; echo $pid; }
mkdir -p "$D/sessions" "$T/.claude/sessions" "$T/.claude/projects/p" "$T/repo"
git -C "$T/repo" init -q && git -C "$T/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
# The permission hook asks only while a process with the app's name (the panel) is running. A compiled
# stand-in, not a copy of /bin/sleep: macOS kills a copied system binary.
printf '#include <unistd.h>\nint main(void){sleep(600);return 0;}\n' > "$T/fake.c"
clang -o "$T/$EXE" "$T/fake.c" || exit 1

tests() {
run() { echo "$1" | HOME="$T" python3 "$H"; echo "exit=$?"; }
show() { python3 - "$D/sessions/$1.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for k in sorted(d):
    v = d[k]
    if k.endswith('At') and isinstance(v, (int, float)): v = 'ms' if v > 1e12 else v
    print(f'   {k} = {json.dumps(v)[:160]}')
PY
}
C="\"cwd\": \"$T/repo\""
echo "== 1 prompt"
run "{\"session_id\":\"s1\",\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"please fix the tests\",
     \"permission_mode\":\"auto\",$C}"
show s1
echo "== 2 pre bash with description"
run "{\"session_id\":\"s1\",\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Bash\",
     \"tool_input\":{\"command\":\"npm test\",\"description\":\"Run the tests\"},\"permission_mode\":\"auto\",$C}"
show s1
echo "== 3 post bash tests"
run "{\"session_id\":\"s1\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",
     \"tool_input\":{\"command\":\"npm test\"},\"tool_response\":{},$C}"
show s1
echo "== 4 pre edit"
run "{\"session_id\":\"s1\",\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Edit\",
     \"tool_input\":{\"file_path\":\"$T/repo/a.py\"},$C}"
show s1
echo "== 5 post edit"
run "{\"session_id\":\"s1\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Edit\",
     \"tool_input\":{\"file_path\":\"$T/repo/a.py\"},$C}"
show s1
echo "== 6 post git commit (heredoc message mentions deploy to prod)"
run "{\"session_id\":\"s1\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",
     \"tool_input\":{\"command\":\"git commit -m \\\"\$(cat <<'X'\\nkubectl apply prod\\nX\\n)\\\"\"},$C}"
show s1
echo "== 7 notification"
run "{\"session_id\":\"s1\",\"hook_event_name\":\"Notification\",
     \"message\":\"Claude needs your permission to use Bash\",\"notification_type\":\"permission_prompt\",$C}"
show s1
echo "== 8 stop"
run "{\"session_id\":\"s1\",\"hook_event_name\":\"Stop\",\"last_assistant_message\":\"All done.\",$C}"
show s1
echo "== 9 subagent pre (agent_id)"
run "{\"session_id\":\"s1\",\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Read\",\"agent_id\":\"ag1\",
     \"tool_input\":{\"file_path\":\"/x/y.md\"},$C}"
show s1
echo "== 10 mcp + webfetch + agent"
run "{\"session_id\":\"s2\",\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"mcp__docs__getPageContent\",
     \"tool_input\":{},$C}"
show s2
# A plugin's server goes by its own name; a connector whose server name is only an id shows just the tool.
run "{\"session_id\":\"s2\",\"hook_event_name\":\"PreToolUse\",
     \"tool_name\":\"mcp__plugin_tools_calendar__list_events\",\"tool_input\":{},$C}"
show s2
run "{\"session_id\":\"s2\",\"hook_event_name\":\"PreToolUse\",
     \"tool_name\":\"mcp__aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee__search_pages\",\"tool_input\":{},$C}"
show s2
run "{\"session_id\":\"s2\",\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"WebFetch\",
     \"tool_input\":{\"url\":\"https://docs.example.com/a\"},$C}"
show s2
run "{\"session_id\":\"s2\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Agent\",
     \"tool_input\":{\"subagent_type\":\"Explore\",\"description\":\"find things\"},$C}"
show s2
echo "== 11 malformed input"; echo 'not json' | HOME="$T" python3 "$H"; echo "exit=$?"
echo '[]' | HOME="$T" python3 "$H"; echo "exit=$?"
echo '{"hook_event_name":"Stop"}' | HOME="$T" python3 "$H"; echo "exit=$?"
echo "== 12 deploy to prod via kubectl"
run "{\"session_id\":\"s3\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",
     \"tool_input\":{\"command\":\"kubectl --context prod apply -f k8s/\"},$C}"
run "{\"session_id\":\"s3\",\"hook_event_name\":\"Stop\",\"last_assistant_message\":\"deployed\",$C}"
show s3

# Permission hook. perl's alarm is the timeout for cases that must end on their own at once.
echo "== P1 panel not running"
echo '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"ls"}}' | HOME="$T" python3 "$P"
echo "exit=$?"
ls "$D/asks" 2>/dev/null | wc -l | tr -d ' '
OTHER=$(detached sleep 600); echo $OTHER > "$D/panel.pid"
echo "== P0 stale panel.pid (another process)"
echo '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"ls"}}' \
  | HOME="$T" perl -e 'alarm 3; exec @ARGV' python3 "$P"
echo "exit=$?"
ls "$D/asks" 2>/dev/null | wc -l | tr -d ' '; rm -rf "$D/asks"
PANEL=$(detached "$T/$EXE"); echo $PANEL > "$D/panel.pid"
echo "{\"pid\": $PANEL, \"sessionId\": \"s1\", \"kind\": \"interactive\", \"status\": \"busy\"}" \
  > "$T/.claude/sessions/$PANEL.json"
echo "{\"pid\": $OTHER, \"sessionId\": \"p1\", \"kind\": \"print\"}" > "$T/.claude/sessions/$OTHER.json"
answer() {  # $1 = event json, $2 = the panel's answer json, or SIGTERM (Claude Code stopping the hook)
  (echo "$1" | HOME="$T" python3 "$P" > "$T/out" 2>&1; echo "exit=$?" >> "$T/out") & HP=$!
  for i in $(seq 1 40); do
    f=$(ls "$D/asks"/*.json 2>/dev/null | grep -v answer | head -1)
    [ -n "$f" ] && break
    sleep 0.1
  done
  [ -z "$f" ] && { echo "no request written"; wait $HP; cat "$T/out"; return; }
  python3 - "$f" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print('   request keys', sorted(d))
print('   tool', d['tool'], 'session', d['sessionId'])
PY
  if [ "$2" = SIGTERM ]; then
    kill -TERM "$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['pid'])" "$f")"
  else
    echo "$2" > "${f%.json}.answer.json"
  fi
  wait $HP; cat "$T/out"; echo "   left in asks: $(ls "$D/asks" | wc -l | tr -d ' ')"
}
echo "== P2 allow"; answer '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"ls"}}' '{"behavior":"allow"}'
echo "== P3 deny"; answer '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"ls"}}' '{"behavior":"deny"}'
echo "== P4 question answers"
answer '{"session_id":"s1","tool_name":"AskUserQuestion",
         "tool_input":{"questions":[{"question":"Q1?","options":[{"label":"a"},{"label":"b"}]}]}}' \
       '{"behavior":"allow","answers":{"Q1?":"a"}}'
echo "== P5 answers ignored for other tools"
answer '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"ls"}}' '{"behavior":"allow","answers":{"x":"y"}}'
echo "== P6 question dismissed"
answer '{"session_id":"s1","tool_name":"AskUserQuestion","tool_input":{"questions":[]}}' '{"behavior":"deny"}'
echo "== P7 cancelled by Claude (SIGTERM)"
answer '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"ls"}}' SIGTERM
step_aside() {
  echo "$1" | HOME="$T" perl -e 'alarm 3; exec @ARGV' python3 "$P"; echo "exit=$?"
  ls "$D/asks" 2>/dev/null | grep -vc answer; rm -f "$D/asks/"*
}
echo "== P8 malformed input"; echo 'nope' | HOME="$T" python3 "$P"; echo "exit=$?"
echo "== P9 sub-agent request"
step_aside '{"session_id":"s1","agent_id":"ag1","tool_name":"Bash","tool_input":{"command":"ls"}}'
echo "== P10 leaving plan mode"; step_aside '{"session_id":"s1","tool_name":"ExitPlanMode","tool_input":{"plan":"x"}}'
echo "== P11 non-interactive session"; step_aside '{"session_id":"p1","tool_name":"Bash","tool_input":{"command":"ls"}}'
echo "== P12 unknown session"; step_aside '{"session_id":"zz","tool_name":"Bash","tool_input":{"command":"ls"}}'
echo "== P13 list input"; step_aside '[]'
echo "== perms"; stat -f '%Lp %N' "$D" "$D/sessions" "$D/sessions/s1.json"

# The permission hook steps aside once the request is settled in Claude (the call's result lands in the
# transcript) or the session ends.
SESS=$(detached sleep 600)
echo "{\"pid\": $SESS, \"sessionId\": \"s9\", \"kind\": \"interactive\"}" > "$T/.claude/sessions/$SESS.json"
TR="$T/.claude/projects/p/s9.jsonl"
INPUT='{"questions":[{"question":"Q?","options":[{"label":"a"},{"label":"b"}]}]}'
# Lines of the session's transcript, one record each: the call, its result, and a hook's progress note.
use() {
  local call="{\"type\":\"tool_use\",\"id\":\"$1\",\"name\":\"AskUserQuestion\",\"input\":$INPUT}"
  echo "{\"type\":\"assistant\",\"message\":{\"content\":[$call]}}" >> "$TR"
}
result() {
  local outcome="{\"type\":\"tool_result\",\"tool_use_id\":\"$1\",\"content\":\"dismissed\"}"
  echo "{\"type\":\"user\",\"message\":{\"content\":[$outcome]}}" >> "$TR"
}
progress() {
  local note="{\"type\":\"hook_progress\",\"tool_use_id\":\"$1\"}"
  echo "{\"type\":\"progress\",\"toolUseID\":\"$1\",\"data\":$note}" >> "$TR"
}
start() {  # $1 = extra event json fields
  : > "$T/out"
  (echo "{\"session_id\":\"s9\",\"tool_name\":\"AskUserQuestion\",\"tool_input\":$INPUT$1}" \
     | HOME="$T" python3 "$P" > "$T/out" 2>&1
   echo "exit=$?" >> "$T/out") & HP=$!
  for i in $(seq 1 40); do ls "$D/asks/"*.json >/dev/null 2>&1 && break; sleep 0.1; done
  echo "   request shown: $(ls "$D/asks" 2>/dev/null | grep -vc answer)"
}
finish() {  # waits up to $1 s for the hook to end on its own
  for i in $(seq 1 $(( $1 * 10 ))); do kill -0 $HP 2>/dev/null || break; sleep 0.1; done
  if kill -0 $HP 2>/dev/null; then echo "   still waiting after ${1}s"; return 1; fi
  local left; left=$(ls "$D/asks" | wc -l | tr -d ' ')
  echo "   hook ended, printed: [$(grep -v exit= "$T/out")] $(grep exit= "$T/out"), requests left: $left"
}
echo "== S1 answered in Claude (result written)"; : > "$TR"; use toolu_A; start ""; sleep 1; result toolu_A; finish 4
echo "== S2 call written to the transcript only after the hook started"
: > "$TR"; start ""; sleep 1.5; use toolu_B; sleep 1; result toolu_B; finish 4
echo "== S3 Claude Code gives the call id"
: > "$TR"; use toolu_C; use toolu_other; start ',"tool_use_id":"toolu_C"'; sleep 1; result toolu_C; finish 4
echo "== S4 a hook-progress line and another call's result don't count; the panel's answer still does"
: > "$TR"; use toolu_D; start ""; progress toolu_D; result toolu_zzz; finish 3
f=$(ls "$D/asks/"*.json | grep -v answer | head -1); echo '{"behavior":"deny"}' > "${f%.json}.answer.json"; finish 3
echo "== S5 the session ends"; : > "$TR"; use toolu_E; start ""; kill $SESS; finish 8

# How the plugin wires the hooks (hooks/hooks.json), that the permission hook gives up waiting before Claude Code
# would stop it, and that the plugin carries the app's version.
echo "== the plugin's hooks"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$REPO/app/Info.plist")
python3 - "$REPO/hooks/hooks.json" "$P" "$REPO/.claude-plugin/plugin.json" "$VERSION" <<'PY'
import json, re, sys
hooks = json.load(open(sys.argv[1]))["hooks"]
for event in sorted(hooks):
    for group in hooks[event]:
        for hook in group["hooks"]:
            run = " ".join([hook["command"]] + hook.get("args", [])).replace("${CLAUDE_PLUGIN_ROOT}/", "")
            timeout = f" timeout {hook['timeout']}" if "timeout" in hook else ""
            print(f"   {event}: {run}{' async' if hook.get('async') else ''}{timeout}")
wait = int(re.search(r"^WAIT_LIMIT = (\d+)", open(sys.argv[2]).read(), re.M).group(1))
print("   the permission hook stops waiting first:", wait < hooks["PermissionRequest"][0]["hooks"][0]["timeout"])
print("   the plugin's version is the app's:", json.load(open(sys.argv[3]))["version"] == sys.argv[4])
PY
}

out=$(tests 2>&1 | sed "s|$T|T|g")
. "$REPO/tests/compare.sh"
compare Hooks "$REPO/tests/hooks.expected.txt" "$out" "${1:-}"
