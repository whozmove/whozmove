# Whozmove's hooks as a Claude Code plugin (plugin/, beside this file), with every module's skills and the script a
# session asks the panel with: what's copied, and the version the copy gets. Sourced by tools/bundle.sh, which puts a
# copy in every build, and by this module's tests.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Claude Code keeps its own copy of an installed plugin, one per version, and makes a new one only for a new version,
# so a hook or a skill changed under the same version never reaches a session. Each copy made here therefore gets a
# version of its own, named after what it holds: <plugin.json's version>+<8 hex digits>. The same hooks and skills
# always get the same version, so going back to an earlier build goes back to them too.
#
# A module's skills for Claude Code are folders of its own, modules/<module>/plugin/skills/<name>/ with a SKILL.md,
# each copied whole into the plugin's skills/, where sessions find it as whozmove:<name>. The modules are looked for in
# $PLUGIN_MODULES (modules, unless a test names a sample folder).

# The script a session asks the panel with (ask-panel.sh, also in every build's Resources), carried in the plugin at
# scripts/ so a session's skills name it by the plugin's own path ("${CLAUDE_PLUGIN_ROOT}/scripts/ask-panel.sh"),
# wherever Whozmove is installed, and always the same version as the skills that name it. (Not bin/: Claude Code's
# claude.ai and Cowork skip a plugin with one.)
PLUGIN_SCRIPT=app/ask-panel.sh

# Every module's skill folders, one per line, in a fixed order; none is fine.
plugin_skills() {
  local dir
  for dir in "${PLUGIN_MODULES:-modules}"/*/plugin/skills/*/; do
    if [ -f "$dir/SKILL.md" ]; then echo "${dir%/}"; fi
  done | LC_ALL=C sort
}

# A skill's files, as paths inside its folder (./SKILL.md, ./…), in a fixed order: never the Finder's or Python's own.
skill_files() {
  (cd "$1" && find . -type f ! -name '.*' ! -path '*/__pycache__/*' | LC_ALL=C sort)
}

# Whether two modules have a skill of the same name, which would take each other's place in the copy: if so, says
# which, naming both folders, and fails.
plugin_skills_apart() {
  plugin_skills | awk -F/ '{
    if ($NF in seen) {
      print "Two modules have a skill named " $NF ": " seen[$NF] " and " $0 > "/dev/stderr"; clash = 1
    }
    else seen[$NF] = $0
  } END { exit clash }'
}

plugin_version() {
  local hash from=modules/claude-code/plugin
  # The plugin's own files (its hooks, and the script a session asks the panel with), then the skills, each by where it
  # goes in the copy and what it holds.
  hash=$({ (cd "$from" && cat .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json \
              hooks/whozmove-claude.py hooks/whozmove-claude-permission.py hooks/whozmove-claude-words.sh \
              hooks/whozmove-claude-words.py)
            cat "$PLUGIN_SCRIPT"
            plugin_skills | while read -r skill; do
              skill_files "$skill" | while read -r file; do
                echo "skills/${skill##*/}/${file#./}"
                cat "$skill/$file"
              done
            done
          } | shasum | cut -c1-8)
  echo "$(plutil -extract version raw -o - "$from/.claude-plugin/plugin.json")+$hash"
}

# A copy of the plugin in the folder $1, with that version; none when two modules' skills share a name.
copy_plugin() {
  local from=modules/claude-code/plugin skill file mode
  plugin_skills_apart || return 1
  mkdir -p "$1/.claude-plugin" "$1/hooks"
  install -S -m 644 "$from/.claude-plugin/plugin.json" "$from/.claude-plugin/marketplace.json" "$1/.claude-plugin/"
  install -S -m 644 "$from/hooks/hooks.json" "$1/hooks/"
  install -S -m 755 "$from/hooks/whozmove-claude.py" "$from/hooks/whozmove-claude-permission.py" \
    "$from/hooks/whozmove-claude-words.sh" "$from/hooks/whozmove-claude-words.py" "$1/hooks/"
  mkdir -p "$1/scripts"
  install -S -m 755 "$PLUGIN_SCRIPT" "$1/scripts/"
  plugin_skills | while read -r skill; do
    skill_files "$skill" | while read -r file; do
      mode=644
      if [ -x "$skill/$file" ]; then mode=755; fi
      mkdir -p "$1/skills/${skill##*/}/$(dirname "${file#./}")"
      install -S -m $mode "$skill/$file" "$1/skills/${skill##*/}/${file#./}"
    done
  done
  plutil -replace version -string "$(plugin_version)" "$1/.claude-plugin/plugin.json"
}
