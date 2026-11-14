#!/bin/bash
# The deploy module's tests: Let It Deploy (Whozmove --print-deploy-asks, compared with asks.expected.txt). Stand-in
# sessions in a sample home, Asker and Other, in one project's checkout, and Asker's conversation resumed in a second
# process; what the mode menu says of the switch, what the panel answers each ask, for the session's own checkout, named
# or not, or another named (the project's, or not: refused), what each second's look decides for one, how long one
# waits, and when the switch ends; then ask-panel.sh over a real socket, run from inside Asker's process and from
# outside any session; and the build in place (Whozmove --print-deploys), from sample runs in the repo and its
# worktree, where nothing runs; and real runs in them (Whozmove --print-builds-up), each with its own port, and kept
# from running once what the command runs has changed since it was confirmed, and a confirmation macOS refuses to save.
# Where a Unix socket, or a save as Deploy makes them, is refused here (Claude Code's sandbox), it gives up at once,
# saying why.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   modules/deploy/tests/test.sh            run and compare
#   modules/deploy/tests/test.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/../../.." || exit 1
. tests/sandboxed.sh "$@"
HERE=modules/deploy/tests
. tests/lib.sh
# Stand-in processes are kept in $T/pids so they're stopped however this ends. The socket goes in a folder of its own
# with a short path, as a socket's path can't be longer than 103 bytes; T is cleaned up even if that one can't be made.
T=$(throwaway deploy) || exit 1
leave_nothing "$T"
S=$(throwaway --short ask) || exit 1
leave_nothing "$T" "$S"
. tests/compare.sh
APP=$(built_app "$T") || exit 1
# Its one record starts with what goes over the panel's ask socket: where one can't be made or reached here (Claude
# Code's sandbox), it gives up at once, saying why, rather than waiting out each timeout.
why=$(sockets_refused "$S")
if [ -n "$why" ]; then
  echo "Let It Deploy: couldn't run here, as $why"
  exit 1
fi
# The same where Deploy's own saves are refused in a throwaway home (Claude Code's sandbox refuses their temporary copy):
# its print runs say so in one line and stop, which --print-deploy-asks given nothing else only checks.
why=$(HOME="$T" "$APP" --print-deploy-asks 2>&1)
if [ -n "$why" ]; then
  said="Deploy's saves are refused here: "
  echo "Let It Deploy: couldn't run here, as Deploy's saves are refused (${why#"$said"})"
  exit 1
fi

# The project: shop, a repo, with a worktree its repo lists (shop-try); a folder outside it (elsewhere); and one whose
# .git only points at the repo's worktree (shop-fake), which the repo doesn't list as its own. git here ignores your
# personal git settings.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$T/.claude/sessions" "$T/elsewhere" "$T/shop-fake"
git -C "$T" init -q -b main shop
git -C "$T/shop" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$T/shop" worktree add -q -b try "$T/shop-try"
cp "$T/shop-try/.git" "$T/shop-fake/.git"
# A stand-in session, as Claude Code's registry lists it: its process, named, in the shop folder, idle, its state
# changed $4 seconds ago (0 if not given), so of two processes in one conversation, the later speaks for it. Asker's
# process is a shell that runs ask-panel.sh whenever $T/go appears, so the script runs from inside it, as a session's
# tool would.
register() {
  local now
  now=$(python3 -c 'import time; print(int(time.time() * 1000))')
  echo "{\"pid\": $1, \"sessionId\": \"$2\", \"name\": \"$3\", \"kind\": \"interactive\", \"entrypoint\": \"cli\",
         \"cwd\": \"$T/shop\", \"status\": \"idle\", \"startedAt\": $now,
         \"statusUpdatedAt\": $((now - ${4:-0} * 1000))}" > "$T/.claude/sessions/$1.json"
}
# shellcheck disable=SC2016
bash -c 'while :; do
  if [ -e "$1/go" ]; then
    rm "$1/go"
    { WHOZMOVE_ASK_SOCKET="$2" "$3" put-in-place; WHOZMOVE_ASK_SOCKET="$2" "$3" status
      WHOZMOVE_ASK_SOCKET="$2" "$3" put-in-place "$1/shop-try"; WHOZMOVE_ASK_SOCKET="$2" "$3" put-in-place "$1/elsewhere"
    } > "$1/inside.txt" 2>&1
    touch "$1/went"
  fi
  sleep 0.1
done' asker "$T" "$S/ask.sock" "$PWD/app/ask-panel.sh" >/dev/null 2>&1 &
ASKER=$!; echo $ASKER >> "$T/pids"; disown $ASKER
sleep 600 >/dev/null 2>&1 &
OTHER=$!; echo $OTHER >> "$T/pids"; disown $OTHER
sleep 600 >/dev/null 2>&1 &
COPY=$!; echo $COPY >> "$T/pids"; disown $COPY
# The stand-in sessions ask the panel in their own names, which only Claude Code's program may: they run bash and
# sleep, which the print runs count as it (in a print run only).
export WHOZMOVE_STAND_IN_CLAUDE=/bin/bash:/bin/sleep
register $ASKER s-asker Asker
register $OTHER s-other Other
register $COPY s-asker Asker 60

out=$({
echo "== Let It Deploy: the switch, each ask and its answer, how long one waits, and when the switch ends"
HOME="$T" "$APP" --print-deploy-asks "$S/ask.sock" 30 $COPY > "$T/print.txt" 2>&1 &
PRINT=$!
for _ in $(seq 1 200); do [ -S "$S/ask.sock" ] && break; sleep 0.1; done
touch "$T/go"
for _ in $(seq 1 100); do [ -e "$T/went" ] && break; sleep 0.1; done
outside=$(WHOZMOVE_ASK_SOCKET="$S/ask.sock" app/ask-panel.sh status 2>&1; echo "exit=$?")
touch "$S/ask.sock.done"
wait $PRINT
cat "$T/print.txt"
echo "== From inside Asker's process: put-in-place, status, then put-in-place for shop-try and for elsewhere"
cat "$T/inside.txt" 2>/dev/null || echo "(it didn't run)"
echo "== ask-panel.sh status, from outside any session"
echo "$outside"
echo "== ask-panel.sh with no panel to ask, and with no word"
WHOZMOVE_ASK_SOCKET="$S/gone.sock" app/ask-panel.sh status; echo "exit=$?"
app/ask-panel.sh; echo "exit=$?"
app/ask-panel.sh put-in-place "$T/gone"; echo "exit=$?"
echo "== The session hook doesn't take asking the panel for a deploy for one (names_deploy)"
python3 -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("hook", sys.argv[1])
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)
for command in sys.argv[2:]:
    print("%s: %s" % (command, "counted as a deploy" if hook.names_deploy(command) else "not a deploy"))
' modules/claude-code/plugin/hooks/whozmove-claude.py \
  '"$HOME/Applications/Whozmove.app/Contents/Resources/ask-panel.sh" put-in-place' \
  '/Applications/Whozmove.app/Contents/Resources/ask-panel.sh status'
echo "== The build in place (--print-deploys): what a deploy from shop and from shop-try would note it starts from now,"
echo "   and the project's build in place, shop's deploy having ended 2 minutes ago and shop-try's 5: the later is in"
echo "   place, the other before it. shop has a commit since shop-try branched, a file changed and a new one"
echo one > "$T/shop/page.txt"
git -C "$T/shop" add page.txt
git -C "$T/shop" -c user.email=t@t -c user.name=t commit -q -m "Add a coupon box"
echo two > "$T/shop/page.txt"
echo new > "$T/shop/notes.txt"
SHOP=$(git -C "$T/shop" rev-parse HEAD) TRY=$(git -C "$T/shop-try" rev-parse HEAD)
# Each run as Deploys.m keeps it (deploys/<FNV-1a hash of the folder's path>/), its shell gone, ended when its status
# was written.
python3 - "$T" "$SHOP" "$TRY" <<'PY'
import json, os, sys, time
T, shop, try_ = sys.argv[1:]
app = os.path.join(T, "Library/Application Support/Whozmove")
def run_dir(folder):
    h = 14695981039346656037
    for byte in os.fsencode(folder):
        h = ((h ^ byte) * 1099511628211) % 2**64
    return f"{app}/deploys/{h:016x}"
now = time.time()
with open(os.path.join(T, "written-at"), "w") as f:
    f.write(str(now))
for name, commit, ended, by in (("shop", shop, 2, None), ("shop-try", try_, 5, "Asker")):
    folder, d = os.path.join(T, name), run_dir(os.path.join(T, name))
    os.makedirs(d, exist_ok=True)
    run = {"folder": folder, "command": "true", "startedAt": int((now - ended * 60 - 5) * 1000), "pid": 99999,
           "processStart": 1, "commit": commit, "uncommitted": 0}
    if by:
        run["by"] = by
    for file, content in (("run.json", json.dumps(run)), ("status", "0\n"), ("log", "")):
        with open(os.path.join(d, file), "w") as f:
            f.write(content)
        at = now - ended * 60 - (5 if file == "run.json" else 0)
        os.utime(os.path.join(d, file), (at, at))
PY
# Times as minutes ago, and the commits by whose they are. The ports kept (from Let It Deploy's confirmations above)
# are looked at before and after.
ports_before=$(cat "$T/Library/Application Support/Whozmove/ports.json" 2>/dev/null)
HOME="$T" "$APP" --print-deploys "$T/shop" "$T/shop-try" | in_minutes "$(cat "$T/written-at")" \
  | sed -e "s|$SHOP|<shop's commit>|g" -e "s|$TRY|<shop-try's commit>|g"
echo "== …and nothing kept by a print run"
ls "$T/Library/Application Support/Whozmove/in-place.json" 2>&1 | sed "s|.*/||"
[ "$(cat "$T/Library/Application Support/Whozmove/ports.json" 2>/dev/null)" = "$ports_before" ] \
  && echo "ports.json as it was" || echo "ports.json changed"
echo "== Real runs (--print-builds-up): \`make show\`, which says the port it's given, confirmed in shop (its port"
echo "   kept then) and run there and in shop-try, each with its own port; then shop-try's recipe changed after the card"
echo "   showed it, as a branch could: it doesn't run, and isn't saved as the card showed it, until the card has shown it"
echo "   again; a command confirmed before what it runs was kept, confirmed once more first; and one that runs nothing"
echo "   checked, without a port as it was confirmed before ports"
printf 'show:\n\t@echo port=$${PORT:-none}\n' | tee "$T/shop/Makefile" > "$T/shop-try/Makefile"
# Servers, on a block of 8 ports free now, never 3000, said from its first ("base"): picked at random, so these tests
# run at the same time by another checkout don't take the same block.
BASE=$(python3 -c '
import random, socket
starts = list(range(41000, 60000, 8))
random.shuffle(starts)
for base in starts:
    held = []
    try:
        for port in range(base, base + 8):
            s = socket.socket()
            s.bind(("127.0.0.1", port))
            held.append(s)
        print(base)
        break
    except OSError:
        pass
    finally:
        for s in held:
            s.close()
')
echo "== …and stand-in servers (Python's http.server): one in shop and one in shop-try at once, each on its own \$PORT,"
echo "   the later in place; one on every address; one on a port of its own; one on two; one that never listens; one"
echo "   whose program isn't installed, in a checkout with no packages and then without its package.json; Install"
echo "   First, with a stand-in npm; one that ends"
echo "   by itself once up; one its shell leaves running, which Stop Deploy stops by its pid; Restart; a press kept while"
echo "   an agent works there; and the port checked before a press: one of Deploy's own builds on it (an older command's,"
echo "   a server's that picks its own port), or a program it didn't start; last, a command holding a made-up token,"
echo "   confirmed once more where macOS refuses the save"
# A program Deploy didn't start, on base+7: the test's own server, started from this script (which stands in for the
# session that started it), stopped as it ends.
python3 -m http.server --bind 127.0.0.1 $((BASE + 7)) >/dev/null 2>&1 &
HELD=$!; echo $HELD >> "$T/pids"
# A deploy's command runs in the account's login shell. A bash one, as GitHub's runner has, says "logout" as it ends and
# "[1] <pid>" when the command starts a job in the background; zsh, this Mac's, says neither. They're the shell's words,
# not the command's, so they're taken out of the last lines and every Mac says the same.
HOME="$T" "$APP" --print-builds-up 20 "$T/shop" "$T/shop-try" "$BASE" $$ \
  | sed -e "s/$((BASE + 1))/<base+1>/g" -e "s/$((BASE + 5))/<base+5>/g" -e "s/$((BASE + 6))/<base+6>/g" \
        -e "s/$((BASE + 7))/<base+7>/g" \
  | sed -E -e 's| / logout"|"|' -e 's|(its last lines ")\[[0-9]+\] [0-9]+ / |\1|' \
          -e 's| / \[[0-9]+\] [0-9]+ / | / |' -e 's| / \[[0-9]+\] [0-9]+"|"|'
} 2>&1 | sed -e "s|$T|T|g" -e "s|${T#/private}|T|g" -e "s|$S|S|g")
compare "Let It Deploy" "$HERE/asks.expected.txt" "$out" "${1:-}"
