# One of tests/checks.sh's rules, run in its one Python process after tests/checks/common.py, with what that makes.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
import os, re

# What a session may do is turned on only by your press in its mode menu: Allowed's set:for:on: and bringBack:why: are
# called from the commands module's menu (Commands.m), and from no other file, the page's messages' handlers included;
# but for a print run's own function (static int Print…), which the tests run in a throwaway home. And the file that
# offers the switches back after a restart is kept (keepTickedAt:) by the app's delegate, and by a print run's own
# function in a throwaway home, nowhere else.
for path in native:
    if os.path.normpath(path) in ("modules/commands/app/Commands.m", "app/core/Allowed.m"):
        continue
    printing = False
    for number, line in enumerate(open(path, encoding="utf-8"), 1):
        if re.match(r"static int Print\w*\(", line) and not line.rstrip().endswith(";"):
            printing = True
        elif line.startswith("}"):
            printing = False
        if not printing and re.search(r"\ballowed\s+(set|bringBack):", line):
            problems.append("%s:%d turns on what a session may do: only the mode menu's items may (Commands.m)"
                            % (path, number))

for path in native:
    if os.path.normpath(path) in ("app/core/AppDelegate.m", "app/core/Allowed.m", "app/core/Allowed.h"):
        continue
    printing = False
    for number, line in enumerate(open(path, encoding="utf-8"), 1):
        if re.match(r"static int Print\w*\(", line) and not line.rstrip().endswith(";"):
            printing = True
        elif line.startswith("}"):
            printing = False
        if not printing and re.search(r"\bkeepTickedAt:", line):
            problems.append("%s:%d keeps ticked.json: only the app's delegate may (AppDelegate.m), and a print run in a "
                            "throwaway home" % (path, number))
