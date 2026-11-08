#!/bin/sh
# Whozmove's words hook, on PostToolBatch and Stop: your words from a session's side chat, handed in between its steps
# (whozmove-claude-words.py). Most steps have nothing waiting, so it looks for Whozmove's flag first, and ends at once
# without starting Python while there's none. The flag's folder must match AppDir in app/shared/Files.m.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
[ -e "$HOME/Library/Application Support/Whozmove/words-waiting" ] || exit 0
exec python3 -I "$(dirname "$0")/whozmove-claude-words.py"
