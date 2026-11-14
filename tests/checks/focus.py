# One of tests/checks.sh's rules, run in its one Python process after tests/checks/common.py, with what that makes.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
import re

# Every focus() says not to scroll there: WebKit centres a box focused without it that isn't wholly in view.
for path in dict.fromkeys(p for s in pages.values() for p in s):
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        for call in re.findall(r"\.focus\(([^)]*)\)", line):
            if "preventScroll: true" not in call:
                problems.append("%s:%d focuses a box without { preventScroll: true }" % (path, n))
