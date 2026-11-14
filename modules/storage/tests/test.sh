#!/bin/bash
# The Storage module's tests: what's said of the disk from what's known of it (Whozmove --print-disk, compared with
# disk.expected.txt); the map of a sample home folder (--print-map, map.expected.txt); Clean up's list for a sample
# developer's home folder (--print-cleanup, and from the first pass alone, --print-cleanup-usual, cleanup.expected.txt);
# the map and Clean up again without Apple's developer tools, then
# with a stand-in for them (tools.expected.txt); the page's plain functions (page-cases.js, run
# with macOS's jsc in UTC, compared with page.expected.txt); and Keys (keys.sh, keys.expected.txt and
# again.expected.txt).
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   modules/storage/tests/test.sh            run and compare
#   modules/storage/tests/test.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/../../.." || exit 1
. tests/sandboxed.sh "$@"
HERE=modules/storage/tests
. tests/lib.sh
T=$(throwaway storage) || exit 1
leave_nothing "$T"
. tests/compare.sh
APP=$(built_app "$T") || exit 1

# A disk as it's known: its size and free space in GB, its samples as [hours ago, GB free], oldest first, and the
# line's last × as {hoursAgo, free, severe}.
mkdir -p "$T/disk"
echo '{"total": 460, "free": 120}' > "$T/disk/plenty-no-samples-yet.json"
echo '{"total": 460, "free": 120, "samples": [[12, 125], [6, 122]]}' > "$T/disk/plenty-samples-under-a-day.json"
echo '{"total": 460, "free": 120, "samples": [[48, 120], [24, 121], [2, 120]]}' > "$T/disk/plenty-not-filling.json"
echo '{"total": 460, "free": 120, "samples": [[168, 160], [96, 140], [24, 126]]}' \
  > "$T/disk/plenty-full-in-weeks.json"
echo '{"total": 460, "free": 18.4, "samples": [[168, 40], [120, 33], [72, 26], [24, 20]]}' \
  > "$T/disk/low-full-in-days.json"
echo '{"total": 460, "free": 18.4}' > "$T/disk/low-pace-not-known.json"
echo '{"total": 460, "free": 40, "samples": [[48, 80], [24, 60]]}' > "$T/disk/under-50-full-within-a-week.json"
echo '{"total": 460, "free": 40, "samples": [[48, 41], [24, 40.5]]}' > "$T/disk/under-50-filling-over-months.json"
echo '{"total": 460, "free": 3.2, "samples": [[30, 9], [6, 4]]}' > "$T/disk/nearly-out.json"
echo '{"total": 460, "free": 0.6, "samples": [[30, 9], [6, 4]]}' > "$T/disk/nearly-out-under-a-gb.json"
echo '{"total": 460, "free": 18.4, "samples": [[48, 26], [24, 22]], "closed": {"hoursAgo": 3, "free": 19}}' \
  > "$T/disk/low-put-away-3-hours-ago.json"
echo '{"total": 460, "free": 18.4, "samples": [[48, 26], [24, 22]], "closed": {"hoursAgo": 25, "free": 19}}' \
  > "$T/disk/low-put-away-a-day-ago.json"
echo '{"total": 460, "free": 16, "samples": [[48, 26], [24, 22]], "closed": {"hoursAgo": 3, "free": 19}}' \
  > "$T/disk/low-put-away-then-a-tenth-fuller.json"
echo '{"total": 460, "free": 3.2, "samples": [[48, 26], [24, 22]], "closed": {"hoursAgo": 3, "free": 6}}' \
  > "$T/disk/put-away-then-nearly-out.json"
echo '{"total": 460, "free": 4.8, "samples": [[48, 26], [24, 22]],
       "closed": {"hoursAgo": 3, "free": 4.9, "severe": true}}' > "$T/disk/nearly-out-put-away.json"
echo '{"total": 0, "free": 10}' > "$T/disk/no-total.json"
# Once Storage is on: what Clean up would clean, on the line, and on the nearly-out one as what to do now; with nothing
# to clean, to see what's using the disk, the nearly-out line keeping its warning.
echo '{"total": 460, "free": 18.4, "cleanable": 33}' > "$T/disk/on-low-with-33-to-clean.json"
echo '{"total": 460, "free": 3.2, "cleanable": 33}' > "$T/disk/on-nearly-out-with-33-to-clean.json"
echo '{"total": 460, "free": 18.4, "cleanable": 0}' > "$T/disk/on-low-nothing-to-clean.json"
echo '{"total": 460, "free": 3.2, "cleanable": 0}' > "$T/disk/on-nearly-out-nothing-to-clean.json"
# Worked out from a map 6 hours old: how old, after what can be cleaned; from one 20 minutes old, nothing more.
echo '{"total": 460, "free": 18.4, "cleanable": 33, "measuredHoursAgo": 6}' > "$T/disk/on-low-33-from-an-old-map.json"
echo '{"total": 460, "free": 18.4, "cleanable": 33, "measuredHoursAgo": 0.33}' \
  > "$T/disk/on-low-33-from-a-fresh-map.json"
# After a clean-up, while what it moved is still in the Trash: where the space is, before what can be cleaned.
echo '{"total": 460, "free": 3.2, "cleanable": 8, "inTrash": 33}' > "$T/disk/on-nearly-out-33-in-the-trash.json"

status=0
out=$(
echo "== What's said of the disk: whether the line shows, what it says, and what Storage's card says"
HOME="$T" "$APP" --print-disk "$T"/disk/*
)
compare "The disk" "$HERE/disk.expected.txt" "$out" "${1:-}" || status=1

# A home folder to measure as the map does, in a folder of its own: files of known sizes (each takes whole 4 KB blocks
# on the disk); a file with a second name, counted once; small files, counted together; a folder macOS protects (Desktop,
# not opened without Full Disk Access, which a sample home never has); a tool's store and the folders that stay; and
# four checkouts: one an agent is at work in, one with a change not committed (whose ignored node_modules can still
# go), one with a commit not pushed, and one too small to show on its own, with a change not committed, which the map
# shows all the same, so git is asked about it before the folder it's in can go.
H="$T/home"
make() { mkdir -p "$(dirname "$H/$1")" && dd if=/dev/zero of="$H/$1" bs=1000000 count="$2" 2>/dev/null; }
make Desktop/kept.bin 2
make Library/Caches/tool/blob 3
make Library/Developer/CoreSimulator/Devices/sim.img 4
make movies/film.mov 5
ln "$H/movies/film.mov" "$H/movies/film-again.mov"
for i in 1 2 3; do echo small > "$H/movies/note$i.txt"; done
# Made without git's template (its sample hooks), so a checkout's .git is about the same size whichever git made it.
mkdir -p "$T/no-template"
for repo in busy dirty ahead; do
  mkdir -p "$H/code/$repo"
  git -C "$H/code/$repo" init -q -b main --template="$T/no-template"
  git -C "$H/code/$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
done
make code/busy/src/data.bin 2
echo node_modules/ > "$H/code/dirty/.gitignore"
git -C "$H/code/dirty" add .gitignore
git -C "$H/code/dirty" -c user.email=t@t -c user.name=t commit -q -m ignore
make code/dirty/node_modules/pkg/lib.bin 2
make code/dirty/src/big.bin 2
echo change > "$H/code/dirty/src/edit.txt"
make code/ahead/big.bin 2
git -C "$H/code/ahead" add big.bin
git -C "$H/code/ahead" -c user.email=t@t -c user.name=t commit -q -m big
git -C "$H/code/ahead" remote add origin https://example.com/ahead.git
git -C "$H/code/ahead" update-ref refs/remotes/origin/main HEAD~1
git -C "$H/code/ahead" branch -q --set-upstream-to=origin/main
mkdir -p "$H/notes/tiny"
git -C "$H/notes/tiny" init -q -b main --template="$T/no-template"
git -C "$H/notes/tiny" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
echo change > "$H/notes/tiny/todo.txt"
# A project with no remote: its history is only on this Mac, so it stays, and so does its .git, which is big enough to
# show; and a small folder holding one Whozmove can't open, which shows all the same, and keeps what holds it.
mkdir -p "$H/code/local"
git -C "$H/code/local" init -q -b main --template="$T/no-template"
python3 -I -c 'import random, sys; random.seed(7); sys.stdout.buffer.write(random.randbytes(2000000))' \
  > "$H/code/local/data.bin"  # the same each run, and not squeezed smaller in git's record
git -C "$H/code/local" add data.bin
# Made at a set time, so the commit's record has the same name each run. Its first two letters name the folder it's
# kept in under .git/objects, which the map shows: made now, it would now and then share the tree's or data.bin's
# folder, and leave one small item fewer.
GIT_AUTHOR_DATE=2030-01-01T10:00:00Z GIT_COMMITTER_DATE=2030-01-01T10:00:00Z \
  git -C "$H/code/local" -c user.email=t@t -c user.name=t commit -q -m data
mkdir -p "$H/notes/kept/shut"
chmod 000 "$H/notes/kept/shut"
echo "{\"$H/code/busy\": \"Claude Code\"}" > "$T/busy.json"
out=$(
echo "== The map of a sample home folder: each part's size on the disk (in MB, to a tenth), what's counted together,"
echo "   and what keeps it from going to the Trash"
HOME="$H" "$APP" --print-map "$T/busy.json" | python3 -I -c '
import json, re, sys
mb = lambda b: "%.1f MB" % (int(b) / 1e6)
parts = json.load(sys.stdin)
for part in parts.values():
    part["size"] = mb(part["size"])
    if "small" in part:
        count, size = re.match(r"(\d+), (\d+) bytes", part["small"]).groups()
        part["small"] = "%s, %s" % (count, mb(size))
print(json.dumps(parts, indent=2, sort_keys=True, ensure_ascii=False))'
)
chmod 755 "$H/notes/kept/shut"  # so the clean-up can take it away
compare "The map" "$HERE/map.expected.txt" "$out" "${1:-}" || status=1

# A developer's home folder for Clean up, in a folder of its own: tools' caches, Xcode's built files and support files
# for two iOS versions (the older one goes), a model, and checkouts: one not changed for long, whose built folders git
# ignores (they start ticked), one changed today (they don't), and one an agent is at work in (they can't go); and a
# repo with two worktrees, one merged and not changed for long (its folder can go to the Trash), and one with work in
# it (left out). Each size in MB, to a tenth; no tool is asked anything, and nothing is cleaned.
D="$T/dev"
dmake() { mkdir -p "$(dirname "$D/$1")" && dd if=/dev/zero of="$D/$1" bs=1000000 count="$2" 2>/dev/null; }
long_ago() { touch -t 200001010000 "$@"; }
dcommit() { git -C "$1" -c user.email=t@t -c user.name=t commit -q "${@:2}"; }
drepo() {
  mkdir -p "$D/$1"
  git -C "$D/$1" init -q -b main --template="$T/no-template"
  dcommit "$D/$1" --allow-empty -m init
  if [ -n "${2:-}" ]; then
    printf "$2" > "$D/$1/.gitignore"
    git -C "$D/$1" add .gitignore
    dcommit "$D/$1" -m ignore
  fi
}
dmake .npm/_cacache/content/blob 2
dmake Library/Caches/Yarn/v6/blob 2
dmake Library/Developer/Xcode/DerivedData/App-abc/Build/blob 3
dmake "Library/Developer/Xcode/iOS DeviceSupport/16.4 (20E247)/Symbols/blob" 2
dmake "Library/Developer/Xcode/iOS DeviceSupport/17.2 (21C62)/Symbols/blob" 2
long_ago "$D/Library/Developer/Xcode/iOS DeviceSupport/16.4 (20E247)"
dmake .ollama/models/blobs/blob 2
drepo code/old-app 'node_modules/\n.next/\nios/build/\n'
dmake code/old-app/node_modules/pkg/lib.bin 3
dmake code/old-app/.next/cache/blob 1
dmake code/old-app/ios/build/blob 1
long_ago "$D/code/old-app" "$D/code/old-app/.git/index"
drepo code/fresh 'node_modules/\n'
dmake code/fresh/node_modules/pkg/lib.bin 2
drepo code/busy 'node_modules/\n'
dmake code/busy/node_modules/pkg/lib.bin 2
drepo code/proj
dmake code/proj/src.bin 1
git -C "$D/code/proj" add src.bin
dcommit "$D/code/proj" -m src
git -C "$D/code/proj" worktree add -q -b done "$D/code/proj-done"
dmake code/proj-done/big.bin 2
git -C "$D/code/proj-done" add big.bin
dcommit "$D/code/proj-done" -m big
git -C "$D/code/proj" merge -q --ff-only done
long_ago "$D/code/proj-done" "$D/code/proj/.git/worktrees/proj-done/index"
git -C "$D/code/proj" worktree add -q -b wip "$D/code/proj-wip"
dmake code/proj-wip/big.bin 2
long_ago "$D/code/proj-wip"
echo "{\"$D/code/busy\": \"Claude Code\"}" > "$T/dev-busy.json"
cleanup_list() {
  python3 -I -c '
import json, sys
for group in json.load(sys.stdin)["groups"]:
    print("%s: %s" % (group["title"], group["says"]))
    for item in group["items"]:
        mark = "locked" if "lock" in item else "ticked" if item["on"] else "      "
        print("  %s  %s · %.1f MB · %s" % (mark, item["name"], item["size"] / 1e6, item["where"]))
        if "lock" in item: print("            %s" % item["lock"]["says"])
        if "command" in item: print("            $ %s" % item["command"])'
}
out=$(
echo "== Clean up for a sample developer's home folder: each group's items, ticked or not, and what keeps any"
HOME="$D" "$APP" --print-cleanup "$T/dev-busy.json" "$D/code/proj" | cleanup_list
echo
echo "== The same before the first map: the first pass's usual places only, listed in a few seconds"
HOME="$D" "$APP" --print-cleanup-usual "$T/dev-busy.json" | cleanup_list
echo
# A home whose Library is a link to a folder elsewhere: the first pass leaves Yarn's cache there out, as the whole
# measure, which never follows a link, does; npm's, in the home folder itself, is listed.
L="$T/linked"
mkdir -p "$T/elsewhere/Library/Caches/Yarn/v6" "$L/.npm/_cacache/content"
dd if=/dev/zero of="$T/elsewhere/Library/Caches/Yarn/v6/blob" bs=1000000 count=2 2>/dev/null
dd if=/dev/zero of="$L/.npm/_cacache/content/blob" bs=1000000 count=2 2>/dev/null
ln -s "$T/elsewhere/Library" "$L/Library"
echo "== The first pass in a home whose Library is a link elsewhere: only what's in the home folder itself"
HOME="$L" "$APP" --print-cleanup-usual | cleanup_list
echo
# A home folder that's a checkout (its settings kept in git): the first pass can't ask git about it, so what it lists
# is kept until the whole measure does.
G="$T/dotfiles"
mkdir -p "$G/.npm/_cacache/content"
git -C "$G" init -q -b main --template="$T/no-template"
dd if=/dev/zero of="$G/.npm/_cacache/content/blob" bs=1000000 count=2 2>/dev/null
echo "== The first pass in a home folder that's a checkout: listed, and kept until the disk is measured"
HOME="$G" "$APP" --print-cleanup-usual | cleanup_list
echo "== …and once it's measured, kept for what git says of that checkout"
HOME="$G" "$APP" --print-cleanup | cleanup_list
echo
# Cleaning, step by step, in a copy of that home, into a folder that stands for the Trash: npm's cache goes, the
# checkout an agent works in stays (saying why, and what to do), one not on the list now stays, and after the map is
# measured again, nothing goes.
cp -R "$D" "$T/dclean"
C="$T/dclean"
echo "{\"$C/code/busy\": \"Claude Code\"}" > "$T/clean-busy.json"
clean_steps() { python3 -I -c '
import json, sys
home, said = sys.argv[1], json.load(sys.stdin)
for step in said["steps"]:
    print("  %s: %s%s%s" % (step["id"].replace(home, "~"), step["state"], " · " + step["why"] if "why" in step else "",
                           " · " + step["then"] if "then" in step else ""))
result = said["result"]
print("  then: %.1f MB in the Trash, cleaned %s, %d stayed" % (result["trashed"] / 1e6, result["cleaned"],
                                                               len(result["failed"])))' "$C"; }
echo "== Cleaning, step by step"
HOME="$C" "$APP" --print-cleanup-clean "$T/trash" "$T/clean-busy.json" "folder:$C/.npm/_cacache" \
  "built:$C/code/busy" "folder:$C/gone" | clean_steps
echo "  in the stand-in Trash: $(ls "$T/trash" | sed 's/^[^ ]* //' | sort | paste -sd , -)"
echo "== After the map is measured again"
HOME="$C" "$APP" --print-cleanup-clean "$T/trash" "$T/clean-busy.json" --stale "folder:$C/Library/Caches/Yarn" \
  | clean_steps
# Library put behind a link once the map is measured, as if moved to another disk: the map's Yarn cache is somewhere
# else now, so it stays.
cp -R "$D" "$T/dlinked"
C="$T/dlinked"
echo '{}' > "$T/no-busy.json"
echo "== Library behind a link by the time it's cleaned"
HOME="$C" "$APP" --print-cleanup-clean "$T/trash" "$T/no-busy.json" --linked "$C/Library" \
  "folder:$C/Library/Caches/Yarn" | clean_steps
)
compare "Clean up" "$HERE/cleanup.expected.txt" "$out" "${1:-}" || status=1

# How Keys judges what Betterleaks finds, a line at a time (--print-keys-judge), for what its rules don't reach in a
# sample line on their own: words joined by dashes or underscores, constants in capitals ending in KEY, a path's hex
# part and a sentence (no key); a UUID a lookup sets as `key` and what a Spotify address names (ids); and what still
# counts: a long passphrase, a UUID set as a service's key, a hook's address ending in its secret, and a password
# ending in a full stop. A sign-in token in escaped JSON ends as the token does, never in a "\". And as they come in AI
# tools' records: a variable given to curl's -u after the address (no key) and a password given to it (counts); a
# sentence with commas and a bracket in it; a private key's header alone in a test's words (no key), and one with its
# key, its line breaks written out (counts); an id of 32 hex in a tool's result (no key); and a header's token in a
# command that gives a variable to -u too (counts: only curl's user and password are read as -u's). Made-up values.
python3 -I -c '
import json, random, string, sys
r = random.Random(241)
pick = lambda chars, n: "".join(r.choice(chars) for _ in range(n))
hexs, alnum = "0123456789abcdef", string.ascii_letters + string.digits
uuid = lambda: "-".join(pick(hexs, n) for n in (8, 4, 4, 4, 12))
lookup, service, blob, hook, track = uuid(), uuid(), pick(hexs, 32), pick(hexs, 32), pick(alnum, 22)
mixed = pick(alnum, 10) + "#" + pick(string.digits, 3) + "."
jwt = "eyJhbGciOiJIUzI1NiJ9." + pick(alnum, 30) + "." + pick(alnum + "_-", 43)
given = pick(alnum, 12) + "!" + pick(string.digits, 2)
body = "\\n".join(pick(alnum + "+/", 70) for _ in range(5))
asset = pick(hexs, 32)
bearer = pick(alnum, 40)
cases = [
    ("words joined by dashes", "generic-api-key", "api_key = \"paste-your-stripe-key-right-here\"", None),
    ("words joined by underscores", "generic-api-key", "secret_key: \"my_long_secret_value_for_testing\"", None),
    ("a long passphrase", "generic-password", "password = \"Correcthorsebatterystaple\"", None),
    ("a constant ending in KEY", "generic-api-key", "auth_token = PAYMENTSERVICEKEY", None),
    ("a constant ending in KEYS", "generic-api-key", "api_key = \"PAYMENTGATEWAYKEYS\"", None),
    ("a variable as the user of a curl-style -u", "curl-auth-user", "cu" "rl -u \"$STRIPE_SECRET_KEY:\" https://api.example.dev/v1",
     "cu" "rl -u \"$STRIPE_SECRET_KEY:\""),
    ("a UUID a lookup sets as key", "generic-api-key", "key=\"" + lookup + "\"", None),
    ("a UUID set as a service key", "generic-api-key", "SERVICE_API_KEY=" + service, None),
    ("a path, its hex part", "generic-api-key", "\"assets/logo-dark.svg\" -> \"/_blob/" + blob + "\"",
     "/_blob/" + blob),
    ("a hook address ending in its secret", "generic-api-key",
     "notify_url = \"https://hooks.example.com/services/" + hook + "\"", None),
    ("what a Spotify address names", "generic-api-key", "track_key: \"spotify:track:" + track + "\"", None),
    ("a sentence a match ran into", "generic-password", "Password managers such as KeyVault use their own marker "
     "types for the same purpose (com.example.secret.marker).", None),
    ("a sentence set as a password", "generic-password", "password: \"Use the admin panel.\"", None),
    ("a password ending in a full stop", "generic-password", "password = \"" + mixed + "\"", None),
    ("a token in escaped JSON", "jwt", "{\\\"session\\\":{\\\"auth\\\":\\\"" + jwt + "\\\"}}", jwt + "\\"),
    ("a variable given to a curl-style -u after its address", "curl-auth-user",
     "cu" "rl https://api.example.dev/v1/refunds -u \"$API_KEY:\"", None),
    ("a password given to a curl-style -u after its address", "curl-auth-user",
     "cu" "rl https://api.example.dev/v1/refunds -u \"shop:" + given + "\"", None),
    ("a sentence with commas and a bracket", "generic-password", "Password managers mark what they copy as concealed, "
     "so a clipboard manager can skip it (the password).", None),
    ("a private key header alone", "private-key", "check(@\"Why: -----BEGIN OPENSSH PRIVATE KEY----- in the notes\");",
     None),
    ("a private key with its key", "private-key", "-----BEGIN OPENSSH PRIVATE KEY-----\\n" + body
     + "\\n-----END OPENSSH PRIVATE KEY-----", None),
    ("an id of 32 hex in a tool result", "generic-api-key", "{\"assets\": [{\"id\": \"" + asset + "\"}]}", None),
    ("a header token beside a variable given to -u", "curl-auth-header",
     "cu" "rl -u \"$API_USER:\" -H \"Authorization: Bearer " + bearer + "\" https://api.example.dev",
     "cu" "rl -u \"$API_USER:\" -H \"Authorization: Bearer " + bearer),
]
json.dump([{"label": l, "rule": rule, "line": line, "match": m or line} for l, rule, line, m in cases],
          open(sys.argv[1], "w"))
' "$T/judge.json"
out=$("$APP" --print-keys-judge "$T/judge.json" | python3 -I -c '
import json, sys
labels = [c["label"] for c in json.load(open(sys.argv[1]))]
for label, said in zip(labels, json.load(sys.stdin)):
    named = " · named %s" % json.dumps(said["named"]) if said.get("named") else ""
    last = " · …%s" % said["last"] if said.get("last") else ""
    print("%s: %s%s%s" % (label, said["judged"], last, named))' "$T/judge.json")
compare "How Keys judges a line" "$HERE/judge.expected.txt" "$out" "${1:-}" || status=1

# Apple's developer tools, as xcode-select names them (DEVELOPER_DIR): missing (an empty folder), then a stand-in whose
# git notes each run and hands it to the real one. Without them, Storage runs no git: the map's checkouts keep all they
# hold, saying why, and Clean up offers no worktree; with them, every git it runs is theirs (RunGit), never
# /usr/bin/git, which offers to install them.
mkdir -p "$T/no-tools" "$T/tools/usr/bin"
real_git="$(env -u DEVELOPER_DIR /usr/bin/xcode-select -p)/usr/bin/git"
printf '#!/bin/bash\necho "$*" >> "%s"\nexec "%s" "$@"\n' "$T/git.log" "$real_git" > "$T/tools/usr/bin/git"
chmod +x "$T/tools/usr/bin/git"
checkouts() { python3 -I -c '
import json, sys
for path, part in sorted(json.load(sys.stdin).items()):
    if part.get("checkout"): print("  %s: %s" % (path, (part.get("lock") or "nothing keeps it").split(": ", 1)[-1]))'; }
out=$(
echo "== Without Apple's developer tools: the map's checkouts, and Clean up's worktrees"
DEVELOPER_DIR="$T/no-tools" HOME="$H" "$APP" --print-map "$T/busy.json" | checkouts
worktrees() { python3 -I -c '
import json, sys
list = json.load(sys.stdin)
offered = any(g["id"] == "worktrees" for g in list["groups"])
print("  Clean up: %s%s" % ("a worktree offered" if offered else "no worktree offered",
                           ", and it says they wait for the tools" if list.get("tools") else ""))'; }
DEVELOPER_DIR="$T/no-tools" HOME="$D" "$APP" --print-cleanup "$T/dev-busy.json" "$D/code/proj" | worktrees
echo "== With them: every git the map and Clean up ran was theirs (the stand-in's), never /usr/bin/git"
rm -f "$T/git.log"
DEVELOPER_DIR="$T/tools" HOME="$H" "$APP" --print-map "$T/busy.json" | checkouts
echo "  the map asked: $(sed -E 's/.* -C [^ ]+ ([a-z-]+).*/\1/' "$T/git.log" | sort -u | tr '\n' ' ')"
rm -f "$T/git.log"
DEVELOPER_DIR="$T/tools" HOME="$D" "$APP" --print-cleanup "$T/dev-busy.json" "$D/code/proj" | worktrees
echo "  Clean up asked: $(sed -E 's/.* -C [^ ]+ ([a-z-]+).*/\1/' "$T/git.log" | sort -u | tr '\n' ' ')"
)
compare "Without the developer tools" "$HERE/tools.expected.txt" "$out" "${1:-}" || status=1

page=$(page_cases "$HERE/page-cases.js") || { echo "$page"; exit 1; }
compare "Storage's page" "$HERE/page.expected.txt" "$page" "${1:-}" || status=1

# Keys: what its look finds in a sample home, with each Betterleaks tools/betterleaks.txt names (keys.sh), on this
# build of the app.
WHOZMOVE_APP="$APP" bash "$HERE/keys.sh" "${1:-}" || status=1
exit $status
