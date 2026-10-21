#!/bin/bash
# The Claude Code module's tests: both hooks of its plugin, run against a throwaway HOME (never your real ~/.claude),
# and what they write and print compared with hooks.expected.txt, beside this file.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Then the hooks run again on the Python in Apple's developer tools (/usr/bin/python3, 3.9), which a Mac with only
# those runs them on, when python3 here is another one; and Whozmove's plugin is put into a stand-in Claude Code as the
# app does as it opens (Whozmove --print-plugin-install), compared with plugin.expected.txt.
#
# Prints the difference and exits 1 if anything changed.
#   modules/claude-code/tests/test.sh            run and compare
#   modules/claude-code/tests/test.sh --update   run and save the output as the new expected (after a change you meant)
# Needs python3, git, clang and perl. Takes about a minute for each Python: the permission hook is waited on in real
# time.
cd "$(dirname "$0")/../../.." || exit 1
REPO=$PWD
HERE=modules/claude-code/tests
PLUGIN="$REPO/modules/claude-code/plugin"
# git here ignores your personal git settings (signing, hooks, …), so the sample repo's commit always works.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
H="$PLUGIN/hooks/whozmove-claude.py"
P="$PLUGIN/hooks/whozmove-claude-permission.py"
# The Python the hooks run on here (HOOKS_PYTHON is set for the second run).
PY=${HOOKS_PYTHON:-python3}
# Whozmove's own folder and process name, taken from the app itself (AppDir in Files.m, CFBundleExecutable
# in app/Info.plist). The hooks spell both out separately, so if they ever disagree with the app, the tests fail
# here instead of the panel quietly showing nothing. The folder has a space in it, so it's always quoted.
APP_LINE='s|.*NSString \*base = \[Home() stringByAppendingPathComponent:@"'
APP_LINE+='\(Library/Application Support/[^"]*\)"].*|\1|p'
# Whichever file defines it now: there must be just the one.
APPDIR=$(find "$REPO/app" "$REPO/modules" -name '*.m' -exec sed -n "$APP_LINE" {} + 2>/dev/null | sort -u)
EXE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$REPO/app/Info.plist")
[ -n "$APPDIR" ] && [ "$(printf '%s\n' "$APPDIR" | wc -l)" -eq 1 ] && [ -n "$EXE" ] \
  || { echo "Couldn't read the app's folder (once) or process name"; exit 1; }
# Stops here if there's no temporary folder: an empty T would make the clean-up below delete this checkout.
T=$(mktemp -d "${TMPDIR:-/tmp}/whozmove-test.XXXXXX") || exit 1
T=$(cd "$T" && pwd -P) || exit 1
D="$T/$APPDIR"
# Stand-in processes are started detached, their pids kept in $T/pids so they're stopped however this ends.
trap 'kill $(cat "$T/pids" 2>/dev/null) 2>/dev/null; rm -rf "$T"' EXIT
detached() { local pid; pid=$("$@" >/dev/null 2>&1 & echo $!); echo $pid >> "$T/pids"; echo $pid; }
mkdir -p "$D/sessions" "$T/.claude/sessions" "$T/.claude/projects/p" "$T/repo" "$T/Applications/$EXE.app"
# Where the app runs from, as it notes it in its folder each time it opens: the hooks record only while it's there.
echo "$T/Applications/$EXE.app" > "$D/app"
git -C "$T/repo" init -q -b main && git -C "$T/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
# A worktree of it, whose .git is a file naming the real git folder: a code review there is noted on its own branch.
git -C "$T/repo" worktree add -q -b side "$T/side"
# The permission hook asks only while a process with the app's name (the panel) is running. A compiled
# stand-in, not a copy of /bin/sleep: macOS kills a copied system binary.
printf '#include <unistd.h>\nint main(void){sleep(600);return 0;}\n' > "$T/fake.c"
clang -o "$T/$EXE" "$T/fake.c" || exit 1

tests() {
run() { echo "$1" | HOME="$T" "$PY" "$H"; echo "exit=$?"; }
show() { python3 - "$D/sessions/$1.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for k in sorted(d):
    v = d[k]
    if k.endswith('At') and isinstance(v, (int, float)): v = 'ms' if v > 1e12 else v
    if isinstance(v, dict) and isinstance(v.get('at'), (int, float)): v = dict(v, at='ms')  # a review's, say
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
echo "== 11 malformed input"; echo 'not json' | HOME="$T" "$PY" "$H"; echo "exit=$?"
echo '[]' | HOME="$T" "$PY" "$H"; echo "exit=$?"
echo '{"hook_event_name":"Stop"}' | HOME="$T" "$PY" "$H"; echo "exit=$?"
echo "== 12 deploy to prod via kubectl"
run "{\"session_id\":\"s3\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",
     \"tool_input\":{\"command\":\"kubectl --context prod apply -f k8s/\"},$C}"
run "{\"session_id\":\"s3\",\"hook_event_name\":\"Stop\",\"last_assistant_message\":\"deployed\",$C}"
show s3
echo "== 13 a build: when it was built is noted"
run "{\"session_id\":\"s4\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",
     \"tool_input\":{\"command\":\"./build.sh\"},\"tool_response\":{},$C}"
show s4
echo "== 14 a code review of committed work: kept through its fixes, settled by its second report"
F1="{\"file\":\"a.py\",\"summary\":\"a\",\"failure_scenario\":\"x\""
F2="{\"file\":\"b.py\",\"summary\":\"b\",\"failure_scenario\":\"y\""
run "{\"session_id\":\"s5\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",
     \"tool_input\":{\"command\":\"git commit -m work\"},$C}"
run "{\"session_id\":\"s5\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"ReportFindings\",
     \"tool_input\":{\"findings\":[$F1},$F2}]},$C}"
run "{\"session_id\":\"s5\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Edit\",
     \"tool_input\":{\"file_path\":\"$T/repo/a.py\"},$C}"
show s5
run "{\"session_id\":\"s5\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"ReportFindings\",
     \"tool_input\":{\"findings\":[$F1,\"outcome\":\"fixed\"},$F2,\"outcome\":\"skipped\"}]},$C}"
show s5
echo "== 15 …and gone once that's committed and the next piece of work starts"
run "{\"session_id\":\"s5\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",
     \"tool_input\":{\"command\":\"git commit -m fixes\"},$C}"
run "{\"session_id\":\"s5\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Edit\",
     \"tool_input\":{\"file_path\":\"$T/repo/c.py\"},$C}"
show s5
echo "== 16 a code review in a worktree, noted on its branch; one with nothing found leaves a commit as it was"
run "{\"session_id\":\"s6\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",
     \"tool_input\":{\"command\":\"git commit -m work\"},\"cwd\":\"$T/side\"}"
run "{\"session_id\":\"s6\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"ReportFindings\",
     \"tool_input\":{\"findings\":[]},\"cwd\":\"$T/side\"}"
show s6
echo "== 17 Whozmove isn't installed (no app noted in its folder): nothing is recorded"
mv "$D/app" "$T/app.kept"
run "{\"session_id\":\"s7\",\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"hello\",$C}"
[ -e "$D/sessions/s7.json" ] && show s7 || echo "   no record"
echo "== 18 the app noted there has gone: looked for again a moment later, then nothing is recorded"
echo "$T/Gone/$EXE.app" > "$D/app"
run "{\"session_id\":\"s7\",\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"hello\",$C}"
[ -e "$D/sessions/s7.json" ] && show s7 || echo "   no record"
mv "$T/app.kept" "$D/app"
echo "== 19 compacting, by itself or asked for: from its start to its end, or to the next step after one stopped"
run "{\"session_id\":\"c1\",\"hook_event_name\":\"PreCompact\",\"trigger\":\"auto\",$C}"
show c1
run "{\"session_id\":\"c1\",\"hook_event_name\":\"PostCompact\",\"trigger\":\"auto\",$C}"
show c1
# A step that came in just after it began (each hook runs on its own), or a sub-agent's, leaves it going; Claude's
# own next step, or its saying it waits for you, a second on, ends it.
run "{\"session_id\":\"c2\",\"hook_event_name\":\"PreCompact\",\"trigger\":\"auto\",$C}"
run "{\"session_id\":\"c2\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Read\",\"tool_input\":{},$C}"
run "{\"session_id\":\"c2\",\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Read\",\"tool_input\":{},$C}"
show c2
sleep 1.1
run "{\"session_id\":\"c2\",\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Read\",\"agent_id\":\"ag2\",
     \"tool_input\":{},$C}"
run "{\"session_id\":\"c2\",\"hook_event_name\":\"Notification\",\"message\":\"Claude needs your permission\",
     \"notification_type\":\"permission_prompt\",$C}"
show c2
run "{\"session_id\":\"c2\",\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Read\",\"tool_input\":{},$C}"
show c2
run "{\"session_id\":\"c3\",\"hook_event_name\":\"PreCompact\",\"trigger\":\"manual\",$C}"
sleep 1.1
run "{\"session_id\":\"c3\",\"hook_event_name\":\"Notification\",\"message\":\"Claude is waiting for your input\",
     \"notification_type\":\"idle_prompt\",$C}"
show c3

# Permission hook. perl's alarm is the timeout for cases that must end on their own at once.
echo "== P1 panel not running"
echo '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"ls"}}' | HOME="$T" "$PY" "$P"
echo "exit=$?"
ls "$D/asks" 2>/dev/null | wc -l | tr -d ' '
# The same hook's part for model switches (PreModelSwitch): only a switch the panel noted is its business. The note
# says the model and how long ago (in seconds).
note() {
  mkdir -p "$D/switches"
  python3 -c "import json, sys, time
json.dump({'to': sys.argv[1], 'at': int(time.time() * 1000) - int(sys.argv[2]) * 1000}, open(sys.argv[3], 'w'))" \
    "$1" "${2:-0}" "$D/switches/m1.panel.json"
}
switch_event() {
  echo "{\"hook_event_name\":\"PreModelSwitch\",\"session_id\":\"m1\",\"from_model\":\"claude-opus-5-5\",
         \"to_model\":\"$1\",\"requested_model\":\"$1\",\"source\":\"command\",\"prompt_cache_warm\":$2,
         \"context_tokens\":152000}"
}
switched() { echo "exit=$?"; echo "   left in switches: $(ls "$D/switches" 2>/dev/null | wc -l | tr -d ' ')"; }
echo "== M1 a switch the panel didn't note"
switch_event claude-sonnet-5-5 true | HOME="$T" python3 "$P"; switched
echo "== M2 the panel's switch, with the panel not running: Claude asks as usual"
note claude-sonnet-5-5; switch_event claude-sonnet-5-5 true | HOME="$T" python3 "$P"; switched
echo "== M3 the panel's switch, with its cache not warm: allowed, nothing asked"
note claude-sonnet-5-5; switch_event claude-sonnet-5-5 false | HOME="$T" python3 "$P"; switched
OTHER=$(detached sleep 600); echo $OTHER > "$D/panel.pid"
echo "== P0 stale panel.pid (another process)"
echo '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"ls"}}' \
  | HOME="$T" perl -e 'alarm 3; exec @ARGV' "$PY" "$P"
echo "exit=$?"
ls "$D/asks" 2>/dev/null | wc -l | tr -d ' '; rm -rf "$D/asks"
PANEL=$(detached "$T/$EXE"); echo $PANEL > "$D/panel.pid"
echo "{\"pid\": $PANEL, \"sessionId\": \"s1\", \"kind\": \"interactive\", \"status\": \"busy\"}" \
  > "$T/.claude/sessions/$PANEL.json"
echo "{\"pid\": $OTHER, \"sessionId\": \"p1\", \"kind\": \"print\"}" > "$T/.claude/sessions/$OTHER.json"
answer() {  # $1 = event json, $2 = the panel's answer json, or SIGTERM (Claude Code stopping the hook)
  (echo "$1" | HOME="$T" "$PY" "$P" > "$T/out" 2>&1; echo "exit=$?" >> "$T/out") & HP=$!
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
  if [ "$3" = SIGTERM ]; then  # an answer the hook must not act on: it's still waiting a second later
    sleep 1; kill -0 $HP 2>/dev/null && echo "   still waiting"
    kill -TERM "$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['pid'])" "$f")"
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
# The panel's switch with a warm cache, asked in the panel: the question, the panel's answer, and what's passed back.
switch_answer() {
  note claude-sonnet-5-5
  (switch_event claude-sonnet-5-5 true | HOME="$T" python3 "$P" > "$T/out" 2>&1; echo "exit=$?" >> "$T/out") & HP=$!
  for i in $(seq 1 40); do [ -f "$D/switches/m1.ask.json" ] && break; sleep 0.1; done
  python3 - "$D/switches/m1.ask.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print('   question', {k: d[k] for k in ('sessionId', 'from', 'to', 'tokens')})
PY
  echo "$1" > "$D/switches/m1.answer.json"
  wait $HP; cat "$T/out"; echo "   left in switches: $(ls "$D/switches" | wc -l | tr -d ' ')"
}
echo "== M4 a note for another model: not the panel's switch"
note claude-haiku-5-5; switch_event claude-sonnet-5-5 true | HOME="$T" python3 "$P"; switched
echo "== M5 a note from two minutes ago: not the panel's switch"
note claude-sonnet-5-5 120; switch_event claude-sonnet-5-5 true | HOME="$T" python3 "$P"; switched
echo "== M6 asked in the panel: switch"; switch_answer '{"allow":true}'
echo "== M7 asked in the panel: keep the model"; switch_answer '{"allow":false}'
PLAN='{"session_id":"s1","tool_name":"ExitPlanMode","tool_input":{"plan":"# Plan","planFilePath":"/p.md"}}'
echo "== P7a plan sent back with notes"; answer "$PLAN" '{"behavior":"deny","message":"  Split step 2.  "}'
echo "== P7b plan stopped"; answer "$PLAN" '{"behavior":"deny","stop":true,"message":"ignored"}'
echo "== P7c plan dismissed without notes"; answer "$PLAN" '{"behavior":"deny"}'
echo "== P7d a plan is never allowed from the panel"; answer "$PLAN" '{"behavior":"allow"}' SIGTERM
echo "== P7e notes and stop ignored for other tools"
answer '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"ls"}}' '{"behavior":"deny","stop":true,"message":"x"}'
step_aside() {
  echo "$1" | HOME="$T" perl -e 'alarm 3; exec @ARGV' "$PY" "$P"; echo "exit=$?"
  ls "$D/asks" 2>/dev/null | grep -vc answer; rm -f "$D/asks/"*
}
echo "== P8 malformed input"; echo 'nope' | HOME="$T" "$PY" "$P"; echo "exit=$?"
echo "== P9 sub-agent request"
step_aside '{"session_id":"s1","agent_id":"ag1","tool_name":"Bash","tool_input":{"command":"ls"}}'
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
     | HOME="$T" "$PY" "$P" > "$T/out" 2>&1
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
python3 - "$PLUGIN/hooks/hooks.json" "$P" "$PLUGIN/.claude-plugin/plugin.json" "$VERSION" <<'PY'
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
switch_wait = int(re.search(r"^SWITCH_WAIT = (\d+)", open(sys.argv[2]).read(), re.M).group(1))
print("   and for a model switch:", switch_wait < hooks["PreModelSwitch"][0]["hooks"][0]["timeout"])
print("   the plugin's version is the app's:", json.load(open(sys.argv[3]))["version"] == sys.argv[4])
PY
}

out=$(tests 2>&1 | sed "s|$T|T|g")
. "$REPO/tests/compare.sh"
status=0
if [ -n "${HOOKS_PYTHON:-}" ]; then
  compare "Hooks on $HOOKS_PYTHON" "$REPO/$HERE/hooks.expected.txt" "$out" || exit 1
  exit 0
fi
compare Hooks "$REPO/$HERE/hooks.expected.txt" "$out" "${1:-}" || status=1
# The same hooks, the same results, on the developer tools' own Python, when it's another one than python3 here.
if [ -x /usr/bin/python3 ] && [ "$(python3 -c 'import sys; print(sys.executable)')" \
     != "$(/usr/bin/python3 -c 'import sys; print(sys.executable)')" ]; then
  HOOKS_PYTHON=/usr/bin/python3 "$REPO/$HERE/test.sh" || status=1
fi

# Whozmove's plugin, put into Claude Code as the app does as it opens: a stand-in claude, found through
# $INSTALL_PATH, writes down what it's asked, answers `plugin list --json` from list.json in its home folder (from
# list-after.json once the plugin has been brought up to date, where there is one), and fails the command its home
# folder's `fail` names, saying why, as Claude Code does.
plugin_cases() {
  . modules/claude-code/plugin.sh
  copy_plugin "$T/hooks"
  local new mine off
  new=$(plutil -extract version raw -o - "$T/hooks/.claude-plugin/plugin.json")
  mine="{\"id\": \"whozmove@whozmove\", \"version\": \"$new\", \"enabled\": true}"
  off="{\"id\": \"whozmove@whozmove\", \"version\": \"$new\", \"enabled\": false}"
  mkdir -p "$T/bin"
  cat > "$T/bin/claude" <<'SH'
#!/bin/bash
PATH=/usr/bin:/bin
echo "claude $*" >> "$HOME/asked"
if [ -f "$HOME/fail" ] && [ "$*" = "$(cat "$HOME/fail")" ]; then
  echo "Installing plugin \"whozmove@whozmove\"..."
  echo "Error: Failed to install plugin \"whozmove@whozmove\": marketplace not reachable" >&2
  exit 1
fi
if [ "$*" = "plugin update whozmove@whozmove" ] && [ -f "$HOME/list-after.json" ]; then
  mv "$HOME/list-after.json" "$HOME/list.json"
fi
if [ "$*" = "plugin list --json" ]; then cat "$HOME/list.json" 2>/dev/null || echo "[]"
else echo '{"outcome":"ok"}'; fi
SH
  chmod +x "$T/bin/claude"
  case_home() {  # a fresh home folder, with what the stand-in lists
    rm -rf "$T/home"; mkdir -p "$T/home"
    printf '%s\n' "$1" > "$T/home/list.json"
  }
  connect() {
    HOME="$T/home" INSTALL_PATH="${WHERE-$T/bin}" "$APP" --print-plugin-install "$@" "$T/hooks"
    echo "   asked:"
    sed -e "s|$T/home|~|g" -e 's|^|     |' "$T/home/asked" 2>/dev/null || echo "     nothing"
    echo "   the copy in Whozmove's folder: $(plutil -extract version raw -o - \
      "$T/home/Library/Application Support/Whozmove/plugin/.claude-plugin/plugin.json" 2>/dev/null || echo none)"
  }
  echo "== 1 the first time: the marketplace is added from Whozmove's folder, then the plugin"
  case_home "[]"; connect
  echo "== 2 there already, this version: nothing to do"
  case_home "[$mine]"; connect
  echo "== 3 an older version there: the marketplace, then the plugin, are updated"
  case_home '[{"id": "whozmove@whozmove", "version": "0.0.1+00000000", "enabled": true}]'; connect
  echo "== 4 taken out since it went in: left out"
  case_home "[]"; connect --before
  echo "== 5 Add Back, after the plugin and its marketplace were taken out, or only the plugin" \
       "(adding it again is fine)"
  case_home "[]"; connect --before --answer addBack
  echo "== 6 turned off in Claude Code: left off"
  case_home "[$off]"; connect
  echo "== 7 Turn On, and a new version with it"
  case_home '[{"id": "whozmove@whozmove", "version": "0.0.1+00000000", "enabled": false}]'; connect --answer turnOn
  echo "== 8 Claude Code lists it, but it can't load: what it says"
  case_home "[{\"id\": \"whozmove@whozmove\", \"version\": \"$new\", \"enabled\": true,
    \"errors\": [\"Marketplace whozmove failed to load: cache-miss\"]}]"; connect
  echo "== 9 installing fails: its last line"
  case_home "[]"; echo "plugin install whozmove@whozmove" > "$T/home/fail"; connect
  echo "== 10 a copy from a marketplace of your own: left as it is, with no second one"
  case_home '[{"id": "whozmove@my-tools", "version": "1.0.0", "enabled": true}]'; connect
  echo "== 11 no claude anywhere"
  case_home "[]"; WHERE= connect
  echo "== 12 only Claude Desktop's own copy"
  case_home "[]"
  desktop="$T/home/Library/Application Support/Claude/claude-code/2.1.302/0/claude.app/Contents/MacOS"
  mkdir -p "$desktop" && cp "$T/bin/claude" "$desktop/claude"
  WHERE= connect
  local copy="$T/home/Library/Application Support/Whozmove/plugin" failing
  failing="[{\"id\": \"whozmove@whozmove\", \"version\": \"$new\", \"enabled\": true,
    \"errors\": [\"Plugin whozmove failed to load: hooks/hooks.json is missing\"]}]"
  echo "== 13 Try Again while it can't load: the hooks copied in again whatever their version, the marketplace and" \
       "the plugin brought up to date, and the list asked again: it loads now"
  case_home "$failing"
  mkdir -p "$(dirname "$copy")" && cp -R "$T/hooks" "$copy" && rm "$copy/hooks/hooks.json"
  printf '%s\n' "[$mine]" > "$T/home/list-after.json"
  connect --before --answer retry
  echo "   its hooks.json: $([ -f "$copy/hooks/hooks.json" ] && echo "there again" || echo missing)"
  echo "== 14 Try Again, and it still can't load: what it says now"
  case_home "$failing"; connect --before --answer retry
}
. "$REPO/tests/lib.sh"
APP=$(built_app "$T") || exit 1
plugin=$(plugin_cases 2>&1 | sed -e "s|$T|T|g" -e 's/+[0-9a-f]\{8\}/+<hash>/g')
compare "Whozmove's plugin" "$REPO/$HERE/plugin.expected.txt" "$plugin" "${1:-}" || status=1
exit $status
