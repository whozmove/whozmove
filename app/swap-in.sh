#!/bin/bash
# Puts a finished build of Whozmove in place, and restarts the app on it, which brings the hooks it carries up to date
# as it starts (modules/install), unless an agent made the build, which this then says. build.sh copies this into every
# build (Contents/Resources) and runs it, the one and then the other:
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
#   swap-in.sh            puts the build this copy is in in place
#   swap-in.sh --restart  restarts the app in ~/Applications, if it's running from there
set -uo pipefail

here=$(cd "$(dirname "$0")/../.." && pwd -P)  # the app bundle this copy is in
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$here/Contents/Info.plist" 2>/dev/null; }
name=$(plist CFBundleName); bundle_id=$(plist CFBundleIdentifier); exe=$(plist CFBundleExecutable)
[ -n "$name" ] && [ -n "$bundle_id" ] && [ -n "$exe" ] || { echo "Couldn't read the build's Info.plist" >&2; exit 1; }
app="$HOME/Applications/$name.app"
program="$app/Contents/MacOS/$exe"
# Whozmove's own folder (AppDir in app/shared/Files.m): its log, the panel's pid, and the copy of the hooks Claude Code
# reads (the Claude Code module's PluginFolder).
folder="$HOME/Library/Application Support/$name"

# Said here, and written to the panel's log (in its format) when there is one.
say() {
  echo "$*"
  [ -d "$folder" ] && echo "$(date -u '+%Y-%m-%d %H:%M:%S +0000')  swap-in: $*" >> "$folder/panel.log"
  return 0
}

if [ "${1:-}" = "--restart" ]; then
  # Stops a running copy, and waits until it has gone: a new copy started while the old one is still there bows out
  # (main.m), and the old one would then leave no panel at all. One that doesn't end when asked is made to.
  stop() {
    kill "$1" 2>/dev/null
    for _ in $(seq 50); do kill -0 "$1" 2>/dev/null || return 0; sleep 0.1; done
    kill -9 "$1" 2>/dev/null
    for _ in $(seq 20); do kill -0 "$1" 2>/dev/null || return 0; sleep 0.1; done
    say "Couldn't stop $name (pid $1), so it wasn't restarted: quit it and open it again"
    return 1
  }
  # Only what runs this very app is restarted. The login item and the panel's pid are the Mac's own and the home
  # folder's, so a build for another home (a test's throwaway one) would otherwise restart the panel you're using.
  # The copy running now is found by the pid the app keeps in its folder, checked to be this app's. A copy running from
  # anywhere else is named instead: this build, opened, would only bow out to it (main.m).
  pid=$(cat "$folder/panel.pid" 2>/dev/null || true)
  running=$([ -n "$pid" ] && ps -p "$pid" -o comm= 2>/dev/null)
  if [ "$running" != "$program" ]; then
    pid=
    if [ "${running##*/}" = "$exe" ]; then
      say "$name is running from ${running%/Contents/MacOS/*}, so nothing was restarted: quit it, then open $app" \
          "to run this build"
      exit 0
    fi
  fi
  job="gui/$(id -u)/$bundle_id"
  job_info=$(launchctl print "$job" 2>/dev/null || true)
  if [ "$(sed -n 's/^[[:space:]]*program = //p' <<< "$job_info" | head -1)" = "$program" ]; then
    # The login item runs this app. A copy running that isn't the login item's own (it was quit, then opened from
    # Finder) is stopped first, as the login item's new copy would bow out to it.
    job_pid=$(sed -n 's/^[[:space:]]*pid = //p' <<< "$job_info" | head -1)
    if [ -n "$pid" ] && [ "$pid" != "$job_pid" ]; then stop "$pid" || exit 1; fi
    launchctl kickstart -k "$job" && say "Restarted $name (its login item)"
    exit
  fi
  # Started some other way.
  if [ -n "$pid" ]; then
    stop "$pid" || exit 1
    # Started as the login item starts it: with this home folder (a test's throwaway one stays its own) and what
    # macOS gives an app, but nothing else of the shell that ran this. That may be an agent's, and the panel would
    # pass it on to every deploy.
    clean=(HOME="$HOME" USER="$(id -un)" LOGNAME="$(id -un)" PATH=/usr/bin:/bin:/usr/sbin:/sbin)
    for var in SHELL TMPDIR LANG SSH_AUTH_SOCK __CF_USER_TEXT_ENCODING; do
      [ -n "${!var:-}" ] && clean+=("$var=${!var}")
    done
    env -i "${clean[@]}" nohup "$program" >/dev/null 2>&1 &
    say "Restarted $name (the copy running from $app)"
  elif [ "$(plutil -extract agent raw -o - "$here/Contents/Resources/build.json" 2>/dev/null)" = true ]; then
    say "$name isn't running, so nothing was restarted: open it to run this build"
  else
    say "$name isn't running, so nothing was restarted: open it to run this build, and it brings its hooks up to" \
        "date as it starts"
  fi
  exit 0
fi

# The folder the build is in: build.sh's work folder.
from=$(dirname "$here")

fail() {
  say "Couldn't put $name in place: $1"
  exit 1
}

codesign --verify --strict "$here" 2>/dev/null || fail "the build is incomplete, or its signature is broken"
mkdir -p "$HOME/Applications" || fail "couldn't make ~/Applications"
# The app in place goes aside first, and comes back if the build can't take its place, so there's always one there.
aside="$from/previous.app"
rm -rf "$aside"
if [ -e "$app" ]; then mv "$app" "$aside" || fail "couldn't move the app in ~/Applications aside"; fi
if ! mv "$here" "$app"; then
  [ -e "$aside" ] && mv "$aside" "$app"
  fail "couldn't move the build into ~/Applications"
fi
rm -rf "$aside"
# Re-registered so Finder, Spotlight and the Dock pick up the icon of the fresh bundle. Not for a test's throwaway
# home: macOS would then know two apps with this id.
own_home=$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory 2>/dev/null | sed 's/^NFSHomeDirectory: //')
if [ "$HOME" = "$own_home" ]; then
  lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  "$lsregister" -f "$app" || true
fi

# The hooks this build carries go into Claude Code as the app starts (modules/install), but not from a build an agent
# made (build.sh records Claude Code's CLAUDECODE mark in its build.json): every session you start would run them, and
# an agent's may be half-way through a change. So such a build says when they aren't the ones in Whozmove's folder,
# which Claude Code reads, and how to put them in place. Their version names their contents
# (modules/claude-code/plugin.sh).
version() { plutil -extract version raw -o - "$1/.claude-plugin/plugin.json" 2>/dev/null; }
if [ "$(plutil -extract agent raw -o - "$app/Contents/Resources/build.json" 2>/dev/null)" = true ] \
    && [ -f "$folder/plugin/.claude-plugin/plugin.json" ] \
    && [ "$(version "$app/Contents/Resources/plugin")" != "$(version "$folder/plugin")" ]; then
  say "The app is in place, but its hooks aren't, as an agent built it: run ./build.sh in your terminal, or press" \
      "Deploy, to put them in place too"
fi

exit 0
