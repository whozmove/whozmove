#!/bin/bash
# The real Claude Code run: Whozmove against a real Claude Code, not samples shaped the way Whozmove expects. Claude
# Code's files, hooks and screen change between versions, and this is what notices: a version is downloaded
# (claude-code.sh, beside this file), pointed at a stand-in for Anthropic's servers (stand-in-api.py, so it needs no
# account and calls no model), given Whozmove's plugin with its own `claude plugin` commands, and driven in a
# pseudo-terminal (pty-driver.py) through what the panel does: a reply, a request for your OK answered at the panel's
# own end of the line, a file written, a command typed over a draft, the mode moved, a question and a plan answered, a
# command left running, a compaction, folder trust and a question asked on the session's side. Then what the app reads of it (its print runs) is compared with
# real.expected.txt, beside this file.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# It runs only where no account can be reached: Claude Code reads its sign-in from the Mac's keychain whatever home
# folder it's given, so on your own Mac it would find yours. So it runs only on a virtual Mac or GitHub's runner, with no
# Claude Code sign-in in its keychain, told so with --throwaway-mac (it checks the Mac too):
#   modules/claude-code/tests/real.sh --throwaway-mac               the version claude-code.txt pins
#   modules/claude-code/tests/real.sh --throwaway-mac --newest      the newest version out
#   modules/claude-code/tests/real.sh --throwaway-mac --at 2.1.310  that version
#   modules/claude-code/tests/real.sh --stand-in-claude             the run's own pieces, with a stand-in Claude Code
#                                                                   (stand-in-claude.py) that reads no sign-in: on any
#                                                                   Mac, compared with real-stand-in.expected.txt
#   --update after any of them saves the output as the new expected copy (after a change you meant).
#   modules/claude-code/tests/real.sh --machine                     says whether a real Claude Code may run here (and
#                                                                   why not), running nothing
#   --record-if-missing with a run: with nothing to compare with yet, it records this run (kept with REAL_RUN_KEEP's
#   records too), says so and passes; else it compares as ever. --has-record (with --stand-in-claude for the stand-in's)
#   exits 0 if there's a record to compare with, 1 if not, running nothing. REAL_RUN_RECORDS: where the records are read
#   and written, this folder unless it's set.
# It ends one of three ways, its last line saying which: passed; Whozmove would break (what differs); or couldn't check
# (a screen or request the run doesn't know, a download that failed), which is the run's own to fix. Exit 0, 1 or 3.
# Needs python3, git, clang and the network (for the download). Takes about four minutes.
cd "$(dirname "$0")/../../.." || exit 1
. tests/sandboxed.sh --downloads "$@"
REPO=$PWD
HERE=modules/claude-code/tests
throwaway=no stand_in=no update= pick=() machine=no record_missing=no has_record=no
for arg in "$@"; do
  case $arg in
    --throwaway-mac) throwaway=yes ;;
    --machine) machine=yes ;;
    --record-if-missing) record_missing=yes ;;
    --has-record) has_record=yes ;;
    --stand-in-claude) stand_in=yes ;;
    --update) update=--update ;;
    --newest) pick=(--newest) ;;
    --at) pick=(--at) ;;
    *) [ "${pick[0]:-}" = --at ] && pick+=("$arg") ;;
  esac
done
# What a run is compared with, in this folder (or REAL_RUN_RECORDS): a real Claude Code's record, or the stand-in's.
records=${REAL_RUN_RECORDS:-$REPO/$HERE}
expected="$records/real.expected.txt"
[ $stand_in = yes ] && expected="$records/real-stand-in.expected.txt"
if [ $has_record = yes ]; then
  [ -f "$expected" ] && [ ! -L "$expected" ]
  exit $?
fi
# A record that's a link would have a run written through it, wherever it points: refused before anything runs.
if [ -L "$expected" ]; then
  echo "couldn't check: $expected is a link, not a record, so nothing is written through it"
  exit 3
fi
# A real Claude Code reads its sign-in from the Mac's keychain whatever home folder it's given, so it runs only where
# there's none to read, and it's the Mac that's checked, not only the flag: a virtual Mac (whose model is
# VirtualMac…) or one of GitHub's own runners, whose keychain holds no Claude Code sign-in. Only whether there is
# one is asked, never the sign-in itself. Why not, or nothing.
not_throwaway() {
  local model
  model=$(sysctl -n hw.model 2>/dev/null)
  if [[ $model != VirtualMac* ]] && ! { [ "${GITHUB_ACTIONS:-}" = true ] &&
                                       [ "${RUNNER_ENVIRONMENT:-}" = github-hosted ]; }; then
    echo "this Mac ($model) isn't a virtual Mac or one of GitHub's runners"
  elif security find-generic-password -s "Claude Code-credentials" >/dev/null 2>&1; then
    echo "this Mac's keychain holds a Claude Code sign-in"
  fi
}
if [ $stand_in = no ]; then
  why=$(not_throwaway)
  if [ $machine = yes ]; then
    echo "${why:-a real Claude Code may run here}"
    exit 0
  fi
  if [ $throwaway = no ] || [ -n "$why" ]; then
    echo "This runs a real Claude Code, which reads its sign-in from the Mac's keychain whatever home folder it's"
    echo "given: it runs only on a throwaway Mac (a virtual Mac, GitHub's runner) told so with --throwaway-mac, and"
    [ -n "$why" ] || why="it wasn't told this is one"
    echo "$why. Check the run's own pieces anywhere with --stand-in-claude."
    exit 2
  fi
fi
APP_LINE='s|.*NSString \*base = \[Home() stringByAppendingPathComponent:@"'
APP_LINE+='\(Library/Application Support/[^"]*\)"].*|\1|p'
APPDIR=$(find "$REPO/app" "$REPO/modules" -name '*.m' -exec sed -n "$APP_LINE" {} + 2>/dev/null | sort -u)
EXE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$REPO/app/Info.plist")
# In /tmp: the panel's socket is in Whozmove's folder there, and a socket's path can't be longer than 103 bytes.
T=$(mktemp -d /tmp/wz-real.XXXXXX) || exit 1
T=$(cd "$T" && pwd -P) || exit 1
trap 'kill $(cat "$T/pids" 2>/dev/null) 2>/dev/null; rm -rf "$T"' EXIT
H="$T/home"
D="$H/$APPDIR"
P="$H/project"
mkdir -p "$D" "$P" "$T/bin" "$T/tmp" "$T/out" "$T/bodies" "$H/Applications/$EXE.app"
echo "$H/Applications/$EXE.app" > "$D/app"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
git -C "$P" init -q -b main && git -C "$P" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
P=$(cd "$P" && pwd -P)

# Each ending; with REAL_RUN_KEEP set, the run's own records (the steps, the stand-in's requests, a failed step's
# screen) are kept in that folder first, as CI keeps them with its run.
ending() {
  [ -n "${REAL_RUN_KEEP:-}" ] && mkdir -p "$REAL_RUN_KEEP" && cp -R "$T/out/." "$REAL_RUN_KEEP/" 2>/dev/null
  echo "$1"
  exit "$2"
}
. "$REPO/tests/lib.sh"
APP=$(built_app "$T") || ending "couldn't check: the app didn't compile" 3
clang -o "$T/$EXE" "$REPO/$HERE/stand-in-app.c" || ending "couldn't check: the stand-in for the panel didn't compile" 3
if [ $stand_in = yes ]; then
  printf '#!/bin/sh\nexec /usr/bin/python3 -I %q "$@"\n' "$REPO/$HERE/stand-in-claude.py" > "$T/bin/claude"
  chmod 755 "$T/bin/claude"
  version=stand-in
else
  version=$($HERE/claude-code.sh --version "${pick[@]}") || ending "couldn't check: no Claude Code version to run" 3
  WHOZMOVE_BUILD_CACHE=${WHOZMOVE_BUILD_CACHE:-$T/cache} $HERE/claude-code.sh "${pick[@]}" "$T/bin" >/dev/null ||
    ending "couldn't check: Claude Code $version didn't download" 3
fi

# The made-up key, approved in the home's state file, with onboarding done and the project trusted, so Claude Code
# opens at its prompt rather than its sign-in screens. Its last 20 characters are what Claude Code keeps of a key.
KEY="sk-ant-api03-stand-in-$(printf '0%.0s' $(seq 60))"
python3 - "$H/.claude.json" "$P" "$KEY" <<'PY'
import json, sys
json.dump({"hasCompletedOnboarding": True, "lastOnboardingVersion": "9.9.9", "theme": "dark",
           "customApiKeyResponses": {"approved": [sys.argv[3][-20:]], "rejected": []},
           "projects": {sys.argv[2]: {"hasTrustDialogAccepted": True, "hasCompletedProjectOnboarding": True}}},
          open(sys.argv[1], "w"), indent=2)
PY
STAND_IN_PROJECT="$P" STAND_IN_BODIES="$T/bodies" python3 -I "$REPO/$HERE/stand-in-api.py" "$T/port" \
  "$T/out/requests.log" >/dev/null 2>&1 &
echo $! >> "$T/pids"
disown
for i in $(seq 1 50); do [ -s "$T/port" ] && break; sleep 0.1; done
[ -s "$T/port" ] || ending "couldn't check: the stand-in server didn't start" 3

# Whozmove's plugin, put into this Claude Code as the app does as it opens.
. modules/claude-code/plugin.sh
copy_plugin "$T/hooks"
plugin=$(HOME="$H" INSTALL_PATH="$T/bin" "$APP" --print-plugin-install "$T/hooks" 2>&1)

# Nothing of the session this is run from reaches Claude Code: only these, as the app itself runs `claude`.
python3 - "$T/settings.json" <<PY
import json, sys
base = {"HOME": "$H", "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8", "TMPDIR": "$T/tmp"}
json.dump({
    "claude": "$T/bin/claude", "home": "$H", "project": "$P", "app": "$APP", "appDir": "$D", "out": "$T/out",
    "standInLog": "$T/out/requests.log", "mirror": "$T/mirror", "startModel": "claude-sonnet-5-5",
    "bodies": "$T/bodies",
    "claudeEnv": dict(base, TERM="xterm-256color", ANTHROPIC_BASE_URL="http://127.0.0.1:$(cat "$T/port")",
                      ANTHROPIC_API_KEY="$KEY", CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="1",
                      DISABLE_AUTOUPDATER="1", CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL="1"),
    "appEnv": base,
    "hookLine": ["$APP", "--print-hook-line", "25"], "hookLineSeconds": 25,
    "standInPanel": ["$T/$EXE", "$D/hook.sock", "python3", "$REPO/$HERE/stand-in-panel.py", "$T/mirror"],
}, open(sys.argv[1], "w"), indent=2)
PY
# The driver runs detached, its parent launchd, so the session it starts has no app above it on any Mac. Run from a
# terminal app, the panel would take that app for the session's and could type into it (Compact), and the record would
# say which terminal the run was started from rather than what the run did. Its pid is kept with the others, so it's
# stopped however this ends.
waiter=$(sh -c 'python3 "$1" "$2" > "$3" 2>&1 & echo $! >> "$5"; wait $!; echo $? > "$4"' sh \
  "$REPO/$HERE/pty-driver.py" "$T/settings.json" "$T/out/steps.txt" "$T/driven" "$T/pids" >/dev/null 2>&1 & echo $!)
echo "$waiter" >> "$T/pids"
while kill -0 "$waiter" 2>/dev/null; do sleep 0.5; done
driven=$(cat "$T/driven" 2>/dev/null || echo 1)

# What the app reads of it, with what changes on every run (the run's folder, ids, times) taken out.
timeless() {
  python3 -c '
import json, sys
def stable(value, key=""):
    if isinstance(value, dict):
        return {k: stable(v, k) for k, v in value.items()}
    if isinstance(value, list):
        return [stable(v) for v in value]
    if key == "pid":
        return "<pid>"
    if key == "procStart":
        return "<time>"
    # Times in milliseconds or in seconds since 1970.
    if isinstance(value, (int, float)) and not isinstance(value, bool) and (1.5e12 < value < 2.5e12 or
                                                                           1.5e9 < value < 2.5e9):
        return "<time>"
    return value
print(json.dumps(stable(json.load(sys.stdin)), indent=2, sort_keys=True, ensure_ascii=False))'
}
normal() {
  sed -e "s|$T|T|g" -e 's/[0-9a-f]\{8\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{12\}/<id>/g' \
      -e 's/[0-9a-f]\{32\}/<id>/g' -e 's/+[0-9a-f]\{8\}/+<hash>/g'
}
out=$( {
  echo "== Whozmove's plugin put in"; printf '%s\n' "$plugin" | normal
  normal < "$T/out/steps.txt"
  for f in rows mode-moves kept; do
    [ -f "$T/out/$f.json" ] || continue
    echo "== --print-$f"; timeless < "$T/out/$f.json" | normal
  done
  # Claude Code would fetch Anthropic's public plugin catalogue into its home by itself, a download the stand-in doesn't
  # see; it's switched off (claudeEnv above), and this says if it happened anyway.
  fetched=no
  [ -d "$H/.claude/plugins/marketplaces" ] && fetched=yes
  echo "== Claude Code fetched its public plugin catalogue: $fetched"
  echo "== asked of the stand-in, by kind"
  python3 -c '
import collections, json, sys
seen = collections.Counter()
for line in open(sys.argv[1]):
    r = json.loads(line)
    seen[r.get("unknown") and "unknown: " + r["unknown"] + " " + r["path"] or r.get("step") or r["path"]] += 1
for k in sorted(seen): print("  ", k)' "$T/out/requests.log"
} )
if [ $driven -eq 3 ]; then
  printf '%s\n' "$out" | tail -40
  ending "couldn't check with Claude Code $version: $(tail -1 "$T/out/steps.txt")" 3
fi
# The first run, with nothing to compare with yet, is what the next runs are compared with: kept with the run's records
# too, as a run on a throwaway Mac leaves nothing behind but them.
if [ ! -e "$expected" ] && [ ! -L "$expected" ] && [ $record_missing = yes ]; then
  printf '%s\n' "$out" > "$expected"
  echo "Nothing to compare with yet: this run records it, in $expected"
  [ -n "${REAL_RUN_KEEP:-}" ] && mkdir -p "$REAL_RUN_KEEP" && cp "$expected" "$REAL_RUN_KEEP/"
  ending "passed with Claude Code $version, recorded" 0
fi
. "$REPO/tests/compare.sh"
if compare "Whozmove with Claude Code $version" "$expected" "$out" "$update"; then
  ending "passed with Claude Code $version" 0
fi
ending "Whozmove would break with Claude Code $version: what it reads differs, above" 1
