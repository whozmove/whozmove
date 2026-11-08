#!/bin/bash
# Builds the app from this checkout, has it print the rows it would show for a sample home folder (never your
# real ~/.claude), and compares them with tests/rows.expected.txt.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   tests/rows.sh            run and compare
#   tests/rows.sh --update   run and save the output as the new expected (after a change you meant)
# Also checks, for each terminal session, whether keys may go into it now and the Shift+Tabs its mode menu would
# type (`--print-mode-moves`), the keys a command is typed with (`--print-typing`), what each session's menus, Compact
# card and next steps say about why nothing can go in now (`--print-why-not`), how a command's result is read
# (`--print-results`), that docs/reference/rows.md describes
# exactly the fields a row has, that the README names the macOS permissions the app asks for while no file in the
# repo names one it doesn't, the command Deploy suggests for sample projects and how their last runs read
# (`--print-deploys`), what the set-up card is told sample commands really run (`--print-deploy-checks`), what the
# usage strip gets from Claude Code's recorded answers and where `claude` is looked for (`--print-usage`), how
# folder trust is read and recorded (`--print-trust`), why a recording counts as talking to an agent
# (`--print-talking`), when a press leaves a terminal's window as it is (`--print-on-top`), that a file read every
# second is read again only once it has changed (`--print-file-reads`), and that a run whose home isn't yours presses,
# types and sends nothing in other apps (`--print-other-apps`).
# Needs clang, git and python3. Takes a few seconds, most of it compiling the app.
cd "$(dirname "$0")/.." || exit 1
. tests/sandboxed.sh "$@"
REPO=$PWD
# git here, the sample repo's and the app's own, ignores your personal git settings (signing, hooks, …).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
# Stops here if there's no temporary folder: an empty T would make the clean-up below delete this checkout.
T=$(mktemp -d "${TMPDIR:-/tmp}/whozmove-rows.XXXXXX") || exit 1
T=$(cd "$T" && pwd -P) || exit 1
# Stand-in session processes are started detached, their pids kept in $T/pids so they're stopped however this ends.
trap 'kill $(cat "$T/pids" 2>/dev/null) 2>/dev/null; kill -CONT $(cat "$T/pids" 2>/dev/null) 2>/dev/null; rm -rf "$T"' EXIT
detached() { local pid; pid=$("$@" >/dev/null 2>&1 & echo $!); echo $pid >> "$T/pids"; echo $pid; }
# Pausing one (as Ctrl+Z does) waits until the subshell that started it has gone, its parent then being launchd: macOS
# wakes the paused processes a parent leaves behind (their process group orphaned), so one paused sooner could be
# running again by the time the app looks.
pause() {
  for _ in $(seq 1 200); do [ "$(parent_of "$1")" = 1 ] && break; sleep 0.01; done
  kill -STOP "$1"
}
. "$REPO/tests/lib.sh"
APP=$(built_app "$T") || exit 1

# A checkout with one uncommitted change, and a worktree of it on its own branch, made before main's last commit.
git -C "$T" init -q -b main repo
echo one > "$T/repo/a.txt"
git -C "$T/repo" add a.txt
git -C "$T/repo" -c user.email=t@t -c user.name=t commit -q -m init
git -C "$T/repo" worktree add -q "$T/repo-wt" -b feature
# The worktree's branch follows the local main, a branch on no remote: that's no upstream on GitHub.
git -C "$T/repo-wt" branch -q --set-upstream-to=main
echo one > "$T/repo/b.txt"
git -C "$T/repo" add b.txt
git -C "$T/repo" -c user.email=t@t -c user.name=t commit -q -m more
echo two >> "$T/repo/a.txt"
printf 'new\nfile\n' > "$T/repo/new.txt"  # a new file, which counts toward the lines added
# A branch with work of its own, measured from where it left main: a commit, and a change on top.
git -C "$T" clone -q repo clone
git -C "$T/clone" checkout -q -b topic
printf 'pushed earlier\ny\n' > "$T/clone/c.txt"
git -C "$T/clone" add c.txt
git -C "$T/clone" -c user.email=t@t -c user.name=t commit -q -m topic
# As if that commit were on the remote already: the branch's upstream has it.
git -C "$T/clone" update-ref refs/remotes/origin/topic HEAD
git -C "$T/clone" branch -q --set-upstream-to=origin/topic
echo z >> "$T/clone/a.txt"
# And how its changes split as git status sees them: one file staged, one staged and then changed again, one not
# staged.
echo staged > "$T/clone/e.txt"
git -C "$T/clone" add e.txt
echo first > "$T/clone/d.txt"
git -C "$T/clone" add d.txt
echo again >> "$T/clone/d.txt"
# Work two sessions did in the clone, as their transcripts below say: s-topic wrote retry.py, which was saved, and added
# to it since; s-clone added a line to it and wrote a new file. c.txt, a.txt, d.txt and e.txt aren't from a session:
# c.txt was committed earlier, and is on the remote, the rest not yet (e.txt only staged), by no one known. A sub-agent of s-clone wrote
# helper.py, and a shell command of s-topic's wrote notes.txt.
printf 'def schedule(invoice):\n    return queue.put(invoice)\n' > "$T/clone/retry.py"
git -C "$T/clone" add retry.py
git -C "$T/clone" -c user.email=t@t -c user.name=t commit -q -m retry retry.py
printf 'def on_card(customer):\n    run_now(customer)\n# reviewed by the second session\n' >> "$T/clone/retry.py"
printf 'Looks good to me overall.\n' > "$T/clone/review.md"
printf 'def helper():\n    return schedule(None)\n' > "$T/clone/helper.py"
printf 'def written_anyway():\n    return schedule(None) or None\n' > "$T/clone/interrupted.py"
printf 'Made by its command.\n' > "$T/clone/notes.txt"
printf 'typed by hand after all\n' > "$T/clone/typed.txt"
mkdir -p "$T/clone/.claude/commands" && printf 'Check the retry queue.\n' > "$T/clone/.claude/commands/check.md"

# Live sessions (stand-in processes), and one whose process has ended: a pid above the highest macOS hands
# out (99999), so no process can ever have it.
TERM_PID=$(detached sleep 600); WT_PID=$(detached sleep 600); DESK_PID=$(detached sleep 600)
MODE_PIDS=$(for _ in 1 2 3 4 5 6; do detached sleep 600; done | paste -sd , -)
TOPIC_PID=$(detached sleep 600); CLONE_PID=$(detached sleep 600)
RUN_PID=$(detached sleep 600)  # a deploy still running
GONE_PID=999999
# And s-term again, resumed while its first process was paused in its terminal (Ctrl+Z): one row, the running one's.
PAUSED_PID=$(detached sleep 600); pause "$PAUSED_PID"
# And s-halt, paused in its terminal with no other copy: nothing goes into it, as its keys would go to the shell.
HALT_PID=$(detached sleep 600); pause "$HALT_PID"
# Conversations open more than once (s-twice, s-ask, s-idle, s-both, two copies each), s-near beside s-ask, and
# s-shell and s-odd, with statuses of their own, and s-bg and s-long, whose agents work in the background.
TWICE_PIDS=$(for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do detached sleep 600; done | paste -sd , -)

# The usage check's own session (modules/claude-code/app/ClaudeUsage.m): registered while it runs, in the folder kept
# for it. Never a row.
USAGE_PID=$(detached sleep 600)
mkdir -p "$T/.claude/sessions" "$T/Library/Application Support/Whozmove/usage"
printf '{"pid": %d, "sessionId": "s-usage-check", "cwd": "%s", "status": "idle", "entrypoint": "sdk-cli",
         "kind": "interactive"}\n' "$USAGE_PID" "$T/Library/Application Support/Whozmove/usage" \
  > "$T/.claude/sessions/$USAGE_PID.json"
# What Claude Code answers the usage check with, among lines that aren't the answer (one for another request): reset
# times with and without fractions of a second, an error, and signed out; and `claude auth status`, signed in and
# out, and in a shape Whozmove doesn't know (made up), which reads as neither, so an answer with no plan's numbers is
# "unknown" beside it, as beside the recorded answers that aren't auth status at all. And `claude` on a PATH and in two
# of Claude Desktop's copies, where 2.1.10 is the newer.
mkdir -p "$T/usage-replies" "$T/bin"
cat > "$T/usage-replies/answer.jsonl" <<'JSONL'
{"type":"system","subtype":"init","session_id":"x"}
not JSON at all
{"type":"control_response","response":{"subtype":"success","request_id":"someone-else","response":{}}}
{"type":"control_response","response":{"subtype":"success","request_id":"whozmove-usage","response":{"subscription_type":"pro","rate_limits_available":true,"rate_limits":{"five_hour":{"utilization":40,"resets_at":"2030-01-01T05:00:00.250000+00:00"},"seven_day":{"utilization":10,"resets_at":"2030-01-04T00:00:00+00:00"},"limits":[{"kind":"session","percent":40,"severity":"normal","resets_at":"2030-01-01T05:00:00.250000+00:00","scope":null},{"kind":"weekly_all","percent":10,"severity":"normal","resets_at":"2030-01-04T00:00:00+00:00","scope":null},{"kind":"weekly_scoped","percent":80,"severity":"warning","resets_at":"2030-01-04T00:00:00+00:00","scope":{"model":{"display_name":"Opus"}}}],"extra_usage":{"is_enabled":false}}}}}
JSONL
echo '{"type":"control_response","response":{"subtype":"error","request_id":"whozmove-usage","error":"Unknown request"}}' \
  > "$T/usage-replies/error.jsonl"
echo '{"type":"control_response","response":{"subtype":"success","request_id":"whozmove-usage","response":{"subscription_type":null,"rate_limits_available":false,"rate_limits":null}}}' \
  > "$T/usage-replies/signed-out.jsonl"
echo '{"loggedIn": true, "authMethod": "claude.ai", "apiProvider": "firstParty"}' > "$T/usage-replies/auth-in.json"
echo '{"loggedIn": false, "authMethod": "none", "apiProvider": "firstParty"}' > "$T/usage-replies/auth-out.json"
echo '{"account": {"state": "active"}, "provider": "firstParty"}' > "$T/usage-replies/auth-changed.json"

# A slash command's result, written the way Claude Code writes it into a transcript: the command's own record, then its
# output, as a message or as a note; an output of an earlier command before the record, which isn't this one's; a
# record with no output yet; and an output with no record at all (Claude Desktop may not write one).
mkdir -p "$T/results"
cat > "$T/results/model-set.jsonl" <<'JSONL'
{"type":"user","message":{"role":"user","content":"<command-name>/model</command-name>\n<command-args>claude-opus-5-5</command-args>"}}
{"type":"user","message":{"role":"user","content":"<local-command-stdout>Set model to \u001b[1mOpus 5.5\u001b[22m and saved as your default for new sessions</local-command-stdout>"}}
JSONL
cat > "$T/results/model-kept.jsonl" <<'JSONL'
{"type":"system","subtype":"local_command","content":"<local-command-stdout>Set effort level to high</local-command-stdout>"}
{"type":"user","message":{"role":"user","content":"<command-name>/model</command-name>"}}
{"type":"system","subtype":"local_command","content":"<local-command-stdout>Kept model as Sonnet 5.5</local-command-stdout>"}
JSONL
cat > "$T/results/model-no-result-yet.jsonl" <<'JSONL'
{"type":"user","message":{"role":"user","content":"<command-name>/model</command-name>"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Still here."}]}}
JSONL
cat > "$T/results/effort-capped.jsonl" <<'JSONL'
{"type":"system","subtype":"local_command","content":"<local-command-stdout>Haiku 5.5 doesn't support max: set to 'xhigh' instead (saved as your default for new sessions)</local-command-stdout>"}
JSONL
cat > "$T/results/effort-set.jsonl" <<'JSONL'
{"type":"user","message":{"role":"user","content":"<command-name>/effort</command-name>"}}
{"type":"system","subtype":"local_command","content":"<local-command-stdout>Set effort level to high (this session only)</local-command-stdout>"}
JSONL
cat > "$T/results/plan.jsonl" <<'JSONL'
{"type":"user","message":{"role":"user","content":"<command-name>/plan</command-name>"}}
{"type":"system","subtype":"local_command","content":"<local-command-stdout>Enabled plan mode</local-command-stdout>"}
JSONL
cat > "$T/results/compact-done.jsonl" <<'JSONL'
{"type":"user","message":{"role":"user","content":"<command-name>/compact</command-name>"}}
{"type":"system","subtype":"local_command","content":"<local-command-stdout>\u001b[2mCompacted. ctrl+o to see full summary\u001b[22m</local-command-stdout>"}
JSONL
cat > "$T/results/compact-refused.jsonl" <<'JSONL'
{"type":"user","message":{"role":"user","content":"<command-name>/compact</command-name>"}}
{"type":"system","subtype":"local_command","content":"<local-command-stdout>\u001b[31mError: Not enough messages to compact.\u001b[39m</local-command-stdout>"}
JSONL
cat > "$T/results/reload-done.jsonl" <<'JSONL'
{"type":"user","message":{"role":"user","content":"<command-name>/reload-plugins</command-name>\n            <command-message>reload-plugins</command-message>\n            <command-args></command-args>"}}
{"type":"system","subtype":"local_command","content":"<local-command-stdout>Reloaded: 2 plugins · 4 skills · 1 agent · 5 hooks · 0 plugin MCP servers · 0 plugin LSP servers</local-command-stdout>"}
JSONL
cat > "$T/results/reload-held.jsonl" <<'JSONL'
{"type":"user","message":{"role":"user","content":"<command-name>/reload-plugins</command-name>"}}
{"type":"system","subtype":"local_command","content":"<local-command-stdout>This reload changes MCP tools (notes) — your next message will re-read the whole conversation instead of using the cache. Run /reload-plugins --force to apply.</local-command-stdout>"}
JSONL
cat > "$T/results/compact-no-result.jsonl" <<'JSONL'
{"type":"user","message":{"role":"user","content":"<command-name>/compact</command-name>"}}
JSONL

copies="$T/Library/Application Support/Claude/claude-code"  # Claude Desktop's own copies, by version
for claude in "$T/bin/claude" "$copies/2.1.9/a1/claude.app/Contents/MacOS/claude" \
              "$copies/2.1.10/b2/claude.app/Contents/MacOS/claude"; do
  mkdir -p "$(dirname "$claude")" && printf '#!/bin/sh\n' > "$claude" && chmod +x "$claude"
done

# Everything else the app reads, with times relative to now so that Claude Desktop's three-day window and
# the like hold whenever this runs. The output turns times back into "now-<minutes>m".
python3 - "$T" "$TERM_PID" "$WT_PID" "$DESK_PID" "$GONE_PID" "$MODE_PIDS" "$TOPIC_PID" "$RUN_PID" \
  "$CLONE_PID" "$PAUSED_PID" "$TWICE_PIDS" "$HALT_PID" <<'PY'
import json, os, sys, time
from datetime import datetime, timezone
T, term_pid, wt_pid, desk_pid, gone_pid = sys.argv[1], *map(int, sys.argv[2:6])
mode_pids = [int(pid) for pid in sys.argv[6].split(",")]
topic_pid = int(sys.argv[7])
run_pid = int(sys.argv[8])
paused_pid = int(sys.argv[10])
clone_pid = int(sys.argv[9])
twice_pids = [int(pid) for pid in sys.argv[11].split(",")]
halt_pid = int(sys.argv[12])
now = time.time()
open(os.path.join(T, "written-at"), "w").write(repr(now))  # what Deploy's sample runs are counted from (in_minutes)

def ms(minutes_ago):
    return int((now - minutes_ago * 60) * 1000)

def iso(minutes_ago):
    return datetime.fromtimestamp(now - minutes_ago * 60, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")

def put(path, data):
    path = os.path.join(T, path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        # A transcript: compact lines, as Claude Code writes them (the app looks for "type":"user").
        if isinstance(data, list):
            f.write("".join(json.dumps(line, separators=(",", ":")) + "\n" for line in data))
        elif isinstance(data, str):
            f.write(data)
        else:
            json.dump(data, f)

repo, wt = os.path.join(T, "repo"), os.path.join(T, "repo-wt")
app = "Library/Application Support/Whozmove"
desktop = "Library/Application Support/Claude/claude-code-sessions/account/org"

put(".claude/settings.json", {"model": "claude-sonnet-5-5", "effortLevel": "medium", "autoCompactWindow": 800000,
                              "modelSettings": {"claude-opus-5-5": {"effortLevel": "high"}},
                              "permissions": {"defaultMode": "default"}})

# Claude Code's registry, one file per process, named after it: a terminal session, a worktree session at work, a
# Claude Desktop session, an ended one, and files that aren't sessions.
put(f".claude/sessions/{term_pid}.json", {"pid": term_pid, "sessionId": "s-term", "cwd": repo, "status": "idle",
                                   "statusUpdatedAt": ms(9), "entrypoint": "cli", "kind": "interactive",
                                   "name": "fix tests", "procStart": "start-1",
                                   "messagingSocketPath": "/tmp/s-term.sock"})
put(f".claude/sessions/{wt_pid}.json", {"pid": wt_pid, "sessionId": "s-wt", "cwd": wt, "status": "busy",
                                   "statusUpdatedAt": ms(2), "entrypoint": "cli", "kind": "interactive",
                                   "procStart": "start-2"})
put(f".claude/sessions/{desk_pid}.json", {"pid": desk_pid, "sessionId": "s-desk", "hostSessionId": "local_desk",
                                   "cwd": repo, "status": "idle", "statusUpdatedAt": ms(30),
                                   "entrypoint": "claude-desktop", "kind": "interactive", "procStart": "start-3"})
put(f".claude/sessions/{paused_pid}.json", {"pid": paused_pid, "sessionId": "s-term", "cwd": repo, "status": "busy",
                                     "statusUpdatedAt": ms(9), "entrypoint": "cli", "kind": "interactive",
                                     "name": "the paused one", "procStart": "start-paused", "startedAt": ms(-1)})
# s-twice, open in two tabs, in a folder of its own: the copy at work speaks for it, though the idle one was started
# later and changed last, and keys go into neither. It has a transcript, so it's a conversation that has started.
twice = os.path.join(T, "twice")
os.makedirs(twice, exist_ok=True)
for pid, status, changed, started in [(twice_pids[0], "busy", 4, 30), (twice_pids[1], "idle", 1, 10)]:
    put(f".claude/sessions/{pid}.json", {"pid": pid, "sessionId": "s-twice", "cwd": twice, "status": status,
                                         "statusUpdatedAt": ms(changed), "entrypoint": "cli", "kind": "interactive",
                                         "name": "tidy the docs", "procStart": f"start-twice-{status}",
                                         "startedAt": ms(started)})
put(".claude/projects/p/s-twice.jsonl", [
    {"type": "user", "message": {"role": "user", "content": "tidy the docs"}, "timestamp": iso(30),
     "isSidechain": False}])
# s-ask, in two tabs: one asks something, so it speaks for the conversation over the one at work, which still counts as
# at work, so s-near, idle in the same folder, waits for it. s-idle, in two tabs both idle: the one whose state changed
# last speaks, though the other started later. s-both, in Claude Desktop and a tab: the tab, which changed last; keys
# may go into it, as none can land in Claude, but not Shift+Tabs, as the two share one record of the mode.
copies = {
    "s-ask": ("ask", "plan the trip", [("waiting", 20, 40, "cli"), ("busy", 2, 5, "cli")]),
    "s-idle": ("idle", "sort the photos", [("idle", 3, 50, "cli"), ("idle", 8, 6, "cli")]),
    "s-both": ("both", "draft the invite", [("idle", 30, 60, "claude-desktop"), ("idle", 5, 20, "cli")]),
}
spare = iter(twice_pids[2:])
for sid, (folder, name, procs) in copies.items():
    os.makedirs(os.path.join(T, folder), exist_ok=True)
    for number, (status, changed, started, entrypoint) in enumerate(procs):
        pid = next(spare)
        record = {"pid": pid, "sessionId": sid, "cwd": os.path.join(T, folder), "status": status,
                  "statusUpdatedAt": ms(changed), "entrypoint": entrypoint, "kind": "interactive", "name": name,
                  "procStart": f"start-{sid}-{number}", "startedAt": ms(started)}
        if entrypoint == "claude-desktop":
            record["hostSessionId"] = f"local_{sid}"
        put(f".claude/sessions/{pid}.json", record)
    put(f".claude/projects/p/{sid}.jsonl", [
        {"type": "user", "message": {"role": "user", "content": name}, "timestamp": iso(60), "isSidechain": False}])
put(f".claude/sessions/{halt_pid}.json", {"pid": halt_pid, "sessionId": "s-halt", "cwd": os.path.join(T, "idle"),
                                          "status": "idle", "statusUpdatedAt": ms(40), "entrypoint": "cli",
                                          "kind": "interactive", "name": "rest a while", "procStart": "start-halt"})
# Its compaction began 20 minutes ago and never said it ended: it's taken as over.
# Its last prompt was a message from another session, cut short by the hook in its closing tag: the message, and who
# sent it.
put(f"Library/Application Support/Whozmove/sessions/s-halt.json", {"compactingAt": ms(20), "lastPrompt":
    '<cross-session-message from="uds:/tmp/sock" from-name="Lead" from-mode="prompting"> Tidy the notes </cross-sess…'})
put(".claude/projects/p/s-halt.jsonl", [
    {"type": "user", "message": {"role": "user", "content": "rest a while"}, "timestamp": iso(40), "isSidechain": False}])
near = next(spare)
put(f".claude/sessions/{near}.json", {"pid": near, "sessionId": "s-near", "cwd": os.path.join(T, "ask"),
                                      "status": "idle", "statusUpdatedAt": ms(25), "entrypoint": "cli",
                                      "kind": "interactive", "name": "pack the bags", "procStart": "start-near"})
# At its prompt while a shell command Claude ran in the background still runs (Claude Code's "shell"): idle, so keys
# can go in. And one with a status Claude Code doesn't write today: Claude is taken to be busy, not gone.
for sid, status, name in [("s-shell", "shell", "watch the build"), ("s-odd", "resuming", "carry on")]:
    pid = next(spare)
    put(f".claude/sessions/{pid}.json", {"pid": pid, "sessionId": sid, "cwd": os.path.join(T, "idle"),
                                         "status": status, "statusUpdatedAt": ms(35), "entrypoint": "cli",
                                         "kind": "interactive", "name": name, "procStart": f"start-{sid}"})
    put(f".claude/projects/p/{sid}.jsonl", [
        {"type": "user", "message": {"role": "user", "content": name}, "timestamp": iso(35), "isSidechain": False}])
# At its prompt, its turn over half an hour after its process started, while what it started goes on in the background,
# beside s-shell and s-odd: an agent of its own on a step (shown, and holding the next steps and Deploy there), the
# shell command its hook noted (over: Claude Code no longer says one runs), an agent noted before this process started
# (the earlier process's), one carried on since (Claude Code listed it again at a stop), one whose own record says it
# has finished, Claude Code's own housekeeping (never shown), a monitor (shown, holding nothing), a kind not known yet
# (held for, until it's known), and an id that isn't plain (not one of the hook's). s-shell's command goes on: shown,
# holding nothing.
bg_pid = next(spare)
put(f".claude/sessions/{bg_pid}.json", {"pid": bg_pid, "sessionId": "s-bg", "cwd": os.path.join(T, "idle"),
                                        "status": "idle", "statusUpdatedAt": ms(4), "entrypoint": "cli",
                                        "kind": "interactive", "name": "review the app", "procStart": "start-s-bg",
                                        "startedAt": ms(30)})
put(".claude/projects/p/s-bg.jsonl", [
    {"type": "user", "message": {"role": "user", "content": "review the app"}, "timestamp": iso(6), "isSidechain": False}])
put(".claude/projects/p/s-bg/subagents/agent-a-done.meta.json", {"agentType": "general-purpose", "finished": True})
put(".claude/projects/p/s-bg/subagents/agent-a-native.meta.json", {"agentType": "general-purpose"})
put(f"{app}/sessions/s-bg.json", {
    "lastPrompt": "review the app", "lastPromptAt": ms(6), "lastReply": "Two reviews are under way.",
    "lastReplyAt": ms(4), "stageAt": ms(4), "transcriptPath": os.path.join(T, ".claude/projects/p/s-bg.jsonl"),
    "backgroundAt": ms(4), "background": {
        "a-native": {"type": "subagent", "what": "Review the native side", "startedAt": ms(5), "listedAt": ms(4),
                     "step": "Reading Storage.m", "stepAt": ms(1)},
        "b-dev": {"type": "shell", "what": "Start the dev server", "command": "npm run dev", "startedAt": ms(5),
                  "listedAt": ms(4)},
        "a-old": {"type": "subagent", "what": "Review the old build", "startedAt": ms(40), "listedAt": ms(35)},
        "t-docs": {"type": "teammate", "what": "Write the docs", "startedAt": ms(40), "listedAt": ms(4)},
        "a-done": {"type": "subagent", "what": "Find the tests", "startedAt": ms(5), "listedAt": ms(4)},
        "d-1": {"type": "dream", "what": "Tidying memories", "startedAt": ms(5), "listedAt": ms(4)},
        "m-log": {"type": "monitor", "what": "Watch the server log", "startedAt": ms(5), "listedAt": ms(4)},
        "x-new": {"type": "something new", "what": "A kind of job not known yet", "startedAt": ms(5),
                  "listedAt": ms(4)},
        "../x": {"type": "subagent", "what": "An id that isn't plain", "startedAt": ms(5), "listedAt": ms(4)}}})
# Pim, a member of the team below, cleared its conversation (/clear): its process goes on in Pim's folder under a new
# id, s-pim, and the id the team file records, s-pim-was, is listed nowhere. And Ivy, another member, whose own session
# runs in Pim's folder, not its own: it stays Ivy's, never Pim's or a duplicate of Pim, said to be in Pim's folder.
pim, ivy = os.path.join(T, "pim"), os.path.join(T, "ivy")
for folder in (pim, ivy):
    os.makedirs(folder, exist_ok=True)
for sid, name, changed, started in [("s-pim", "start afresh", 7, 45), ("s-ivy", "look at Pim's", 6, 40)]:
    pid = next(spare)
    put(f".claude/sessions/{pid}.json", {"pid": pid, "sessionId": sid, "cwd": pim, "status": "idle",
                                         "statusUpdatedAt": ms(changed), "entrypoint": "cli", "kind": "interactive",
                                         "name": name, "procStart": f"start-{sid}", "startedAt": ms(started)})
# One agent in the background, with a name too long for a wait to say whole: cut at a word's end.
long_pid = next(spare)
put(f".claude/sessions/{long_pid}.json", {"pid": long_pid, "sessionId": "s-long", "cwd": os.path.join(T, "long"),
                                          "status": "idle", "statusUpdatedAt": ms(3), "entrypoint": "cli",
                                          "kind": "interactive", "name": "write the tests", "procStart": "start-s-long",
                                          "startedAt": ms(20)})
os.makedirs(os.path.join(T, "long"), exist_ok=True)
put(".claude/projects/p/s-long.jsonl", [
    {"type": "user", "message": {"role": "user", "content": "write the tests"}, "timestamp": iso(5), "isSidechain": False}])
put(f"{app}/sessions/s-long.json", {"lastPrompt": "write the tests", "lastPromptAt": ms(5), "lastReply": "On it.",
                                    "lastReplyAt": ms(3), "backgroundAt": ms(3), "background": {
    "a-tests": {"type": "subagent", "what": "Write the search box tests and check every edge case there is",
                "startedAt": ms(4), "listedAt": ms(3)}}})
put(f"{app}/sessions/s-shell.json", {"backgroundAt": ms(35), "background": {
    "b-watch": {"type": "shell", "what": "Watch the build", "command": "make watch", "startedAt": ms(35)}}})
put(f".claude/sessions/{gone_pid}.json", {"pid": gone_pid, "sessionId": "s-gone", "cwd": repo, "status": "idle",
                                   "statusUpdatedAt": ms(60), "entrypoint": "cli", "kind": "interactive"})
# A session on a branch of its own in a clone of the repo (so GitHub's copy is the repo), which committed work there
# and is working on more: keys can't go in, but the one Backspace a request may press while Claude works can.
put(f".claude/sessions/{topic_pid}.json", {"pid": topic_pid, "sessionId": "s-topic", "cwd": os.path.join(T, "clone"),
                                    "status": "busy", "statusUpdatedAt": ms(15), "entrypoint": "cli",
                                    "kind": "interactive", "procStart": "start-topic"})
# It's compacting, by itself, mid-turn.
put(f"Library/Application Support/Whozmove/sessions/s-topic.json", {"outcome": "Committed", "outcomeAt": ms(15),
                                                                    "compactingAt": ms(1),
    # A message from another session cut short inside its opening tag: who sent it isn't known, nor what it says.
    "lastPrompt": '<cross-session-message from="uds:/tmp/a-folder-with-a-very-long-name…'})
# And another session in that clone, idle: its next steps and Deploy wait for the agent at work there. Its last prompt
# was a message from a session with no name, whole.
put(f"Library/Application Support/Whozmove/sessions/s-clone.json", {"lastPrompt":
    '<cross-session-message from="uds:/tmp/sock"> Check the notes. </cross-session-message> Sent by another session.'})
put(f".claude/sessions/{clone_pid}.json", {"pid": clone_pid, "sessionId": "s-clone", "cwd": os.path.join(T, "clone"),
                                    "status": "idle", "statusUpdatedAt": ms(20), "entrypoint": "cli",
                                    "kind": "interactive", "name": "review notes", "procStart": "start-clone"})
put(".claude/sessions/broken.json", "not json")
put(".claude/sessions/notes.txt", "not a session")

# The team the session leading it keeps (docs/reference/team.md): it runs as s-near, in its own folder; Wren, a member
# at work in the worktree on one job while another waits on you to try it (its row's track is the one it's at work on,
# and its line the try's ask, with Deploy for it: `alsoAsks`); Moss, a member in the clone, building, with s-clone,
# another session, open there too; one of your own sessions it follows, waiting on you to pick; and Bea, a member whose recorded
# session now runs somewhere else (s-desk, in the repo), which so doesn't count as it. Wren's try says P0, and holds up
# its other one; the one you pick between is Critical, in any
# case, and asks by its decision; Moss's says a word the ladder doesn't have, which reads as P2. The lead names what's
# next for you, Wren's job, so it takes that job's priority and title. Moss's job gives its time in seconds, as some tools write it; but the
# file says Moss is busy reviewing another's, which its row says in place of where its job stands. Wren and Moss are
# each in a group the file names (Wren's with room round its name), in the order its `groups` gives, which also names
# one nobody is in. The file also lists the lead among the sessions it follows, which leaves it its own place. Two
# jobs wait their turn after review, at a step nobody works on ("Ready to try"): Wren's, sized small and little work,
# which its row doesn't speak for, as it has one at work; and Moss's, with a size and an effort the panel
# doesn't know, left out, which moved after Moss's build but isn't the job marked now, as one at work comes first.
# Neither counts as at work for the lead. Your try says it waits too, but a step on you is what you're waited on for,
# never one that waits its turn.
def steps(*ids):
    words = {"plan": "Plan", "build": "Build", "review": "Review", "test": "Your try", "merge-yes": "Your yes",
             "merge": "Merge", "sketch": "Sketch", "look": "Look", "ready": "Ready to try"}
    kinds = {"plan": "approve", "test": "try", "merge-yes": "approve", "look": "choose", "build": "try"}
    return [{"id": i, "word": words[i], "you": i in ("plan", "test", "merge-yes", "look"), "kind": kinds.get(i),
             **({"waits": True} if i in ("ready", "test") else {})}
            for i in ids]
app_change = steps("plan", "build", "review", "test", "merge-yes", "merge")
put(f"{app}/team/team.json", {"version": 1, "projects": {repo: {
    "lead": {"session": "s-near", "worktree": os.path.join(T, "ask"), "name": "Atlas", "since": ms(90),
              "next": {"short": "Try the search box", "ask": "Try the search box, then say yes to merging it",
                       "job": "j1"}},
    "members": {
        "Wren": {"session": "s-wt", "worktree": wt, "part": "docs", "group": " Writers ",
                 "tag": " Design lead ", "shown": " Wren of docs "},
        "Moss": {"session": "s-topic", "worktree": os.path.join(T, "clone"), "part": "tests",
                 "group": "Reviewers", "doing": " Reviewing ", "status": "Wren's search box",
                 "tag": "Too many words here"},
        "Bea": {"session": "s-desk", "worktree": twice, "part": "icons"},
        "Pim": {"session": "s-pim-was", "worktree": pim, "part": "sounds"},
        "Ivy": {"session": "s-ivy", "worktree": ivy, "part": "colours"}},
    "groups": ["Reviewers", "Writers", "Nobody's"],
    "goals": [{"id": "launch", "name": "Spring launch", "due": "Fri"}, {"id": "speed", "name": " Faster pages "},
              {"id": "a goal", "name": "An id with a space"}, {"id": "launch", "name": "Named twice"}, {"id": "nameless"},
              {"id": "how-we-work", "name": "How we work", "work": True}],
    "followed": {"sort the photos": {"session": "s-idle", "worktree": os.path.join(T, "idle")},
                 "the desk": {"session": "s-near"}},
    "jobs": {
        "j1": {"title": "Search box", "stage": "test", "member": "Wren", "goal": "launch",
               "steps": app_change, "at": "test", "stageAt": ms(30),
               "short": "Try the search box", "ask": "Try it on a page with a hundred results",
               "priority": "p0"},
        "j2": {"title": "Faster sync", "stage": "build", "member": "Wren",
               "steps": app_change, "at": "build", "stageAt": ms(5), "dependsOn": ["j1"]},
        "j3": {"title": "Font picker", "stage": "build", "member": "Moss", "goal": "speed",
               "steps": steps("build", "test", "merge-yes", "merge"), "at": "build", "stageAt": ms(10) // 1000,
               "priority": "someday"},
        "j4": {"title": "Album covers", "stage": "look", "followed": "sort the photos",
               "goal": "no such goal",
               "steps": steps("sketch", "look"), "at": "look", "stageAt": ms(50),
               "decision": "Pick one of three covers", "priority": "Critical"},
        "j5": {"title": "Later", "stage": "queued", "member": "Moss",
               "steps": app_change},
        "j6": {"title": "Steps the file doesn't give", "stage": "build",
               "member": "Bea", "at": "build"},
        "j7": {"title": "Old banner", "stage": "done", "member": "Wren", "goal": "launch",
               "doneAt": ms(2 * 24 * 60), "dependsOn": ["j1"]},
        "j8": {"title": "A dropped idea", "stage": "dropped", "member": "Bea"},
        "j9": {"title": "Dark theme", "stage": "ready", "member": "Wren", "goal": "speed",
               "steps": steps("build", "review", "ready", "test"), "at": "ready", "stageAt": ms(15),
               "size": "small", "effort": "low"},
        "j10": {"title": "Tooltips", "stage": "ready", "member": "Moss",
                "steps": steps("build", "review", "ready", "test"), "at": "ready", "stageAt": ms(4),
                "size": "huge", "effort": 3}}}}})

# Terminal sessions in each permission mode, for the mode menu's Shift+Tab counts: in auto (so auto is in
# its cycle), in plan with nothing known about auto, in a project whose settings turn auto off (in plan, and
# one still in auto), in bypass, and in dontAsk.
no_auto = os.path.join(T, "no-auto")
put("no-auto/.claude/settings.json", {"disableAutoMode": "disable"})
for number, (sid, cwd, mode) in enumerate([("m-auto", repo, "auto"), ("m-plan", repo, "plan"),
                                           ("m-noauto-plan", no_auto, "plan"), ("m-noauto-in-auto", no_auto, "auto"),
                                           ("m-bypass", repo, "bypassPermissions"), ("m-dontask", repo, "dontAsk")]):
    put(f".claude/sessions/{mode_pids[number]}.json", {"pid": mode_pids[number], "sessionId": sid, "cwd": cwd,
                                                      "status": "idle", "statusUpdatedAt": ms(50), "entrypoint": "cli",
                                                      "kind": "interactive", "procStart": f"start-mode-{number}"})
    put(f"Library/Application Support/Whozmove/sessions/{sid}.json", {"permissionMode": mode})

# Transcripts. s-term: a prompt in acceptEdits, a reply with its usage and the effort it was made with (over the
# settings' effort), a PR it made, and a sub-agent's reply that must not count. s-wt: a prompt in plan mode (its only
# record of its mode), a reply with no effort (the settings' stands), then a compaction that leaves the context smaller,
# with the summary Claude Code writes after it, which isn't a message: the conversation last moved with the reply.
put(".claude/projects/p/s-term.jsonl", [
    {"type": "user", "message": {"role": "user", "content": "please fix the tests"}, "timestamp": iso(10),
     "permissionMode": "acceptEdits", "isSidechain": False},
    {"type": "assistant", "message": {"model": "claude-opus-5-5", "content": [{"type": "text", "text": "Done."}],
     "usage": {"input_tokens": 1200, "cache_creation_input_tokens": 3000, "cache_read_input_tokens": 420000,
               "output_tokens": 800}}, "timestamp": iso(9), "isSidechain": False, "effort": "xhigh"},
    {"type": "pr-link", "prUrl": "https://github.com/example/whozmove/pull/7", "prNumber": 7,
     "prRepository": "example/whozmove", "timestamp": iso(8)},
    # What it wrote: a plan sent back and its second version, still waiting; a page and notes it created, and the page
    # written again later; and what isn't listed: a file it rewrote, one in Claude Code's own folder, and code.
    *[{"type": "assistant", "isSidechain": False, "timestamp": iso(when),
       "message": {"content": [{"type": "tool_use", "id": cid, "name": tool, "input": tool_input}]}}
      for cid, tool, tool_input, when in [
          ("p1", "ExitPlanMode", {"plan": "# Fix the tests\nFirst try.", "planFilePath": T + "/.claude/plans/fix.md"}, 9.6),
          ("w1", "Write", {"file_path": repo + "/docs/flow.html", "content": "<html><title> Retry flow </title>"}, 9.6),
          ("w2", "Write", {"file_path": repo + "/notes.md", "content": "\n## Pricing notes\nText."}, 9.6),
          ("w3", "Write", {"file_path": repo + "/README.md", "content": "# Readme"}, 9.6),
          ("w4", "Write", {"file_path": T + "/.claude/plans/fix.md", "content": "# Fix"}, 9.6),
          ("w5", "Write", {"file_path": repo + "/app.py", "content": "print()"}, 9.6)]],
    {"type": "user", "isSidechain": False, "timestamp": iso(9.6), "message": {"content": [
        {"type": "tool_result", "tool_use_id": "p1", "is_error": True, "content": "The user wants changes"},
        {"type": "tool_result", "tool_use_id": "w1", "content": "File created successfully at: x"}]}},
    # A record about a call that comes before its result, which must not hide it.
    {"type": "attachment", "timestamp": iso(9.6), "attachment": {"type": "hook_success", "tool_use_id": "w2"}},
    *[{"type": "user", "isSidechain": False, "timestamp": iso(9.6), "message": {"content": [
        {"type": "tool_result", "tool_use_id": cid, "content": text}]}}
      for cid, text in [("w2", "File created successfully at: x"), ("w3", "The file x has been updated."),
                        ("w4", "File created successfully at: x"), ("w5", "File created successfully at: x")]],
    {"type": "assistant", "isSidechain": False, "timestamp": iso(9.3), "message": {"content": [
        {"type": "tool_use", "id": "p2", "name": "ExitPlanMode", "input": {"plan": "# Fix the tests, again\nBetter.",
                                                                           "planFilePath": T + "/.claude/plans/fix.md"}},
        {"type": "tool_use", "id": "w6", "name": "Write", "input": {"file_path": repo + "/docs/flow.html",
                                                                   "content": "<title>Retry flow, v2</title>"}}]}},
    {"type": "user", "isSidechain": False, "timestamp": iso(9.3), "message": {"content": [
        {"type": "tool_result", "tool_use_id": "w6", "content": "The file x has been updated."}]}},
    {"type": "assistant", "message": {"model": "claude-haiku-5-5", "content": [{"type": "text", "text": "sub"}],
     "usage": {"input_tokens": 10, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 5}},
     "timestamp": iso(7), "isSidechain": True, "effort": "low"},
])
put(".claude/projects/p/s-wt.jsonl", [
    {"type": "user", "message": {"role": "user", "content": "run the suite"}, "timestamp": iso(4),
     "permissionMode": "plan", "isSidechain": False},
    {"type": "assistant", "message": {"model": "claude-opus-5-5", "content": [{"type": "text", "text": "Testing."}],
     "usage": {"input_tokens": 100, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 300000}},
     "timestamp": iso(3), "isSidechain": False},
    {"type": "system", "subtype": "compact_boundary", "compactMetadata": {"postTokens": 52000}, "timestamp": iso(2)},
    {"type": "user", "message": {"role": "user", "content": "This session is being continued from a previous one."},
     "timestamp": iso(2), "isSidechain": False, "isCompactSummary": True, "isVisibleInTranscriptOnly": True},
])

# Edits, as Claude Code records each one's result. s-topic: retry.py written, then added to; and edits that aren't
# counted: a file outside its checkout, and one in Claude Code's own folder; and a write with no result. s-clone: a line added to retry.py, and
# review.md written.
clone = os.path.join(T, "clone")
def edit(uuid, path, minutes_ago, patch=None, content=None):
    result = {"filePath": path, "structuredPatch": patch or [], "originalFile": None}
    if content is not None:
        result.update(type="create", content=content)
    return {"type": "user", "uuid": uuid, "isSidechain": False, "timestamp": iso(minutes_ago), "toolUseResult": result,
            "message": {"content": [{"type": "tool_result", "tool_use_id": "t-" + uuid, "content": "ok"}]}}
def shell(uuid, minutes_ago, command, diff=None):
    result = {"stdout": "", "stderr": "", "interrupted": False, "isImage": False, "noOutputExpected": False}
    if diff is not None:
        result["bashEditDiff"] = diff
    return [{"type": "assistant", "isSidechain": False, "timestamp": iso(minutes_ago), "message": {"content": [
                {"type": "tool_use", "id": "b-" + uuid, "name": "Bash", "input": {"command": command}}]}},
            {"type": "user", "isSidechain": False, "timestamp": iso(minutes_ago), "toolUseResult": result,
             "message": {"content": [{"type": "tool_result", "tool_use_id": "b-" + uuid, "content": ""}]}}]
put(".claude/projects/p/s-topic.jsonl", [
    # In auto mode, where Claude Code records what each shell command changed: notes.txt is its command's (a "git" in
    # the text it hands its script isn't one it runs), but what a git command brought in (a.txt's line) isn't.
    {"type": "permission-mode", "permissionMode": "auto", "sessionId": "s-topic"},
    *shell("n1", 14, "./make-notes.sh <<'EOF'\nthen `git status` shows it\nEOF", {"files": [{"filePath": clone + "/notes.txt", "created": True, "hunks": [
        {"oldStart": 0, "oldLines": 0, "newStart": 1, "newLines": 1, "lines": ["+Made by its command."]}]}],
        "moreFiles": 0}),
    *shell("g1", 14, "cd " + clone + " && git stash pop", {"files": [{"filePath": clone + "/a.txt", "hunks": [
        {"oldStart": 1, "oldLines": 1, "newStart": 1, "newLines": 2, "lines": [" a", "+z"]}]}], "moreFiles": 0}),
    edit("e1", clone + "/retry.py", 30, content="def schedule(invoice):\n    return queue.put(invoice)\n"),
    edit("e2", clone + "/retry.py", 16, patch=[{"oldStart": 1, "oldLines": 2, "newStart": 1, "newLines": 4, "lines": [
        " def schedule(invoice):", "     return queue.put(invoice)", "+def on_card(customer):", "+    run_now(customer)"]}]),
    edit("e3", T + "/elsewhere.txt", 16, content="not in the checkout\n"),
    edit("e4", T + "/.claude/notes.md", 16, content="Claude Code's own\n"),
    # A write whose turn was interrupted: its request is there, its result never was, and the file was written.
    {"type": "assistant", "isSidechain": False, "timestamp": iso(15), "message": {"content": [
        {"type": "tool_use", "id": "w-cut", "name": "Write", "input": {
            "file_path": clone + "/interrupted.py",
            "content": "def written_anyway():\n    return schedule(None) or None\n"}}]}},
    # A write you turned down: what it asked for isn't its, though you then typed the same line yourself.
    {"type": "assistant", "isSidechain": False, "timestamp": iso(15), "message": {"content": [
        {"type": "tool_use", "id": "w-no", "name": "Write", "input": {
            "file_path": clone + "/typed.txt", "content": "typed by hand after all\n"}}]}},
    {"type": "user", "isSidechain": False, "timestamp": iso(15), "message": {"content": [
        {"type": "tool_result", "tool_use_id": "w-no", "is_error": True, "content": "The user turned this down."}]}},
    # A project's own .claude folder is work like any other (only Claude Code's own, in the home folder, isn't).
    edit("e5", clone + "/.claude/commands/check.md", 15, content="Check the retry queue.\n"),
    # Back in default mode since: the commands above were still recorded, as they ran in auto mode. A git command
    # since doesn't count against that: what git changes is never a session's.
    {"type": "permission-mode", "permissionMode": "default", "sessionId": "s-topic"},
    *shell("g2", 13, "git status --short"),
])
put(".claude/projects/p/s-clone.jsonl", [
    # A shell command in default mode, where Claude Code doesn't record what it changed: it could have changed
    # anything, so what s-clone changed isn't known.
    {"type": "permission-mode", "permissionMode": "default", "sessionId": "s-clone"},
    *shell("t1", 22, "./tidy.sh"),
    edit("c1", clone + "/retry.py", 21, patch=[{"oldStart": 3, "oldLines": 2, "newStart": 3, "newLines": 3, "lines": [
        " def on_card(customer):", "     run_now(customer)", "+# reviewed by the second session"]}]),
    edit("c2", clone + "/review.md", 21, content="Looks good to me overall.\n"),
])
# s-clone's sub-agent, whose record Claude Code keeps beside the session's own: its edits are the session's.
put(".claude/projects/p/s-clone/subagents/agent-a1.jsonl", [
    edit("a1", clone + "/helper.py", 20, content="def helper():\n    return schedule(None)\n"),
])

# What the hook recorded. s-term's is an older hook's, which notes where it edited but not when: the end of its turn
# that tested stands in (workEditedAt).
put(f"{app}/sessions/s-term.json", {"lastPrompt": "please fix the tests", "lastPromptAt": ms(10),
                                    "lastReply": "All done: the tests pass.", "lastReplyAt": ms(9), "notice": None,
                                    "permissionMode": "acceptEdits", "stageAt": ms(9),
                                    "activity": None, "activityAt": ms(9), "outcome": "Tested", "outcomeAt": ms(9),
                                    "workRoot": repo, "turnReached": [], "workSteps": ["Tested"],
                                    "audit": {"found": 3, "left": 1, "settled": True, "at": ms(9)}})
# At work, with a watcher it left running in the background: the registry says only busy, so the hook's list stands.
put(f"{app}/sessions/s-wt.json", {"lastPrompt": "run the suite", "lastPromptAt": ms(2), "stageAt": ms(1),
                                  "activity": "Run the tests", "activityAt": ms(1), "workRoot": repo,
                                  "backgroundAt": ms(3), "background": {
                                      "b-vitest": {"type": "shell", "what": "Run the tests in watch mode",
                                                   "command": "vitest --watch", "startedAt": ms(3)}}})
# Claude Desktop's own record of a conversation (below) goes on its row before the hook's, and where both say when it
# last did something, the later time stands: the hook's for s-desk, Claude's for s-closed.
put(f"{app}/sessions/s-desk.json", {"activityAt": ms(5)})
# A conversation with no process has nothing running in the background, whatever its hook last listed.
put(f"{app}/sessions/s-closed.json", {"activityAt": ms(300), "backgroundAt": ms(300), "background": {
    "a-left": {"type": "subagent", "what": "Left over", "startedAt": ms(300)}}})

# Whozmove's hooks as put in place a day ago, with Don't Wait on Me's part, which the sessions here, started since, run:
# their mode menu offers it (--print-why-not).
hook = os.path.join(T, app, "plugin/hooks/whozmove-claude-permission.py")
os.makedirs(os.path.dirname(hook), exist_ok=True)
with open(hook, "w") as f:
    f.write("ASKS = 'asks'\nDONT_WAIT = 'dont-wait'\n")
os.utime(hook, (now - 86400, now - 86400))

# Requests waiting for an OK: the oldest per session shows, as its hook left it (this one goes by itself in 3 minutes
# if no one answers: Don't Wait on Me); one too long to show in full (over ShownLength in app/Asks.m) is cut short;
# one whose hook has gone is cleared away.
put(f"{app}/asks/aaaa1111.json", {"id": "aaaa1111", "sessionId": "s-term", "tool": "Bash",
                                  "input": {"command": "npm test", "description": "Run the tests"},
                                  "cwd": repo, "at": ms(2), "pid": term_pid, "expiresAt": ms(-3)})
put(f"{app}/asks/dddd4444.json", {"id": "dddd4444", "sessionId": "s-term", "tool": "Bash",
                                  "input": {"command": "npm run lint"}, "cwd": repo, "at": ms(1), "pid": term_pid})
put(f"{app}/asks/bbbb2222.json", {"id": "bbbb2222", "sessionId": "s-wt", "tool": "Write",
                                  "input": {"file_path": os.path.join(wt, "big.txt"), "content": "x" * 100005},
                                  "cwd": wt, "at": ms(1), "pid": wt_pid})
put(f"{app}/asks/cccc3333.json", {"id": "cccc3333", "sessionId": "s-term", "tool": "Bash",
                                  "input": {"command": "ls"}, "cwd": repo, "at": ms(5), "pid": gone_pid})

# Claude Desktop's conversations: the running one, a closed one whose folder has gone, and ones that mustn't show: too
# old, archived, not a conversation file.
put(f"{desktop}/local_desk.json", {"sessionId": "local_desk", "cliSessionId": "s-desk", "title": "Desk chat",
                                   "cwd": repo, "lastActivityAt": ms(30), "model": "claude-sonnet-5-5",
                                   "effort": "low", "permissionMode": "plan", "isArchived": False})
put(f"{desktop}/local_closed.json", {"sessionId": "local_closed", "cliSessionId": "s-closed", "title": "Closed chat",
                                     "cwd": os.path.join(T, "gone"), "originCwd": repo, "lastActivityAt": ms(120),
                                     "model": "claude-haiku-5-5"})
put(f"{desktop}/local_old.json", {"sessionId": "local_old", "title": "Old chat", "cwd": repo,
                                  "lastActivityAt": ms(5 * 24 * 60)})
put(f"{desktop}/local_arch.json", {"sessionId": "local_arch", "title": "Archived chat", "cwd": repo,
                                   "lastActivityAt": ms(60), "isArchived": True})
put(f"{desktop}/other.json", {"sessionId": "nope"})

# Terminal sessions Whozmove kept (modules/claude-code/app/KeptSessions.m), in a folder outside the checkouts: ended in
# Ghostty (with what its hooks recorded), in iTerm2, in Terminal and in an app no module knows (which opens again in the
# first terminal: a print run follows no pick), each a row; and ones that mustn't show: too old, its transcript gone,
# its folder gone, one cleared while its process went on as s-clone, s-term (running) and s-closed (Claude Desktop's
# own), and files that aren't records.
ended, kept = os.path.join(T, "ended"), f"{app}/conversations"
os.makedirs(ended, exist_ok=True)
def keep(sid, terminal, minutes_ago, cwd=ended, transcript=True, **more):
    path = os.path.join(T, f".claude/projects/p/{sid}.jsonl")
    if transcript:
        put(path, [{"type": "user", "message": {"role": "user", "content": f"carry on with {sid}"},
                    "timestamp": iso(minutes_ago + 1), "isSidechain": False},
                   {"type": "assistant", "message": {"model": "claude-opus-5-5",
                                                     "content": [{"type": "text", "text": "Done."}]},
                    "timestamp": iso(minutes_ago), "isSidechain": False}])
    put(f"{kept}/{sid}.json", {"sessionId": sid, "cwd": cwd, "terminal": terminal, "pid": 4242,
                               "procStart": f"start-{sid}", "transcript": path, "activeAt": ms(minutes_ago),
                               "name": f"the {sid} one", **more})
keep("k-ghostty", "com.mitchellh.ghostty", 120)
put(f"{app}/sessions/k-ghostty.json", {"lastPrompt": "carry on with k-ghostty", "lastPromptAt": ms(121),
                                       "lastReply": "Done: the page loads again.", "lastReplyAt": ms(120),
                                       "permissionMode": "acceptEdits", "stageAt": ms(120)})
keep("k-iterm", "com.googlecode.iterm2", 200)
keep("k-terminal", "com.apple.Terminal", 300)
keep("k-vscode", "com.microsoft.VSCode", 400)

# Four more teams, each led from a conversation ended in its own folder, for what the lead says is next for you: only in
# full (the row says the whole of it), low with a job the file doesn't have (no title), not words at all (nothing next),
# and only a few words.
with open(os.path.join(T, app, "team/team.json")) as f:
    team = json.load(f)
for sid, nxt in [("k-next-ask", {"ask": "Read the three opening lines on the page and say which one reads best"}),
                 ("k-next-low", {"short": "Pick a cover", "priority": "p2", "job": "j99"}),
                 ("k-next-odd", "Pick a cover"),
                 ("k-next-same", {"short": "Read the proofs"})]:
    folder = os.path.join(T, sid)
    os.makedirs(folder, exist_ok=True)
    keep(sid, "com.apple.Terminal", 500, cwd=folder)
    team["projects"][folder] = {"lead": {"session": sid, "worktree": folder, "name": sid, "next": nxt}}
# The first two have a member, ended in its folder too, whose last prompt was a message another session sent, its
# process gone: who sent it, by its name and its address.
team["projects"][os.path.join(T, "k-next-ask")]["members"] = {
    "Fern": {"session": "k-fern", "worktree": os.path.join(T, "k-next-ask"), "part": "words",
             "group": "team"}}
team["projects"][os.path.join(T, "k-next-low")]["members"] = {
    "Sage": {"session": "k-sage", "worktree": os.path.join(T, "k-next-low"), "part": "covers"},
    "Reed": {"session": "k-reed", "worktree": os.path.join(T, "k-next-low"), "part": "spines"}}
# Each has jobs not under way, and its row says where the one it speaks for stands. Fern's are queued: the one shown
# is the more pressing of its P1 ones queued first, with words of its own, over a P2 one queued earlier (its times
# in seconds), a P1 one queued later, and one with no time, which goes last. Sage's are parked, with no words (its
# stage alone), and one done says nothing; but one waits its turn after review, under way, so its row speaks for that
# one, by its step's word, idle. Reed, whose session isn't running, has only two parked jobs: the one marked now is the
# one that moved last.
team["projects"][os.path.join(T, "k-next-ask")]["jobs"] = {
    "j7": {"title": "Opening lines", "stage": "queued", "member": "Fern",
           "priority": "p2", "queuedAt": ms(600) // 1000, "stageAt": ms(600) // 1000},
    "j8": {"title": "Page titles", "stage": "queued", "member": "Fern",
           "status": "after the covers", "priority": "p1", "queuedAt": ms(300), "stageAt": ms(300)},
    "j13": {"title": "Chapter heads", "stage": "queued", "member": "Fern",
            "priority": "p1", "queuedAt": ms(250), "stageAt": ms(250)},
    "j14": {"title": "Index", "stage": "queued", "member": "Fern", "priority": "P1"}}
team["projects"][os.path.join(T, "k-next-low")]["jobs"] = {
    "j9": {"title": "Back covers", "stage": "parked", "member": "Sage",
           "stageAt": ms(200)},
    "j12": {"title": "Spine", "stage": "parked", "member": "Sage", "stageAt": ms(150)},
    "j10": {"title": "Front covers", "stage": "done", "member": "Sage",
            "status": "shipped", "stageAt": ms(100)},
    "j17": {"title": "Endpapers", "stage": "ready", "member": "Sage",
            "steps": steps("build", "review", "ready", "test"), "at": "ready", "stageAt": ms(180)},
    "j18": {"title": "Ribbons", "stage": "parked", "member": "Reed", "stageAt": ms(90)},
    "j19": {"title": "Head bands", "stage": "parked", "member": "Reed", "stageAt": ms(70)}}
# The third has a member with two jobs under way, the one that moved last without steps: its row speaks for that one
# alone, with no track, so its line and its track are never two jobs'. The first's member names Team as its group, and
# the third's a name with a character that can't be seen: neither is a group of its own. The third also lists itself
# among its members, which leaves it its own place, and not among the sessions it leads.
team["projects"][os.path.join(T, "k-next-odd")]["members"] = {
    "Ivy": {"session": "k-ivy", "worktree": os.path.join(T, "k-next-odd"), "part": "layout",
            "group": "Lay\u200bout"},
    "Ash": {"session": "k-next-odd", "worktree": os.path.join(T, "k-next-odd"), "part": "lead"}}
team["projects"][os.path.join(T, "k-next-odd")]["jobs"] = {
    "j15": {"title": "Margins", "stage": "build", "member": "Ivy",
            "steps": steps("build", "test", "merge-yes", "merge"), "at": "build", "stageAt": ms(40)},
    "j16": {"title": "Gutters", "stage": "build", "member": "Ivy",
            "status": "wider gutters", "stageAt": ms(20)}}
keep("k-ivy", "com.apple.Terminal", 470, cwd=os.path.join(T, "k-next-odd"))
keep("k-sage", "com.apple.Terminal", 460, cwd=os.path.join(T, "k-next-low"))
put(f"{app}/sessions/k-sage.json", {"lastPrompt": '<cross-session-message from="uds:/tmp/cc-socks/1.sock" '
                                    'from-name="covers desk" from-mode="prompting"> Draw three covers '
                                    '</cross-session-message>', "lastPromptAt": ms(462),
                                    "lastReply": "Three covers are drawn", "lastReplyAt": ms(460)})
keep("k-fern", "com.apple.Terminal", 450, cwd=os.path.join(T, "k-next-ask"))
put(f"{app}/sessions/k-fern.json", {"lastPrompt": '<cross-session-message from="uds:/tmp/cc-socks/1.sock" '
                                    'from-name="k-next-ask" from-mode="prompting"> Write the opening lines '
                                    '</cross-session-message>', "lastPromptAt": ms(452),
                                    "lastReply": "Three opening lines are on the page", "lastReplyAt": ms(450)})
# A team whose file names the session you talk to (`front`) apart from the one running it, each in its own folder: the
# front is the chief, with the name it shows, and the one running it keeps the team's counts and the sessions it leads.
# The file also lists the front among its members, which leaves it the front's place, never a member's. The fourth team
# names its lead's own session as its front, which is the lead, still the chief; another names a front and no lead,
# which fronts no team; and one names a front and a lead with no session, which fronts no team either. Their folders sort after the others', so the first team with a lead stays the one above.
# The front runs in the project's own folder, so another conversation ended there (k-desk-own) is said to be in its
# folder but isn't the team's history (no `history`), as yours are there too; the lead's folder apart from it is.
# The one running the team behind its front takes the group and the tag the file gives it, as a member does, and
# the file's `groups` names Team (in its own case) among them, so Lo, in no group, is placed there; the one that is
# the chief keeps no group or tag, whatever the file says.
desk, behind, alone, unseated = (os.path.join(T, name) for name in ("studio-desk", "studio-behind", "studio-alone",
                                                                      "studio-unseated"))
for folder in (desk, behind, alone, unseated):
    os.makedirs(folder, exist_ok=True)
team["projects"][desk] = {
    "front": {"session": "k-desk", "worktree": desk, "name": "Desk", "shown": " The desk "},
    "lead": {"session": "k-behind", "worktree": behind, "name": "Kit", "group": " Reviewers ",
             "tag": " lead "},
    "members": {"Rue": {"session": "k-desk", "worktree": desk, "part": "talk"},
                "Lo": {"session": "k-lo", "worktree": behind, "part": "build"}},
    "groups": ["Reviewers", "team", "Writers"]}
team["projects"][os.path.join(T, "k-next-same")]["front"] = {"session": "k-next-same", "name": "Same"}
team["projects"][os.path.join(T, "k-next-same")]["lead"].update(group="Reviewers", tag="lead")
team["projects"][alone] = {"front": {"session": "k-alone", "worktree": alone, "name": "Alone"}}
team["projects"][unseated] = {"front": {"session": "k-unseated", "worktree": unseated, "name": "Unseated"},
                              "lead": {"name": "Nobody yet"}}
keep("k-desk", "com.apple.Terminal", 440, cwd=desk)
keep("k-desk-own", "com.apple.Terminal", 445, cwd=desk)
keep("k-behind", "com.apple.Terminal", 430, cwd=behind)
keep("k-lo", "com.apple.Terminal", 420, cwd=behind)
keep("k-alone", "com.apple.Terminal", 410, cwd=alone)
keep("k-unseated", "com.apple.Terminal", 405, cwd=unseated)
put(f"{app}/team/team.json", team)
keep("k-old", "com.mitchellh.ghostty", 4 * 24 * 60)
keep("k-no-transcript", "com.mitchellh.ghostty", 60, transcript=False)
keep("k-folder-gone", "com.mitchellh.ghostty", 60, cwd=os.path.join(T, "never-made"))
keep("k-cleared", "com.mitchellh.ghostty", 30, pid=clone_pid, procStart="start-clone")
keep("s-term", "com.mitchellh.ghostty", 9, cwd=repo, transcript=False, name="old name")
keep("s-closed", "com.mitchellh.ghostty", 120, cwd=repo, transcript=False)
put(f"{kept}/broken.json", "not json")
put(f"{kept}/k-misnamed.json", {"sessionId": "k-other", "cwd": ended})

# Projects, each with what Whozmove looks for to suggest a deploy command (modules/deploy/app/Deploys.m), in the order
# it looks: one per kind; scripts and targets that look as if they could reach production, by what they run (never
# suggested: the next that fits is); and one with nothing to go on (no Deploy).
projects = {
    "whozmove": {"build.sh": "#!/bin/bash\n", "app/swap-in.sh": "#!/bin/bash\n"},
    "compose": {"compose.yaml": "services: {}\n"},
    "pm2": {"ecosystem.config.js": "module.exports = {};\n"},
    "pkg-local": {"package.json": {"scripts": {"deploy:local": "node scripts/install.js"}}, "pnpm-lock.yaml": ""},
    "pkg-prod": {"package.json": {"scripts": {"deploy:local": "vercel --prod"}}},
    "pkg-fly": {"package.json": {"scripts": {"deploy:local": "fly deploy --local-only",
                                             "install:local": "node scripts/install.js"}}},
    "make": {"Makefile": "build:\n\tcc main.c\ninstall:\n\tcp a.out ~/bin/\n"},
    "make-prod": {"Makefile": "install: publish\n\tcp a.out ~/bin/\npublish:\n\tgit push origin main\n"
                              "deploy-local: ## Deploy it\n\tvercel --prod\n"},
    "pkg-bin": {"package.json": {"bin": {"tool": "cli.js"}}},
    "rust": {"Cargo.toml": "[package]\nname = \"tool\"\n", "src/main.rs": "fn main() {}\n"},
    "go": {"go.mod": "module tool\n", "main.go": "package main\n"},
    "python": {"pyproject.toml": "[project]\nname = \"tool\"\n\n[project.scripts]\ntool = \"tool:main\"\n"},
    "nothing": {"README.md": "Notes\n"},
}
for name, files in projects.items():
    for path, content in files.items():
        put(f"projects/{name}/{path}", content)

# Some of those folders' last deploy, as modules/deploy/app/Deploys.m keeps it (deploys/<FNV-1a hash of the folder's
# path>/): one that went through, one that failed, one you stopped (the status its shell wrote as it went doesn't
# count), one that ended without writing its status (it ended when its log last changed), one still running, one whose
# status is written but whose shell is still there
# (running), and one noted without when its shell started, whose pid is in use now (ended: the pid alone could be
# anyone's).
import ctypes, struct
def started(pid):
    # When a process started, as app/shared/Processes.m's ProcessStartedAt reads it: kinfo_proc's p_starttime, in microseconds.
    info, size = ctypes.create_string_buffer(648), ctypes.c_size_t(648)
    mib = (ctypes.c_int * 4)(1, 14, 1, pid)  # CTL_KERN, KERN_PROC, KERN_PROC_PID
    if ctypes.CDLL(None).sysctl(mib, 4, info, ctypes.byref(size), None, 0) != 0 or not size.value:
        return 0
    sec, usec = struct.unpack_from("<qi", info.raw, 0)
    return sec * 1000000 + usec

# s-near, the lead, registered as started when its process did and with its messaging address, so a message it sent is
# known by its process: one of your own sessions it follows had its last prompt from it, and its reply went to it, not
# to you. Its own last prompt came from itself, which never makes it one that replies to itself. Both came just now: a
# message from before its sender's process started isn't taken for that process's.
with open(os.path.join(T, f".claude/sessions/{near}.json")) as f:
    put(f".claude/sessions/{near}.json", {**json.load(f), "startedAt": started(near) // 1000,
                                          "messagingSocketPath": f"/tmp/cc-socks/{near}.sock"})
put(f"{app}/sessions/s-near.json", {"lastPrompt": f'<cross-session-message from="uds:/tmp/cc-socks/{near}.sock" '
                                    'from-name="pack the bags" from-mode="prompting"> Look again at the list '
                                    '</cross-session-message>', "lastPromptAt": ms(0),
                                    "lastReply": "The list is up to date", "lastReplyAt": ms(0)})
put(f"{app}/sessions/s-idle.json", {"lastPrompt": f'<cross-session-message from="uds:/tmp/cc-socks/{near}.sock" '
                                    'from-name="pack the bags" from-mode="prompting"> Pick three covers '
                                    '</cross-session-message>', "lastPromptAt": ms(0),
                                    "lastReply": "Three covers are ready", "lastReplyAt": ms(0)})

def run_dir(folder):
    h = 14695981039346656037
    for byte in os.fsencode(folder):
        h = ((h ^ byte) * 1099511628211) % 2**64
    return f"{app}/deploys/{h:016x}"

def last_run(name, pid, files, minutes_ago, noted_start=True):
    folder = os.path.join(T, "projects", name)
    run = {"folder": folder, "command": "x", "startedAt": ms(10), "pid": pid}
    if noted_start:
        run["processStart"] = started(pid) or 1  # a shell that's gone: any start time no process has now
    put(f"{run_dir(folder)}/run.json", run)
    for file, content in files.items():
        put(f"{run_dir(folder)}/{file}", content)
    for file in list(files) + ["run.json"]:
        at = now - (10 if file == "run.json" else minutes_ago) * 60
        os.utime(os.path.join(T, run_dir(folder), file), (at, at))

last_run("compose", gone_pid, {"status": "0\n", "log": "Started\n"}, 3)
last_run("make", gone_pid, {"status": "2\n", "log": "cc main.c\nmake: *** [install] Error 1\n\n"}, 3)
last_run("pm2", gone_pid, {"status": "143\n", "stopped": "stopped", "log": "Reloading\n"}, 2)
last_run("go", gone_pid, {"log": "go: downloading\n"}, 4)
last_run("rust", run_pid, {"log": "Compiling\n"}, 1)
last_run("python", run_pid, {"status": "0\n", "log": "done\n"}, 1)
last_run("pkg-fly", run_pid, {"log": "Deploying\n"}, 1, noted_start=False)

# A project for what the set-up card is told a command really runs: package scripts (with their pre- ones, npm's
# start, and a script that runs another runner's), and Makefile targets with what they depend on, and a file the
# Makefile includes and one it names by a variable; a shell script that runs make, and a file given to node. Then a
# project with a GNUmakefile beside its Makefile (make reads the first), and one whose package.json is a pipe, which is
# never read (it would hold Deploy's queue).
put("check-project/package.json", {"scripts": {"deploy:local": "fly deploy --local-only",
                                               "predeploy:local": "npm run build", "build": "tsc",
                                               "install:local": "node scripts/install.js", "ship": "vercel --prod",
                                               "prestart": "npm run build", "start": "node server.js",
                                               "serve": "bun run start"}})
put("check-project/Makefile", ".PHONY: install deploy-local publish\n-include config.mk\ninclude $(EXTRA)\n\n"
                              "build: main.c ## Build it\n\tcc -o tool main.c\n\n"
                              "install: build\n\tcp tool $(PREFIX)/\n\ndeploy-local: build publish\n\t./tool --install\n\n"
                              "publish:\n\tgit push origin main\n\nVERSION := 1.0\n")
put("check-project/config.mk", "PREFIX := ~/bin\n")
put("check-project/server.js", "require('http').createServer().listen(process.env.PORT)\n")
put("check-project/scripts/up.sh", "#!/bin/sh\nmake install\n")
put("gnu-project/GNUmakefile", "all:\n\t@echo the GNU one\n")
put("gnu-project/Makefile", "all:\n\t@echo not this one\n")
os.makedirs(os.path.join(T, "fifo-project"), exist_ok=True)
os.mkfifo(os.path.join(T, "fifo-project/package.json"))
# Files a command depends on that the check can't read: a package.json and a Makefile linked from outside the
# checkout, and a Makefile including one outside it, all said as such, never passed over. A program that isn't UTF-8
# (bin/server), checked by its bytes. Words the reading must not pass over: a runner's options before `run`, a word it
# doesn't know, a file node loads first, `sh -c`'s text, and a script sourced. And a project with only a lower-case
# gnumakefile, which make reads first on a disk that doesn't tell case apart. Then output sent to a log the server
# writes, which isn't what it runs.
put("shared/package.json", {"scripts": {"build": "tsc"}})
put("shared/common.mk", "PREFIX := ~/bin\n")
put("outside-project/linked/README.md", "Notes\n")
os.symlink(os.path.join(T, "shared/package.json"), os.path.join(T, "outside-project/package.json"))
os.symlink(os.path.join(T, "shared/common.mk"), os.path.join(T, "outside-project/linked/Makefile"))
put("outside-project/Makefile", "include ../shared/common.mk\ninstall:\n\tcp tool $(PREFIX)/\n")
os.makedirs(os.path.join(T, "check-project/bin"), exist_ok=True)
with open(os.path.join(T, "check-project/bin/server"), "wb") as f:
    f.write(b"#!/bin/sh\n# caf\xe9\nexec node server.js\n")
put("check-project/hook.js", "process.env.READY = '1'\n")
# A project whose web folder has its own package.json, which is what runs after `cd web`, from a command, a Makefile
# recipe or a script; and ways of cd the check can't follow (a variable, back out of the checkout, `-`).
put("cd-project/package.json", {"scripts": {"dev": "vite"}})
put("cd-project/web/package.json", {"scripts": {"dev": "next dev"}})
put("cd-project/Makefile", "web:\n\tcd web && npm run dev\n")
put("cd-project/scripts/web.sh", "#!/bin/sh\ncd web\nnpm run dev\n")
put("check-project/server.log", "listening\n")
# A cd inside ( ), undone at the ), and one in a sourced script, which moves the line that sourced it: neither is
# followed, and the card says so. A folder with no package.json of its own (docs), where npm reads the one above it; a
# script that isn't in the package.json found; and a project whose only package.json is above the checkout.
put("cd-project/docs/README.md", "Notes\n")
put("cd-project/scripts/env.sh", "#!/bin/sh\ncd web\n")
put("above/package.json", {"scripts": {"dev": "vite"}})
put("above/inner-project/README.md", "Notes\n")
# What package runners read besides package.json: a yarn named by .yarnrc.yml, one named outside the checkout and one
# that isn't there; an .npmrc that sets node's options; and the lockfile an install reads.
put("yarn-project/package.json", {"scripts": {"dev": "vite"}})
put("yarn-project/.yarnrc.yml", "yarnPath: .yarn/releases/yarn-4.cjs\n")
put("yarn-project/.yarn/releases/yarn-4.cjs", "// yarn 4\n")
put("yarn-away/package.json", {"scripts": {"dev": "vite"}})
put("yarn-away/.yarnrc.yml", "yarnPath: ../shared/yarn.cjs\n")
put("shared/yarn.cjs", "// yarn\n")
put("yarn-gone/package.json", {"scripts": {"dev": "vite"}})
put("yarn-gone/.yarnrc.yml", "yarnPath: .yarn/releases/yarn-9.cjs\n")
put("npmrc-project/package.json", {"scripts": {"dev": "vite"}})
put("npmrc-project/.npmrc", "node-options=--require ./hook.js\n")
put("npmrc-project/package-lock.json", {"lockfileVersion": 3})
# yarn's Plug'n'Play loaders, a plugin .yarnrc.yml names and one that isn't there, and the .yarnrc.yml of each folder
# up from the package (a web package in yarn-pnp, with one at the top); bun's settings and the files it preloads, one
# missing; and pnpm's workspace at the top.
put("yarn-pnp/package.json", {"scripts": {"dev": "vite"}})
put("yarn-pnp/.yarnrc.yml", "plugins:\n  - path: .yarn/plugins/tool.cjs\n  - path: .yarn/plugins/gone.cjs\n")
put("yarn-pnp/.yarn/plugins/tool.cjs", "// a plugin\n")
put("yarn-pnp/.pnp.cjs", "// the loader\n")
put("yarn-pnp/.pnp.loader.mjs", "// the loader for ES modules\n")
put("yarn-pnp/web/package.json", {"scripts": {"dev": "next dev"}})
put("yarn-pnp/web/.yarnrc.yml", "enableTelemetry: false\n")
put("bun-project/package.json", {"scripts": {"dev": "bun run server.ts"}})
put("bun-project/bunfig.toml", 'preload = ["./setup.ts", "./gone.ts"]\n')
put("bun-project/setup.ts", "console.log('ready')\n")
put("bun-project/server.ts", "Bun.serve({ port: Number(process.env.PORT), fetch: () => new Response('ok') })\n")
put("pnpm-project/package.json", {"scripts": {"dev": "vite"}})
put("pnpm-project/pnpm-workspace.yaml", "packages:\n  - 'apps/*'\n")
put("case-project/gnumakefile", "all:\n\t@echo the lower-case one\n")
put("case-project/Makefile", "all:\n\t@echo not this one\n")

# Claude Code's state file, which says which folders you've trusted Claude in (among much else, here a sample of it),
# laid out as Claude Code writes it: two-space indents, no new line at the end, readable only by you.
for name in ("trust/lone", "trust/parent/child", "fresh", "repo/sub"):
    os.makedirs(os.path.join(T, name), exist_ok=True)
put(".claude.json", json.dumps({"numStartups": 3, "oauthAccount": {"emailAddress": "sample@example.com"},
                                "projects": {repo: {"allowedTools": [], "hasTrustDialogAccepted": True},
                                             os.path.join(T, "trust/parent"): {"hasTrustDialogAccepted": True},
                                             os.path.join(T, "trust/lone"): {"allowedTools": ["Bash(ls)"],
                                                                              "hasTrustDialogAccepted": False}}},
                               indent=2))
os.chmod(os.path.join(T, ".claude.json"), 0o600)
PY

# The rows, ordered by session, with what changes from run to run made stable: times become "now-<minutes>m",
# process ids "pid" (and in a messaging address), the sample home "T", and very long text a note of its length.
rows() {
HOME="$T" "$APP" --print-rows | python3 -c '
import json, re, sys, time
from datetime import datetime
now = time.time()
def stable(value, key=""):
    if isinstance(value, dict):
        return {k: stable(v, k) for k, v in value.items()}
    if isinstance(value, list):
        return [stable(v) for v in value]
    if key == "pid" and isinstance(value, int) and value > 0:
        return "pid"
    if key == "stageAt" and isinstance(value, (int, float)) and 0 < value < 1e11:  # the page takes ms, never seconds
        return "in seconds"
    if key == "promptFromAddress" and isinstance(value, str):  # the address names a sample process
        return re.sub(r"/\d+\.sock$", "/pid.sock", value)
    if key == "v" and isinstance(value, int):  # how many times the changes were counted, which depends on timing
        return "v"
    if key == "headAt" and isinstance(value, int):  # when a sample was committed, however long the tests took since
        return "headAt"
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        for scale in (1000, 1):  # ms or s since 1970
            if 1.5e9 < value / scale < 2.5e9:
                ago = round((now - value / scale) / 60)
                return "now-%dm" % ago if ago >= 0 else "now+%dm" % -ago  # one to come: a request going by itself
    if isinstance(value, str) and re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d+)?Z", value):
        return "now-%dm" % round((now - datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()) / 60)
    if isinstance(value, str) and len(value) > 200:
        return "<%d characters, ending %r>" % (len(value), value[-12:])
    return value
rows = sorted(json.load(sys.stdin), key=lambda row: str(row.get("sessionId")))
print(json.dumps(stable(rows), indent=2, sort_keys=True, ensure_ascii=False))
print("the usage check listed as a row:", any(row.get("sessionId") == "s-usage-check" for row in rows))
'
echo "requests left in asks: $(ls "$T/Library/Application Support/Whozmove/asks" | sort | tr '\n' ' ')"
echo "== What's kept of each running terminal session so its row stays once it ends (with a stand-in for its terminal),"
echo "   and which of those kept are dropped: their process went on to another conversation (left), or they've gone"
echo "   (stale)"
HOME="$T" "$APP" --print-kept | in_minutes | sed -E 's/"pid": [0-9]+/"pid": "pid"/'
echo "files kept in the sample home after the runs: $(ls "$T/Library/Application Support/Whozmove/conversations" \
  | sort | tr '\n' ' ')"
echo "== Fields Row sends that docs/reference/rows.md doesn't describe, or describes but Row doesn't send"
python3 - "$REPO" <<'PY'
import os, re, sys
repo = sys.argv[1]
# Whichever file implements Row now: there must be just the one.
rows = sorted(os.path.join(d, name) for top in ("app", "parts", "modules") for d, _, files in os.walk(f"{repo}/{top}")
              for name in files if name.endswith(".m")
              and re.search(r"^@implementation Row\b", open(os.path.join(d, name), encoding="utf-8").read(), re.M))
if len(rows) != 1:
    sys.exit("Row is implemented in %d files, not one" % len(rows))
sent = set(re.findall(r'json\[@"(\w+)"\]', open(rows[0]).read()))
described = set()
for line in open(f"{repo}/docs/reference/rows.md"):
    if line.startswith("| `"):
        described |= set(re.findall(r"`(\w+)`", line.split("|")[1]))
for name in sorted(sent - described): print("not described:", name)
for name in sorted(described - sent): print("described, not sent:", name)
PY
echo "== macOS permissions the app asks for that README.md doesn't name, and repo files naming one it doesn't ask for"
python3 - "$REPO" <<'PY'
import os, subprocess, sys
repo = sys.argv[1]
def read(path):
    return open(f"{repo}/{path}", encoding="utf-8").read()
code = "".join(open(os.path.join(d, name), encoding="utf-8").read()
               for top in ("app", "parts", "modules") for d, _, files in sorted(os.walk(f"{repo}/{top}"))
               for name in sorted(files) if name.endswith(".m"))
# Each permission by the name macOS gives it, and the call that shows the app asks for it. The README must tell
# people about each one the app asks for; once it stops asking for one, every mention of it has to go too.
asks = {"Accessibility": "AXIsProcessTrusted" in code, "Automation": "NSAppleScript" in code,
        "Full Disk Access": "Privacy_AllFiles" in code}
tracked = subprocess.run(["git", "-C", repo, "ls-files", "-z"], capture_output=True, text=True).stdout.split("\0")
for permission, asked in asks.items():
    if asked:
        if permission not in read("README.md"):
            print("README.md doesn't name", permission)
        continue
    for path in tracked:
        if path in ("", "LICENSE", "tests/rows.sh", "tests/rows.expected.txt"):
            continue
        try:
            if permission in read(path):
                print(path, "still names", permission)
        except (OSError, UnicodeDecodeError):
            pass  # an image or the icon
# macOS shows this text when it asks for Automation, so it's there exactly while the app sends Apple Events.
if ("NSAppleEventsUsageDescription" in read("app/Info.plist")) != asks["Automation"]:
    print("app/Info.plist's NSAppleEventsUsageDescription doesn't match whether the app sends Apple Events")
PY
echo "== Each terminal session: why keys can't go into it now (null: they can), and the Shift+Tabs its mode menu"
echo "   would type (null: not offered)"
HOME="$T" "$APP" --print-mode-moves
echo "== The keys a slash command is typed with, and where typing stops when the session moves on"
HOME="$T" "$APP" --print-typing
echo "== Why nothing can go into a session now, as its model, effort and mode menus, its Compact card and its next"
echo "   steps say it (null: something can), with a terminal the panel types into unless said otherwise"
HOME="$T" "$APP" --print-why-not
echo "== Whether now is a natural break to compact a session, and why (null: not now): the context ring's Compact now"
echo "   and Compact at Breaks both go by it"
HOME="$T" "$APP" --print-compact-time
echo "== Which sessions' requests are held as you answer them: in their tab just now with you at the Mac, whether"
echo "   they go by themselves (Don't Wait on Me) or wait on you"
HOME="$T" "$APP" --print-held
echo "== Whether a terminal's window is on top, so a press on the row of the session its tab shows leaves it be"
echo "   (otherwise its tab is shown, which brings its window up)"
HOME="$T" "$APP" --print-on-top
echo "== A file read every second is read again only once it has changed (its size, or only its date), and never kept"
echo "   while it can't be read or once it's gone"
HOME="$T" "$APP" --print-file-reads
echo "== From a home that isn't your own, Whozmove presses, types and sends nothing in other apps, whichever way it"
echo "   would, and panel.log says so once"
HOME="$T/other-apps" "$APP" --print-other-apps
echo "== A command's result as read from a transcript (null: none yet), and what it says: the value now in effect"
echo "   (null: nothing changed), whether the pick was saved as the default, the Compact card's note (null: it"
echo "   compacted), and whether a reload of the plugins took"
HOME="$T" "$APP" --print-results "/model claude-opus-5-5" "$T/results/model-set.jsonl" \
  "/model claude-opus-5-5" "$T/results/model-kept.jsonl" \
  "/model claude-haiku-5-5" "$T/results/model-no-result-yet.jsonl" \
  "/effort max" "$T/results/effort-capped.jsonl" "/effort high" "$T/results/effort-set.jsonl" \
  "/plan" "$T/results/plan.jsonl" "/compact keep the tests" "$T/results/compact-done.jsonl" \
  "/compact" "$T/results/compact-refused.jsonl" "/compact" "$T/results/compact-no-result.jsonl" \
  "/reload-plugins" "$T/results/reload-done.jsonl" "/reload-plugins" "$T/results/reload-held.jsonl"
echo "== Each session: why its next steps and its Deploy wait now (null: they don't), for its own agent or another"
echo "   at work in the same checkout"
HOME="$T" "$APP" --print-waits
echo "== The changes view of the clone, as git shows it: Changes (what git diff shows, then the files git doesn't track"
echo "   yet), Staged (git diff --cached; d.txt, staged and then changed again, is in both), from either session's side"
HOME="$T" "$APP" --print-changes s-topic unstaged | sed -E 's/"v" : [0-9]+/"v" : "v"/'
HOME="$T" "$APP" --print-changes s-clone staged | sed -E 's/"v" : [0-9]+/"v" : "v"/'
echo "== Outgoing, from s-topic's side: the clone's commits not on its upstream yet, one by one, each with what it changed"
HOME="$T" "$APP" --print-changes s-topic outgoing \
  | sed -E 's/"v" : [0-9]+/"v" : "v"/; s/"(hash|short)" : "[0-9a-f]+"/"\1" : "id"/; s/"at" : [0-9.e+]+/"at" : "at"/'
echo "== Deploy in sample projects: the command Whozmove suggests (null: no Deploy), the folder's last run as the page"
echo "   is told it, and the build in place a run that went through makes (outside git, and from before commits were"
echo "   noted: without one)"
# Their times count from when the runs were written, however long the tests above took.
HOME="$T" "$APP" --print-deploys "$T"/projects/* | in_minutes "$(cat "$T/written-at")"
echo "== What the set-up card is told a command really runs (all of it, with the files checked before every run, what"
echo "   isn't checked and what Whozmove can't follow), and whether that looks as if it could reach production"
HOME="$T" "$APP" --print-deploy-checks "$T/check-project" "make install" "make deploy-local" "make" \
  "npm run deploy:local" "pnpm deploy:local" "yarn run install:local" "NODE_ENV=dev npm run ship && make install" \
  "docker compose up -d --build" "kubectl apply -f k8s/" "./build.sh --now" "npm run nothing-here" "npm start" \
  "bun serve" "yarn workspace web run build" "npm --prefix web run build" "make -C sub install" "./scripts/up.sh" \
  "node server.js" "sh scripts/up.sh" | in_minutes
HOME="$T" "$APP" --print-deploy-checks "$T/gnu-project" "make" | in_minutes
HOME="$T" "$APP" --print-deploy-checks "$T/fifo-project" "npm run build" | in_minutes
HOME="$T" "$APP" --print-deploy-checks "$T/outside-project" "npm run build" "make install" "make -f linked/Makefile" \
  | in_minutes
HOME="$T" "$APP" --print-deploy-checks "$T/check-project" "./bin/server" "npm --loglevel silent run build" \
  "npm --loglevel silent start" "node -r ./hook.js server.js" "node -r dotenv/config server.js" \
  "sh -c 'npm run build && make install'" "source scripts/up.sh" ". scripts/up.sh" | in_minutes
HOME="$T" "$APP" --print-deploy-checks "$T/case-project" "make" | in_minutes
HOME="$T" "$APP" --print-deploy-checks "$T/cd-project" "cd web && npm run dev" "pushd web; npm run dev; popd; npm run dev" \
  "make web" "./scripts/web.sh" 'cd $APP_DIR && npm run dev' "cd .. && npm run dev" "cd - && npm run dev" \
  "(cd web && npm ci) && npm run dev" "source scripts/env.sh && npm run dev" "cd docs && npm run dev" \
  "cd web && npm run build" | in_minutes
HOME="$T" "$APP" --print-deploy-checks "$T/above/inner-project" "npm run dev" | in_minutes
HOME="$T" "$APP" --print-deploy-checks "$T/yarn-project" "yarn dev" | in_minutes
HOME="$T" "$APP" --print-deploy-checks "$T/yarn-away" "yarn dev" | in_minutes
HOME="$T" "$APP" --print-deploy-checks "$T/yarn-gone" "yarn dev" | in_minutes
HOME="$T" "$APP" --print-deploy-checks "$T/npmrc-project" "npm run dev" "npm ci" | in_minutes
HOME="$T" "$APP" --print-deploy-checks "$T/yarn-pnp" "yarn dev" "cd web && yarn dev" | in_minutes
HOME="$T" "$APP" --print-deploy-checks "$T/bun-project" "bun dev" | in_minutes
HOME="$T" "$APP" --print-deploy-checks "$T/pnpm-project" "pnpm dev" | in_minutes
HOME="$T" "$APP" --print-deploy-checks "$T/cd-project" 'case $1 in up) echo up;; esac; (cd web && npm ci) && npm run dev' \
  | in_minutes
HOME="$T" "$APP" --print-deploy-checks "$T/check-project" "node server.js > server.log 2>&1" \
  "node server.js &> server.log" "node server.js >>server.log 2>&1 < /dev/null" | in_minutes
# Whether what's kept for a command in a folder changes when a file it depends on does: before, the file given new
# text (printf's), after.
kept_changes() {
  local before after
  before=$(HOME="$T" "$APP" --print-deploy-checks "$1" "$2")
  # shellcheck disable=SC2059
  printf "$4" > "$3"
  after=$(HOME="$T" "$APP" --print-deploy-checks "$1" "$2")
  python3 -c 'import json, sys; c = sys.argv[1]; a, b = (json.loads(x)[c]["fingerprint"] for x in sys.argv[2:])
print("changed" if a != b else "the same")' "$2" "$before" "$after"
}
echo "== What's kept changes with a file it depends on: a program that isn't UTF-8, in a byte that doesn't decode; the"
echo "   yarn .yarnrc.yml names; an .npmrc's node options; for an install, only the lockfile; yarn's Plug'n'Play loader;"
echo "   and a file bun preloads"
kept_changes "$T/check-project" "./bin/server" "$T/check-project/bin/server" '#!/bin/sh\n# caf\xe8\nexec node server.js\n'
kept_changes "$T/yarn-project" "yarn dev" "$T/yarn-project/.yarn/releases/yarn-4.cjs" '// yarn 4.1\n'
kept_changes "$T/npmrc-project" "npm run dev" "$T/npmrc-project/.npmrc" 'node-options=--require ./other.js\n'
kept_changes "$T/npmrc-project" "npm ci" "$T/npmrc-project/package-lock.json" '{"lockfileVersion": 3, "packages": {}}\n'
kept_changes "$T/yarn-pnp" "yarn dev" "$T/yarn-pnp/.pnp.cjs" '// another loader\n'
kept_changes "$T/bun-project" "bun dev" "$T/bun-project/setup.ts" "console.log('changed')\n"
echo "== What the usage strip gets from Claude Code's recorded answers (null: none there) and from \`claude auth"
echo "   status\`, and where \`claude\` is looked for, best first"
HOME="$T" USAGE_PATH="$T/bin" "$APP" --print-usage "$T"/usage-replies/*
echo "== Whether Claude may work in a folder (the folder, its checkout, its repo or a folder above it is trusted)"
HOME="$T" "$APP" --print-trust "$T/repo" "$T/repo/sub" "$T/repo-wt" "$T/trust/parent/child" "$T/trust/lone" \
  "$T/trust" | in_minutes
echo "== Trusting one from the card: only that project's key changes, and the file keeps its layout and who may read it"
cp "$T/.claude.json" "$T/claude-state-before.json"
HOME="$T" "$APP" --print-trust --trust "$T/trust/lone" "$T/trust/lone" | in_minutes
HOME="$T" "$APP" --print-trust --trust "$T/trust" "$T/trust" | in_minutes
python3 - "$T" <<'PY'
import json, os, sys
T = sys.argv[1]
before = json.load(open(f"{T}/claude-state-before.json"))
text = open(f"{T}/.claude.json").read()
after = json.loads(text)
for key in sorted(set(before) | set(after)):
    if key != "projects" and before.get(key) != after.get(key): print("changed:", key)
for folder in sorted(set(before["projects"]) | set(after["projects"])):
    if before["projects"].get(folder) != after["projects"].get(folder):
        print("project", folder, "->", json.dumps(after["projects"].get(folder), sort_keys=True))
print("two-space indents:", text.split("\n")[1].startswith('  "'), "| no new line at the end:", not text.endswith("\n"),
      "| readable only by you:", oct(os.stat(f"{T}/.claude.json").st_mode & 0o777),
      "| lock left behind:", os.path.exists(f"{T}/.claude.json.lock"))
PY
echo "== …waiting while Claude Code holds its lock (and giving up after 5s), and clearing one a writer left behind"
mkdir "$T/.claude.json.lock"
HOME="$T" "$APP" --print-trust --trust "$T/fresh" "$T/fresh" | in_minutes
echo "the lock is still theirs: $([ -d "$T/.claude.json.lock" ] && echo yes || echo no)"
touch -t 202601010000 "$T/.claude.json.lock"
HOME="$T" "$APP" --print-trust --trust "$T/fresh" "$T/fresh" | in_minutes
echo "the old lock is gone: $([ -d "$T/.claude.json.lock" ] && echo no || echo yes)"
echo "== Why a recording counts as talking to an agent (null: it doesn't), by what was in front as it began"
mkdir -p "$T/talking"
SESSION='"rows": [{"sessionId": "s-voice", "pid": 4242}]'
GHOSTTY='"front": "com.mitchellh.ghostty"'
CLAUDE='{"pid": 4242, "parent": 4200, "path": "/opt/homebrew/bin/claude", "app": "com.mitchellh.ghostty"}'
DICTATION='{"pid": 5000, "parent": 1, "path": "/Applications/Example Dictation.app/Contents/MacOS/Example Dictation",
            "app": "com.example.dictation"}'
CALL='{"pid": 6000, "parent": 1, "path": "/Applications/Example Call.app/Contents/MacOS/Example Call",
       "app": "com.example.call"}'
DESKTOP='{"pid": 7000, "parent": 1, "path": "/Applications/Claude.app/Contents/MacOS/Claude",
          "app": "com.anthropic.claudefordesktop"}'
echo "{\"recording\": $CLAUDE, \"then\": {\"front\": \"com.apple.finder\"}, $SESSION}" > "$T/talking/voice-mode.json"
echo "{\"recording\": $CLAUDE, \"then\": {$GHOSTTY, \"going\": true}, $SESSION}" \
  > "$T/talking/voice-mode-already-going.json"
echo "{\"recording\": {\"pid\": 4300, \"parent\": 4242, \"path\": \"/opt/homebrew/bin/rec\"}, \"then\": {},
       $SESSION}" > "$T/talking/voice-mode-through-sox.json"
echo "{\"recording\": {\"pid\": 4301, \"parent\": 4242, \"path\": \"/opt/homebrew/bin/ffmpeg\"}, \"then\": {},
       $SESSION}" > "$T/talking/a-command-the-session-runs.json"
echo "{\"recording\": $DESKTOP, \"then\": {\"front\": \"com.apple.Safari\"}, $SESSION}" \
  > "$T/talking/claude-dictation.json"
echo "{\"recording\": $DICTATION, \"then\": {$GHOSTTY, \"tab\": \"s-voice\"}, $SESSION}" \
  > "$T/talking/dictation-into-a-session-tab.json"
echo "{\"recording\": $DICTATION, \"then\": {$GHOSTTY, \"tab\": \"\"}, $SESSION}" \
  > "$T/talking/dictation-into-a-plain-shell.json"
echo "{\"recording\": $DICTATION, \"then\": {\"front\": \"com.anthropic.claudefordesktop\"}, $SESSION}" \
  > "$T/talking/dictation-into-claude.json"
echo "{\"recording\": $DICTATION, \"then\": {\"front\": \"com.apple.finder\", \"keyboard\": true}, $SESSION}" \
  > "$T/talking/dictation-into-the-panel.json"
echo "{\"recording\": $DICTATION, \"then\": {\"front\": \"com.apple.Notes\"}, $SESSION}" \
  > "$T/talking/dictation-elsewhere.json"
echo "{\"recording\": $CALL, \"then\": {$GHOSTTY, \"tab\": \"s-voice\", \"going\": true}, $SESSION}" \
  > "$T/talking/a-call-going-on.json"
echo "{\"recording\": $CALL, \"then\": {$GHOSTTY, \"tab\": \"s-voice\"}, $SESSION}" \
  > "$T/talking/a-call-started-on-a-session.json"
HOME="$T" "$APP" --print-talking "$T"/talking/*.json
echo "== Each lead's next for you, and its queue of picks by id, in its order (the second lead's of 105 picks as how many"
echo "   it keeps and its first and last). Left out of the first queue: an id that isn't plain, and one named twice"
team="$T/Library/Application Support/Whozmove/team/team.json"
cp "$team" "$T/team-before-queue.json"
python3 - "$team" <<'Q'
import json, sys
with open(sys.argv[1]) as f:
    team = json.load(f)
projects = list(team["projects"].values())
lead = next(p for p in projects if p["lead"]["name"] == "Atlas")["lead"]
lead["queue"] = [{"id": "j1-try", "job": "j1", "short": "Try the search box"}, {"id": "covers", "job": "j4"},
                 {"id": "a cover"}, {"id": "j1-try", "job": "j2"}, {"id": "no-job"}, {"id": "spine", "job": "j99"}]
low = next(p for p in projects if p["lead"]["name"] == "k-next-low")["lead"]
low["queue"] = [{"id": "p%d" % n, "job": "j99"} for n in range(1, 106)]
with open(sys.argv[1], "w") as f:
    json.dump(team, f)
Q
HOME="$T" "$APP" --print-rows | python3 -c '
import json, sys
for row in sorted(json.load(sys.stdin), key=lambda row: str(row.get("sessionId"))):
    team = row.get("team") or {}
    if team.get("role") != "lead":
        continue
    queue = team.get("queue")
    if queue and len(queue) > 10:
        queue = {"kept": len(queue), "first": queue[0], "last": queue[-1]}
    print(row["sessionId"], json.dumps({"next": team.get("next"), "queue": queue}, sort_keys=True))
'
echo "== Each team as a whole, as the team board gets it (with that file): its lead, its goals (an id with a space, one"
echo "   named twice and one without a name left out, and How we work marked as a heading for how the team works), its"
echo "   queue, and every job but the dropped one, each with its goal when the team has it, whose it is and that session,"
echo "   what it holds up, and its steps with the kinds of those that wait on you (one on a step that doesn't, and a word"
echo "   One Task doesn't know, left out); a done one with when it was done; and the job each member's row speaks for"
echo "   marked now"
# Times are counted from when the sample was written, as the deploys' are, so a slow run never crosses a minute.
HOME="$T" "$APP" --print-teams | python3 -c '
import json, sys
now = float(sys.argv[1])
def stable(value):
    if isinstance(value, dict):
        return {k: stable(v) for k, v in value.items()}
    if isinstance(value, list):
        return [stable(v) for v in value]
    if isinstance(value, (int, float)) and not isinstance(value, bool) and 1.5e12 < value < 2.5e12:
        return "now-%dm" % round((now - value / 1000) / 60)
    return value
teams = json.load(sys.stdin)
for team in teams:
    if len(team["queue"]) > 10:
        team["queue"] = "%d picks" % len(team["queue"])
print(json.dumps(stable(teams), indent=2, sort_keys=True, ensure_ascii=False))
' "$(cat "$T/written-at")"
echo "== Team Board's card on the panel's back, for the same team, and whether its figures are the board's own counts"
HOME="$T" "$APP" --print-teams > "$T/teams.json"
HOME="$T" "$APP" --print-board-card "$T/repo" | tee "$T/card.json"
cat > "$T/card-check.js" <<CHECK
load('tests/page-harness.js');
const card = JSON.parse(read('$T/card.json'));
const c = boardCounts(boardTeam({ teams: JSON.parse(read('$T/teams.json')) }, '$T/repo').jobs, NOW);
print('its figures are the board\'s counts: ' + (card.figure === (c.moving ? String(c.moving) : 'Nothing')
  && card.lines[0] === (c.you ? \`\${c.you} \${c.you === 1 ? 'needs' : 'need'} you\` : 'Nothing needs you')));
CHECK
page_cases "$T/card-check.js"
echo "== A team file reads the same whatever its version: 5, 1 or none"
HOME="$T" "$APP" --print-teams > "$T/teams-as-written.json"
for version in 5 none; do
  python3 - "$team" "$version" <<'Q'
import json, sys
with open(sys.argv[1]) as f:
    team = json.load(f)
if sys.argv[2] == "none":
    team.pop("version", None)
else:
    team["version"] = int(sys.argv[2])
with open(sys.argv[1], "w") as f:
    json.dump(team, f)
Q
  HOME="$T" "$APP" --print-teams > "$T/teams-version.json"
  cmp -s "$T/teams-as-written.json" "$T/teams-version.json" && echo "version $version: the same" || echo "version $version: differs"
done
echo "== With Show Teams off, the file isn't read: no teams, no row has a team, and Group by Team isn't offered"
HOME="$T" "$APP" --print-teams --switch-off
mv "$T/team-before-queue.json" "$team"
echo "== A member is its workspace: whoever runs in a member's own folder holds its seat. Pim's conversation, cleared, is"
echo "   Pim; s-twice, in Bea's folder while Bea's recorded session runs elsewhere, is Bea; s-clone, beside Moss's own"
echo "   session, is a duplicate of Moss; Ivy's own session in Pim's folder stays Ivy's; and the lead's sessions it leads,"
echo "   and what's next for you, name the sessions holding the seats (its next made Pim's job here). With nothing running"
echo "   in Tam's folder and the file's id for Tam naming no session listed, Tam's conversation that moved last, ended,"
echo "   is Tam, the older one only in Tam's folder; the lead leads it, a pick by Tam's name reaches it, and Take Me There"
echo "   carries it on"
python3 - "$team" "$T" <<'Q'
import json, os, sys, time
T = sys.argv[2]
with open(sys.argv[1]) as f:
    team = json.load(f)
atlas = next(p for p in team["projects"].values() if p["lead"]["name"] == "Atlas")
atlas["jobs"]["j11"] = {"title": "Chimes", "stage": "build", "member": "Pim"}
atlas["lead"]["next"]["job"] = "j11"
tam = os.path.join(T, "tam")
os.makedirs(tam, exist_ok=True)
atlas["members"]["Tam"] = {"session": "k-tam-was", "worktree": tam, "part": "storage"}
atlas["jobs"]["j12"] = {"title": "Old files", "stage": "build", "member": "Tam"}
with open(sys.argv[1], "w") as f:
    json.dump(team, f)
# Tam's two conversations, ended (Whozmove kept them as their tabs closed): the later one, and one before it, whose id
# comes first, so only when each last moved can tell them apart.
kept = os.path.join(T, "Library/Application Support/Whozmove/conversations")
with open(os.path.join(T, "written-at")) as f:
    at = float(f.read())
for sid, minutes_ago in (("k-tam-later", 3), ("k-tam-earlier", 50)):
    transcript = os.path.join(T, ".claude/projects/p", sid + ".jsonl")
    with open(transcript, "w") as f:
        f.write(json.dumps({"type": "user", "message": {"role": "user", "content": "tidy the old files"},
                            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(at - minutes_ago * 60)),
                            "isSidechain": False}) + "\n")
    with open(os.path.join(kept, sid + ".json"), "w") as f:
        json.dump({"sessionId": sid, "cwd": tam, "terminal": "com.apple.Terminal", "pid": 4242,
                   "procStart": "start-" + sid, "transcript": transcript,
                   "activeAt": int((at - minutes_ago * 60) * 1000), "name": "the %s one" % sid}, f)
Q
HOME="$T" "$APP" --print-rows | tee "$T/seat-rows.json" | python3 -c '
import json, sys
rows = {row["sessionId"]: row for row in json.load(sys.stdin)}
for sid in ("s-pim", "s-ivy", "s-twice", "s-desk", "s-clone", "s-topic", "k-tam-later", "k-tam-earlier"):
    team = rows[sid].get("team") or {}
    print(sid, rows[sid].get("status"),
          json.dumps({k: team[k] for k in ("role", "name", "inFolderOf", "duplicate", "earlier", "seat") if k in team},
                     sort_keys=True))
lead = rows["s-near"]["team"]
print("the lead leads", lead["leads"], "and what is next is for", lead["next"].get("for"))
# One Task takes a pick by a member'"'"'s name for one of the sessions the lead leads whose own row places it on the team
# (role, and no inFolderOf), named so: Tam'"'"'s is the ended conversation on its row.
print("a pick for Tam by name reaches", [sid for sid in lead["leads"] if rows.get(sid, {}).get("team", {}).get("role")
      and not rows[sid]["team"].get("inFolderOf") and rows[sid]["team"].get("name") == "Tam"])
'
HOME="$T" "$APP" --print-teams > "$T/seat-teams.json"
cat > "$T/seat-check.js" <<CHECK
load('tests/page-harness.js');
const team = boardTeam({ teams: JSON.parse(read('$T/seat-teams.json')) }, '$T/repo');
const sessions = JSON.parse(read('$T/seat-rows.json'));
print('Take Me There on Tam\'s job: ' + JSON.stringify(boardTakeMe(team.jobs.find((j) => j.id === 'j12'), team,
                                                                     sessions)));
CHECK
page_cases "$T/seat-check.js"
echo "== Without the team file: no row has a place in a team, nor a mark"
rm "$team"
HOME="$T" "$APP" --print-rows | python3 -c '
import json, sys
print("rows with a place:", [row["sessionId"] for row in json.load(sys.stdin) if "team" in row])
'
}

# The sample home is under /private/var; macOS also gives paths there as /var, so both spellings become T.
out=$(rows 2>&1 | sed -e "s|$T|T|g" -e "s|${T#/private}|T|g")
. "$REPO/tests/compare.sh"
compare Rows "$REPO/tests/rows.expected.txt" "$out" "${1:-}"
