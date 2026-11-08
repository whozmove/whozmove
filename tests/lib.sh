# Shared by the tests that run the app: the app built once per run, and the time-stable JSON they compare.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# After `. tests/lib.sh` (from the checkout's root):
#   app=$(built_app "$T") || exit 1    the app: tests/all.sh's build when it made one (WHOZMOVE_APP), else built
#                                      into that folder now
#   … | in_minutes                     JSON with its times as "now-<minutes>m", so it reads the same on every run
#   page_cases <cases.js> [<module>/<page>]
#                                      runs a file of the page's cases outside the app (macOS's jsc, in UTC, the page's
#                                      scripts loaded first, its modules' included), printing what they print; or one of
#                                      a module's own pages' cases, with that page's scripts (tools/page.sh --pages)
#   parent_of <pid>                    the process's parent's pid, or nothing once it has gone
#   sockets_refused <folder>           why a Unix socket in that folder can't be made or reached here, or nothing
#   running_from <path>                the pids of the processes running the program at that path, one a line

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

# JSON with its times (ms since 1970) as "now-<minutes>m", so it reads the same on every run. Given when its samples
# were written (seconds since 1970), it counts from then, so a slow machine can't move them by a minute.
in_minutes() {
python3 -c '
import json, sys, time
now = float(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1] else time.time()
def stable(value):
    if isinstance(value, dict):
        return {k: stable(v) for k, v in value.items()}
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
