#!/bin/bash
# Installs Whozmove from this checkout: builds ~/Applications/Whozmove.app and opens it. As it opens, the app sets
# itself up, as one installed from Homebrew does: it opens at every login from then on, and adds its hooks to Claude
# Code, as a plugin.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Take it all out again with: ./install.sh --uninstall
set -euo pipefail
cd "$(dirname "$0")"

# The app's name, bundle id (its login item's label) and executable, from app/Info.plist as build.sh reads them.
plist() { /usr/libexec/PlistBuddy -c "Print :$1" app/Info.plist; }
name=$(plist CFBundleName); label=$(plist CFBundleIdentifier); exe=$(plist CFBundleExecutable)
# The folders below are deleted on --uninstall, so an empty name must never get that far.
[ -n "$name" ] && [ -n "$label" ] && [ -n "$exe" ] || { echo "Couldn't read app/Info.plist"; exit 1; }
app="$HOME/Applications/$name.app"
agent="$HOME/Library/LaunchAgents/$label.plist"
domain="gui/$(id -u)"
# Whozmove's own folder (AppDir in app/shared/Files.m), and the plugin's copy in it, which Claude Code runs the hooks
# from. The plugin and its marketplace are both called whozmove (modules/claude-code/plugin/).
folder="$HOME/Library/Application Support/$name"
plugin="$folder/plugin"
id="whozmove@whozmove"

# The running app's pid, from the one it keeps in its folder, checked to still be the app's (nothing is ever found by
# name, which could catch something else), or nothing while it isn't running.
running_pid() {
  local pid command
  pid=$(cat "$folder/panel.pid" 2>/dev/null || true)
  command=$([ -n "$pid" ] && ps -p "$pid" -o comm= 2>/dev/null || true)
  if [ -n "$command" ] && [ "$(basename "$command")" = "$exe" ]; then echo "$pid"; fi
}

# Stops the running app: its login item, and a copy started some other way, by its checked pid.
stop_app() {
  launchctl bootout "$domain/$label" 2>/dev/null || true
  local pid
  pid=$(running_pid)
  if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; fi
}

if [ "${1:-}" = "--uninstall" ]; then
  stop_app
  rm -f "$agent"
  if command -v claude >/dev/null 2>&1; then
    claude plugin uninstall "$id" >/dev/null 2>&1 || true
    claude plugin marketplace remove whozmove >/dev/null 2>&1 || true
  else
    echo "Claude Code's claude command isn't on PATH, so take the hooks out in a Claude Code session:"
    echo "  /plugin uninstall $id"
    echo "  /plugin marketplace remove whozmove"
  fi
  # Its record of setting itself up goes too, so an install after this one adds the hooks again rather than taking
  # them as ones you took out of Claude Code.
  rm -rf "$plugin" "$app" "$folder/install.json" "$folder/reloads.json"
  echo "Removed $name: the app, its login item and its hooks."
  # The rest of Whozmove's folder holds each session's last message and Claude's last reply: it goes only if you say.
  if [ -d "$folder" ]; then
    answer=
    [ -t 0 ] && { read -r -p "Also delete Whozmove's folder, with each session's last message and reply? [y/N] " \
      answer || answer=; }
    case "$answer" in
      [yY]*) rm -rf "$folder"; echo "Deleted $folder" ;;
      *) echo "Kept $folder" ;;
    esac
  fi
  exit 0
fi

# build.sh restarts a copy that was running, so only one that wasn't is opened: a second would only bow out.
was_running=$(running_pid)
./build.sh
[ -n "$was_running" ] || open "$app"
echo "$name is open: it sets itself up as it opens, and the line under its header says if it needs you."
