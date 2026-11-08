#!/bin/bash
# The sessions module's tests: Sessions on the panel's back for a sample home (Whozmove --print-sessions), with made-up
# conversations in Claude Code's folder: two that ended (one named with /rename, one with its sub-agents', tools' and
# edited files' records beside it and Whozmove's own note of it), one open and free, one working, one paused in its
# terminal (each a stand-in process this test starts), one Claude Desktop keeps, and a file in a project's folder that
# isn't a conversation. Then moving three to the Trash (the working one left out, the open one ended first), Undo,
# moving one again and Put Back, Finder's Put Back (a file back under the name the Trash gave it, given its own again,
# and nothing renamed for a note that names another file),
# Put Back refused with a file there again or with its note changed to send a file
# elsewhere, and the Trash emptied; each time what the page shows and where every file is. Files go into a stand-in
# Trash of the test's, never macOS's own. And what the run Sessions starts for each file it moves to macOS's Trash
# (--helper-trash-item) refuses, each refused file left where it was: a path that isn't whole, one with "..", one
# that isn't there, a link named as a conversation's transcript, a file in a project's folder that isn't a
# conversation's, a conversation's transcript in a project folder that's a link to somewhere else, and one of a
# conversation's own files in this throwaway home, as macOS's Trash is your account's. Then, with a stand-in for that
# run, which moves into the stand-in Trash: a conversation of five files moved, each row's steps as it goes; one whose
# run refuses a file, saying why with Show in Finder; one whose run moved its file but didn't finish (counted as
# moved); one whose run moved its file without saying where (the rest back, and said); a conversation kept through a
# project folder that's a link, greyed with its way; and a file Finder put back under the Trash's name given its own
# back by the module's tick. Compared with sessions.expected.txt. Then its page's rules (page-cases.js, with macOS's
# jsc), compared with page.expected.txt.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   modules/sessions/tests/test.sh            run and compare
#   modules/sessions/tests/test.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/../../.." || exit 1
. tests/sandboxed.sh "$@"
HERE=modules/sessions/tests
# Stops here if there's no temporary folder: an empty T would make the clean-up below delete this checkout.
T=$(mktemp -d "${TMPDIR:-/tmp}/whozmove-sessions.XXXXXX") || exit 1
T=$(cd "$T" && pwd -P) || exit 1
# Stand-in processes are kept in $T/pids so they're stopped however this ends (a paused one is carried on first).
stop() { kill -CONT $(cat "$T/pids" 2>/dev/null) 2>/dev/null; kill $(cat "$T/pids" 2>/dev/null) 2>/dev/null; }
trap 'stop; rm -rf "$T"' EXIT
. tests/lib.sh
. tests/compare.sh
APP=$(built_app "$T") || exit 1

H="$T/home"
OLD=0a1b2c3d-0000-4000-8000-000000000001     # ended 3 hours ago, in Ghostty, with records beside it
DOCS=0a1b2c3d-0000-4000-8000-000000000002    # ended 7 hours ago, renamed
OPEN=0a1b2c3d-0000-4000-8000-000000000003    # open and free
BUSY=0a1b2c3d-0000-4000-8000-000000000004    # working
DESK=0a1b2c3d-0000-4000-8000-000000000005    # Claude Desktop keeps it
PAUSED=0a1b2c3d-0000-4000-8000-000000000006  # paused in its terminal
STALE=0a1b2c3d-0000-4000-8000-000000000007   # its file names a process that started long after the session did
mkdir -p "$H/code/shop" "$H/code/blog" "$H/.claude/sessions" "$H/Library/Application Support/Whozmove"

# A made-up conversation: its transcript, written as Claude Code writes one, its last message `minutes` ago.
conversation() {
  python3 -I - "$H" "$@" <<'PY'
import json, os, sys, time
home, sid, folder, minutes, ai, custom = sys.argv[1:7]
now = time.time()
at = lambda m: time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(now - float(m) * 60))
cwd = os.path.join(home, folder)
project = os.path.join(home, ".claude/projects", cwd.replace("/", "-"))
os.makedirs(project, exist_ok=True)
with open(os.path.join(project, sid + ".jsonl"), "w") as f:
    # As compact as Claude Code writes its records.
    line = lambda **x: f.write(json.dumps(dict(sessionId=sid, **x), separators=(",", ":")) + "\n")
    line(type="user", cwd=cwd, timestamp=at(float(minutes) + 2), message={"role": "user", "content": "go on"})
    if ai: line(type="ai-title", aiTitle=ai)
    if custom: line(type="custom-title", customTitle=custom)
    line(type="assistant", cwd=cwd, timestamp=at(minutes), message={"role": "assistant", "content": "Done."})
PY
}
conversation "$OLD" code/shop 180 "Old refactor" ""
conversation "$DOCS" code/shop 420 "Fix the links" "Docs links"
conversation "$OPEN" code/shop 25 "Coupon codes" ""
conversation "$BUSY" code/shop 1 "Image resize" ""
conversation "$DESK" code/blog 48 "Pricing page copy" ""
conversation "$PAUSED" code/blog 60 "Draft post" ""
conversation "$STALE" code/blog 90 "Old feed" ""
PROJECT="$H/.claude/projects/$(echo "$H/code/shop" | tr / -)"
mkdir -p "$PROJECT/$OLD/subagents" "$H/.claude/file-history/$OLD"
echo '{}' > "$PROJECT/$OLD/subagents/agent-1.jsonl"
echo 'before' > "$H/.claude/file-history/$OLD/a1b2@v1"
echo '{"type": "summary"}' > "$PROJECT/memory.jsonl"
W="$H/Library/Application Support/Whozmove"
mkdir -p "$W/sessions" "$W/conversations"
echo "{\"lastPrompt\": \"go on\"}" > "$W/sessions/$OLD.json"
echo "{\"sessionId\": \"$OLD\", \"terminal\": \"Ghostty\"}" > "$W/conversations/$OLD.json"
# Claude Desktop keeps one of them, whether it's tracked or not.
D="$H/Library/Application Support/Claude/claude-code-sessions/account/org"
mkdir -p "$D"
echo "{\"sessionId\": \"local_desk\", \"cliSessionId\": \"$DESK\", \"title\": \"Pricing page copy\",
       \"cwd\": \"$H/code/blog\"}" > "$D/local_desk.json"

# The open ones: a stand-in process each, registered as Claude Code registers a session's.
register() {
  local pid=$1 sid=$2 status=$3 folder=$4 before=${5:-0} now
  now=$(python3 -c "import time; print(int(time.time() * 1000) - $before)")
  echo "{\"pid\": $pid, \"sessionId\": \"$sid\", \"kind\": \"interactive\", \"entrypoint\": \"cli\",
         \"cwd\": \"$H/$folder\", \"status\": \"$status\", \"startedAt\": $now, \"statusUpdatedAt\": $now}" \
    > "$H/.claude/sessions/$pid.json"
}
# Started detached, so their parent is launchd and no app is above them: otherwise they would inherit whatever terminal
# this test runs in, and Sessions would say "Running in Ghostty" here and "Running in a terminal" on a runner with none.
# Every Mac then says the same.
detached() { local pid; pid=$("$@" >/dev/null 2>&1 & echo $!); echo $pid >> "$T/pids"; echo $pid; }
for which in OPEN BUSY PAUSED STALE; do
  eval "${which}_PID=$(detached sleep 600)"
done
register "$OPEN_PID" "$OPEN" idle code/shop
register "$BUSY_PID" "$BUSY" busy code/shop
register "$PAUSED_PID" "$PAUSED" idle code/blog
kill -STOP "$PAUSED_PID"
# Its file says its session started an hour before this process did: a pid handed on since, never to be sent anything.
register "$STALE_PID" "$STALE" idle code/blog 3600000

TRASH="$T/Trash"
# What Sessions shows, after a press when one is given: its sections' items, each with its line, why it can't go and
# its way, its marks, and what the press did; with the home folder written as ~.
sessions() {
  HOME="$H" "$APP" --print-sessions "$TRASH" "$@" 2>&1 | python3 -I -c '
import json, sys
home = sys.argv[1]
raw = sys.stdin.read()
try: page = json.loads(raw)
except Exception: print(raw.replace(home, "~")); sys.exit()
print("count %s" % page.get("count"))
for section in page.get("sections", []):
    print("%s%s" % (section["title"], "" if section.get("tickable") else " (not tickable)"))
    for item in section["items"]:
        extra = (" · why: %s" % item["why"]) if item.get("why") else ""
        if item.get("way"): extra += " · way: %s" % item["way"]["title"]
        if item.get("marks"): extra += " · marks: %s" % ",".join(item["marks"])
        if item.get("buttons"): extra += " · " + " / ".join(b["title"] for b in item["buttons"])
        print("  %s: %s%s" % (item["title"], item["line"], extra))
    if section.get("foot"): print("  (%s)" % section["foot"])
said = page.get("said")
if said: print("said: %s%s" % (said["text"], "".join(" [%s]" % b["title"] for b in said.get("buttons", []))))
titles = {item["id"]: item["title"] for section in page.get("sections", []) for item in section["items"]}
for sid, words in sorted(page.get("steps", {}).items()):
    print("steps of %s: %s" % (titles.get(sid, sid), " > ".join(words)))
' "$H"
}
# Where each of a conversation's files is now: in Claude Code's folder, Whozmove's, or the stand-in Trash.
where() {
  local found
  found=$( { find "$H/.claude/projects" "$H/.claude/file-history" "$W/sessions" "$W/conversations" "$TRASH" \
               -mindepth 1 -maxdepth 2 2>/dev/null; } \
             | sed "s|$H|~|; s|$T|T|; s|$(echo "$H" | tr / -)|~|" | grep -v memory.jsonl | sort)
  echo "files:"; echo "$found" | sed 's/^/  /'
}
alive() { kill -0 "$1" 2>/dev/null && echo "running" || echo "ended"; }

out=$(sessions)
out+=$'\n\n'"== Move to Trash: Old refactor, Coupon codes (open), Image resize (working)"$'\n'
out+=$(sessions trash "$OLD" "$OPEN" "$BUSY")
out+=$'\n'"Coupon codes' process: $(alive "$OPEN_PID") · Image resize's: $(alive "$BUSY_PID")"$'\n'$(where)
out+=$'\n\n'"== Move to Trash: Old feed, whose file names another process"$'\n'$(sessions trash "$STALE")
out+=$'\n'"that process: $(alive "$STALE_PID")"
out+=$'\n\n'"== Undo"$'\n'$(sessions undo "$OLD" "$OPEN")$'\n'$(where)
out+=$'\n\n'"== Move Old refactor again, then Put Back"$'\n'$(sessions trash "$OLD")
out+=$'\n'$(sessions putback "$OLD")$'\n'$(where)
# Finder's Put Back brings each file back beside its own place under the name it has in the Trash, where the Trash gave
# one of the two named by the id a name of its own: Sessions, as it next looks, gives it its own name back.
out+=$'\n\n'"== Move Old refactor again, then Finder's Put Back"$'\n'$(sessions trash "$OLD")
python3 -I - "$W/trashed/$OLD.json" <<'PY3'
import json, os, sys
for item in json.load(open(sys.argv[1]))["items"]:
    os.rename(item["to"], os.path.join(os.path.dirname(item["from"]), os.path.basename(item["to"])))
PY3
out+=$'\n'"put back by Finder:"$'\n'$(where)$'\n'"then Sessions:"$'\n'$(sessions)$'\n'$(where)
# A note naming another file beside a free place (another conversation's transcript, not a name the Trash gives) has
# nothing renamed: here Old refactor's edited files' place, free, and Docs links' transcript copied beside it.
FH="$H/.claude/file-history"
mv "$FH/$OLD" "$T/held"
cp "$PROJECT/$DOCS.jsonl" "$FH/$DOCS.jsonl"
mkdir -p "$TRASH"
echo "{\"id\": \"$OLD\", \"items\": [{\"from\": \"$FH/$OLD\", \"to\": \"$TRASH/$DOCS.jsonl\"}]}" \
  > "$W/trashed/$OLD.json"
sessions > /dev/null
out+=$'\n'"a note naming another file: $([ -e "$FH/$DOCS.jsonl" ] && [ ! -e "$FH/$OLD" ] && echo "nothing renamed" ||
  echo "renamed")"
rm -f "$FH/$DOCS.jsonl" "$W/trashed/$OLD.json"
mv "$T/held" "$FH/$OLD"
out+=$'\n\n'"== Move Docs links, then Put Back with a file there again"$'\n'$(sessions trash "$DOCS")
echo 'new' > "$PROJECT/$DOCS.jsonl"
out+=$'\n'$(sessions putback "$DOCS")
out+=$'\n\n'"== Move Old refactor, then Put Back with its note sending a file elsewhere"$'\n'$(sessions trash "$OLD")
python3 -I - "$W/trashed/$OLD.json" "$H/.zshrc" <<'PY2'
import json, sys
note = json.load(open(sys.argv[1]))
note["items"][0]["from"] = sys.argv[2]
json.dump(note, open(sys.argv[1], "w"))
PY2
out+=$'\n'$(sessions putback "$OLD")$'\n'"a file there: $([ -e "$H/.zshrc" ] && echo yes || echo no)"
out+=$'\n\n'"== The Trash emptied"$'\n'
rm -rf "$TRASH"
out+=$(sessions)

# What the run for one file refuses, before it would move anything to macOS's Trash: none of these gets that far.
LINKED=0a1b2c3d-0000-4000-8000-000000000008
ln -s "$H/.zshrc" "$PROJECT/$LINKED.jsonl"
touch "$H/.zshrc"
mkdir -p "$T/elsewhere"
ln -s "$T/elsewhere" "$H/.claude/projects/-elsewhere"
conversation "$LINKED" elsewhere 30 "Elsewhere" ""
mv "$H/.claude/projects/$(echo "$H/elsewhere" | tr / -)/$LINKED.jsonl" "$T/elsewhere/$LINKED.jsonl"
refused() {
  local said
  said=$(HOME="$H" "$APP" --helper-trash-item "$2" 2>&1; echo "exit $?")
  echo "trash item, $1: $(echo "$said" | python3 -I -c 'import json, sys
lines = sys.stdin.read().splitlines()
print("%s, %s" % (json.loads("\n".join(lines[:-1])).get("why"), lines[-1]))')$(
    [ -e "$2" ] || [ -L "$2" ] && echo ", left where it was")"
}
out+=$'\n\n'"== What the run for one file refuses"
out+=$'\n'$(refused "not a whole path" "code/shop/$DOCS.jsonl")
out+=$'\n'$(refused 'with ".."' "$PROJECT/../$(basename "$PROJECT")/$DOCS.jsonl")
out+=$'\n'$(refused "not there" "$PROJECT/0a1b2c3d-0000-4000-8000-000000000099.jsonl")
out+=$'\n'$(refused "a link named as a transcript" "$PROJECT/$LINKED.jsonl")
out+=$'\n'$(refused "a project's file that isn't a conversation's" "$PROJECT/memory.jsonl")
out+=$'\n'$(refused "a transcript in a project folder that's a link" "$H/.claude/projects/-elsewhere/$LINKED.jsonl")
out+=$'\n'$(refused "a conversation's transcript, in a home folder that isn't yours" "$PROJECT/$DOCS.jsonl")

# A stand-in for the run Sessions starts for each file, given as --print-sessions' --helper: it moves the file into the
# stand-in Trash and says where, unless its mode file names a way to go wrong for a file whose path holds a word.
MANY=0a1b2c3d-0000-4000-8000-000000000009
conversation "$MANY" code/shop 240 "Many pieces" ""
many_files() {
  mkdir -p "$PROJECT/$MANY/subagents" "$H/.claude/file-history/$MANY"
  echo '{}' > "$PROJECT/$MANY/subagents/agent-1.jsonl"
  echo 'before' > "$H/.claude/file-history/$MANY/c3d4@v1"
  echo "{\"lastPrompt\": \"go on\"}" > "$W/sessions/$MANY.json"
}
many_files
cat > "$T/helper" <<HELPER
#!/bin/bash
path=\$2 name=\$(basename "\$2")
read -r mode word < "$T/helper-mode"
case "\$path" in *"\$word"*) ;; *) mode=fine ;; esac
mkdir -p "$TRASH"
to="$TRASH/\$name" n=2
while [ -e "\$to" ]; do to="$TRASH/\$name \$n" n=\$((n + 1)); done
case \$mode in
  refuse) echo '{"why": "it'"'"'s a link"}'; exit 1 ;;
  unsaid) mv "\$path" "$TRASH/unsaid-\$name"; exit 1 ;;
  cut-off) mv "\$path" "\$to"; printf '{"to": "%s"}\\n' "\$to"; exit 1 ;;
  *) mv "\$path" "\$to"; printf '{"to": "%s"}\\n' "\$to" ;;
esac
HELPER
chmod +x "$T/helper"
with_helper() { sessions --helper "$T/helper" "$@"; }
many_where() { where | grep -e "$MANY" -e "Trash/unsaid"; }
echo "fine" > "$T/helper-mode"
out+=$'\n\n'"== Move Many pieces through the run, then Undo"$'\n'$(with_helper trash "$MANY")$'\n'$(many_where)
out+=$'\n'$(sessions undo "$MANY" | grep said)
echo "refuse file-history" > "$T/helper-mode"
out+=$'\n\n'"== Move Many pieces, the run refusing its edited files' copies"$'\n'$(with_helper trash "$MANY")
out+=$'\n'$(many_where)
echo "cut-off file-history" > "$T/helper-mode"
out+=$'\n\n'"== Move Many pieces, the run moving its edited files' copies but not finishing"
out+=$'\n'$(with_helper trash "$MANY" | grep -e said -e steps)$'\n'$(many_where)
out+=$'\n'$(sessions undo "$MANY" | grep said)
echo "unsaid file-history" > "$T/helper-mode"
out+=$'\n\n'"== Move Many pieces, the run moving its edited files' copies without saying where"
out+=$'\n'$(with_helper trash "$MANY" | grep -e said -e steps -e Elsewhere)$'\n'$(many_where)
mv "$TRASH/unsaid-$MANY" "$H/.claude/file-history/$MANY"
# Finder's Put Back, then only the module's tick: the file under the Trash's name gets its own back.
echo "fine" > "$T/helper-mode"
out+=$'\n\n'"== Move Many pieces, Finder's Put Back, then the module's tick"
out+=$'\n'$(with_helper trash "$MANY" | grep said)
python3 -I - "$W/trashed/$MANY.json" <<'PY4'
import json, os, sys
for item in json.load(open(sys.argv[1]))["items"]:
    os.rename(item["to"], os.path.join(os.path.dirname(item["from"]), os.path.basename(item["to"])))
PY4
out+=$'\n'"put back by Finder:"$'\n'$(many_where)
HOME="$H" "$APP" --print-sessions "$TRASH" tick > /dev/null
out+=$'\n'"after the tick:"$'\n'$(many_where)
failed=0
compare "Sessions, for a sample home" "$HERE/sessions.expected.txt" "$out" "${1:-}" || failed=1

page=$(page_cases "$HERE/page-cases.js") || { echo "$page"; exit 1; }
compare "Sessions' page" "$HERE/page.expected.txt" "$page" "${1:-}" || failed=1
exit $failed
