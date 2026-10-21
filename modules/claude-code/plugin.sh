# Whozmove's hooks as a Claude Code plugin (plugin/, beside this file): what's copied, and the version the copy gets.
# Sourced by tools/bundle.sh, which puts a copy in every build, and by this module's tests.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Claude Code keeps its own copy of an installed plugin, one per version, and makes a new one only for a new version,
# so a hook changed under the same version never reaches a session. Each copy made here therefore gets a version of
# its own, named after the hooks' contents: <plugin.json's version>+<8 hex digits>. The same hooks always get the same
# version, so going back to an earlier build goes back to its hooks too.

plugin_version() {
  local hash from=modules/claude-code/plugin
  hash=$(cd "$from" && cat .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json \
    hooks/whozmove-claude.py hooks/whozmove-claude-permission.py | shasum | cut -c1-8)
  echo "$(plutil -extract version raw -o - "$from/.claude-plugin/plugin.json")+$hash"
}

# A copy of the plugin in the folder $1, with that version.
copy_plugin() {
  local from=modules/claude-code/plugin
  mkdir -p "$1/.claude-plugin" "$1/hooks"
  install -S -m 644 "$from/.claude-plugin/plugin.json" "$from/.claude-plugin/marketplace.json" "$1/.claude-plugin/"
  install -S -m 644 "$from/hooks/hooks.json" "$1/hooks/"
  install -S -m 755 "$from/hooks/whozmove-claude.py" "$from/hooks/whozmove-claude-permission.py" "$1/hooks/"
  plutil -replace version -string "$(plugin_version)" "$1/.claude-plugin/plugin.json"
}
