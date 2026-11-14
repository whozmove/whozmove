# One of tests/checks.sh's rules, run in its one Python process after tests/checks/common.py, with what that makes.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
import os, re

# Whozmove acts on another app (an Apple event, an Accessibility press or a set value, a posted key, a link or a file
# opened in it) only through app/shared's AppleEvents.m, AppleScript.m, Accessibility.m and Links.m, which do nothing
# while this run's home isn't surely your own (MayActOnOtherApps), so no test, print run or copy given a throwaway home
# drives your apps. A way to act written anywhere else in the app would go round that, so it fails here. Launching an
# app, or bringing one forward, isn't acting on it.
OTHER_APP_WAYS = re.compile(r"\b(NSAppleScript|OSAScript|NSUserAppleScriptTask|NSUserScriptTask|sendEventWithOptions|"
                            r"AESendMessage|AESend|AEDeterminePermissionToAutomateTarget|SBApplication|osa(?:script)|"
                            r"AXUIElementPerformAction|AXUIElementSetAttributeValue|AXUIElementPostKeyboardEvent|"
                            r"CGEventPost|CGEventPostToPid|CGEventPostToPSN|openURLs?)\b")
GUARDED = ("app/shared/AppleEvents.m", "app/shared/AppleScript.m", "app/shared/Accessibility.m",
           "app/shared/Links.m")
# macOS's open is the same opening by another door: run as a program (its path, or "open" given to one of
# Processes.h's runners), it's let through only where the app opens itself again after an update.
OPEN_RUN = re.compile(r"/usr/bin/op(?:en)\b|\b(?:RunTool|SpawnDetached|RunBriefly|RunConversation|RunFeeding|"
                      r"RunInCheckout)\(\s*@\"op(?:en)\"")
OPEN_RUN_WHERE = ("modules/install/app/InstallModule.m",)
for top in ("app", "parts", "modules"):
    for folder, folders, files in os.walk(top):
        folders[:] = sorted(f for f in folders if f not in ("tests", "page", "plugin"))
        for name in sorted(files):
            path = os.path.join(folder, name)
            comment = "#" if name.endswith((".sh", ".py")) else "//"
            if not name.endswith((".m", ".h", ".c", ".sh", ".py")) or path in GUARDED:
                continue
            for at, line in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
                found = None if line.lstrip().startswith(comment) else OTHER_APP_WAYS.search(line) or (
                    path not in OPEN_RUN_WHERE and OPEN_RUN.search(line))
                if found:
                    problems.append("%s:%d acts on another app with %s, round the check that a throwaway home does "
                                    "nothing: use AppleEvents.h, AppleScript.h, Accessibility.h or Links.h"
                                    % (path, at, found.group(1) if found.re is OTHER_APP_WAYS else "open"))
