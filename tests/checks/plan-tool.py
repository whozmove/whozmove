# One of tests/checks.sh's rules, run in its one Python process after tests/checks/common.py, with what that makes.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
import os, re

# Claude Code's plan request is its module's to read and answer: another module that shows a plan Claude waits on (the
# reader) asks core.planAsks, which says it in the panel's own words and sends the messages that answer it, so its
# tool's name, and those messages, are named in that module alone. The patterns are written so their own text doesn't
# match them.
PLAN_TOOL = re.compile(r"\bExit(?:PlanMode)\b|'(?:answer|hold)(?:Ask)'|'approve(?:Shown)Plan'")
for path in sorted(set(listed_files)):
    if os.path.splitext(path)[1] not in (".m", ".h", ".js") or "tests" in path.split("/") \
            or path.startswith("modules/claude-code/") or not os.path.isfile(path):
        continue
    for n, line in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
        if PLAN_TOOL.search(line.split("//")[0]):
            problems.append("%s:%d names Claude Code's plan tool or a message that answers it: only its module reads "
                            "its requests and answers them, and the others ask core.planAsks" % (path, n))
