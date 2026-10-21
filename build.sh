#!/bin/bash
# Builds ~/Applications/Whozmove.app from app/, modules/, panel/ and icon/, and puts it in place: the app brings the
# hooks it carries up to date as it starts. Run again after editing any of them, or a hook.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Once you've set Deploy up for Whozmove in the panel (its command is ./build.sh --now), an agent's build only
# compiles while the panel is running: Deploy, on the agent's row, puts it in place when you press it, as it would for
# any project. You running it in your terminal puts it in place at once. Inside Claude Code, a command you run with !
# carries the same mark as an agent's, so it's left to Deploy too.
set -euo pipefail
cd "$(dirname "$0")"
. tools/bundle.sh

now=no
for arg in "$@"; do
  case $arg in
    --now) now=yes ;;
    *) echo "Unknown option: $arg (there's only --now)"; exit 2 ;;
  esac
done

# The app's name, bundle id and executable are written down once, in app/Info.plist; this, tools/bundle.sh and
# install.sh read them from there, so a rename can't leave a stale copy behind (a stale signing id would quietly lose
# the Accessibility grant; a stale job label would stop the restart).
plist() { /usr/libexec/PlistBuddy -c "Print :$1" app/Info.plist; }
name=$(plist CFBundleName); bundle_id=$(plist CFBundleIdentifier); exe=$(plist CFBundleExecutable)
app="$HOME/Applications/$name.app"
# Whozmove's own folder (AppDir in app/shared/Files.m): the panel's pid, and the deploy commands you've saved (deploy.json),
# which say whether an agent's build leaves putting it in place to Deploy.
folder="$HOME/Library/Application Support/$name"
# Built aside, and put in place only once it's complete, so a failed build leaves the working app in place.
work=$(mktemp -d "${TMPDIR:-/tmp}/$exe.XXXXXX")
trap 'rm -rf "$work"' EXIT
new="$work/$name.app"
# The program, the page, the icon, swap-in.sh and the hooks (tools/bundle.sh).
make_bundle "$new"

# Where the build came from, for the panel's header (app/core/Builds.m), which names the running build by it. Also
# whether an agent built it (Claude Code marks the commands an agent runs with CLAUDECODE), whose hooks the app leaves
# as they are (modules/install), as app/swap-in.sh then says.
python3 - "$new/Contents/Resources/build.json" <<'PY'
import json, os, subprocess, sys, time

def git(*args):
    try:
        run = subprocess.run(["git", "--no-optional-locks", *args], capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return None
    return run.stdout.strip() if run.returncode == 0 else None

info = {"builtAt": int(time.time() * 1000), "root": git("rev-parse", "--show-toplevel") or os.getcwd()}
commit = git("rev-parse", "HEAD")
if commit:
    info["commit"] = commit
    branch = git("symbolic-ref", "--short", "-q", "HEAD")
    if branch:
        info["branch"] = branch
    else:
        info["detached"] = commit[:7]
    info["changes"] = bool(git("status", "--porcelain"))
    # A linked worktree, named as app/shared/Git.m names one: its folder, and the repo's main checkout it belongs to.
    here = git("rev-parse", "--absolute-git-dir")
    common = git("rev-parse", "--path-format=absolute", "--git-common-dir")
    if here and common and os.path.realpath(here) != os.path.realpath(common):
        main = os.path.dirname(common) if os.path.basename(common) == ".git" else common
        info.update(worktree=os.path.basename(info["root"]), mainRoot=main,
                    worktreeOf=os.path.splitext(os.path.basename(main))[0])
if os.environ.get("CLAUDECODE"):
    info["agent"] = True
with open(sys.argv[1], "w") as f:
    json.dump(info, f, indent=1, sort_keys=True)
PY

# Last, with build.json in it (tools/bundle.sh).
sign_bundle "$new"

# Whether to stop at compiling and leave putting the build in place to Deploy, in the panel: when an agent runs this
# (Claude Code marks the commands an agent runs with CLAUDECODE), the panel is running with Deploy's button showing, and
# you've saved a deploy command for this project there. The project is keyed as the panel keys it
# (modules/deploy/app/Deploys.m): the repo's main checkout, so its worktrees share one command. The panel's own Deploy
# runs without that mark, so it puts the build in place.
project=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
case "$project" in */.git) project=$(dirname "$project") ;; "") project=$(pwd -P) ;; esac
# Whether one of the panel's switches is on (Git's page on the panel's back has them), as the panel keeps it in its
# preferences under this home folder: one never changed is on.
switch_on() { [ "$(defaults read "$HOME/Library/Preferences/$bundle_id.plist" "$1" 2>/dev/null)" != 0 ]; }
leaves_it_to_deploy() {
  [ -n "${CLAUDECODE:-}" ] || return 1
  local pid
  pid=$(cat "$folder/panel.pid" 2>/dev/null) || return 1
  [ "$(basename "$(ps -p "$pid" -o comm= 2>/dev/null)")" = "$exe" ] || return 1
  # With Show Next Steps or Show Deploy off, no row has a Deploy button to press.
  switch_on showNextSteps && switch_on showDeploy || return 1
  python3 - "$folder/deploy.json" "$project" <<'PY'
import json, sys
try:
    command = json.load(open(sys.argv[1]))["projects"][sys.argv[2]]["command"]
except (OSError, ValueError, KeyError, TypeError):
    sys.exit(1)
sys.exit(0 if isinstance(command, str) and command else 1)
PY
}

if leaves_it_to_deploy; then
  [ "$now" = yes ] && echo "--now is for running it yourself; leaving it to Deploy in Whozmove instead."
  echo "Built, not put in place: press Deploy on this session's row in Whozmove, or run ./build.sh in a terminal" \
       "outside Claude Code."
  exit 0
fi

"$new/Contents/Resources/swap-in.sh"
echo "Built $app"
"$app/Contents/Resources/swap-in.sh" --restart
