# One of tests/checks.sh's rules, run in its one Python process after tests/checks/common.py, with what that makes.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
import os, re

# Only the gathering of notices sets who sent each and what putting one away does (contracts/NoticeGathering.h): Notice
# itself, Modules as it gathers them, and the notifications module; never a sender.
for path in native:
    path = os.path.normpath(path)
    if path in ("app/contracts/Notice.m", "parts/bridge/app/Modules.m") or path.startswith("modules/notifications/"):
        continue
    for number, line in enumerate(open(path, encoding="utf-8"), 1):
        if re.match(r'\s*#import\s+"NoticeGathering\.h"', line):
            problems.append("%s:%d imports NoticeGathering.h: only the gathering of notices may (Modules.m)"
                            % (path, number))
