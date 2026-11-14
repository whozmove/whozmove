# One of tests/checks.sh's rules, run in its one Python process after tests/checks/common.py, with what that makes.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
import re

# Each page's scripts share one scope.
for scope in pages.values():
    defined = {}
    for path in scope:
        text = open(path, encoding="utf-8").read()
        for name in re.findall(r"^(?:async )?function ([\w$]+)|^(?:const|let|var|class) ([\w$]+)", text, re.M):
            name = name[0] or name[1]
            defined.setdefault(name, []).append(path)
    for name, where in sorted(defined.items()):
        if len(where) > 1:
            problems.append("%s is defined in %s" % (name, " and ".join(where)))
