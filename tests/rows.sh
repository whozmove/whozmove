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
# (`--print-deploys`), what the set-up card is told sample commands really run (`--print-deploy-checks`), and what
# the usage strip gets from Claude Code's recorded answers and where `claude` is looked for (`--print-usage`), what
# a new conversation's start runs (`--print-starts`), and how folder trust is read and recorded (`--print-trust`).
# Needs clang, git and python3. Takes a few seconds, most of it compiling the app.
cd "$(dirname "$0")/.." || exit 1
REPO=$PWD
# git here, the sample repo's and the app's own, ignores your personal git settings (signing, hooks, …).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
# Stops here if there's no temporary folder: an empty T would make the clean-up below delete this checkout.
T=$(mktemp -d "${TMPDIR:-/tmp}/whozmove-rows.XXXXXX") || exit 1
T=$(cd "$T" && pwd -P) || exit 1
# Stand-in session processes are started detached, their pids kept in $T/pids so they're stopped however this ends.
trap 'kill $(cat "$T/pids" 2>/dev/null) 2>/dev/null; rm -rf "$T"' EXIT
detached() { local pid; pid=$("$@" >/dev/null 2>&1 & echo $!); echo $pid >> "$T/pids"; echo $pid; }
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
# And how its changes split for the island's gauge: one file staged, one staged and then changed again, one not staged.
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
# Checkouts with an extra stage (docs/reference/stages.md), each named by its own git config: one you've allowed, one not
# answered yet (its row asks), one answered Not Now, and one whose command prints something that isn't the stage's.
STAGE='{"label":"to review","count":3,"edits":1,"editFiles":["a.txt"],"header":"3 to review","items":["1  First"],'\
'"actions":[{"title":"Send","run":"true"}]}'
STAGE_COMMAND="printf '%s' '$STAGE'"
for name in allowed asks later junk; do
  git -C "$T" init -q -b main "$name"
  echo one > "$T/$name/a.txt"
  git -C "$T/$name" add a.txt
  git -C "$T/$name" -c user.email=t@t -c user.name=t commit -q -m init
  git -C "$T/$name" config whozmove.stage "$STAGE_COMMAND"
done
git -C "$T/junk" config whozmove.stage "echo not json"
echo two >> "$T/allowed/a.txt"

# Live sessions (stand-in processes), and one whose process has ended: a pid above the highest macOS hands
# out (99999), so no process can ever have it.
TERM_PID=$(detached sleep 600); WT_PID=$(detached sleep 600); DESK_PID=$(detached sleep 600)
MODE_PIDS=$(for _ in 1 2 3 4 5 6; do detached sleep 600; done | paste -sd , -)
TOPIC_PID=$(detached sleep 600); CLONE_PID=$(detached sleep 600)
STAGE_PIDS=$(for _ in allowed asks later junk; do detached sleep 600; done | paste -sd , -)
RUN_PID=$(detached sleep 600)  # a deploy still running
GONE_PID=999999

# The usage check's own session (modules/claude-code/app/ClaudeUsage.m): registered while it runs, in the folder kept
# for it. Never a row.
USAGE_PID=$(detached sleep 600)
mkdir -p "$T/.claude/sessions" "$T/Library/Application Support/Whozmove/usage"
printf '{"pid": %d, "sessionId": "s-usage-check", "cwd": "%s", "status": "idle", "entrypoint": "sdk-cli",
         "kind": "interactive"}\n' "$USAGE_PID" "$T/Library/Application Support/Whozmove/usage" \
  > "$T/.claude/sessions/$USAGE_PID.json"
# What Claude Code answers the usage check with, among lines that aren't the answer (one for another request): reset
# times with and without fractions of a second, an error, and signed out; and `claude auth status`, signed in and
# out. And `claude` on a PATH and in two of Claude Desktop's copies, where 2.1.10 is the newer.
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
python3 - "$T" "$TERM_PID" "$WT_PID" "$DESK_PID" "$GONE_PID" "$MODE_PIDS" "$TOPIC_PID" "$STAGE_PIDS" \
  "$STAGE_COMMAND" "$RUN_PID" "$CLONE_PID" <<'PY'
import json, os, sys, time
from datetime import datetime, timezone
T, term_pid, wt_pid, desk_pid, gone_pid = sys.argv[1], *map(int, sys.argv[2:6])
mode_pids = [int(pid) for pid in sys.argv[6].split(",")]
topic_pid = int(sys.argv[7])
stage_pids = [int(pid) for pid in sys.argv[8].split(",")]
stage_command = sys.argv[9]
run_pid = int(sys.argv[10])
clone_pid = int(sys.argv[11])
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
put(f".claude/sessions/{gone_pid}.json", {"pid": gone_pid, "sessionId": "s-gone", "cwd": repo, "status": "idle",
                                   "statusUpdatedAt": ms(60), "entrypoint": "cli", "kind": "interactive"})
# A session on a branch of its own in a clone of the repo (so GitHub's copy is the repo), which committed work there
# and is working on more: keys can't go in, but the one Backspace a request may press while Claude works can.
put(f".claude/sessions/{topic_pid}.json", {"pid": topic_pid, "sessionId": "s-topic", "cwd": os.path.join(T, "clone"),
                                    "status": "busy", "statusUpdatedAt": ms(15), "entrypoint": "cli",
                                    "kind": "interactive", "procStart": "start-topic"})
put(f"Library/Application Support/Whozmove/sessions/s-topic.json", {"outcome": "Committed", "outcomeAt": ms(15)})
# And another session in that clone, idle: its island's steps and Deploy wait for the agent at work there.
put(f".claude/sessions/{clone_pid}.json", {"pid": clone_pid, "sessionId": "s-clone", "cwd": os.path.join(T, "clone"),
                                    "status": "idle", "statusUpdatedAt": ms(20), "entrypoint": "cli",
                                    "kind": "interactive", "name": "review notes", "procStart": "start-clone"})
# A session in each checkout with an extra stage, and your answers about them (Whozmove's own stages.json): the
# command allowed in one, Not Now in another, the junk one allowed; the asking one has none yet.
for number, name in enumerate(["allowed", "asks", "later", "junk"]):
    put(f".claude/sessions/{stage_pids[number]}.json", {"pid": stage_pids[number], "sessionId": f"x-{name}",
                                                       "cwd": os.path.join(T, name), "status": "idle",
                                                       "statusUpdatedAt": ms(40), "entrypoint": "cli",
                                                       "kind": "interactive", "procStart": f"start-stage-{number}"})
put("Library/Application Support/Whozmove/stages.json", {"projects": {
    os.path.join(T, "allowed"): {"command": stage_command, "allowedAt": ms(30)},
    os.path.join(T, "later"): {"command": stage_command, "notNowAt": ms(30)},
    os.path.join(T, "junk"): {"command": "echo not json", "allowedAt": ms(30)}}})
put(".claude/sessions/broken.json", "not json")
put(".claude/sessions/notes.txt", "not a session")

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

# Transcripts. s-term: a prompt in acceptEdits, a reply with its usage, a PR it made, and a sub-agent's reply
# that must not count. s-wt: a prompt in plan mode (its only record of its mode), a reply, then a compaction
# that leaves the context smaller.
put(".claude/projects/p/s-term.jsonl", [
    {"type": "user", "message": {"role": "user", "content": "please fix the tests"}, "timestamp": iso(10),
     "permissionMode": "acceptEdits", "isSidechain": False},
    {"type": "assistant", "message": {"model": "claude-opus-5-5", "content": [{"type": "text", "text": "Done."}],
     "usage": {"input_tokens": 1200, "cache_creation_input_tokens": 3000, "cache_read_input_tokens": 420000,
               "output_tokens": 800}}, "timestamp": iso(9), "isSidechain": False},
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
     "timestamp": iso(7), "isSidechain": True},
])
put(".claude/projects/p/s-wt.jsonl", [
    {"type": "user", "message": {"role": "user", "content": "run the suite"}, "timestamp": iso(4),
     "permissionMode": "plan", "isSidechain": False},
    {"type": "assistant", "message": {"model": "claude-opus-5-5", "content": [{"type": "text", "text": "Testing."}],
     "usage": {"input_tokens": 100, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 300000}},
     "timestamp": iso(3), "isSidechain": False},
    {"type": "system", "subtype": "compact_boundary", "compactMetadata": {"postTokens": 52000}, "timestamp": iso(2)},
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

# What the hook recorded.
put(f"{app}/sessions/s-term.json", {"lastPrompt": "please fix the tests", "lastPromptAt": ms(10),
                                    "lastReply": "All done: the tests pass.", "lastReplyAt": ms(9), "notice": None,
                                    "permissionMode": "acceptEdits", "stageAt": ms(9),
                                    "activity": None, "activityAt": ms(9), "outcome": "Tested", "outcomeAt": ms(9),
                                    "turnReached": [], "workSteps": ["Tested"],
                                    "audit": {"found": 3, "left": 1, "settled": True, "at": ms(9)}})
put(f"{app}/sessions/s-wt.json", {"lastPrompt": "run the suite", "lastPromptAt": ms(2), "stageAt": ms(1),
                                  "activity": "Run the tests", "activityAt": ms(1), "workRoot": repo})
# Claude Desktop's own record of a conversation (below) goes on its row before the hook's, and where both say when it
# last did something, the later time stands: the hook's for s-desk, Claude's for s-closed.
put(f"{app}/sessions/s-desk.json", {"activityAt": ms(5)})
put(f"{app}/sessions/s-closed.json", {"activityAt": ms(300)})

# Requests waiting for an OK: the oldest per session shows; one too long to show in full (over ShownLength in
# app/Asks.m) is cut short; one whose hook has gone is cleared away.
put(f"{app}/asks/aaaa1111.json", {"id": "aaaa1111", "sessionId": "s-term", "tool": "Bash",
                                  "input": {"command": "npm test", "description": "Run the tests"},
                                  "cwd": repo, "at": ms(2), "pid": term_pid})
put(f"{app}/asks/dddd4444.json", {"id": "dddd4444", "sessionId": "s-term", "tool": "Bash",
                                  "input": {"command": "npm run lint"}, "cwd": repo, "at": ms(1), "pid": term_pid})
put(f"{app}/asks/bbbb2222.json", {"id": "bbbb2222", "sessionId": "s-wt", "tool": "Write",
                                  "input": {"file_path": os.path.join(wt, "big.txt"), "content": "x" * 100005},
                                  "cwd": wt, "at": ms(1), "pid": wt_pid})
put(f"{app}/asks/cccc3333.json", {"id": "cccc3333", "sessionId": "s-term", "tool": "Bash",
                                  "input": {"command": "ls"}, "cwd": repo, "at": ms(5), "pid": gone_pid})

# Claude Desktop's conversations: the running one (Claude says it ended its turn blocked on you), a closed one
# whose folder has gone, and ones that mustn't show: too old, archived, not a conversation file.
put(f"{desktop}/local_desk.json", {"sessionId": "local_desk", "cliSessionId": "s-desk", "title": "Desk chat",
                                   "cwd": repo, "lastActivityAt": ms(30), "model": "claude-sonnet-5-5",
                                   "effort": "low", "permissionMode": "plan", "isArchived": False,
                                   "postTurnSummary": {"status_category": "blocked"},
                                   "postTurnSummaryFor": "u1", "lastAssistantUuid": "u1"})
put(f"{desktop}/local_closed.json", {"sessionId": "local_closed", "cliSessionId": "s-closed", "title": "Closed chat",
                                     "cwd": os.path.join(T, "gone"), "originCwd": repo, "lastActivityAt": ms(120),
                                     "model": "claude-haiku-5-5"})
put(f"{desktop}/local_old.json", {"sessionId": "local_old", "title": "Old chat", "cwd": repo,
                                  "lastActivityAt": ms(5 * 24 * 60)})
put(f"{desktop}/local_arch.json", {"sessionId": "local_arch", "title": "Archived chat", "cwd": repo,
                                   "lastActivityAt": ms(60), "isArchived": True})
put(f"{desktop}/other.json", {"sessionId": "nope"})

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

# A project for what the set-up card is told a command really runs: package scripts, and Makefile targets with what
# they depend on.
put("check-project/package.json", {"scripts": {"deploy:local": "fly deploy --local-only",
                                               "predeploy:local": "npm run build", "build": "tsc",
                                               "install:local": "node scripts/install.js", "ship": "vercel --prod"}})
put("check-project/Makefile", ".PHONY: install deploy-local publish\n\n"
                              "build: main.c ## Build it\n\tcc -o tool main.c\n\n"
                              "install: build\n\tcp tool ~/bin/\n\ndeploy-local: build publish\n\t./tool --install\n\n"
                              "publish:\n\tgit push origin main\n\nVERSION := 1.0\n")

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
# process ids "pid", the sample home "T", and very long text a note of its length.
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
    if key == "v" and isinstance(value, int):  # how many times the changes were counted, which depends on timing
        return "v"
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        for scale in (1000, 1):  # ms or s since 1970
            if 1.5e9 < value / scale < 2.5e9:
                return "now-%dm" % round((now - value / scale) / 60)
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
echo "== Fields Row sends that docs/reference/rows.md doesn't describe, or describes but Row doesn't send"
python3 - "$REPO" <<'PY'
import os, re, sys
repo = sys.argv[1]
# Whichever file implements Row now: there must be just the one.
rows = sorted(os.path.join(d, name) for top in ("app", "modules") for d, _, files in os.walk(f"{repo}/{top}")
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
               for top in ("app", "modules") for d, _, files in sorted(os.walk(f"{repo}/{top}"))
               for name in sorted(files) if name.endswith(".m"))
# Each permission by the name macOS gives it, and the call that shows the app asks for it. The README must tell
# people about each one the app asks for; once it stops asking for one, every mention of it has to go too.
asks = {"Accessibility": "AXIsProcessTrusted" in code, "Automation": "NSAppleScript" in code}
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
echo "== A command's result as read from a transcript (null: none yet), and what it says: the value now in effect"
echo "   (null: nothing changed), whether the pick was saved as the default, and the Compact card's note (null: it"
echo "   compacted)"
HOME="$T" "$APP" --print-results "/model claude-opus-5-5" "$T/results/model-set.jsonl" \
  "/model claude-opus-5-5" "$T/results/model-kept.jsonl" \
  "/model claude-haiku-5-5" "$T/results/model-no-result-yet.jsonl" \
  "/effort max" "$T/results/effort-capped.jsonl" "/effort high" "$T/results/effort-set.jsonl" \
  "/plan" "$T/results/plan.jsonl" "/compact keep the tests" "$T/results/compact-done.jsonl" \
  "/compact" "$T/results/compact-refused.jsonl" "/compact" "$T/results/compact-no-result.jsonl"
echo "== Each session: why its island's steps and its Deploy wait now (null: they don't), for its own agent or another"
echo "   at work in the same checkout"
HOME="$T" "$APP" --print-waits
echo "== The changes view of two sessions in the clone, of what isn't committed: s-topic's own files, then s-clone's,"
echo "   which aren't known (it ran a shell command Claude Code didn't record), so it gets all sessions', with no line said"
echo "   to be no listed session's;"
echo "   each changed line credited to whoever wrote it (a session or its sub-agent, or unknown), and whether it's staged"
echo "   or committed"
HOME="$T" "$APP" --print-changes s-topic session | sed -E 's/"v" : [0-9]+/"v" : "v"/'
HOME="$T" "$APP" --print-changes s-clone branch | sed -E 's/"v" : [0-9]+/"v" : "v"/'
echo "== The island's commits stage pressed, from s-topic's side: what the clone's commits not on its upstream yet changed,"
echo "   each line credited as the rest are, with the commit it's from"
HOME="$T" "$APP" --print-changes s-topic commits | sed -E 's/"v" : [0-9]+/"v" : "v"/'
echo "== Deploy in sample projects: the command Whozmove suggests (null: no Deploy), and the folder's last run as the"
echo "   page is told it"
# Their times count from when the runs were written, however long the tests above took.
HOME="$T" "$APP" --print-deploys "$T"/projects/* | in_minutes "$(cat "$T/written-at")"
echo "== What the set-up card is told a command really runs, and whether that looks as if it could reach production"
HOME="$T" "$APP" --print-deploy-checks "$T/check-project" "make install" "make deploy-local" "make" \
  "npm run deploy:local" "pnpm deploy:local" "yarn run install:local" "NODE_ENV=dev npm run ship && make install" \
  "docker compose up -d --build" "kubectl apply -f k8s/" "./build.sh --now" "npm run nothing-here" | in_minutes
echo "== What the usage strip gets from Claude Code's recorded answers (null: none there) and from \`claude auth"
echo "   status\`, and where \`claude\` is looked for, best first"
HOME="$T" USAGE_PATH="$T/bin" "$APP" --print-usage "$T"/usage-replies/*
echo "== New conversations: the command a terminal start runs in its tab, and Claude Desktop's link"
HOME="$T" "$APP" --print-starts | in_minutes
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
}

# The sample home is under /private/var; macOS also gives paths there as /var, so both spellings become T.
out=$(rows 2>&1 | sed -e "s|$T|T|g" -e "s|${T#/private}|T|g")
. "$REPO/tests/compare.sh"
compare Rows "$REPO/tests/rows.expected.txt" "$out" "${1:-}"
