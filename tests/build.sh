#!/bin/bash
# Runs build.sh against a throwaway HOME (never your real ~/Applications or Whozmove's folder) and compares what it does
# with tests/build.expected.txt: when an agent's build only compiles, leaving it to Deploy in the panel, and when a
# build goes straight in; the hooks every build carries, sealed in its signature, even with a Finder tag on one, and
# left for the app to bring up to date as it opens, which an agent's build says it won't do; restarting only the app it
# replaced, the copy that's really running, with a clean environment; and building nothing on a Mac older than the
# macOS the app needs.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   tests/build.sh            run and compare
#   tests/build.sh --update   run and save the output as the new expected (after a change you meant)
# What's tested is build.sh, not the app, so each build compiles a stand-in (an empty main) for the app's code and takes a
# second or two. Needs clang, git and python3.
cd "$(dirname "$0")/.." || exit 1
. tests/sandboxed.sh "$@"
REPO=$PWD
. "$REPO/tests/lib.sh"
# Betterleaks' download is kept where your own builds keep it, so the builds below, each with a throwaway HOME, don't
# fetch it again (tools/betterleaks.sh).
export WHOZMOVE_BUILD_CACHE=${WHOZMOVE_BUILD_CACHE:-$HOME/Library/Caches/Whozmove-build}
# git here ignores your personal git settings (signing, hooks, …), so the sample repo's commit always works.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$REPO/app/Info.plist"; }
NAME=$(plist CFBundleName); EXE=$(plist CFBundleExecutable); ID=$(plist CFBundleIdentifier)
[ -n "$NAME" ] && [ -n "$EXE" ] && [ -n "$ID" ] || { echo "Couldn't read app/Info.plist"; exit 1; }
# Stops here if there's no temporary folder, before anything is made or started.
T=$(throwaway build) || exit 1
# Stand-in processes are started detached, their pids kept in $T/pids so they're stopped however this ends (with
# SIGKILL, as one of them ignores being asked).
trap 'kill -9 $(cat "$T/pids" 2>/dev/null) 2>/dev/null; rm -rf "$T"' EXIT
D="$T/Library/Application Support/$NAME"
APP="$T/Applications/$NAME.app"
# Where launchd says a login item's file is, made up (not the usual place, so the file it names is seen to be the one
# loaded).
AGENT_FILE="$T/Elsewhere/$ID.plist"

# The files a build is made from, as a repo of their own, with a stand-in for the app's sources; and a worktree of it.
mkdir -p "$T/repo" "$D"
(cd "$REPO" && tar -cf - build.sh tools app/Info.plist app/swap-in.sh app/ask-panel.sh icon/AppIcon.icns panel \
   $(ls -d parts modules 2>/dev/null)) | tar -C "$T/repo" -xf -
# The app's own code isn't needed: one stand-in file compiles in its place.
find "$T/repo" -name '*.m' -delete
printf 'int main(void) { return 0; }\n' > "$T/repo/app/main.m"
# A Finder tag on one of its hooks (Finder information, which codesign refuses in a bundle), so the builds from it
# below sign a bundle the tag would go into.
xattr -wx com.apple.FinderInfo 0000000000000000000C00000000000000000000000000000000000000000000 \
  "$T/repo/modules/claude-code/plugin/hooks/whozmove-claude.py"
git -C "$T/repo" init -q -b main
git -C "$T/repo" add -A
git -C "$T/repo" -c user.email=t@t -c user.name=t commit -q -m init
git -C "$T/repo" worktree add -q "$T/fix-hover" -b fix-hover
# A stand-in for the panel: a process with the app's name (compiled: macOS kills a copied system binary), and one that
# also writes down the environment it was started with. And one for launchctl, whose login item is what $T/job says
# (none without it), and which writes down what it's asked to do.
printf '#include <unistd.h>\nint main(void){sleep(600);return 0;}\n' > "$T/sleeper.c"
cat > "$T/telling.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
extern char **environ;
int main(void) {
  char path[4096];
  snprintf(path, sizeof path, "%s/started-with", getenv("HOME") ? getenv("HOME") : "/nowhere");
  FILE *f = fopen(path, "w");
  for (char **e = environ; f && *e; e++) fprintf(f, "%s\n", *e);
  if (f) fclose(f);
  sleep(600);
  return 0;
}
C
mkdir -p "$T/stand-in" "$T/bin"
clang -o "$T/stand-in/$EXE" "$T/sleeper.c" || exit 1
clang -o "$T/telling" "$T/telling.c" || exit 1
# A bootstrap fails as many times as $T/bootstrap-fails says (none without it), as launchd does for a moment after a
# bootout.
cat > "$T/bin/launchctl" <<SH
#!/bin/bash
if [ "\$1" = print ]; then cat "$T/job" 2>/dev/null || exit 113; exit; fi
echo "launchctl \$*" >> "$T/launchctl.log"
if [ "\$1" = bootstrap ] && [ "\$(cat "$T/bootstrap-fails" 2>/dev/null || echo 0)" -gt 0 ]; then
  echo \$(( \$(cat "$T/bootstrap-fails") - 1 )) > "$T/bootstrap-fails"
  exit 5
fi
exit 0
SH
chmod +x "$T/bin/launchctl"

tests() {
# Runs a command in a checkout as you'd run it in your terminal (with an agent's marks taken off, since this test may
# itself be run by one), with the throwaway home, the stand-in launchctl, and any VAR=value given first.
run_in() {
  local dir=$1; shift
  (cd "$dir" && env -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID HOME="$T" PATH="$T/bin:$PATH" "$@" 2>&1)
}
# A deploy command saved for the repo in the panel (modules/deploy/app/Deploys.m), or none.
saved() { printf '{"projects": {"%s": {"command": "./build.sh --now"}}}\n' "$T/repo" > "$D/deploy.json"; }
unsaved() { rm -f "$D/deploy.json"; }
panel_up() { detached "$T/stand-in/$EXE" > "$D/panel.pid"; }
panel_down() { kill "$(cat "$D/panel.pid")"; }
# What a build recorded about where it came from (build.json), on one line.
recorded() {
  python3 - "$1/Contents/Resources/build.json" <<'PY'
import json, sys
try:
    b = json.load(open(sys.argv[1]))
except OSError:
    print("none"); sys.exit()
print(" ".join(f"{k}={b[k]}" for k in sorted(b) if k not in ("builtAt", "commit")),
      "commit:", len(b.get("commit", "")), "digits")
PY
}
installed() { echo "installed: $(recorded "$APP")"; }
# The entitlements the signed program or bundle $2 asks for, each with its value, after the words $1.
entitlements() {
  codesign --display --entitlements - --xml "$2" 2>/dev/null >"$T/entitlements.plist"
  python3 - "$1" "$T/entitlements.plist" <<'PY'
import plistlib, sys
try:
    asked = plistlib.load(open(sys.argv[2], "rb"))
except (OSError, plistlib.InvalidFileException, ValueError):
    asked = {}
print(sys.argv[1] + ":", ", ".join(f"{k} = {asked[k]}" for k in sorted(asked)) or "none")
PY
}
# Whether the program $1 is signed to run with the hardened runtime.
hardened() { grep -q '^CodeDirectory .*flags=0x[0-9a-f]*([^)]*runtime' <<<"$(codesign --display --verbose "$1" 2>&1)"; }
# The hooks the app in place carries, and whether its signature covers them: a copy of it checks out, until a hook in
# it is changed. And the script a session asks the panel with, ready to run. How it's signed: with the hardened
# runtime, Betterleaks inside too, and the entitlements it asks for, each with its value.
carried() {
  local hooks=Contents/Resources/plugin
  echo "it carries the hooks: $(plutil -extract version raw -o - "$APP/$hooks/.claude-plugin/plugin.json")"
  [ -x "$APP/Contents/Resources/ask-panel.sh" ] && echo "and ask-panel.sh" || echo "but not ask-panel.sh"
  codesign --verify --strict "$APP" 2>/dev/null && echo "its signature checks out" || echo "its signature is broken"
  hardened "$APP" && echo "it runs with the hardened runtime" || echo "it runs without the hardened runtime"
  hardened "$APP/Contents/Helpers/betterleaks" && echo "and so does Betterleaks inside" \
    || echo "but Betterleaks inside doesn't"
  entitlements "its entitlements" "$APP"
  entitlements "Betterleaks' entitlements" "$APP/Contents/Helpers/betterleaks"
  rm -rf "$T/changed.app"
  cp -R "$APP" "$T/changed.app"
  codesign --verify --strict "$T/changed.app" 2>/dev/null && echo "an unchanged copy checks out" \
    || echo "an unchanged copy doesn't check out"
  echo "# changed" >> "$T/changed.app/$hooks/hooks/whozmove-claude.py"
  codesign --verify --strict "$T/changed.app" 2>/dev/null && echo "with a hook changed, it still checks out" \
    || echo "with a hook changed, it no longer checks out"
  rm -rf "$T/changed.app"
}
# Whether the app in the stand-in ~/Applications changed since the last look.
before=
changed() {
  local now
  now=$(stat -f %m "$APP/Contents/MacOS/$EXE" 2>/dev/null)
  [ "$now" != "$before" ] && echo "the app in ~/Applications: replaced" || echo "the app in ~/Applications: as it was"
  before=$now
}

echo "== 1 an agent, with no deploy command saved: straight into ~/Applications, and nothing else is restarted"
unsaved; panel_up
run_in "$T/repo" CLAUDECODE=1 ./build.sh
installed; changed; carried

echo "== 2 an agent, with Whozmove's deploy command saved and the panel running: it only compiles"
saved
sleep 1  # so a replaced app shows a new time
run_in "$T/repo" CLAUDECODE=1 ./build.sh
changed

echo "== 3 an agent in a worktree (the repo's command covers it), even with --now: it only compiles"
run_in "$T/fix-hover" CLAUDECODE=1 ./build.sh --now
changed

echo "== 3b the same with Show Deploy off in the panel, so no row has the button to press: straight in"
mkdir -p "$T/Library/Preferences"
defaults write "$T/Library/Preferences/$ID.plist" showDeploy -bool false
sleep 1
run_in "$T/repo" CLAUDECODE=1 ./build.sh
changed
defaults delete "$T/Library/Preferences/$ID.plist" showDeploy
sleep 1  # so the next build's app shows a new time

echo "== 4 you, in your terminal: straight in"
run_in "$T/fix-hover" ./build.sh
installed; changed

echo "== 5 an agent, with the command saved but the panel not running: straight in"
panel_down
sleep 1
run_in "$T/repo" CLAUDECODE=1 ./build.sh
installed; changed

echo "== 6 a build leaves the hooks in Whozmove's folder as they are: the app brings them up to date as it opens"
mkdir -p "$D/plugin/.claude-plugin"
echo '{"name": "whozmove", "version": "0.0.1+00000000"}' > "$D/plugin/.claude-plugin/plugin.json"
run_in "$T/repo" ./build.sh
echo "the hooks in Whozmove's folder: $(plutil -extract version raw -o - "$D/plugin/.claude-plugin/plugin.json")"

echo "== 7 an agent's build leaves them too, as the app it makes won't bring them up to date, and says how to"
run_in "$T/repo" CLAUDECODE=1 ./build.sh
echo "the hooks in Whozmove's folder: $(plutil -extract version raw -o - "$D/plugin/.claude-plugin/plugin.json")"

echo "== 8 restarting: the app running from ~/Applications is, the stand-in running from elsewhere isn't; the new copy"
echo "   starts with nothing of the environment of what restarted it (an agent's, here) but who and where you are"
run_in "$T/repo" "$APP/Contents/Resources/swap-in.sh" --restart; echo "exit=$?"
cp "$T/telling" "$APP/Contents/MacOS/$EXE"
old=$(detached env HOME="$T" "$APP/Contents/MacOS/$EXE")
echo "$old" > "$D/panel.pid"
sleep 0.5
rm -f "$T/started-with"
run_in "$T/repo" CLAUDECODE=1 CLAUDE_CODE_MESSAGING_TOKEN=secret ANTHROPIC_BASE_URL=http://example.invalid \
  "$APP/Contents/Resources/swap-in.sh" --restart; echo "exit=$?"
kill -0 "$old" 2>/dev/null && echo "the old one is still running" || echo "the old one has stopped"
new=$(running_from "$APP/Contents/MacOS/$EXE")
echo "$new" >> "$T/pids"
[ -n "$new" ] && echo "a new one is running from T/Applications" || echo "nothing new is running"
for _ in $(seq 50); do [ -s "$T/started-with" ] && break; sleep 0.1; done
echo "it started with: $(sed -n 's/=.*//p' "$T/started-with" | grep -v -e '^__CF_' -e '^LANG$' -e '^SSH_AUTH_SOCK$' \
  -e '^TMPDIR$' -e '^SHELL$' | sort | paste -sd ' ' -) (HOME=$(sed -n 's/^HOME=//p' "$T/started-with"))"

echo "== 9 one that doesn't quit when asked is made to, and only then started again"
kill $new 2>/dev/null
printf '#include <signal.h>\n#include <unistd.h>\nint main(void){signal(SIGTERM,SIG_IGN);sleep(600);return 0;}\n' \
  > "$T/stubborn.c"
clang -o "$T/stubborn" "$T/stubborn.c" || exit 1
rm -f "$APP/Contents/MacOS/$EXE"
cp "$T/stubborn" "$APP/Contents/MacOS/$EXE"
old=$(detached "$APP/Contents/MacOS/$EXE")
echo "$old" > "$D/panel.pid"
run_in "$T/repo" "$APP/Contents/Resources/swap-in.sh" --restart; echo "exit=$?"
kill -0 "$old" 2>/dev/null && echo "the old one is still running" || echo "the old one has stopped"
new=$(running_from "$APP/Contents/MacOS/$EXE")
echo "$new" >> "$T/pids"
[ -n "$new" ] && echo "a new one is running from T/Applications" || echo "nothing new is running"

echo "== 10 the login item runs the app, but the copy running is one opened another way (after Quit): that copy is"
echo "   stopped first, as the login item's new one would bow out to it, then the login item is restarted"
kill -9 $new 2>/dev/null
rm -f "$APP/Contents/MacOS/$EXE"
cp "$T/stand-in/$EXE" "$APP/Contents/MacOS/$EXE"
other=$(detached "$APP/Contents/MacOS/$EXE")
echo "$other" > "$D/panel.pid"
printf 'gui/1/%s = {\n\tpath = %s\n\tprogram = %s\n}\n' "$ID" "$AGENT_FILE" "$APP/Contents/MacOS/$EXE" > "$T/job"
run_in "$T/repo" "$APP/Contents/Resources/swap-in.sh" --restart; echo "exit=$?"
kill -0 "$other" 2>/dev/null && echo "the copy opened another way is still running" \
  || echo "the copy opened another way has stopped"
echo "launchctl was asked:"; cat "$T/launchctl.log"

echo "== 11 the login item's own copy is the one running: just the login item is restarted"
rm -f "$T/launchctl.log"
own=$(detached "$APP/Contents/MacOS/$EXE")
echo "$own" > "$D/panel.pid"
# What launchd prints for the job on macOS 27.2: a block of nested lines tying it to the build it loaded, which the
# lines before and after it must not be mistaken for.
printf 'gui/1/%s = {\n\tpath = %s\n\tLWCR = {\n\t\t"reqs" => {\n\t\t\t"cdhash" => {\n\t\t\t\t"$in" => [\n' \
  "$ID" "$AGENT_FILE" > "$T/job"
printf '\t\t\t\t\t0 = 3f786850e387550fdab836ed7e6dc881de23001b\n\t\t\t\t]\n\t\t\t}\n\t\t}\n' >> "$T/job"
printf '\t\t"vers" => 1\n\t}\n' >> "$T/job"
printf '\tpid = %s\n\tprogram = %s\n}\n' "$own" "$APP/Contents/MacOS/$EXE" >> "$T/job"
run_in "$T/repo" "$APP/Contents/Resources/swap-in.sh" --restart; echo "exit=$?"
kill -0 "$own" 2>/dev/null && echo "its copy is left to launchctl to restart" || echo "its copy was stopped"
echo "launchctl was asked:"; cat "$T/launchctl.log"

echo "== 11b the job names no file it came from: the usual place for a login item is loaded"
rm -f "$T/launchctl.log"
printf 'gui/1/%s = {\n\tpid = %s\n\tprogram = %s\n}\n' "$ID" "$own" "$APP/Contents/MacOS/$EXE" > "$T/job"
run_in "$T/repo" "$APP/Contents/Resources/swap-in.sh" --restart; echo "exit=$?"
echo "launchctl was asked:"; cat "$T/launchctl.log"

echo "== 11c loading it fails for a moment after it was unloaded: it's tried again"
rm -f "$T/launchctl.log"
echo 3 > "$T/bootstrap-fails"
run_in "$T/repo" "$APP/Contents/Resources/swap-in.sh" --restart; echo "exit=$?"
echo "launchctl was asked:"; cat "$T/launchctl.log"

echo "== 11d loading it never works: this build is started on its own, with the login item's copy gone"
rm -f "$T/launchctl.log"
kill "$own" 2>/dev/null
printf 'gui/1/%s = {\n\tpath = %s\n\tprogram = %s\n}\n' "$ID" "$AGENT_FILE" "$APP/Contents/MacOS/$EXE" > "$T/job"
echo 1000 > "$T/bootstrap-fails"
run_in "$T/repo" "$APP/Contents/Resources/swap-in.sh" --restart; echo "exit=$?"
echo "launchctl was asked $(grep -c bootstrap "$T/launchctl.log") times to load it"
new=$(running_from "$APP/Contents/MacOS/$EXE")
echo "$new" >> "$T/pids"
echo "copies running from T/Applications: $(grep -c . <<< "$new")"
kill $new 2>/dev/null

echo "== 11e loading it never works, and this build won't start on its own either: it says how to start it"
printf 'int main(void){return 0;}\n' > "$T/quitter.c"
clang -o "$T/quitter" "$T/quitter.c" || exit 1
rm -f "$APP/Contents/MacOS/$EXE"
cp "$T/quitter" "$APP/Contents/MacOS/$EXE"
echo 1000 > "$T/bootstrap-fails"
run_in "$T/repo" "$APP/Contents/Resources/swap-in.sh" --restart; echo "exit=$?"
rm -f "$T/job" "$T/bootstrap-fails"

echo "== 12 a Mac older than the macOS the app needs: nothing is built, and the app in place stays"
mkdir -p "$T/older"
printf '#!/bin/bash\necho 14.6\n' > "$T/older/sw_vers"
chmod +x "$T/older/sw_vers"
changed > /dev/null
sleep 1
run_in "$T/repo" PATH="$T/older:$T/bin:$PATH" ./build.sh; echo "exit=$?"
changed

# A signing keychain (tools/signing.sh) stands in as a plain file in the throwaway home: the build only asks whether
# it's there and what it holds, and making a real one would add it to the keychains macOS searches for you.
mkdir -p "$T/Library/Keychains"
echo "not a keychain" > "$T/Library/Keychains/whozmove-signing.keychain-db"

echo "== 13 with a signing keychain here, an agent's build is ad hoc and never goes in, with no deploy command saved"
unsaved
sleep 1
run_in "$T/repo" CLAUDECODE=1 ./build.sh; echo "exit=$?"
changed

echo "== 14 you, with a signing keychain that holds no certificate that works: nothing is built, and nothing goes in"
sleep 1
run_in "$T/repo" ./build.sh; echo "exit=$?"
changed
rm -f "$T/Library/Keychains/whozmove-signing.keychain-db"
}

# What changes from run to run made stable: the throwaway folder becomes T, build.sh's work folder <work>, the hooks'
# hash <hash>, your user id in launchd's names <uid>.
out=$(tests 2>&1 | sed -e "s|$T|T|g" -e "s|^.*/$EXE\.[A-Za-z0-9]\{6\}/|<work>/|" -e 's/+[0-9a-f]\{8\}/+<hash>/g' \
                       -e 's|gui/[0-9]*\([ /]\)|gui/<uid>\1|g')
. "$REPO/tests/compare.sh"
compare Build "$REPO/tests/build.expected.txt" "$out" "${1:-}"
