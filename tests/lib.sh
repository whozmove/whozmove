# Shared by the tests that run the app: the app built once per run, and the time-stable JSON they compare.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# After `. tests/lib.sh` (from the checkout's root):
#   app=$(built_app "$T") || exit 1    the app: tests/all.sh's build when it made one (WHOZMOVE_APP), else built
#                                      into that folder now
#   … | in_minutes                     JSON with its times as "now-<minutes>m", so it reads the same on every run
#   page_cases <cases.js>              runs a file of the page's cases outside the app (macOS's jsc, in UTC, the page's
#                                      scripts loaded first, its modules' included), printing what they print

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

# JSON with its times (ms since 1970) as "now-<minutes>m", so it reads the same on every run.
in_minutes() {
python3 -c '
import json, sys, time
now = time.time()
def stable(value):
    if isinstance(value, dict):
        return {k: stable(v) for k, v in value.items()}
    if isinstance(value, (int, float)) and not isinstance(value, bool) and 1.5e12 < value < 2.5e12:
        return "now-%dm" % round((now - value / 1000) / 60)
    return value
print(json.dumps(stable(json.load(sys.stdin)), indent=2, sort_keys=True, ensure_ascii=False))
'
}

# A file of the page's cases, run as tests/panel.sh runs the core's: with macOS's JavaScriptCore, in UTC so the clock
# times read the same everywhere, after the page's scripts in the order the page loads them (tools/page.sh).
page_cases() {
  local jsc=/System/Library/Frameworks/JavaScriptCore.framework/Versions/Current/Helpers/jsc srcs
  [ -x "$jsc" ] || { echo "Couldn't find macOS's jsc at $jsc"; return 1; }
  srcs=$(tools/page.sh --scripts) || return 1
  TZ=UTC "$jsc" "$1" -- $srcs 2>&1
}
