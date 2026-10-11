#!/bin/bash
# Builds the app from this checkout, has it print the rows it would show for a sample home folder (never your
# real ~/.claude), and compares them with tests/rows.expected.txt.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   tests/rows.sh            run and compare
#   tests/rows.sh --update   run and save the output as the new expected (after a change you meant)
# Also checks, for each terminal session, whether keys may go into it now and the Shift+Tabs its mode menu would
# type (`--print-mode-moves`), the keys a command is typed with (`--print-typing`), that docs/rows.md describes
# exactly the fields a row has, and that the README names the macOS permissions the app asks for while no public
# file names one it doesn't.
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
clang -fobjc-arc -framework Cocoa -framework WebKit -framework JavaScriptCore "$REPO"/app/*.m -o "$T/Whozmove" || exit 1

# A checkout with one uncommitted change, and a worktree of it on its own branch.
git -C "$T" init -q -b main repo
echo one > "$T/repo/a.txt"
git -C "$T/repo" add a.txt
git -C "$T/repo" -c user.email=t@t -c user.name=t commit -q -m init
git -C "$T/repo" worktree add -q "$T/repo-wt" -b feature
echo two >> "$T/repo/a.txt"

# Live sessions (stand-in processes), and one whose process has ended: a pid above the highest macOS hands
# out (99999), so no process can ever have it.
TERM_PID=$(detached sleep 600); WT_PID=$(detached sleep 600); DESK_PID=$(detached sleep 600)
MODE_PIDS=$(for _ in 1 2 3 4 5 6; do detached sleep 600; done | paste -sd , -)
GONE_PID=999999

# Everything else the app reads, with times relative to now so that Claude Desktop's three-day window and
# the like hold whenever this runs. The output turns times back into "now-<minutes>m".
python3 - "$T" "$TERM_PID" "$WT_PID" "$DESK_PID" "$GONE_PID" "$MODE_PIDS" <<'PY'
import json, os, sys, time
from datetime import datetime, timezone
T, term_pid, wt_pid, desk_pid, gone_pid = sys.argv[1], *map(int, sys.argv[2:6])
mode_pids = [int(pid) for pid in sys.argv[6].split(",")]
now = time.time()

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

# What the hook recorded.
put(f"{app}/sessions/s-term.json", {"lastPrompt": "please fix the tests", "lastPromptAt": ms(10),
                                    "lastReply": "All done: the tests pass.", "lastReplyAt": ms(9), "notice": None,
                                    "permissionMode": "acceptEdits", "stageAt": ms(9),
                                    "activity": None, "activityAt": ms(9), "outcome": "Tested", "outcomeAt": ms(9),
                                    "turnReached": [], "workSteps": ["Tested"],
                                    "audit": {"found": 3, "left": 1, "settled": True, "at": ms(9)}})
put(f"{app}/sessions/s-wt.json", {"lastPrompt": "run the suite", "lastPromptAt": ms(2), "stageAt": ms(1),
                                  "activity": "Run the tests", "activityAt": ms(1), "workRoot": repo})

# Requests waiting for an OK: the oldest per session shows; one too long to show in full is cut short; one
# whose hook has gone is cleared away.
put(f"{app}/asks/aaaa1111.json", {"id": "aaaa1111", "sessionId": "s-term", "tool": "Bash",
                                  "input": {"command": "npm test", "description": "Run the tests"},
                                  "cwd": repo, "at": ms(2), "pid": term_pid})
put(f"{app}/asks/dddd4444.json", {"id": "dddd4444", "sessionId": "s-term", "tool": "Bash",
                                  "input": {"command": "npm run lint"}, "cwd": repo, "at": ms(1), "pid": term_pid})
put(f"{app}/asks/bbbb2222.json", {"id": "bbbb2222", "sessionId": "s-wt", "tool": "Write",
                                  "input": {"file_path": os.path.join(wt, "big.txt"), "content": "x" * 5000},
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
PY

# The rows, ordered by session, with what changes from run to run made stable: times become "now-<minutes>m",
# process ids "pid", the sample home "T", and very long text a note of its length.
rows() {
HOME="$T" "$T/Whozmove" --print-rows | python3 -c '
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
'
echo "requests left in asks: $(ls "$T/Library/Application Support/Whozmove/asks" | sort | tr '\n' ' ')"
echo "== Fields app/Row.m sends that docs/rows.md doesn't describe, or describes but app/Row.m doesn't send"
python3 - "$REPO" <<'PY'
import re, sys
repo = sys.argv[1]
sent = set(re.findall(r'json\[@"(\w+)"\]', open(f"{repo}/app/Row.m").read()))
described = set()
for line in open(f"{repo}/docs/rows.md"):
    if line.startswith("| `"):
        described |= set(re.findall(r"`(\w+)`", line.split("|")[1]))
for name in sorted(sent - described): print("not described:", name)
for name in sorted(described - sent): print("described, not sent:", name)
PY
echo "== macOS permissions the app asks for that README.md doesn't name, and public files naming one it doesn't ask for"
python3 - "$REPO" <<'PY'
import os, subprocess, sys
repo = sys.argv[1]
def read(path):
    return open(f"{repo}/{path}", encoding="utf-8").read()
code ="".join(read(f"app/{name}") for name in sorted(os.listdir(f"{repo}/app")) if name.endswith(".m"))
# Each permission by the name macOS gives it, and the call that shows the app asks for it. The README must tell
# people about each one the app asks for; once it stops asking for one, every mention of it has to go too.
asks = {"Accessibility": "AXIsProcessTrusted" in code, "Automation": "NSAppleScript" in code}
public = subprocess.run(["git", "-C", repo, "ls-files", "-z"], capture_output=True, text=True).stdout.split("\0")
for permission, asked in asks.items():
    if asked:
        if permission not in read("README.md"):
            print("README.md doesn't name", permission)
        continue
    for path in public:
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
HOME="$T" "$T/Whozmove" --print-mode-moves
echo "== The keys a slash command is typed with, and where typing stops when the session moves on"
HOME="$T" "$T/Whozmove" --print-typing
}

# The sample home is under /private/var; macOS also gives paths there as /var, so both spellings become T.
out=$(rows 2>&1 | sed -e "s|$T|T|g" -e "s|${T#/private}|T|g")
. "$REPO/tests/compare.sh"
compare Rows "$REPO/tests/rows.expected.txt" "$out" "${1:-}"
