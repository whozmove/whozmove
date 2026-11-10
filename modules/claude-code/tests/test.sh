#!/bin/bash
# The Claude Code module's tests: the hooks of its plugin, run against a throwaway HOME (never your real ~/.claude),
# and what they write and print compared with hooks.expected.txt, beside this file.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Then the hooks run again on the Python in Apple's developer tools (/usr/bin/python3, 3.9), which a Mac with only
# those runs them on, when python3 here is another one; and Whozmove's plugin is put into a stand-in Claude Code as
# the app does as it opens (Whozmove --print-plugin-install), with the modules' skills for it from a sample folder of
# modules, compared with plugin.expected.txt; and Don't Wait on Me's files that go as the app opens (Whozmove
# --print-dont-wait-files), compared with dont-wait.expected.txt. Last, what a session you allow may answer for you in
# a team member's session (Whozmove --print-answer-for), compared with answer-for.expected.txt; what a sample
# transcript's replies used today (Whozmove --print-spent), compared with spent.expected.txt; Claude's reply to words
# put into its prompt (Whozmove --print-reply), compared with reply.expected.txt; words handed to a session's own hook
# between its steps (Whozmove --print-between-steps), compared with between-steps.expected.txt; which commands left
# running in the background are Whozmove's own waits, left off the row (Whozmove --print-own-waits), compared with
# own-waits.expected.txt; how long an ended session stays listed while it waits (Whozmove --print-kept-waits),
# compared with kept-waits.expected.txt; a question asked on a
# session's side, run by nothing (Whozmove --print-aside), compared with aside.expected.txt; that a note a session
# wrote is read back without waiting for another's transcript to be read (Whozmove --print-writing-wait), compared
# with writing-wait.expected.txt; how each line of a sample transcript got there, as Keys is told it (Whozmove
# --print-record-how), compared with record-how.expected.txt; what a session's reads keep across restarts, and that
# going on from it reads only what's new and comes to a read from the start (Whozmove --print-reads), compared with
# reads.expected.txt; and its part of the page (page-cases.js), compared with page.expected.txt.
#
# Prints the difference and exits 1 if anything changed.
#   modules/claude-code/tests/test.sh            run and compare
#   modules/claude-code/tests/test.sh --update   run and save the output as the new expected (after a change you meant)
# Needs python3, git, clang and perl. Takes about a minute for each Python: the permission hook is waited on in real
# time.
cd "$(dirname "$0")/../../.." || exit 1
. tests/sandboxed.sh "$@"
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
# In /tmp rather than $TMPDIR: the panel's socket is in Whozmove's folder there, and a socket's path can't be longer
# than 103 bytes. Where /tmp is refused (Claude Code's sandbox), its own temporary folder, which is short there.
T=$(mktemp -d /tmp/wz-hooks.XXXXXX 2>/dev/null || mktemp -d "${TMPDIR:-/tmp}/wz-hooks.XXXXXX") || exit 1
T=$(cd "$T" && pwd -P) || exit 1
D="$T/$APPDIR"
# Where the stand-in panel mirrors what the hook asks it over its line, and takes the test's answers from (never
# Whozmove's own folder).
L="$T/line"
# Stand-in processes are started detached, their pids kept in $T/pids so they're stopped however this ends.
trap 'kill $(cat "$T/pids" 2>/dev/null) 2>/dev/null; rm -rf "$T"' EXIT
detached() { local pid; pid=$("$@" >/dev/null 2>&1 & echo $!); echo $pid >> "$T/pids"; echo $pid; }
mkdir -p "$D/sessions" "$T/.claude/sessions" "$T/.claude/projects/p" "$T/repo" "$T/Applications/$EXE.app"
# Where the app runs from, as it notes it in its folder each time it opens: the hooks record only while it's there.
echo "$T/Applications/$EXE.app" > "$D/app"
# Where a Unix socket can't be made or reached here (Claude Code's sandbox), each section that goes over the hook's
# line fails at once, saying why, rather than waiting out each of its timeouts; it's never compared, nor recorded.
. "$REPO/tests/lib.sh"
SOCKETS=$(sockets_refused "$T")
refused_here() { echo "$1: couldn't run here, as $SOCKETS"; status=1; }
git -C "$T/repo" init -q -b main && git -C "$T/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
# A worktree of it, whose .git is a file naming the real git folder: a code review there is noted on its own branch.
git -C "$T/repo" worktree add -q -b side "$T/side"
# The permission hook asks only while a process with the app's name (the panel) is running, and only over a line to the
# panel's own process: the stand-in for it (stand-in-app.c), compiled under that name.
clang -o "$T/$EXE" "$REPO/$HERE/stand-in-app.c" || exit 1
# The stand-in panel mirrors a request away a moment after its hook's line closes: what's left is counted once it has.
settled() { for i in $(seq 1 100); do [ -z "$(ls "$L/asks" 2>/dev/null)" ] && break; sleep 0.05; done; }
# The request the hook has put to the stand-in panel: $f where its answer and hold go, and $fs what it asked, which
# stays readable once the hook is done with it (the stand-in's seen/, numbered in the order they came), both empty if
# none came. It's the first the stand-in saw after mark_request, which each case runs just before it starts its hook,
# so one a busy Mac's hook was done with before this looked is found too, and never an earlier case's. Waited for up to
# 20s, as the hook can be slow to start while the Mac is busy (it's there in well under a second otherwise). When none
# came, what the stand-in's log says of its lines meanwhile is shown, with the times this waited between, so a failure
# says whether the hook asked late, never reached the panel, or its line closed.
SEEN_MARK=0
mark_request() { SEEN_MARK=$(ls "$L/seen" 2>/dev/null | grep -c '\.json$'); }
await_request() {
  local began
  began=$(date +%s)
  fs="$L/seen/$((SEEN_MARK + 1)).json"
  for i in $(seq 1 200); do
    if [ -f "$fs" ]; then
      f="$L/asks/$(python3 -c "import json, sys; print(json.load(open(sys.argv[1]))['id'])" "$fs").json"
      return 0
    fi
    sleep 0.1
  done
  echo "   no request came between $began and $(date +%s); the stand-in's log from a little before:"
  awk -v t=$((began - 5)) '$1 >= t' "$L/log" 2>/dev/null | sed 's/^/     /'
  f=; fs=; return 1
}
# Waits until $1 seconds after the request was asked, by its own clock, rather than for a fixed time from whenever this
# got round to looking, which a busy Mac makes late.
at_plus() { python3 -c "import json, sys, time
time.sleep(max(0, json.load(open(sys.argv[1]))['at'] / 1000 + float(sys.argv[2]) - time.time()))" "$fs" "$1"; }
# The panel's answer to that request, or its hold, written beside it in the test's own folder: with no request, never
# anywhere else, and it says so.
answer_request() {  # $1 = the answer json
  [ -n "$f" ] || { echo "   no request to answer"; return 1; }
  echo "$1" > "${f%.json}.answer.json"
}
hold_request() { [ -n "$f" ] && touch "${f%.json}.held"; }
# The stand-in panel: listening on the panel's socket, mirroring into $L (or the folder given).
panel() {
  local pid
  pid=$(detached env STAND_IN_LOG="${1:-$L}/log" "$T/$EXE" "$D/hook.sock" python3 "$REPO/$HERE/stand-in-panel.py" \
    "${1:-$L}")
  for i in $(seq 1 40); do [ -d "${1:-$L}/asks" ] && break; sleep 0.1; done
  echo $pid
}

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
# Moves when the session's compaction began to that many seconds from now (back, for a negative number), so a step
# counts as coming just after it, or a second on, however slowly this Mac runs the hooks: each run starts a Python,
# and macOS's own can take a few hundred milliseconds on a busy Mac.
began() { python3 - "$D/sessions/$1.json" "$2" <<'PY'
import json, sys, time
d = json.load(open(sys.argv[1]))
d['compactingAt'] = int((time.time() + float(sys.argv[2])) * 1000)
json.dump(d, open(sys.argv[1], 'w'))
PY
}
C="\"cwd\": \"$T/repo\""
echo "== 1 prompt"
run "{\"session_id\":\"s1\",\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"please fix the tests\",
     \"permission_mode\":\"auto\",$C}"
show s1
echo "== 1a a session id that isn't one: nothing written, in Whozmove's folder or out of it"
LONG_ID=$(printf '%0129d' 0 | tr 0 a)  # one past the longest id taken
for id in "../escape" "a/b" "" "$LONG_ID"; do
  run "{\"session_id\":\"$id\",\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"hi\",$C}"
done
echo "   outside sessions: $(ls "$D" | grep -c escape) · in it: $(ls "$D/sessions" | grep -vc '^s1\.json')"
echo "== 1b input that isn't an event: nothing done, no error"; run '[]'; run 'x'
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
began c2 60
run "{\"session_id\":\"c2\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Read\",\"tool_input\":{},$C}"
run "{\"session_id\":\"c2\",\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Read\",\"tool_input\":{},$C}"
show c2
began c2 -2
run "{\"session_id\":\"c2\",\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Read\",\"agent_id\":\"ag2\",
     \"tool_input\":{},$C}"
run "{\"session_id\":\"c2\",\"hook_event_name\":\"Notification\",\"message\":\"Claude needs your permission\",
     \"notification_type\":\"permission_prompt\",$C}"
show c2
run "{\"session_id\":\"c2\",\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Read\",\"tool_input\":{},$C}"
show c2
run "{\"session_id\":\"c3\",\"hook_event_name\":\"PreCompact\",\"trigger\":\"manual\",$C}"
began c3 -2
run "{\"session_id\":\"c3\",\"hook_event_name\":\"Notification\",\"message\":\"Claude is waiting for your input\",
     \"notification_type\":\"idle_prompt\",$C}"
show c3
echo "== 20 background work: a job started is noted, each Stop's list is taken as it is, a background agent's end and"
echo "   its steps; a sub-agent's own job, a foreground Agent call and a hand-back change nothing"
# Each job the record keeps, its times as "ms", and the session's own live line.
jobs() { python3 - "$D/sessions/$1.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for k, job in sorted((d.get('background') or {}).items()):
    print(f'   {k}: ' + json.dumps({f: ('ms' if f.endswith('At') else v) for f, v in sorted(job.items())}))
print('   jobs:', len(d.get('background') or {}), '· live line:', json.dumps(d.get('activity')),
      '· transcript noted:', str(d.get('transcriptPath', '')).endswith('/b1.jsonl'),
      '· the turn reached:', json.dumps(d.get('turnReached')))
PY
}
run "{\"session_id\":\"b1\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Agent\",
     \"tool_input\":{\"description\":\"Review the native side\",\"prompt\":\"…\",\"subagent_type\":\"general-purpose\"},
     \"tool_response\":{\"isAsync\":true,\"status\":\"async_launched\",\"agentId\":\"a01\",
                        \"description\":\"Review the native side\"},$C}"
run "{\"session_id\":\"b1\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",
     \"tool_input\":{\"command\":\"npm run dev\",\"description\":\"Start the dev server\",\"run_in_background\":true},
     \"tool_response\":{\"stdout\":\"\",\"backgroundTaskId\":\"b02\"},$C}"
# Moved to the background part-way through (Ctrl+B): the call didn't ask for it, but Claude Code's answer says so.
run "{\"session_id\":\"b1\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",
     \"tool_input\":{\"command\":\"sleep 30\"},\"tool_response\":{\"stdout\":\"\",\"backgroundTaskId\":\"b03\"},$C}"
# A foreground Agent call's answer, and a job a sub-agent started (its own, handed back to it).
run "{\"session_id\":\"b1\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Agent\",
     \"tool_input\":{\"description\":\"Find the tests\"},\"tool_response\":{\"status\":\"completed\",\"agentId\":\"a04\"},$C}"
run "{\"session_id\":\"b1\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",\"agent_id\":\"a01\",
     \"tool_input\":{\"command\":\"sleep 9\"},\"tool_response\":{\"backgroundTaskId\":\"b05\"},$C}"
jobs b1
# The background agent's step goes on its job, not on the session's live line.
run "{\"session_id\":\"b1\",\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Read\",\"agent_id\":\"a01\",
     \"tool_input\":{\"file_path\":\"$T/repo/Storage.m\"},$C}"
run "{\"session_id\":\"b1\",\"hook_event_name\":\"Stop\",\"last_assistant_message\":\"Started them.\",
     \"transcript_path\":\"$T/.claude/projects/p/b1.jsonl\",
     \"background_tasks\":[{\"id\":\"a01\",\"type\":\"subagent\",\"status\":\"running\",
                            \"description\":\"Review the native side\"},
                           {\"id\":\"b02\",\"type\":\"shell\",\"status\":\"running\",\"description\":\"\",
                            \"command\":\"npm run dev\"},
                           {\"id\":\"t06\",\"type\":\"teammate\",\"status\":\"pending\",\"description\":\"Write the docs\"}],
     $C}"
jobs b1
# A hand-back is Claude's turn: the list waits for that turn's Stop.
run "{\"session_id\":\"b1\",\"hook_event_name\":\"UserPromptSubmit\",
     \"prompt\":\"<task-notification><task-id>a01</task-id><status>completed</status></task-notification>\",$C}"
run "{\"session_id\":\"b1\",\"hook_event_name\":\"SubagentStop\",\"agent_id\":\"a01\",\"agent_type\":\"general-purpose\",
     \"agent_transcript_path\":\"$T/a01.jsonl\",\"stop_hook_active\":false,$C}"
jobs b1
# A Stop from a Claude Code that sends no list keeps it; an empty list clears it.
run "{\"session_id\":\"b1\",\"hook_event_name\":\"Stop\",\"last_assistant_message\":\"Done.\",$C}"
jobs b1
run "{\"session_id\":\"b1\",\"hook_event_name\":\"Stop\",\"last_assistant_message\":\"All done.\",\"background_tasks\":[],$C}"
jobs b1
# Whether each shell command is recorded just as it was written (`exact`), which is the only time the app may leave a
# job off its row as Whozmove's own wait: a plain wait is; one with a line break, \r\n or a tab in it, or long enough
# to be cut, isn't, as its record (joined, folded, cut) could read as one; and the same from a turn's stop list.
LONG="echo$(printf ' a long word%.0s' $(seq 1 30))"
for job in "b91|ask-panel.sh wait" "b92|ask-panel.sh\\nticket --wait" "b93|ask-panel.sh\\r\\nticket --wait" \
           "b94|ask-panel.sh\\twait" "b95|$LONG"; do
  run "{\"session_id\":\"b9\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",
       \"tool_input\":{\"command\":\"${job#*|}\"},\"tool_response\":{\"backgroundTaskId\":\"${job%%|*}\"},$C}"
done
jobs b9
run "{\"session_id\":\"b9\",\"hook_event_name\":\"Stop\",\"last_assistant_message\":\"Waiting.\",
     \"background_tasks\":[{\"id\":\"b91\",\"type\":\"shell\",\"status\":\"running\",\"command\":\"ask-panel.sh wait\"},
                           {\"id\":\"b92\",\"type\":\"shell\",\"status\":\"running\",
                            \"command\":\"ask-panel.sh\\nticket --wait\"}],$C}"
jobs b9
# An event from before the list last changed (the hooks run on their own) changes nothing: a start that comes in late.
python3 - "$D/sessions/b1.json" <<'PY'
import json, sys, time
d = json.load(open(sys.argv[1]))
d['backgroundAt'] = int((time.time() + 60) * 1000)
json.dump(d, open(sys.argv[1], 'w'))
PY
run "{\"session_id\":\"b1\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",
     \"tool_input\":{\"command\":\"sleep 1\"},\"tool_response\":{\"backgroundTaskId\":\"b07\"},$C}"
jobs b1
# A damaged record (a time that isn't a number) is read as no time, so the session is still recorded; an id that isn't
# plain is no job of Claude Code's; and a test run sent to the background has tested nothing yet.
python3 - "$D/sessions/b1.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d.update(backgroundAt='soon', background={'b09': {'type': 'shell', 'what': 'x', 'startedAt': 'then', 'stepAt': []}})
json.dump(d, open(sys.argv[1], 'w'))
PY
run "{\"session_id\":\"b1\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",
     \"tool_input\":{\"command\":\"make test\"},\"tool_response\":{\"backgroundTaskId\":\"b10\"},$C}"
run "{\"session_id\":\"b1\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",
     \"tool_input\":{\"command\":\"ls\"},\"tool_response\":{\"backgroundTaskId\":\"../x\"},$C}"
run "{\"session_id\":\"b1\",\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Read\",\"agent_id\":[\"a01\"],
     \"tool_input\":{},$C}"
jobs b1
# A sub-agent's test run sent to the background has tested nothing yet either, and it's no job of the session's.
run "{\"session_id\":\"b2\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",\"agent_id\":\"a11\",
     \"tool_input\":{\"command\":\"make test\"},\"tool_response\":{\"backgroundTaskId\":\"b12\"},$C}"
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print('   a sub-agent\'s, in the background: jobs', len(d.get('background') or {}), '· the turn reached', json.dumps(d.get('turnReached')))" "$D/sessions/b2.json"

# Permission hook. perl's alarm is the timeout for cases that must end on their own at once.
echo "== P1 panel not running"
echo '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"ls"}}' | HOME="$T" "$PY" "$P"
echo "exit=$?"
ls "$L/asks" 2>/dev/null | wc -l | tr -d ' '
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
ls "$L/asks" 2>/dev/null | wc -l | tr -d ' '; rm -rf "$L/asks"
PANEL=$(panel); echo $PANEL > "$D/panel.pid"
echo "{\"pid\": $PANEL, \"sessionId\": \"s1\", \"kind\": \"interactive\", \"status\": \"busy\"}" \
  > "$T/.claude/sessions/$PANEL.json"
echo "{\"pid\": $OTHER, \"sessionId\": \"p1\", \"kind\": \"print\"}" > "$T/.claude/sessions/$OTHER.json"
answer() {  # $1 = event json, $2 = the panel's answer json, or SIGTERM (Claude Code stopping the hook)
  mark_request
  (echo "$1" | HOME="$T" WHOZMOVE_HOOK_WHY=1 "$PY" "$P" > "$T/out" 2>&1; echo "exit=$?" >> "$T/out") & HP=$!
  await_request || { echo "no request written"; wait $HP; cat "$T/out"; return; }
  python3 - "$fs" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print('   request keys', sorted(d))
print('   tool', d['tool'], 'session', d['sessionId'])
PY
  if [ "$2" = SIGTERM ]; then
    kill -TERM "$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['pid'])" "$fs")"
  else
    answer_request "$2"
  fi
  if [ "$3" = SIGTERM ]; then  # an answer the hook must not act on: it's still waiting a second later
    sleep 1; kill -0 $HP 2>/dev/null && echo "   still waiting"
    kill -TERM "$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['pid'])" "$fs")"
  fi
  wait $HP; settled; cat "$T/out"; echo "   left in asks: $(ls "$L/asks" | wc -l | tr -d ' ')"
}
# Which program a process runs (program_of), asked of macOS, and by ps on a Python without ctypes: the same answer.
echo "== P1b the panel's program, with ctypes and without it"
"$PY" - "$P" <<'PY'
import importlib.util, os, sys
def hook():
    spec = importlib.util.spec_from_file_location("hook", sys.argv[1])
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
asked = hook().program_of(os.getpid())
class NoCtypes:  # a Python built without ctypes: importing it fails
    def find_spec(self, name, path=None, target=None):
        if name == "ctypes" or name.startswith("ctypes."):
            raise ImportError("no ctypes here")
sys.modules.pop("ctypes", None)
sys.meta_path.insert(0, NoCtypes())
by_ps = hook().program_of(os.getpid())
print("   asked of macOS:", bool(asked), "· by ps, without ctypes:", bool(by_ps),
      "· the same program:", os.path.basename(asked or "") == os.path.basename(by_ps or "-"))
PY
echo "== P1a a session id that isn't one: left to Claude's own prompt, the panel never asked"
echo '{"session_id":"../s1","tool_name":"Bash","tool_input":{"command":"ls"}}' \
  | HOME="$T" perl -e 'alarm 3; exec @ARGV' "$PY" "$P"
echo "exit=$?"; echo "   asked: $(ls "$L/asks" 2>/dev/null | wc -l | tr -d ' ')"
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
echo "== P6a question turned down to chat about it: Claude Code's clarify words, with the answer picked so far"
answer '{"session_id":"s1","tool_name":"AskUserQuestion",
         "tool_input":{"questions":[{"question":"Where?","options":[{"label":"a"}]},
                                    {"question":"Which?","options":[{"label":"b"}]}]}}' \
       '{"behavior":"deny","clarify":true,"answers":{"Where?":" Under   the total ","Nowhere?":"x"},"message":"no"}'
echo "== P6b clarify for another tool: a plain deny"
answer '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"ls"}}' '{"behavior":"deny","clarify":true}'
echo "== P6c words with a question's deny, no clarify: dropped"
answer '{"session_id":"s1","tool_name":"AskUserQuestion","tool_input":{"questions":[]}}' \
       '{"behavior":"deny","message":"Do it anyway"}'
echo "== P7 cancelled by Claude (SIGTERM)"
answer '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"ls"}}' SIGTERM
# The panel's switch with a warm cache, asked in the panel: the question, the panel's answer, and what's passed back.
switch_answer() {
  note claude-sonnet-5-5
  (switch_event claude-sonnet-5-5 true | HOME="$T" WHOZMOVE_HOOK_WHY=1 python3 "$P" > "$T/out" 2>&1
   echo "exit=$?" >> "$T/out") & HP=$!
  for i in $(seq 1 100); do [ -f "$L/switches/m1.ask.json" ] && break; sleep 0.1; done
  [ -f "$L/switches/m1.ask.json" ] || { echo "no question asked"; wait $HP; cat "$T/out"; return; }
  python3 - "$L/switches/m1.ask.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print('   question', {k: d[k] for k in ('sessionId', 'from', 'to', 'tokens')})
PY
  echo "$1" > "$L/switches/m1.answer.json"
  wait $HP; cat "$T/out"; echo "   left in switches: $(ls "$D/switches" | wc -l | tr -d ' ')"
  # The stand-in takes its copy of the question away only once it sees the hook's line close, so the next case
  # waits for that: otherwise it could find this one's copy, gone as it reads it.
  for i in $(seq 1 40); do [ -f "$L/switches/m1.ask.json" ] || break; sleep 0.05; done
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
echo "== P7d a bare allow for a plan is dropped"; answer "$PLAN" '{"behavior":"allow"}' SIGTERM
echo "== P7f a plan approved for you (approvePlan): an allow with an empty input, never the panel's"
answer "$PLAN" '{"behavior":"allow","approvePlan":true,"updatedInput":{"plan":"Something else"}}'
echo "== P7g approvePlan on a request for your OK is dropped"
answer '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"ls"}}' '{"behavior":"allow","approvePlan":true}' SIGTERM
echo "== P7e notes and stop ignored for other tools"
answer '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"ls"}}' '{"behavior":"deny","stop":true,"message":"x"}'
step_aside() {
  echo "$1" | HOME="$T" perl -e 'alarm 3; exec @ARGV' "$PY" "$P"; echo "exit=$?"
  ls "$L/asks" 2>/dev/null | grep -vc answer; rm -f "$L/asks/"*
}
echo "== P8 malformed input"; echo 'nope' | HOME="$T" "$PY" "$P"; echo "exit=$?"
echo "== P9 sub-agent request"
step_aside '{"session_id":"s1","agent_id":"ag1","tool_name":"Bash","tool_input":{"command":"ls"}}'
echo "== P11 non-interactive session"; step_aside '{"session_id":"p1","tool_name":"Bash","tool_input":{"command":"ls"}}'
echo "== P12 unknown session"; step_aside '{"session_id":"zz","tool_name":"Bash","tool_input":{"command":"ls"}}'
echo "== P13 list input"; step_aside '[]'
echo "== perms"; stat -f '%Lp %N' "$D" "$D/sessions" "$D/sessions/s1.json"

# The permission hook steps aside once the request is settled in Claude (the call's result lands in the
# transcript), once Claude Code says the session has been idle since the request, or once the session ends.
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
  : > "$T/out"; mark_request
  (echo "{\"session_id\":\"s9\",\"tool_name\":\"AskUserQuestion\",\"tool_input\":$INPUT$1}" \
     | HOME="$T" WHOZMOVE_HOOK_WHY=1 "$PY" "$P" > "$T/out" 2>&1
   echo "exit=$?" >> "$T/out") & HP=$!
  if await_request; then echo "   request shown: 1"; else echo "   request shown: 0"; fi
}
# A case where the hook must end: room for a busy Mac, which only a case that's failing uses. finish alone is for one
# that shows the hook still waiting after that long.
ends() { finish $(( $1 + 10 )); }
finish() {  # waits up to $1 s for the hook to end on its own
  for i in $(seq 1 $(( $1 * 10 ))); do kill -0 $HP 2>/dev/null || break; sleep 0.1; done
  if kill -0 $HP 2>/dev/null; then echo "   still waiting after ${1}s"; return 1; fi
  local left; settled; left=$(ls "$L/asks" | wc -l | tr -d ' ')
  echo "   hook ended, printed: [$(grep -v exit= "$T/out")] $(grep exit= "$T/out"), requests left: $left"
}
echo "== S1 answered in Claude (result written)"; : > "$TR"; use toolu_A; start ""; sleep 1; result toolu_A; ends 4
echo "== S2 call written to the transcript only after the hook started"
: > "$TR"; start ""; sleep 1.5; use toolu_B; sleep 1; result toolu_B; ends 4
echo "== S3 Claude Code gives the call id"
: > "$TR"; use toolu_C; use toolu_other; start ',"tool_use_id":"toolu_C"'; sleep 1; result toolu_C; ends 4
echo "== S4 a hook-progress line and another call's result don't count; the panel's answer still does"
: > "$TR"; use toolu_D; start ""; progress toolu_D; result toolu_zzz; finish 3
await_request; answer_request '{"behavior":"deny"}'; ends 3
# A plan's input as the request carries it, read again from its file after you changed it, so it isn't the call's.
plan_use() {
  local call="{\"type\":\"tool_use\",\"id\":\"$1\",\"name\":\"ExitPlanMode\",\"input\":{\"plan\":\"# Old\",\"planFilePath\":\"/p.md\"}}"
  echo "{\"type\":\"assistant\",\"message\":{\"content\":[$call]}}" >> "$TR"
}
plan_start() {
  : > "$T/out"; mark_request
  (echo '{"session_id":"s9","tool_name":"ExitPlanMode","tool_input":{"plan":"# New","planFilePath":"/p.md"}}' \
     | HOME="$T" WHOZMOVE_HOOK_WHY=1 "$PY" "$P" > "$T/out" 2>&1
   echo "exit=$?" >> "$T/out") & HP=$!
  if await_request; then echo "   request shown: 1"; else echo "   request shown: 0"; fi
}
# Claude Code's record of a request it made, which holds the conversation's calls again.
request_record() {
  local call="{\"type\":\"tool_use\",\"id\":\"$1\",\"name\":\"ExitPlanMode\",\"input\":{}}"
  echo "{\"type\":\"api-request-blob\",\"message\":{\"content\":[$call]}}" >> "$TR"
}
echo "== S5 a plan changed since Claude wrote it, approved in Claude; an earlier plan, settled, doesn't count"
: > "$TR"; plan_use toolu_F0; result toolu_F0; request_record toolu_F0; plan_start; sleep 1.5; plan_use toolu_F
sleep 1; result toolu_F; ends 4
echo "== S6 a plan, approved, then the turn stopped: Claude Code says the session is idle since"
: > "$TR"; plan_use toolu_G; plan_start; sleep 1.5
python3 -c "import json, sys, time
json.dump({'pid': int(sys.argv[1]), 'sessionId': 's9', 'kind': 'interactive', 'status': 'idle',
           'statusUpdatedAt': int(time.time() * 1000)}, open(sys.argv[2], 'w'))" $SESS "$T/.claude/sessions/$SESS.json"
ends 8
registry() {  # $1 = pid, $2 = status, $3 = seconds ago it took it
  python3 -c "import json, sys, time
json.dump({'pid': int(sys.argv[1]), 'sessionId': 's9', 'kind': 'interactive', 'status': sys.argv[2],
           'statusUpdatedAt': int(time.time() * 1000) - int(sys.argv[3]) * 1000}, open(sys.argv[4], 'w'))" \
    "$1" "$2" "$3" "$T/.claude/sessions/$1.json"
}
echo "== S7 idle since before the request: Claude's prompt may be up, so it waits"
registry $SESS idle 60; : > "$TR"; plan_use toolu_H; plan_start; finish 6
await_request; answer_request '{"behavior":"deny"}'; ends 3
echo "== S8 open twice: the copy it asks in goes idle since, the other works on"
registry $SESS busy 0; : > "$TR"; plan_use toolu_I; plan_start; registry $HP idle 0; ends 8
rm -f "$T/.claude/sessions/$HP.json"
echo "== S9 a plan, approved, then the turn stopped with a command still running: at its prompt (shell) since"
: > "$TR"; plan_use toolu_K; plan_start; sleep 1.5; registry $SESS shell 0; ends 8
registry $SESS busy 0
echo "== S10 an earlier plan never answered, this one written late: this one's result counts"
: > "$TR"; plan_use toolu_J0; plan_start; sleep 1.5; plan_use toolu_J; sleep 1.5; result toolu_J; ends 4
echo "== S11 the session ends"; : > "$TR"; use toolu_E; start ""; kill $SESS; ends 8

# Don't Wait on Me: for a session that doesn't wait on you, a request no one answers goes by itself, turned down for
# now. The panel's file says 300 seconds; here, 2.
dont_wait() {
  mkdir -p "$D/dont-wait"
  python3 -c "import json, sys, time
json.dump({'since': int(time.time() * 1000), 'after': int(sys.argv[2])}, open(sys.argv[1], 'w'))" \
    "$D/dont-wait/s1.json" "${1:-2}"
}
expiring() {  # $1 = event json
  : > "$T/out"; mark_request
  (echo "$1" | HOME="$T" WHOZMOVE_HOOK_WHY=1 "$PY" "$P" > "$T/out" 2>&1; echo "exit=$?" >> "$T/out") & HP=$!
  await_request
  python3 - "$fs" <<'PY2'
import json, sys
d = json.load(open(sys.argv[1]))
print('   goes by itself after:', '%ds' % ((d['expiresAt'] - d['at']) // 1000) if 'expiresAt' in d else 'never')
PY2
}
moved_on() {  # whether the request says it goes later than its wait of $1 s from when it was asked
  python3 -c "import json, sys
d = json.load(open(sys.argv[1])); print('   expiresAt moved on:', d['expiresAt'] - d['at'] > int(sys.argv[2]) * 1000)" \
    "$f" "$1"
}
BASH_ASK='{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"ls"}}'
echo "== E1 a question no one answers"
dont_wait; expiring "{\"session_id\":\"s1\",\"tool_name\":\"AskUserQuestion\",\"tool_input\":$INPUT}"; ends 5
echo "== E2 a request for your OK no one answers"; dont_wait; expiring "$BASH_ASK"; ends 5
echo "== E3 a plan never goes by itself"; dont_wait; expiring "$PLAN"; finish 4
answer_request '{"behavior":"deny"}'; ends 3
echo "== E4 a session that waits on you"; rm "$D/dont-wait/s1.json"; expiring "$BASH_ASK"; finish 4
answer_request '{"behavior":"deny"}'; ends 3
echo "== E5 held in the panel: it waits a while longer"
dont_wait 3; expiring "$BASH_ASK"; at_plus 1.5; hold_request; at_plus 3.5
kill -0 $HP 2>/dev/null && echo "   still waiting past when it would have gone"; moved_on 3; ends 4
echo "== E6 held each second while its tab is in front, then not"
dont_wait 3; expiring "$BASH_ASK"; for t in 0.5 1.5 2.5; do at_plus $t; hold_request; done; at_plus 3.5
kill -0 $HP 2>/dev/null && echo "   still waiting past when it would have gone"; ends 6
rm "$D/dont-wait/s1.json"

# The words hook (whozmove-claude-words.sh, then .py): your words from a side chat, handed in as a session's tool calls
# finish or its turn ends, as the panel hands them, and nothing otherwise. Before J2, whose listener takes the panel's
# socket.
W="$PLUGIN/hooks/whozmove-claude-words.sh"
words_hook() {  # $1 = the event json; what it prints, and what the stand-in panel was asked
  rm -f "$L/words/"*.asked.json
  echo "$1" | HOME="$T" PATH="$(dirname "$(command -v "$PY")"):$PATH" /bin/sh "$W"; echo "   exit=$?"
  echo "   asked the panel: $(cat "$L/words/"*.asked.json 2>/dev/null || echo nothing)"
}
rm -f "$D/words-waiting"
echo "== W1 no words waiting: the flag isn't there, so it ends before Python starts"
printf 'Do the smaller migration first.' > "$L/words/s1.txt"
words_hook '{"hook_event_name":"PostToolBatch","session_id":"s1"}'
: > "$D/words-waiting"
echo "== W2 words waiting for the session: handed in as its tool calls finish"
words_hook '{"hook_event_name":"PostToolBatch","session_id":"s1"}'
echo "== W3 asked again: they went once"
words_hook '{"hook_event_name":"PostToolBatch","session_id":"s1"}'
echo "== W4 as its turn ends: handed in as Stop's additional context"
printf 'Keep the old table.' > "$L/words/s1.txt"
words_hook '{"hook_event_name":"Stop","session_id":"s1","stop_hook_active":false}'
echo "== W5 a sub-agent's tool calls: nothing asked"
printf 'For the session itself.' > "$L/words/s1.txt"
words_hook '{"hook_event_name":"PostToolBatch","session_id":"s1","agent_id":"a1","agent_type":"Explore"}'
rm -f "$L/words/s1.txt"
echo "== W6 another event: nothing asked"
words_hook '{"hook_event_name":"PreToolUse","session_id":"s1"}'
echo "== W7 malformed input"
words_hook 'nope'
echo "== W8 no panel running: nothing asked, nothing said"
echo $OTHER > "$D/panel.pid"
words_hook '{"hook_event_name":"PostToolBatch","session_id":"s1"}'
echo $PANEL > "$D/panel.pid"
rm -f "$D/words-waiting"

# Only the panel answers, down the line the hook opened: an answer written in Whozmove's folder, as any program running
# as you could write one, does nothing; and a listener that isn't the panel's own process is asked nothing.
echo "== J1 an answer written in Whozmove's folder does nothing"
expiring "$BASH_ASK"
mkdir -p "$D/asks"; echo '{"behavior":"allow"}' > "$D/asks/$(basename "$f" .json).answer.json"
sleep 1.5; kill -0 $HP 2>/dev/null && echo "   still waiting after 1.5s"
answer_request '{"behavior":"deny"}'; ends 3
rm -rf "$D/asks"
echo "== J2 a listener at the panel's socket that isn't the panel: the hook asks it nothing, and steps aside"
FAKE=$(panel "$T/elsewhere"); step_aside "$BASH_ASK"
echo "   asked of it: $(ls "$T/elsewhere/asks" | wc -l | tr -d ' ')"; kill $FAKE

# How the plugin wires the hooks (hooks/hooks.json), that the permission hook gives up waiting before Claude Code
# would stop it, and that the plugin carries the app's version.
echo "== the plugin's hooks"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$REPO/app/Info.plist")
python3 - "$PLUGIN/hooks/hooks.json" "$P" "$PLUGIN/.claude-plugin/plugin.json" "$VERSION" \
  "$REPO/modules/claude-code/app/DontWait.m" <<'PY'
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
minutes = int(re.search(r"^const NSInteger kDontWaitMinutes = (\d+);", open(sys.argv[5]).read(), re.M).group(1))
print("   and a request the app lets go by itself:", minutes * 60 <= wait - 100)
print("   the plugin's version is the app's:", json.load(open(sys.argv[3]))["version"] == sys.argv[4])
PY
# The Claude Code version the real run checks with (real.sh, through claude-code.txt) is the one the docs say Whozmove
# is tested with, so moving one moves the other.
python3 - "$REPO/$HERE/claude-code.txt" "$REPO/docs/using/install.md" <<'PY'
import re, sys
pin = next(line.split()[1] for line in open(sys.argv[1]) if line.startswith("checked "))
section = re.search(r"^## What it's tested with\s*$(.*?)(?=^## |\Z)", open(sys.argv[2]).read(), re.M | re.S)
named = re.search(r"Claude Code (\d+\.\d+\.\d+)", section.group(1) if section else "")
print("   the docs name the Claude Code the real run checks with:", bool(named) and named.group(1) == pin)
PY
# The real Claude Code run (real.sh) never runs one where it could read a sign-in: without --throwaway-mac it refuses
# anywhere, and with it, on any Mac its own check turns down (this one, unless it's a virtual Mac or GitHub's runner, with
# no Claude Code sign-in in its keychain), it refuses before it downloads or starts anything. Where the check allows it,
# there's nothing to turn down here.
# Each is asked with a curl that only fails and an empty download cache, so a guard that ever broke ends in "couldn't
# download" and fails here, and never fetches or runs a Claude Code.
echo "== the real Claude Code run, on a Mac that isn't throwaway"
mkdir -p "$T/no-network" "$T/no-downloads"
printf '#!/bin/sh\nexit 1\n' > "$T/no-network/curl" && chmod 755 "$T/no-network/curl"
refuse() { PATH="$T/no-network:$PATH" WHOZMOVE_BUILD_CACHE="$T/no-downloads" "$REPO/$HERE/real.sh" "$@"; }
refuse --newest > "$T/real-refused" 2>&1
echo "   without --throwaway-mac, refused: $([ $? = 2 ] && grep -q "runs only on a throwaway Mac" "$T/real-refused" &&
  echo True || echo False)"
why=$("$REPO/$HERE/real.sh" --machine)
refused=True
if [ "$why" != "a real Claude Code may run here" ]; then
  refuse --throwaway-mac --newest > "$T/real-refused" 2>&1
  [ $? = 2 ] && grep -qF "$why" "$T/real-refused" || refused=False
fi
echo "   with it, refused wherever its check turns the Mac down: $refused"
}

. "$REPO/tests/compare.sh"
status=0
if [ -n "${HOOKS_PYTHON:-}" ]; then
  [ -z "$SOCKETS" ] || { refused_here "Hooks on $HOOKS_PYTHON"; exit 1; }
  out=$(tests 2>&1 | sed "s|$T|T|g")
  compare "Hooks on $HOOKS_PYTHON" "$REPO/$HERE/hooks.expected.txt" "$out" || exit 1
  exit 0
fi
if [ -n "$SOCKETS" ]; then
  refused_here Hooks
else
  out=$(tests 2>&1 | sed "s|$T|T|g")
  compare Hooks "$REPO/$HERE/hooks.expected.txt" "$out" "${1:-}" || status=1
fi
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
# The modules' skills for Claude Code, from a sample folder of modules: each copied whole into the plugin's skills/,
# a new version for a skill added, changed or renamed (with none, the hooks' own, as before there were any), and two
# modules' skills of the same name stopping the copy, both named.
skill_cases() {
  . modules/claude-code/plugin.sh
  local M="$T/skill-modules" none before
  none=$(PLUGIN_MODULES="$T/no-modules" plugin_version)
  listed() {  # $1 = the copy: its skills' files, with their modes
    (cd "$1" && find skills -type f | LC_ALL=C sort | while read -r f; do echo "   $f $(stat -f %Lp "$f")"; done)
  }
  versus() {  # how the version with $M's skills compares with $1
    local now; now=$(PLUGIN_MODULES="$M" plugin_version)
    [ "$now" = "$1" ] && echo "   the same version" || echo "   a new version"
  }
  echo "== K1 no module with a skill: the version the plugin's own files alone name (its hooks and its script)"
  local own_only
  own_only=$({ (cd modules/claude-code/plugin && cat .claude-plugin/plugin.json .claude-plugin/marketplace.json \
    hooks/hooks.json hooks/whozmove-claude.py hooks/whozmove-claude-permission.py hooks/whozmove-claude-words.sh \
    hooks/whozmove-claude-words.py); cat app/ask-panel.sh; } \
    | shasum | cut -c1-8)
  [ "${none##*+}" = "$own_only" ] && echo "   the same version" || echo "   a new version"
  echo "== K6 the script a session asks the panel with, carried at scripts/, runnable, as the app's own"
  PLUGIN_MODULES="$T/no-modules" copy_plugin "$T/own-copy"
  local copied="$T/own-copy/scripts/ask-panel.sh"
  echo "   scripts/ask-panel.sh $(stat -f %Lp "$copied"):" \
    "$(cmp -s "$copied" app/ask-panel.sh && echo "the same as app/ask-panel.sh" || echo differs)"
  echo "   …a change to it:"
  mkdir -p "$T/tree/app" "$T/tree/modules/claude-code"
  cp -R modules/claude-code/plugin "$T/tree/modules/claude-code/"
  cp app/ask-panel.sh "$T/tree/app/"
  local mine changed
  mine=$(cd "$T/tree" && PLUGIN_MODULES="$T/no-modules" plugin_version)
  echo '# changed' >> "$T/tree/app/ask-panel.sh"
  changed=$(cd "$T/tree" && PLUGIN_MODULES="$T/no-modules" plugin_version)
  [ "$mine" = "$changed" ] && echo "   the same version" || echo "   a new version"
  mkdir -p "$M/notes/plugin/skills/hand-over/scripts" "$M/notes/plugin/skills/drafts" "$M/maps/plugin/skills/find-place"
  printf -- '---\nname: hand-over\n---\nHand the user a task.\n' > "$M/notes/plugin/skills/hand-over/SKILL.md"
  printf '#!/bin/sh\necho sent\n' > "$M/notes/plugin/skills/hand-over/scripts/send.sh"
  chmod +x "$M/notes/plugin/skills/hand-over/scripts/send.sh"
  touch "$M/notes/plugin/skills/hand-over/.DS_Store" "$M/notes/plugin/skills/drafts/notes.md"
  printf 'Find a place.\n' > "$M/maps/plugin/skills/find-place/SKILL.md"
  echo "== K2 two modules' skills, each copied whole (but the Finder's files); a folder with no SKILL.md isn't one"
  PLUGIN_MODULES="$M" copy_plugin "$T/with-skills"; listed "$T/with-skills"; versus "$none"
  echo "== K3 a skill's words changed"
  before=$(PLUGIN_MODULES="$M" plugin_version)
  printf 'Find a place on the map.\n' > "$M/maps/plugin/skills/find-place/SKILL.md"; versus "$before"
  echo "== K4 a skill renamed"
  before=$(PLUGIN_MODULES="$M" plugin_version)
  mv "$M/maps/plugin/skills/find-place" "$M/maps/plugin/skills/look-up"; versus "$before"
  echo "== K5 two modules with a skill of the same name: no copy"
  mkdir -p "$M/tasks/plugin/skills/hand-over" && printf 'Mine too.\n' > "$M/tasks/plugin/skills/hand-over/SKILL.md"
  PLUGIN_MODULES="$M" copy_plugin "$T/clashing" && echo "   copied" || echo "   stopped"
  [ -e "$T/clashing" ] && echo "   a copy was made" || echo "   no copy"
}
plugin=$({ plugin_cases; skill_cases; } 2>&1 | sed -e "s|$T|T|g" -e 's/+[0-9a-f]\{8\}/+<hash>/g')
compare "Whozmove's plugin" "$REPO/$HERE/plugin.expected.txt" "$plugin" "${1:-}" || status=1

# The panel's own end of the hook's line (Whozmove --print-hook-line, which answers each request "deny"), with the
# real hook run from inside a stand-in session's process, as Claude Code runs it: a request naming its own session is
# taken and answered; one naming another session, from the same process, is refused, and the hook steps aside, so
# Claude asks itself; and a second line asking with the id of a request still waiting is refused, so a press on one
# row can't answer another's. The stand-in session runs the hook with the event in `go`, or the script in `raw`.
line_cases() {
  local home="$T/lh" real other print
  mkdir -p "$home/.claude/sessions" "$home/$APPDIR"
  # shellcheck disable=SC2016
  real=$(detached bash -c 'while :; do
    if [ -e "$1/go" ]; then ev=$(cat "$1/go"); rm "$1/go"; echo "$ev" | HOME="$1" "$2" "$3" > "$1/said" 2>&1
      touch "$1/went"; fi
    if [ -e "$1/raw" ]; then HOME="$1" "$2" "$1/raw" > "$1/said" 2>&1; rm "$1/raw"; touch "$1/went"; fi
    sleep 0.1
  done' real "$home" "$PY" "$P")
  other=$(detached sleep 600)
  echo "{\"pid\": $real, \"sessionId\": \"s-real\", \"kind\": \"interactive\", \"status\": \"busy\",
         \"startedAt\": $(python3 -c 'import time; print(int(time.time() * 1000))')}" > "$home/.claude/sessions/$real.json"
  echo "{\"pid\": $other, \"sessionId\": \"s-other\", \"kind\": \"interactive\", \"status\": \"busy\",
         \"startedAt\": $(python3 -c 'import time; print(int(time.time() * 1000))')}" > "$home/.claude/sessions/$other.json"
  HOME="$home" "$APP" --print-hook-line 60 > "$T/line.txt" 2>&1 & print=$!
  for i in $(seq 1 100); do [ -S "$home/$APPDIR/hook.sock" ] && break; sleep 0.1; done
  ask() {  # $1 = the session the request names
    rm -f "$home/went"
    echo "{\"session_id\":\"$1\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}" > "$home/go"
    for i in $(seq 1 100); do [ -e "$home/went" ] && break; sleep 0.1; done
    echo "   the hook printed: [$(cat "$home/said")]"
  }
  echo "== L1 from inside s-real, naming s-real: taken, and answered"; ask s-real
  echo "== L2 from inside s-real, naming s-other: refused, and the hook steps aside"; ask s-other
  echo "== L3 from inside s-real, a second line asking with the id of one still waiting: refused"
  rm -f "$home/went"
  cat > "$home/raw.tmp" <<'PY'
import json, os, socket
path = os.path.expanduser("~/Library/Application Support/Whozmove/hook.sock")
ask = {"ask": {"id": "abc123", "sessionId": "s-real", "tool": "Bash", "input": {}, "at": 0}}
first, second = socket.socket(socket.AF_UNIX), socket.socket(socket.AF_UNIX)
first.connect(path)
first.sendall((json.dumps(ask) + "\n").encode())
print("   the first is answered:", first.recv(4096).decode().strip())
second.connect(path)
second.sendall((json.dumps(ask) + "\n").encode())
print("   the second is told:", second.recv(4096).decode().strip())
PY
  mv "$home/raw.tmp" "$home/raw"
  for i in $(seq 1 100); do [ -e "$home/went" ] && break; sleep 0.1; done
  cat "$home/said"
  touch "$home/$APPDIR/hook-line.done"; wait $print
  echo "== what the panel's end says of each"; sed 's/answered [0-9a-f]*/answered <id>/' "$T/line.txt"
  kill $real $other
}
if [ -n "$SOCKETS" ]; then
  refused_here "The hook's line"
else
  line=$(line_cases 2>&1 | sed "s|$T|T|g")
  compare "The hook's line" "$REPO/$HERE/line.expected.txt" "$line" "${1:-}" || status=1
fi

# The real Claude Code run's first record, as CI's makes it: with nothing to compare with yet, --record-if-missing
# records the run, says so, keeps the record with the run's own and passes, the stand-in Claude Code standing in for a
# real one here; and --has-record says whether there's one. The run's hooks reach the panel down its socket, so where
# no socket can be reached it couldn't run: a run recorded there would record every request as never reaching it.
record_cases() {
  local records="$T/records" kept="$T/kept"
  mkdir -p "$records"
  echo "== with nothing to compare with yet"
  WHOZMOVE_APP="$APP" REAL_RUN_RECORDS="$records" REAL_RUN_KEEP="$kept" \
    "$REPO/$HERE/real.sh" --stand-in-claude --record-if-missing > "$T/record-run" 2>&1
  echo "   exit=$?"
  grep -E "^Nothing to compare with yet|^passed" "$T/record-run" | sed -e "s|$records|RECORDS|" -e 's/^/   /'
  echo "   kept with the run's records: $([ -s "$kept/real-stand-in.expected.txt" ] && echo yes || echo no)"
  echo "   the same as the module's own record: $(cmp -s "$records/real-stand-in.expected.txt" \
    "$REPO/$HERE/real-stand-in.expected.txt" && echo yes || echo no)"
  # Where it isn't (another Mac's runner, say), the lines that differ, so the log says why without the run's files.
  diff "$REPO/$HERE/real-stand-in.expected.txt" "$records/real-stand-in.expected.txt" 2>/dev/null | head -40 \
    | sed 's/^/     /'
  echo "== a record that's a link, pointing nowhere yet"
  mkdir -p "$T/linked"
  ln -s "$T/elsewhere/written-through.txt" "$T/linked/real-stand-in.expected.txt"
  WHOZMOVE_APP="$APP" REAL_RUN_RECORDS="$T/linked" "$REPO/$HERE/real.sh" --stand-in-claude --record-if-missing \
    > "$T/linked-run" 2>&1
  echo "   exit=$?"
  sed -e "s|$T/linked|LINKED|" -e 's/^/   /' "$T/linked-run"
  echo "   written through it: $([ -e "$T/elsewhere/written-through.txt" ] && echo yes || echo no)"
  echo "== --has-record"
  REAL_RUN_RECORDS="$records" "$REPO/$HERE/real.sh" --stand-in-claude --has-record
  echo "   with one: exit=$?"
  REAL_RUN_RECORDS="$T/none" "$REPO/$HERE/real.sh" --has-record
  echo "   without: exit=$?"
}
if [ -n "$SOCKETS" ]; then
  refused_here "The real run's first record"
else
  record=$(record_cases 2>&1 | sed -e "s|$T|T|g")
  compare "The real run's first record" "$REPO/$HERE/record.expected.txt" "$record" "${1:-}" || status=1
fi

# Where the real run's downloads are kept, given or by default, asking nothing of the network (a curl that only fails is
# first on PATH), wherever the test runs.
cache_cases() {
  mkdir -p "$T/no-network"
  printf '#!/bin/sh\nexit 1\n' > "$T/no-network/curl" && chmod 755 "$T/no-network/curl"
  local given default
  given=$(PATH="$T/no-network:$PATH" WHOZMOVE_BUILD_CACHE="$T/cache" "$REPO/$HERE/claude-code.sh" --cache-folder)
  echo "   given: $([ "$given" = "$T/cache" ] && echo True || echo False)"
  default=$(PATH="$T/no-network:$PATH" env -u WHOZMOVE_BUILD_CACHE "$REPO/$HERE/claude-code.sh" --cache-folder)
  local home=False
  case $default in "$HOME/Library/Caches/"*) home=True ;; esac
  echo "   by default, in the home folder's caches: $home"
}
cache=$(cache_cases 2>&1 | sed -e "s|$T|T|g")
compare "Where the real run's downloads are kept" "$REPO/$HERE/cache.expected.txt" "$cache" "${1:-}" || status=1

# Don't Wait on Me's files as the app opens (Whozmove --print-dont-wait-files): one whose session has the switch's record
# stays, and one without goes, as the menu shows the switch off there and the hook would otherwise let its requests go.
mkdir -p "$T/dw"
dont_wait_files=$(HOME="$T/dw" "$APP" --print-dont-wait-files 2>&1)
compare "Don't Wait on Me's files" "$REPO/$HERE/dont-wait.expected.txt" "$dont_wait_files" "${1:-}" || status=1

# What a session you allow may answer for you (May Send Back Plans and May Answer Questions; Whozmove
# --print-answer-for, as the panel), in a sample home: a repo shop
# with worktrees for Wren, Bea, Moss and Pip, another repo (other), and a team file naming Atlas (leading it, in shop),
# Wren, Bea, Moss, Pip, Ivy, Rex, Sol and Far (members, Far working in other) and Mine (one of yours, in shop). Sol's
# recorded session isn't running, and another, s-sol, runs in Sol's workspace, so it is Sol; and a second session,
# s-twin, runs in Wren's beside Wren's own, a duplicate. Each but
# Atlas is a stand-in session whose process runs the real permission hook for a plan (Moss, Pip and Mine: questions,
# Moss's three of them), as Claude Code would, and Long, one of yours in shop, runs it twice: a command, then a plan
# too long for the panel to show whole;
# Atlas's runs ask-panel.sh whenever `cmd` appears, so the script runs from inside its session. Another process is
# registered as Atlas's session too, idle, as anything could write in Claude Code's registry.
answer_cases() {
  local home="$T/ah" print atlas forged now name wren long
  mkdir -p "$home/.claude/sessions" "$home/$APPDIR/team" "$T/ah-atlas"
  git -C "$home" init -q -b main shop
  git -C "$home/shop" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  for name in wren bea moss pip ivy rex sol; do git -C "$home/shop" worktree add -q -b "$name" "$home/shop-$name"; done
  # Whozmove's hooks in place, before any session starts, so each session has every part of them.
  mkdir -p "$home/$APPDIR/plugin/hooks"
  cp "$P" "$home/$APPDIR/plugin/hooks/"
  sleep 1
  git -C "$home" init -q -b main other
  now=$(python3 -c 'import time; print(int(time.time() * 1000))')
  register() {  # $1 pid, $2 session, $3 name, $4 folder, $5 status, $6 seconds since its state changed
    echo "{\"pid\": $1, \"sessionId\": \"$2\", \"name\": \"$3\", \"kind\": \"interactive\", \"entrypoint\": \"cli\",
           \"cwd\": \"$4\", \"status\": \"$5\", \"startedAt\": $now,
           \"statusUpdatedAt\": $((now - ${6:-0} * 1000))}" > "$home/.claude/sessions/$1.json"
  }
  asking() {  # $1 session, $2 name, $3 folder, $4 tool, $5 its input, then the stand-in's own flags: a stand-in whose
              # real hook asks when `go` appears
    local dir="$T/ah-$1" pid
    mkdir -p "$dir"
    echo "{\"session_id\":\"$1\",\"tool_name\":\"$4\",\"cwd\":\"$3\",\"tool_input\":$5}" > "$dir/event"
    # shellcheck disable=SC2016
    pid=$(detached bash -c 'while :; do
      if [ -e "$1/go" ]; then rm "$1/go"; HOME="$2" "$3" "$4" < "$1/event" > "$1/said" 2>&1; touch "$1/went"; fi
      sleep 0.1
    done' asking "$dir" "$home" "$PY" "$P" "${@:6}")
    register "$pid" "$1" "$2" "$3" waiting
  }
  # The plan as its file holds it, as plan mode writes it before asking.
  mkdir -p "$home/plans"
  printf '# Search box, version 2\nText' > "$home/plans/p.md"
  plan=$(printf '{"plan":"# Search box, version 2\\nText","planFilePath":"%s/plans/p.md"}' "$home")
  asking s-wren Wren "$home/shop-wren" ExitPlanMode "$plan"
  asking s-bea Bea "$home/shop-bea" ExitPlanMode "$plan"
  question='{"questions":[{"question":"Which index?","options":[{"label":"Titles"},{"label":"Text"}]}]}'
  asking s-mine Mine "$home/shop" AskUserQuestion "$question"
  asking s-far Far "$home/other" ExitPlanMode "$plan"
  asking s-ivy Ivy "$home/shop-ivy" ExitPlanMode "$plan"
  asking s-rex Rex "$home/shop-rex" ExitPlanMode "$plan" --permission-mode bypassPermissions
  asking s-sol "new chimes" "$home/shop-sol" ExitPlanMode "$plan"
  asking s-twin "fix tooltips" "$home/shop-wren" ExitPlanMode "$plan"
  asking s-pip Pip "$home/shop-pip" AskUserQuestion "$question"
  asking s-moss Moss "$home/shop-moss" AskUserQuestion \
    '{"questions":[{"question":"Which index?","options":[{"label":"Titles"},{"label":"Text"}]},
      {"question":"Which pages?","multiSelect":true,"options":[{"label":"Docs"},{"label":"Blog"},{"label":"Shop"}]},
      {"question":"How many results?","kind":"number","min":1,"max":50}]}'
  # Long, a session of yours with two requests waiting, each from a hook of its own: a command, then a second later a
  # plan too long for the panel to show whole.
  mkdir -p "$T/ah-s-long"
  echo "{\"session_id\":\"s-long\",\"tool_name\":\"Bash\",\"cwd\":\"$home/shop\",
         \"tool_input\":{\"command\":\"ls\"}}" > "$T/ah-s-long/event"
  python3 -c 'import json, sys
print(json.dumps({"session_id": "s-long", "tool_name": "ExitPlanMode", "cwd": sys.argv[1],
                  "tool_input": {"plan": "# Every page\n" + "Step.\n" * 20000}}))' "$home/shop" > "$T/ah-s-long/event2"
  # shellcheck disable=SC2016
  long=$(detached bash -c 'while :; do
    if [ -e "$1/go" ]; then
      rm "$1/go"
      HOME="$2" "$3" "$4" < "$1/event" > "$1/said" 2>&1 &
      sleep 1
      HOME="$2" "$3" "$4" < "$1/event2" > "$1/said2" 2>&1 &
    fi
    sleep 0.1
  done' asking "$T/ah-s-long" "$home" "$PY" "$P")
  register "$long" s-long Long "$home/shop" waiting
  # Atlas runs as a stand-in for Claude Code's own program (stand-in.c under its name, which the print run is told
  # counts as it), in its folder, as only such a session holds the switches kept for its folder.
  mkdir -p "$T/ah-bin"; clang -O0 -o "$T/ah-bin/claude" "$REPO/$HERE/stand-in.c"
  # shellcheck disable=SC2016
  atlas=$(cd "$home/shop" && detached "$T/ah-bin/claude" -c 'while :; do
    if [ -e "$1/cmd" ]; then HOME="$2" sh "$1/cmd" > "$1/said" 2>&1; rm "$1/cmd"; touch "$1/went"; fi
    sleep 0.1
  done' atlas "$T/ah-atlas" "$home")
  register "$atlas" s-atlas Atlas "$home/shop" waiting
  forged=$(detached sleep 600)
  register "$forged" s-atlas Atlas "$home/shop" idle 60
  cat > "$home/$APPDIR/team/team.json" <<JSON
{"version": 3, "projects": {"$home/shop": {
  "lead": {"session": "s-atlas", "worktree": "$home/shop", "name": "Atlas", "since": $now},
  "members": {
    "Wren": {"session": "s-wren", "worktree": "$home/shop-wren", "part": "search"},
    "Bea": {"session": "s-bea", "worktree": "$home/shop-bea", "part": "docs"},
    "Moss": {"session": "s-moss", "worktree": "$home/shop-moss", "part": "fonts"},
    "Pip": {"session": "s-pip", "worktree": "$home/shop-pip", "part": "icons"},
    "Ivy": {"session": "s-ivy", "worktree": "$home/shop-ivy", "part": "maps"},
    "Rex": {"session": "s-rex", "worktree": "$home/shop-rex", "part": "pay"},
    "Sol": {"session": "s-sol-was", "worktree": "$home/shop-sol", "part": "sounds"},
    "Far": {"session": "s-far", "worktree": "$home/other", "part": "billing"}},
  "followed": {"Mine": {"session": "s-mine"}}}}}
JSON
  # Atlas's stand-in runs stand-in.c under Claude Code's name, and the others bash, both of which this run counts as
  # Claude Code's program; the forged one runs sleep, which it doesn't. Only Atlas works in Atlas's folder, as the
  # system says: the others' bash runs where the test does, whatever their records say.
  WHOZMOVE_STAND_IN_CLAUDE="$T/ah-bin/claude:/bin/bash" HOME="$home" "$APP" --print-answer-for 60 "$atlas" "$forged" \
    > "$T/answer.txt" 2>&1 & print=$!
  for i in $(seq 1 100); do [ -S "$home/$APPDIR/hook.sock" ] && break; sleep 0.1; done
  for name in s-wren s-bea s-mine s-far s-moss s-pip s-ivy s-rex s-sol s-twin s-long; do touch "$T/ah-$name/go"; done
  for i in $(seq 1 300); do [ -e "$home/$APPDIR/ids.json" ] && break; sleep 0.1; done
  wren=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["s-wren"])' "$home/$APPDIR/ids.json")
  moss=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["s-moss"])' "$home/$APPDIR/ids.json")
  ivy=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["s-ivy"])' "$home/$APPDIR/ids.json")
  digest=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["s-ivy"])' "$home/$APPDIR/digests.json")
  # Each request's id as whose it is, as the print run shows them.
  python3 -c 'import json, sys
for session, ask in json.load(open(sys.argv[1])).items(): print("s/%s/<%s'"'"'s>/g" % (ask, session))' \
    "$home/$APPDIR/ids.json" > "$T/ids.sed"
  cat > "$T/ah-atlas/cmd" <<SH
"$REPO/app/ask-panel.sh" waiting; echo "exit=\$?"
printf '%s\n' "Split step 2 first," "and keep the results in one list." \
  | "$REPO/app/ask-panel.sh" send-back $wren; echo "exit=\$?"
"$REPO/app/ask-panel.sh" send-back $wren < /dev/null; echo "exit=\$?"
python3 -c 'print("x" * 4001)' | "$REPO/app/ask-panel.sh" send-back $wren; echo "exit=\$?"
printf '%s\n' '{"Which index?": {"written": "Titles,\nthen text"}, "Which pages?": {"options": ["Docs", "Docs",' \
  '"Blog"]}, "How many results?": {"written": "020"}}' | "$REPO/app/ask-panel.sh" answer $moss; echo "exit=\$?"
"$REPO/app/ask-panel.sh" answer $moss < /dev/null; echo "exit=\$?"
"$REPO/app/ask-panel.sh" approve $ivy $digest; echo "exit=\$?"
"$REPO/app/ask-panel.sh" approve $ivy; echo "exit=\$?"
SH
  for i in $(seq 1 100); do [ -e "$T/ah-atlas/went" ] && break; sleep 0.1; done
  for i in $(seq 1 100); do [ -e "$T/ah-s-wren/went" ] && break; sleep 0.1; done
  for i in $(seq 1 100); do [ -e "$T/ah-s-moss/went" ] && break; sleep 0.1; done
  for i in $(seq 1 100); do [ -e "$T/ah-s-ivy/went" ] && break; sleep 0.1; done
  for i in $(seq 1 100); do [ -e "$T/ah-s-twin/went" ] && break; sleep 0.1; done
  outside=$(HOME="$home" "$REPO/app/ask-panel.sh" waiting; echo "exit=$?")
  echo "== The cases, and what the panel answers each"
  touch "$home/$APPDIR/answer-for.done"; wait $print
  cat "$T/answer.txt"
  echo "== From inside Atlas's session: waiting, send-back for Wren's plan, then with no note, with one too long, then"
  echo "   answer for Moss's question, and with no answers, then approve for Ivy's plan, and with no digest"
  sed -f "$T/ids.sed" "$T/ah-atlas/said" | sed 's|\\/|/|g'  # JSON's \/ as /, so the sample home is masked below
  echo "== From outside any session: waiting"
  echo "$outside"
  echo "== What Wren's real hook passed on to Claude"
  cat "$T/ah-s-wren/said"
  echo "== What Moss's real hook passed on to Claude"
  cat "$T/ah-s-moss/said"
  echo "== What Ivy's real hook passed on to Claude"
  cat "$T/ah-s-ivy/said"
  echo "== What Rex's real hook passed on to Claude, given allow and approvePlan from the page: nothing, still waiting"
  cat "$T/ah-s-rex/said"
  echo "== What the real hook of the second session in Wren's workspace passed on to Claude, approved by your press"
  cat "$T/ah-s-twin/said"
}
if [ -n "$SOCKETS" ]; then
  refused_here "Answered for you"
else
  answer=$(answer_cases 2>&1 | sed "s|$T|T|g")
  compare "Answered for you" "$REPO/$HERE/answer-for.expected.txt" "$answer" "${1:-}" || status=1
fi

# Which session holds the answer-for switches kept for its folder (Whozmove --print-switch-holder), by what the system
# says of each process, in a sample home with a team file: stand-in sessions this run starts, each stand-in.c under the
# name of what it stands for (claude, Claude Code's own signed build; node, an older Claude Code from npm, run by Node;
# other, any program), started, closed and made the lead in turn; and the rule alone (WhyNotHold), on made-up facts.
holder_cases() {
  local home="$T/sh" now
  mkdir -p "$home/shop" "$home/$APPDIR/team" "$T/sh-bin"
  clang -O0 -o "$T/sh-bin/claude" "$REPO/$HERE/stand-in.c"
  for name in node other; do cp "$T/sh-bin/claude" "$T/sh-bin/$name"; done
  now=$(python3 -c 'import time; print(int(time.time() * 1000))')
  cat > "$home/$APPDIR/team/team.json" <<JSON
{"version": 3, "projects": {"$home/shop": {
  "lead": {"session": "s-one", "worktree": "$home/shop", "name": "Atlas", "since": $now},
  "members": {"Wren": {"session": "s-wren", "worktree": "$home/shop-wren", "part": "search"},
              "Moss": {"session": "s-moss", "worktree": "$home/shop/wt-moss", "part": "fonts"},
              "Rook": {"session": "s-rook", "worktree": "$home", "part": "maps"}}}}}
JSON
  echo "== Ticked while another Claude Code session runs inside the folder: refused; once it's closed: on"
  echo "== Its session closes and a new one there is made the lead: on for it, and said under the header"
  echo "== Then each that can't hold them: any program counts for nothing; npm's Claude Code, another program, one"
  echo "   running elsewhere than its record says, one a Claude Code session started (signed, npm's, or in no registry"
  echo "   at all, and where that walk stops: at this run in a print run, never short in the app); then a /clear, recorded"
  echo "   as the lead, holds them; a member in a worktree inside the folder doesn't count against it, one whose record"
  echo "   names a folder above it does, and so does a second copy of the lead's own conversation"
  echo "   with a new line; one whose starting shell has exited passes (the limit the line under the header covers); and"
  echo "   one that might bypass holds all but May Approve Plans"
  WHOZMOVE_STAND_IN_CLAUDE="$T/sh-bin/claude" HOME="$home" "$APP" --print-switch-holder "$T/sh-bin" \
    "open s-one shop" "open s-two shop/sub" "tick s-one" "close s-two" "tick s-one" "why s-one" notices \
    "close s-one" "open s-three shop" "lead s-three" "why s-three" notices \
    "open s-four shop/sub as=other" "why s-three" "close s-four" \
    "open s-five shop as=node" "why s-three" "lead s-five" "why s-five" "close s-five" \
    "open s-six shop as=other" "lead s-six" "why s-six" "close s-six" \
    "open s-seven shop at=elsewhere" "lead s-seven" "why s-seven" "close s-seven" \
    "pair s-boss s-eight shop" "lead s-eight" "why s-eight" "close s-boss" \
    "pair s-npm-boss s-eleven shop as=node" "lead s-eleven" "why s-eleven" "close s-npm-boss" \
    "pair s-unlisted s-twelve shop unlisted" "lead s-twelve" "why s-twelve" "close s-unlisted" stops rule \
    "clear s-three s-cleared" "lead s-cleared" "why s-cleared" notices "close s-cleared" \
    "orphan s-ten shop" "lead s-ten" "why s-ten" "close s-ten" \
    "open s-lead shop" "lead s-lead" "open s-moss shop/wt-moss" "why s-lead" "close s-moss" \
    "open s-rook . at=shop" "why s-lead" "close s-rook" "open s-copy shop id=s-lead" "why s-lead" "close s-copy" \
    "close s-lead" \
    "open s-nine shop bypass" "lead s-nine" "why s-nine" "untick s-nine" "why s-nine" 2>&1
}
# The terminal app each new session runs in and the time it started, which the line under the header names, as <app>
# and <time>, so the output is the same each run and wherever the tests run.
holder=$(holder_cases 2>&1 | sed "s|$T|T|g" \
  | sed -E 's/a new session( in [^,]+)?, started at [^:]*:[0-9]{2}[^:]*:/a new session<app>, started at <time>:/g')
compare "Who holds the switches kept for a folder" "$REPO/$HERE/switch-holder.expected.txt" "$holder" "${1:-}" \
  || status=1

# What a session's replies used today (Whozmove --print-spent), from a sample transcript and its sub-agent's record,
# stamped from the start of the run's day so a run just after midnight reads the same: a reply from before midnight
# left out; one written over three lines as it streamed (each line with its usage so far) counted once, as its last
# line says, 93000; an API error's "<synthetic>" reply left out; the sub-agent's reply, over two lines, 20150. Each file
# read whole, a line at a time, and again from its start as if rewritten must all agree, and today is 113150.
spent_cases() {
  "${PY:-python3}" - "$T/spent" <<'PY'
import json, os, sys, datetime
folder = sys.argv[1]
start = datetime.datetime.now().replace(hour=0, minute=0, second=0, microsecond=0).timestamp()
def at(seconds):  # seconds from the start of today, as Claude Code stamps a line
    return datetime.datetime.fromtimestamp(start + seconds, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
def reply(reply_id, seconds, parts, model="claude-opus-5-5"):
    return [{"type": "assistant", "timestamp": at(seconds), "message": {"id": reply_id, "model": model,
             "content": [{"type": kind}], "usage": usage}} for kind, usage in parts]
def usage(inp, write, read, out):
    return {"input_tokens": inp, "cache_creation_input_tokens": write, "cache_read_input_tokens": read,
            "output_tokens": out}
def put(path, lines):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write("".join(json.dumps(line, separators=(",", ":")) + "\n" for line in lines))
put(f"{folder}/s.jsonl", [
    *reply("m-before", -60, [("text", usage(1000, 0, 50000, 100))]),
    {"type": "user", "timestamp": at(30), "message": {"role": "user", "content": "go on"}},
    *reply("m-1", 60, [("thinking", usage(300, 2000, 90000, 10)), ("text", usage(300, 2000, 90000, 300)),
                       ("tool_use", usage(300, 2000, 90000, 700))]),
    *reply("m-error", 120, [("text", usage(5000, 0, 0, 0))], model="<synthetic>"),
])
put(f"{folder}/s/subagents/agent-a1.jsonl", [
    *reply("s-1", 90, [("thinking", usage(100, 0, 20000, 20)), ("text", usage(100, 0, 20000, 50))]),
])
PY
  "$APP" --print-spent "$T/spent/s.jsonl"
}
spent=$(spent_cases 2>&1)
compare "What it used today" "$REPO/$HERE/spent.expected.txt" "$spent" "${1:-}" || status=1

# Claude's reply to words put into a session's prompt (Whozmove --print-reply), from a sample transcript: a reply in
# two parts of one message joined, after a tool call and its result; a slash command's record, Claude Code's own line
# and a sub-agent's words, none of which end the turn or count; a prompt in text parts with spaces at its ends, asked
# again later, whose later turn counts instead; a long reply cut short; a turn with only a tool call so far; and words
# never sent. Each read whole and from the file's second line.
reply_cases() {
  "${PY:-python3}" - "$T/reply.jsonl" <<'PY'
import json, sys, datetime
def at(seconds):
    return datetime.datetime.fromtimestamp(seconds, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
lines = [{"type": "summary", "summary": "Coupons"}]
def you(seconds, content, **more):
    lines.append(dict(type="user", timestamp=at(seconds), message={"role": "user", "content": content}, **more))
def claude(seconds, reply_id, parts, **more):
    lines.append(dict(type="assistant", timestamp=at(seconds), message={"id": reply_id, "role": "assistant",
                                                                         "content": parts}, **more))
you(100, "Where should the coupon box go?")
claude(101, "m1", [{"type": "thinking", "thinking": "Looking."}])
claude(102, "m1", [{"type": "text", "text": "Let me look."}])
claude(103, "m1", [{"type": "tool_use", "id": "t1", "name": "Read", "input": {}}])
you(104, [{"type": "tool_result", "tool_use_id": "t1", "content": "checkout.html"}])
claude(105, "m2", [{"type": "text", "text": "Under the total,"}])
claude(106, "m2", [{"type": "text", "text": "where it's seen before paying."}])
you(107, "<command-name>/model</command-name>")
you(108, "Caveat: the messages below were generated by the user", isMeta=True)
claude(109, "s1", [{"type": "text", "text": "A sub-agent's words"}], isSidechain=True)
you(200, [{"type": "text", "text": "  And on phones?  "}])
claude(201, "m3", [{"type": "text", "text": "Smaller, under the total."}])
you(250, "Show the whole list")
claude(251, "m4", [{"type": "text", "text": "x" * 20000}])
you(300, "And on phones?")
claude(301, "m6", [{"type": "text", "text": "The same, full width."}])
you(400, "Run the tests")
claude(401, "m5", [{"type": "tool_use", "id": "t2", "name": "Bash", "input": {}}])
open(sys.argv[1], "w").write("".join(json.dumps(line, separators=(",", ":")) + "\n" for line in lines))
PY
  "$APP" --print-reply "$T/reply.jsonl" 0 "Where should the coupon box go?" 0 "And on phones?" 250000 "And on phones?" \
    350000 "And on phones?" 0 "Show the whole list" 0 "Run the tests" 0 "Never sent"
}
reply=$(reply_cases 2>&1)
compare "Its replies" "$REPO/$HERE/reply.expected.txt" "$reply" "${1:-}" || status=1

# Words handed to a session's own hook between its steps (Whozmove --print-between-steps): what the hook is handed,
# whose hook may take them, and how a sample transcript records them taken in, with what Claude wrote after them.
between=$(HOME="$T" "$APP" --print-between-steps 2>&1)
compare "Words between steps" "$REPO/$HERE/between-steps.expected.txt" "$between" "${1:-}" || status=1

# Which commands a session left running in the background are Whozmove's own waits (Whozmove --print-own-waits): only
# the plugin's own ask-panel.sh with one of its wait words and only flags after it is left off, so a command of the
# session's own isn't.
# Each module's waits, as gathered, are then run through ask-panel.sh itself with no panel to reach: one it turns away
# for its words (exit 2) has drifted from what the module's asks take.
own=$(HOME="$T" "$APP" --print-own-waits 2>&1
  printf '%s\n' "$(HOME="$T" "$APP" --print-own-waits 2>/dev/null)" | sed -n 's/^waits: //p' | while read -r words; do
    # shellcheck disable=SC2086
    WHOZMOVE_ASK_SOCKET="$T/no-panel.sock" sh "$REPO/app/ask-panel.sh" $words >/dev/null 2>&1
    [ $? -eq 2 ] && echo "ask-panel.sh turns away: $words" || echo "ask-panel.sh takes: $words"
  done)
compare "Whozmove's own waits" "$REPO/$HERE/own-waits.expected.txt" "$own" "${1:-}" || status=1

# How long an ended session stays listed (Whozmove --print-kept-waits): 3 days, or 30 while its row waits on someone
# else, so one woken while it was closed still has its Resume; and never once its transcript has gone.
kept_waits=$(HOME="$T" "$APP" --print-kept-waits 2>&1)
compare "Ended sessions kept while they wait" "$REPO/$HERE/kept-waits.expected.txt" "$kept_waits" "${1:-}" || status=1

# A question asked on a session's side (Whozmove --print-aside), running nothing of Claude Code's: the command and the
# words it runs, the model and program it's asked with, how each ending of its output is read, the steps it says as it
# answers, which versions are asked for its thinking's summaries, what its checker lets it read and run in a sample
# folder, when a follow-up goes into the open copy and what a fresh one is told, a kept conversation with a stand-in
# that answers each line, a question asked of stand-ins for Claude Code that take or turn down the summaries' flag, and
# its process kept out of everything read from Claude Code's registry while it runs. It has a home of its own, as the earlier sections leave stand-in
# sessions running in the shared home's registry, which the print would count as sessions of its own.
mkdir -p "$T/aside-home"
aside=$(HOME="$T/aside-home" "$APP" --print-aside 2>&1)
compare "Asked on the side" "$REPO/$HERE/aside.expected.txt" "$aside" "${1:-}" || status=1

# The words a side question's copy gives each step it takes (Whozmove --print-aside --steps) beside those the session's
# own hook gives the same tool call (activity_for), so the two can't drift apart: the same, but where the copy says
# less on purpose (a file outside the session's folder, a search or pattern naming a path, git's own command in place
# of Claude's words for it, a tool a side question may not use), which is said beside it. A word that drifts fails.
mkdir -p "$T/steps-folder/src"
steps=$(HOME="$T" python3 - "$H" "$APP" "$T/steps-folder" "$T/steps.json" <<'PY' 2>&1
import importlib.util, json, subprocess, sys
hook_path, app, folder, samples_path = sys.argv[1:5]
spec = importlib.util.spec_from_file_location("hook", hook_path)
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)
# Each: whether the two say the same (else why not), what it is, the tool and what it was given.
samples = [
    ("", "Read, a file in the folder", "Read", {"file_path": folder + "/src/cart.ts"}),
    ("", "Grep, a word", "Grep", {"pattern": "total"}),
    ("", "Grep, a long pattern, cut", "Grep", {"pattern": "function (add|remove)LineFromTheCart\\("}),
    ("", "Glob, a pattern in the folder", "Glob", {"pattern": "src/**/*.ts"}),
    ("", "Glob, a long pattern, cut", "Glob", {"pattern": "src/components/checkout/**/*.test.tsx"}),
    ("", "Bash, a command with no words for it", "Bash", {"command": "cat notes.txt"}),
    ("a file outside the session's folder", "Read, outside the folder", "Read", {"file_path": "/etc/hosts"}),
    ("a search naming a path", "Grep, a path", "Grep", {"pattern": "/Users/you/"}),
    ("a pattern naming a path", "Glob, a whole path", "Glob", {"pattern": "/etc/*"}),
    ("git's own command, not Claude's words", "Bash, git with Claude's words for it", "Bash",
     {"command": "git log --oneline -5", "description": "Show the last commits in /Users/you/shop"}),
    ("a tool a side question may not use", "Edit", "Edit", {"file_path": folder + "/src/cart.ts"}),
]
with open(samples_path, "w") as out:
    json.dump([{"tool": tool, "input": given} for _, _, tool, given in samples], out)
copy = subprocess.run([app, "--print-aside", "--steps", samples_path, folder], capture_output=True, text=True,
                      check=True).stdout.split("\n")
drifted = False
for (apart, what, tool, given), copied in zip(samples, copy):
    said = hook.activity_for(tool, given)
    if apart:
        print(f"{what}: the hook “{said}”, the copy “{copied}” ({apart})")
    elif said == copied:
        print(f"{what}: both “{said}”")
    else:
        drifted = True
        print(f"{what}: DRIFTED, the hook “{said}”, the copy “{copied}”")
sys.exit(1 if drifted else 0)
PY
) || { echo "A side question's steps have drifted from the hook's words:"; echo "$steps"; status=1; }
compare "A side question's steps, beside the hook's" "$REPO/$HERE/aside-steps.expected.txt" "$steps" "${1:-}" \
  || status=1

# Who may ask the panel in a session's name (Whozmove --print-askers), through the asks' own path with no socket: in a
# sample home, each a process of the test's own, with its record in Claude Code's registry. Real, Other, Twin, Elsewhere
# and Usurper run a stand-in for Claude Code's program (a compiled pause, which the print run is told counts as it);
# Inner is one Real started, so it runs inside Real's session; Twin's record says it's Other, while Other runs;
# Elsewhere's, in a folder of its own, says it's Gone, which Whozmove kept working in shop once it ended; Forger is
# another program (sleep), its record saying it's Real. Then Usurper's
# record says it's Real once Real's own says it's another session; Tucked, a program not Claude Code's (sleep)
# that Holder started, asks with a record of its own; and Npm, the stand-in copied under Node's name, asks as an older
# Claude Code from npm would, its arguments overwritten by its title.
asker_cases() {
  local home="$T/askers" now real inner other twin elsewhere forger usurper holder tucked npm
  mkdir -p "$home/.claude/sessions" "$home/shop" "$home/elsewhere" "$home/$APPDIR/conversations" "$home/bin"
  cat > "$home/stand-in.c" <<'C'
#include <stdio.h>
#include <string.h>
#include <unistd.h>
/* Claude Code's stand-in: it pauses; with `spawn <file> [program…]`, it first starts another of itself (or that
   program) and writes its pid there. */
int main(int argc, char **argv) {
    if (argc >= 3 && strcmp(argv[1], "spawn") == 0) {
        pid_t child = fork();
        if (child == 0) {
            if (argc > 3) execv(argv[3], argv + 3);
            else execl(argv[0], argv[0], (char *)0);
            _exit(1);
        }
        FILE *file = fopen(argv[2], "w");
        if (file) { fprintf(file, "%d\n", child); fclose(file); }
    }
    for (;;) pause();
}
C
  clang -o "$home/bin/claude" "$home/stand-in.c" || return 1
  now=$(python3 -c 'import time; print(int(time.time() * 1000))')
  register() {  # $1 pid, $2 session, $3 name, $4 folder
    echo "{\"pid\": $1, \"sessionId\": \"$2\", \"name\": \"$3\", \"kind\": \"interactive\", \"entrypoint\": \"cli\",
           \"cwd\": \"$4\", \"status\": \"idle\", \"startedAt\": $now, \"statusUpdatedAt\": $now}" \
      > "$home/.claude/sessions/$1.json"
  }
  real=$(cd "$home/shop" && detached "$home/bin/claude" spawn "$home/inner.pid")
  for _ in $(seq 1 50); do [ -s "$home/inner.pid" ] && break; sleep 0.1; done
  inner=$(cat "$home/inner.pid"); echo "$inner" >> "$T/pids"
  other=$(cd "$home/shop" && detached "$home/bin/claude")
  twin=$(cd "$home/shop" && detached "$home/bin/claude")
  elsewhere=$(cd "$home/elsewhere" && detached "$home/bin/claude")
  forger=$(cd "$home/shop" && detached sleep 600)
  usurper=$(cd "$home/shop" && detached "$home/bin/claude")
  holder=$(cd "$home/shop" && detached "$home/bin/claude" spawn "$home/tucked.pid" /bin/sleep 600)
  for _ in $(seq 1 50); do [ -s "$home/tucked.pid" ] && break; sleep 0.1; done
  tucked=$(cat "$home/tucked.pid"); echo "$tucked" >> "$T/pids"
  cp "$home/bin/claude" "$home/bin/node"
  npm=$(cd "$home/shop" && detached "$home/bin/node")
  register "$real" s-real Real "$home/shop"
  register "$inner" s-inner Inner "$home/shop"
  register "$other" s-other Other "$home/shop"
  register "$twin" s-other Other "$home/shop"
  register "$elsewhere" s-gone Gone "$home/elsewhere"
  register "$forger" s-real Real "$home/shop"
  register "$usurper" s-usurper Usurper "$home/shop"
  register "$holder" s-holder Holder "$home/shop"
  register "$tucked" s-tucked Tucked "$home/shop"
  register "$npm" s-npm Npm "$home/shop"
  echo "{\"sessionId\": \"s-gone\", \"cwd\": \"$home/shop\", \"name\": \"Gone\"}" \
    > "$home/$APPDIR/conversations/s-gone.json"
  WHOZMOVE_STAND_IN_CLAUDE="$home/bin/claude" HOME="$home" "$APP" --print-askers \
    "$real" "$inner" "$other" "$twin" "$elsewhere" "$forger" "$usurper" "$holder" "$tucked" "$npm" 2>&1
}
askers=$(asker_cases 2>&1 | sed -E -e "s|$T|T|g" -e "s|${T#/private}|T|g" -e 's/\(([0-9]+)\)/(pid)/g')
compare "Who may ask in a session's name" "$REPO/$HERE/askers.expected.txt" "$askers" "${1:-}" || status=1

# A note a session wrote, read back for the reader while another session's long transcript is read from its start, as
# every one is when Whozmove opens (Whozmove --print-writing-wait): it comes back without waiting for that read.
writing_wait_cases() {
  "${PY:-python3}" - "$T/writing-home" <<'PY'
import json, os, sys
home = sys.argv[1]
projects, notes = os.path.join(home, ".claude/projects/-sample-shop"), os.path.join(home, "shop/notes")
os.makedirs(projects), os.makedirs(notes)
goals = "# Goals\n\n" + "".join("- Keep the coupon box under the total, line %d.\n" % i for i in range(120))
open(os.path.join(notes, "goals.md"), "w").write(goals)
at = "2026-01-02T10:00:00.000Z"
def line(entry):
    return json.dumps(dict(entry, timestamp=at), separators=(",", ":")) + "\n"
def you(content):
    return line({"type": "user", "message": {"role": "user", "content": content}})
def claude(reply_id, parts):
    return line({"type": "assistant", "message": {"id": reply_id, "role": "assistant", "content": parts}})
with open(os.path.join(projects, "s-note.jsonl"), "w") as f:
    f.write(you("Write the goals down"))
    f.write(claude("m1", [{"type": "tool_use", "id": "w1", "name": "Write",
                           "input": {"file_path": os.path.join(notes, "goals.md"), "content": goals}}]))
    f.write(you([{"type": "tool_result", "tool_use_id": "w1", "content": "File created successfully at: goals.md"}]))
# Long enough that reading it from its start takes far longer than reading the note.
with open(os.path.join(projects, "s-long.jsonl"), "w") as f:
    step = 0
    while f.tell() < 30 * 1024 * 1024:
        step += 1
        f.write(you("Go on, step %d" % step))
        f.write(claude("r%d" % step, [{"type": "text", "text": "Reading the checkout code and its tests. " * 200}]))
PY
  HOME="$T/writing-home" "$APP" --print-writing-wait s-note s-long
}
writing_wait=$(writing_wait_cases 2>&1)
compare "A writing read while transcripts are" "$REPO/$HERE/writing-wait.expected.txt" "$writing_wait" "${1:-}" \
  || status=1

# How each line of a sample transcript got there, as Keys is told it (Whozmove --print-record-how): what you typed and
# what you queued while Claude worked are sent; a tool's result, read; Claude's replies and its prompt to a sub-agent,
# wrote; and a compaction's summary, what Claude Code added (meta, on a sub-agent's record too) and what was queued from
# elsewhere (another session, a task finishing, or added by Claude Code) say nobody.
record_how_cases() {
  "${PY:-python3}" - "$T/record-how.jsonl" <<'PY'
import json, sys
lines = []
def you(uuid, content, **more):
    lines.append(dict(type="user", uuid=uuid, message={"role": "user", "content": content}, **more))
def claude(uuid, text, **more):
    lines.append(dict(type="assistant", uuid=uuid, message={"role": "assistant", "content": [
        {"type": "text", "text": text}]}, **more))
def queued(uuid, text, **more):
    lines.append(dict(type="attachment", uuid=uuid, attachment=dict(type="queued_command", prompt=text, **more)))
you("typed", "Deploy the shop with sk-sample-0000")
queued("queued", "And use sk-sample-1111 for the staging one")
queued("queued-typed", "Then tell me", origin={"kind": "human"})
queued("queued-peer", "From the docs session: done", origin={"kind": "peer"})
queued("queued-task", "The tests finished", origin={"kind": "task-notification"}, isMeta=True)
queued("queued-meta", "Carry on", isMeta=True)
lines.append(dict(type="attachment", uuid="other-attachment", attachment={"type": "todo", "content": []}))
you("result", [{"type": "tool_result", "tool_use_id": "t1", "content": "deployed"}])
claude("reply", "Deployed with sk-sample-0000")
you("summary", "Summary: deployed the shop", isCompactSummary=True)
you("meta", "Caveat: the messages below were generated by the user", isMeta=True)
you("agent-prompt", "Check the staging key works", isSidechain=True)
you("agent-meta", "Notes for this project: the staging key is sk-sample-2222", isSidechain=True, isMeta=True)
you("agent-result", [{"type": "tool_result", "tool_use_id": "t2", "content": "ok"}], isSidechain=True)
claude("agent-reply", "sk-sample-2222 works", isSidechain=True)
open(sys.argv[1], "w").write("".join(json.dumps(line, separators=(",", ":")) + "\n" for line in lines))
PY
  HOME="$T/record-home" "$APP" --print-record-how "$T/record-how.jsonl"
}
record_how=$(record_how_cases 2>&1)
compare "How each line got there" "$REPO/$HERE/record-how.expected.txt" "$record_how" "${1:-}" || status=1

# What a session's reads keep across restarts (Whozmove --print-reads), from a sample transcript and a sub-agent's
# record, both cut part way on a made-up first day (the transcript in the middle of a line, as Claude Code writes one,
# in a reply going on across midnight, with a plan presented, a note written and an edit asked for whose results come
# after it), kept, then grown on the next day, with a new sub-agent's record: going on from what was kept reads only
# what's new and comes to what reading it all from its start does. Then why a kept read is read from its start once it
# or a file it read has changed, or it doesn't read back as it should; that nothing is kept with a key-shaped topic;
# and which kept reads a prune takes away.
reads_cases() {
  "${PY:-python3}" - "$T/reads-home" "$T/reads-grown" 5a3e0c1d-7b2f-4c9a-9e61-0d4b8f2a1c37 <<'PY'
import json, os, sys
home, grown, sid = sys.argv[1], sys.argv[2], sys.argv[3]
project = os.path.join(home, ".claude/projects/-sample-shop")
shop = "/sample/shop"
def at(day, clock):  # a made-up day (1 or 2) and time, as Claude Code stamps a line
    return f"2000-01-0{day}T{clock}.000Z"
def usage(inp, write, read, out):
    return {"input_tokens": inp, "cache_creation_input_tokens": write, "cache_read_input_tokens": read,
            "output_tokens": out}
def reply(rid, when, content, used, side=False):
    return {"type": "assistant", "isSidechain": side, "timestamp": when, "effort": "high",
            "message": {"id": rid, "model": "claude-opus-5-5", "content": content, "usage": used}}
def results(when, *items, side=False, **more):
    return {"type": "user", "isSidechain": side, "timestamp": when, "message": {"content": list(items)}, **more}
def result(cid, text, error=False):
    item = {"type": "tool_result", "tool_use_id": cid, "content": text}
    if error:
        item["is_error"] = True
    return item
def prompt(when, words, mode):
    return {"type": "user", "isSidechain": False, "timestamp": when, "permissionMode": mode,
            "message": {"role": "user", "content": words}}
def call(cid, name, given):
    return {"type": "tool_use", "id": cid, "name": name, "input": given}
def patched(cid, when, path, lines, side=False):
    return results(when, result(cid, "ok"), side=side,
                   toolUseResult={"filePath": path, "structuredPatch": [{"oldStart": 1, "oldLines": 1, "newStart": 1,
                                                                         "newLines": 2, "lines": lines}]})
def made(cid, when, path, content, side=False):
    return results(when, result(cid, "ok"), side=side,
                   toolUseResult={"type": "create", "filePath": path, "content": content, "structuredPatch": []})
def text(lines):
    return "".join(json.dumps(line, separators=(",", ":")) + "\n" for line in lines)

# The session, up to the cut on the first day: a plan presented, a note written, an edit made and one asked for that
# will fail, a PR, a shell command, a topic, and a reply streaming across midnight, its second line half written.
before = [
    {"type": "permission-mode", "permissionMode": "default", "sessionId": sid},
    prompt(at(1, "10:00:00"), "Fix the checkout's totals", "default"),
    {"type": "ai-title", "aiTitle": "Fix the checkout", "sessionId": sid},
    reply("r1", at(1, "10:01:00"), [
        {"type": "text", "text": "Here's the plan."},
        call("p1", "ExitPlanMode", {"plan": "# Round the totals once\n1. Round at the end.",
                                    "planFilePath": "/sample/home/.claude/plans/totals.md"})],
        usage(1000, 5000, 20000, 400)),
    reply("r2", at(1, "10:03:00"), [
        call("w1", "Write", {"file_path": shop + "/docs/totals.md",
                             "content": "# How totals round\nOnce, at the end."}),
        call("e1", "Edit", {"file_path": shop + "/cart.js", "old_string": "total = a + b",
                            "new_string": "total = round(a + b)"}),
        call("e2", "Edit", {"file_path": shop + "/cart.js", "old_string": "tax = t", "new_string": "tax = round(t)"})],
        usage(200, 1000, 26000, 300)),
    patched("e1", at(1, "10:04:00"), shop + "/cart.js", ["-total = a + b", "+total = round(a + b)", "+// once"]),
    {"type": "pr-link", "prUrl": "https://github.com/sample/shop/pull/12", "prNumber": 12,
     "prRepository": "sample/shop", "timestamp": at(1, "10:05:00")},
    reply("r3", at(1, "10:06:00"), [call("b1", "Bash", {"command": "npm test"}),
                                    call("a1", "Artifact", {"file_path": shop + "/docs/receipt.html",
                                                            "content": "<title>A receipt</title>"})],
          usage(100, 0, 27000, 50)),
    results(at(1, "10:07:00"), result("b1", "passed"), toolUseResult={"stdout": "passed", "stderr": ""}),
    reply("r4", at(1, "23:59:50"), [{"type": "thinking", "thinking": "Totals next."}], usage(300, 2000, 90000, 10)),
]
going_on = reply("r4", at(2, "00:00:10"), [{"type": "text", "text": "Totals now round once."}],
                 usage(300, 2000, 90000, 300))
# After the cut, on the second day: the reply going on, the plan approved, the note made, the edit failed, a prompt in
# another mode, a newer topic, and another reply.
after = [
    going_on,
    results(at(2, "00:01:00"), result("p1", "User has approved your plan."),
            result("w1", "File created successfully at: " + shop + "/docs/totals.md"),
            result("e2", "String to replace not found in file.", error=True)),
    # The page published, at an address whose name and password, query and fragment aren't kept.
    results(at(2, "00:01:30"), result("a1", "Published"),
            toolUseResult={"url": "https://sample:sample-token@example.com/page/7?token=sample-token#top"}),
    prompt(at(2, "00:02:00"), "Now the tax", "acceptEdits"),
    {"type": "ai-title", "aiTitle": "Fix the checkout's totals and tax", "sessionId": sid},
    reply("r5", at(2, "00:03:00"), [{"type": "text", "text": "Tax rounds too."}], usage(400, 1500, 95000, 200)),
]
# A sub-agent's record, which grows across the cut too, and a second sub-agent's, which starts after it.
helper_before = [
    reply("s1", at(1, "10:30:00"), [call("e10", "Write", {"file_path": shop + "/tax.js",
                                                         "content": "export const rate = 0.2\n"})],
          usage(100, 0, 20000, 50), side=True),
    made("e10", at(1, "10:31:00"), shop + "/tax.js", "export const rate = 0.2\n", side=True),
]
helper_after = [
    reply("s2", at(2, "00:04:00"), [call("e11", "Edit", {"file_path": shop + "/tax.js", "old_string": "0.2",
                                                         "new_string": "0.25"})], usage(100, 0, 21000, 60), side=True),
    patched("e11", at(2, "00:05:00"), shop + "/tax.js", ["-export const rate = 0.2", "+export const rate = 0.25",
                                                         "+export const rounds = true"], side=True),
]
second = [
    reply("t1", at(2, "00:06:00"), [call("e20", "Edit", {"file_path": shop + "/README.md", "old_string": "Shop",
                                                         "new_string": "The shop"})],
          usage(50, 0, 9000, 30), side=True),
    patched("e20", at(2, "00:07:00"), shop + "/README.md", ["-# Shop", "+# The shop", "+Rounds once."], side=True),
]

os.makedirs(os.path.join(project, sid, "subagents"), exist_ok=True)
os.makedirs(os.path.join(grown, "subagents"), exist_ok=True)
whole = text(before + after)
half = text([going_on])
cut = text(before) + half[:len(half) // 2]
open(os.path.join(project, sid + ".jsonl"), "w").write(cut)
open(os.path.join(grown, sid + ".jsonl"), "w").write(whole)
open(os.path.join(project, sid, "subagents/agent-a1.jsonl"), "w").write(text(helper_before))
open(os.path.join(grown, "subagents/agent-a1.jsonl"), "w").write(text(helper_before + helper_after))
open(os.path.join(grown, "subagents/agent-b2.jsonl"), "w").write(text(second))
PY
  HOME="$T/reads-home" "$APP" --print-reads 5a3e0c1d-7b2f-4c9a-9e61-0d4b8f2a1c37 "$T/reads-grown" "$T/reads-kept" \
    946684800000 946771200000
}
reads=$(reads_cases 2>&1)
# What a read keeps changes only with its shape (kReadsShape), so a copy kept in the old one is read afresh: the
# fingerprint of what the sample keeps may change only where the shape does, --update or not.
kept_as() { python3 -c 'import json, sys; k = json.load(sys.stdin)["kept"]; print(k["shape"], k["fingerprint"])'; }
was=$(kept_as < "$REPO/$HERE/reads.expected.txt" 2>/dev/null)
now=$(printf '%s\n' "$reads" | kept_as 2>/dev/null)
if [ -n "$was" ] && [ "${was%% *}" = "${now%% *}" ] && [ "$was" != "$now" ]; then
  echo "What the reads keep has changed, but not its shape: raise kReadsShape (modules/claude-code/app/Transcripts.m)."
  status=1
else
  compare "What the reads keep" "$REPO/$HERE/reads.expected.txt" "$reads" "${1:-}" || status=1
fi

# Its part of the page: what each request is and what Claude's line says about it, each kind's card, what a press or a
# key sends, and what shows once it's answered (page-cases.js, run with macOS's jsc in UTC).
cd "$REPO" || exit 1
page=$(page_cases "$HERE/page-cases.js") || { echo "$page"; exit 1; }
compare "Its page" "$REPO/$HERE/page.expected.txt" "$page" "${1:-}" || status=1
exit $status
