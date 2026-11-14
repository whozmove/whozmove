# One of tests/checks.sh's rules, run in its one Python process after tests/checks/common.py, with what that makes.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
import os

# The README names each macOS permission the app asks for, and no file in the project names one it doesn't.
def read(path):
    return open(path, encoding="utf-8").read()
code = "".join(open(os.path.join(d, name), encoding="utf-8").read()
               for top in ("app", "parts", "modules") for d, _, files in sorted(os.walk(top))
               for name in sorted(files) if name.endswith(".m"))
# Each permission by the name macOS gives it, and the call that shows the app asks for it. The README must tell
# people about each one the app asks for; once it stops asking for one, every mention of it has to go too, but in the
# licence and in this rule.
asks = {"Accessibility": "AXIsProcessTrusted" in code, "Automation": "NSAppleScript" in code,
        "Full Disk Access": "Privacy_AllFiles" in code}
for permission, asked in asks.items():
    if asked:
        if permission not in read("README.md"):
            problems.append("README.md doesn't name %s, which the app asks for" % permission)
        continue
    for path in listed_files:
        if path in ("", "LICENSE", "tests/checks/permissions.py") or not os.path.isfile(path):
            continue
        try:
            if permission in read(path):
                problems.append("%s still names %s, which the app no longer asks for" % (path, permission))
        except (OSError, UnicodeDecodeError):
            pass  # an image or the icon
# macOS shows this text when it asks for Automation, so it's there exactly while the app sends Apple Events.
if ("NSAppleEventsUsageDescription" in read("app/Info.plist")) != asks["Automation"]:
    problems.append("app/Info.plist's NSAppleEventsUsageDescription doesn't match whether the app sends Apple Events")
