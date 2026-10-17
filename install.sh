#!/bin/bash
# Installs Whozmove: its hooks, as a Claude Code plugin, and ~/Applications/Whozmove.app, started at every login
# (and now).
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Take it all out again with: ./install.sh --uninstall
set -euo pipefail
cd "$(dirname "$0")"
. modules/claude-code/plugin.sh

# The app's name, bundle id (the login item's label) and executable, from app/Info.plist as build.sh reads them.
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

# Stops the running app: its login item, and a copy started some other way, by the pid the app keeps in its folder.
# That pid is checked to still be the app's, and nothing is ever stopped by name, which could catch something else.
stop_app() {
  launchctl bootout "$domain/$label" 2>/dev/null || true
  local pid command
  pid=$(cat "$folder/panel.pid" 2>/dev/null || true)
  command=$([ -n "$pid" ] && ps -p "$pid" -o comm= 2>/dev/null || true)
  if [ -n "$command" ] && [ "$(basename "$command")" = "$exe" ]; then kill "$pid" 2>/dev/null || true; fi
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
  rm -rf "$plugin" "$app"
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

[ -d "$app" ] || ./build.sh

# A copy, so that a hook being edited here reaches your sessions only when this (or ./build.sh) runs again. Its
# version names the hooks' contents (modules/claude-code/plugin.sh).
mkdir -p "$plugin"
chmod 700 "$folder"
copy_plugin "$plugin"
if command -v claude >/dev/null 2>&1; then
  claude plugin marketplace add "$plugin" >/dev/null
  claude plugin install "$id" >/dev/null
  # Already installed, Claude Code keeps the copy it made until it's told of a new version. If it can't be told (no
  # network, say), the hooks it has keep working, so that's said and the install goes on to the login item.
  if claude plugin marketplace update whozmove >/dev/null && claude plugin update "$id" >/dev/null; then
    echo "Added Whozmove's hooks to Claude Code: sessions started from now on use them."
  else
    echo "Added Whozmove's hooks, but Claude Code couldn't take this version of them yet: run ./install.sh again later."
  fi
else
  echo "Claude Code's claude command isn't on PATH, so add the hooks in a Claude Code session:"
  echo "  /plugin marketplace add \"$plugin\""
  echo "  /plugin install $id"
fi

stop_app
mkdir -p "$(dirname "$agent")"
sed -e "s|__LABEL__|$label|" -e "s|__APP__|$app|" -e "s|__EXE__|$exe|" app/login-item.plist > "$agent"
launchctl bootstrap "$domain" "$agent"
echo "$name will start at login (and is running now)."
