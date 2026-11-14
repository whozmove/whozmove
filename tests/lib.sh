# Shared by the tests: a throwaway folder and its clean-up, the app built once per run, stand-in processes, and the
# time-stable JSON they compare.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# After `. tests/lib.sh` (from the checkout's root):
#   T=$(throwaway <name>) || exit 1    a new folder for the test, by its real path, in $TMPDIR
#   S=$(throwaway --short <name>) || exit 1
#                                      one in /tmp, short enough for a Unix socket's path (else in $TMPDIR), by
#                                      its real path too
#   leave_nothing "$T" ["$S"] [-- <command>]
#                                      as the test ends, however it ends: <command> first, then the processes it started
#                                      stopped (their pids in $T/pids), and the folders removed
#   app=$(built_app "$T") || exit 1    the app: tests/all.sh's build when it made one (WHOZMOVE_APP), else built
#                                      into that folder now
#   pid=$(detached <command>…)         starts a stand-in process apart from the test, its pid written to $T/pids
#   pause <pid>                        pauses it, as Ctrl+Z does, once macOS can't wake it again by itself
#   … | in_minutes                     JSON with its times as "now-<minutes>m", so it reads the same on every run
#   page_cases <cases.js> [<module>/<page>]
#                                      runs a file of the page's cases outside the app (macOS's jsc, in UTC, the page's
#                                      scripts loaded first, its modules' included), printing what they print; or one of
#                                      a module's own pages' cases, with that page's scripts (tools/page.sh --pages)
#   page_test <name> <folder> "${1:-}" [<module>/<page>]
#                                      runs <folder>/page-cases.js so, and compares what it prints with
#                                      <folder>/page.expected.txt (tests/compare.sh, sourced first), --update saving it
#   parent_of <pid>                    the process's parent's pid, or nothing once it has gone
#   sockets_refused <folder>           why a Unix socket in that folder can't be made or reached here, or nothing
#   running_from <path>                the pids of the processes running the program at that path, one a line

# A throwaway folder, named for its test after the prefix the test's sandbox lets it write (whozmove-, or wz- in
# /tmp), by its real path ($TMPDIR is under /var, which is /private/var, and /tmp is /private/tmp), so the paths a
# test prints read one way. A short one is for a Unix socket, whose whole path must fit in 104 bytes: in /tmp, or in
# $TMPDIR where /tmp is refused.
throwaway() {
  local folder
  # A folder that wasn't made stops here: an empty name would read as the folder the test runs in, its checkout, which
  # its clean-up would then remove.
  if [ "$1" = --short ]; then
    folder=$(mktemp -d "/tmp/wz-$2.XXXXXX" 2>/dev/null || mktemp -d "${TMPDIR:-/tmp}/wz-$2.XXXXXX") || return 1
  else
    folder=$(mktemp -d "${TMPDIR:-/tmp}/whozmove-$1.XXXXXX") || return 1
  fi
  (cd "$folder" && pwd -P)
}

# The test's clean-up, as it ends however it ends: the test's own clean-up first (after --), then the stand-in
# processes it started (detached keeps their pids in the first folder's pids file) stopped, paused ones woken so they
# can end, and the folders made writable again (a test may lock one) and removed. An empty path or / is refused as a
# mistake: it names no folder of the test's.
leave_nothing() {
  local folders=() more= f quoted=
  while [ $# -gt 0 ]; do
    if [ "$1" = -- ]; then shift; more="$*"; break; fi
    folders+=("$1")
    shift
  done
  [ ${#folders[@]} -gt 0 ] || { echo "leave_nothing: no folder to remove" >&2; return 1; }
  for f in "${folders[@]}"; do
    if [ -z "$f" ] || [ "$f" = / ]; then echo "leave_nothing: no folder to remove" >&2; return 1; fi
    quoted="$quoted $(printf '%q' "$f")"
  done
  # The folders are fixed now, quoted as they are; the pids are read as the test ends.
  local stop="pids=\$(cat $(printf '%q' "${folders[0]}")/pids 2>/dev/null); kill \$pids 2>/dev/null"
  trap "${more:+$more; }$stop; kill -CONT \$pids 2>/dev/null; chmod -R u+rwx$quoted 2>/dev/null; rm -rf$quoted" EXIT
}

built_app() {
  if [ -n "${WHOZMOVE_APP_FAILED:-}" ]; then
    echo "The app didn't compile (tests/all.sh says why)" >&2
    return 1
  fi
  if [ -n "${WHOZMOVE_APP:-}" ] && [ -x "$WHOZMOVE_APP" ]; then
    echo "$WHOZMOVE_APP"
    return
  fi
  tools/compile.sh "$1/Whozmove" -O0 >&2 || return 1
  echo "$1/Whozmove"
}

# A stand-in process (a session's, a terminal's), started apart from the test with nothing of its output kept: its pid
# is printed, and written to $T/pids for leave_nothing to stop, so the test's T is made before it's called.
detached() { local pid; pid=$("$@" >/dev/null 2>&1 & echo $!); echo $pid >> "$T/pids"; echo $pid; }
# Pausing one (as Ctrl+Z does) waits until the subshell that started it has gone, its parent then being launchd: macOS
# wakes the paused processes a parent leaves behind (their process group orphaned), so one paused sooner could be
# running again by the time the app looks.
pause() {
  for _ in $(seq 1 200); do [ "$(parent_of "$1")" = 1 ] && break; sleep 0.01; done
  kill -STOP "$1"
}

# JSON with its times (ms since 1970) as "now-<minutes>m", in objects and lists alike, so it reads the same on every
# run. Given when its samples were written (seconds since 1970), it counts from then, so a slow machine can't move
# them by a minute.
in_minutes() {
python3 -c '
import json, sys, time
now = float(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1] else time.time()
def stable(value):
    if isinstance(value, dict):
        return {k: stable(v) for k, v in value.items()}
    if isinstance(value, list):
        return [stable(v) for v in value]
    if isinstance(value, (int, float)) and not isinstance(value, bool) and 1.5e12 < value < 2.5e12:
        return "now-%dm" % round((now - value / 1000) / 60)
    return value
print(json.dumps(stable(json.load(sys.stdin)), indent=2, sort_keys=True, ensure_ascii=False))
' "${1:-}"
}

# A file of the page's cases, run as tests/panel.sh runs the core's: with macOS's JavaScriptCore, in UTC so the clock
# times read the same everywhere, after the page's scripts in the order the page loads them (tools/page.sh), or a
# module page's.
page_cases() {
  local jsc=/System/Library/Frameworks/JavaScriptCore.framework/Versions/Current/Helpers/jsc srcs
  [ -x "$jsc" ] || { echo "Couldn't find macOS's jsc at $jsc"; return 1; }
  srcs=$(tools/page.sh --scripts ${2:+"$2"}) || return 1
  TZ=UTC "$jsc" "$1" -- $srcs 2>&1
}

# A part's or module's page cases, compared with what was recorded beside them: what a few-line test.sh runs.
page_test() {
  local page
  page=$(page_cases "$2/page-cases.js" ${4:+"$4"}) || { echo "$page"; return 1; }
  compare "$1" "$2/page.expected.txt" "$page" "$3"
}

# A process's parent, and the processes running a program, asked of macOS's own libproc: ps is set-user-id and pgrep
# asks a service, and Claude Code's sandbox refuses both, while these calls answer there as anywhere.
parent_of() {
python3 -I -c '
import ctypes, sys
info = ctypes.create_string_buffer(136)  # struct proc_bsdinfo, whose fifth field is the parent pid
libc = ctypes.CDLL("/usr/lib/libSystem.B.dylib")
if libc.proc_pidinfo(int(sys.argv[1]), 3, ctypes.c_uint64(0), info, 136) == 136:  # PROC_PIDTBSDINFO
    print(int.from_bytes(info.raw[16:20], "little"))
' "$1"
}
# Claude Code's sandbox refuses a Unix socket (making one, or reaching one that was made), and a test that waits on a
# socket it can't have would wait out every timeout, or for ever: such a test asks this first, and gives up at once
# with its reason where there's one.
sockets_refused() {
python3 -I -c '
import os, socket, sys, tempfile
folder = tempfile.mkdtemp(prefix="s", dir=sys.argv[1])
path, made = os.path.join(folder, "s"), False
try:
    server = socket.socket(socket.AF_UNIX)
    server.bind(path)
    made = True
    server.listen(1)
    client = socket.socket(socket.AF_UNIX)
    client.settimeout(2)
    client.connect(path)
except OSError as e:
    print("a Unix socket there can\x27t be %s (%s)" % ("reached" if made else "made", e.strerror or e))
finally:
    if made:
        os.unlink(path)
    os.rmdir(folder)
' "$1"
}

running_from() {
python3 -I -c '
import ctypes, os, sys
libc = ctypes.CDLL("/usr/lib/libSystem.B.dylib")
pids = (ctypes.c_int * 8192)()
wanted = os.path.realpath(sys.argv[1])
for pid in pids[:libc.proc_listallpids(pids, ctypes.sizeof(pids))]:
    path = ctypes.create_string_buffer(4096)
    if pid > 0 and libc.proc_pidpath(pid, path, 4096) > 0 and os.path.realpath(path.value.decode()) == wanted:
        print(pid)
' "$1"
}
