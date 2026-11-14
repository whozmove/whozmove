# One of tests/checks.sh's rules, run in its one Python process after tests/checks/common.py, with what that makes.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
import os, re

# A plan is approved from the panel only by an answer marked approvePlan, which the hook takes for a plan alone, and
# which only AnswerFor adds (sendApproval:), after the one check a session you allow and your press beside the list
# both go through. So no other file of the app sets it on an answer, and the page never names it: your press sends
# approveShownPlan, a message apart, which the app checks before it answers. Its print run (ClaudeCodePrints.m) sends
# one from the page on purpose, to show the hook drops it. The pattern is written so its own text doesn't match it.
APPROVE_SET = {".m": re.compile(r"@\"approve(?:Plan)\"\]?\s*[:=]"), ".js": re.compile(r"\bapprove(?:Plan)\b")}
APPROVE_SETTERS = {"modules/claude-code/app/AnswerFor.m", "modules/claude-code/app/ClaudeCodePrints.m"}
for path in sorted(set(listed_files)):
    kind = os.path.splitext(path)[1]
    if kind not in (".m", ".js") or "tests" in path.split("/") or path in APPROVE_SETTERS or not os.path.isfile(path):
        continue
    for n, line in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
        text = line.split("//")[0]
        if APPROVE_SET[kind].search(text):
            problems.append("%s:%d sets or names approvePlan: only AnswerFor adds it to an answer, after its one check, "
                            "and the page sends approveShownPlan instead" % (path, n))
