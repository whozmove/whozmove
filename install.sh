#!/bin/bash
# Installs Whozmove: its hooks, as a Claude Code plugin, and ~/Applications/Whozmove.app, started at every login
# (and now).
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Take it all out again with: ./install.sh --uninstall
set -euo pipefail
cd "$(dirname "$0")"

# The app's name, bundle id (the login item's label) and executable, from app/Info.plist as build.sh reads them.
plist() { /usr/libexec/PlistBuddy -c "Print :$1" app/Info.plist; }
name=$(plist CFBundleName); label=$(plist CFBundleIdentifier); exe=$(plist CFBundleExecutable)
# The folders below are deleted on --uninstall, so an empty name must never get that far.
[ -n "$name" ] && [ -n "$label" ] && [ -n "$exe" ] || { echo "Couldn't read app/Info.plist"; exit 1; }
app="$HOME/Applications/$name.app"
agent="$HOME/Library/LaunchAgents/$label.plist"
domain="gui/$(id -u)"
# Whozmove's own folder (AppDir in app/Files.m), and the plugin's copy in it, which Claude Code runs the hooks
# from. The plugin and its marketplace are both called whozmove (.claude-plugin/).
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

# Hooks added to ~/.claude/settings.json by hand would run as well as the plugin's, so each would run twice.
# Only the names of the events they're under are read, with a JSON parser: the file holds secrets.
if python3 - "$HOME/.claude/settings.json" <<'PY'
import json, sys
try:
    hooks = json.load(open(sys.argv[1])).get("hooks", {})
    found = sorted(event for event, groups in hooks.items() for group in groups for hook in group.get("hooks", [])
                   if "whozmove-claude" in str(hook.get("command", "")))
except (OSError, ValueError, AttributeError, TypeError):
    found = []
if found:
    print("Whozmove's hooks are already in ~/.claude/settings.json, under " + ", ".join(found) + ".")
    print("Take those entries out first, or each hook would run twice, then run ./install.sh again.")
sys.exit(0 if found else 1)
PY
then
  exit 1
fi

[ -d "$app" ] || ./build.sh

# A copy, so that a hook being edited here reaches your sessions only when this runs again.
mkdir -p "$plugin/.claude-plugin" "$plugin/hooks"
chmod 700 "$folder"
install -S -m 644 .claude-plugin/plugin.json .claude-plugin/marketplace.json "$plugin/.claude-plugin/"
install -S -m 644 hooks/hooks.json "$plugin/hooks/"
install -S -m 755 hooks/whozmove-claude.py hooks/whozmove-claude-permission.py "$plugin/hooks/"
if command -v claude >/dev/null 2>&1; then
  claude plugin marketplace add "$plugin" >/dev/null
  claude plugin install "$id" >/dev/null
  echo "Added Whozmove's hooks to Claude Code: sessions started from now on use them."
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
