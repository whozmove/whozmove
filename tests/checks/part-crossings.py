# One of tests/checks.sh's rules, run in its one Python process after tests/checks/common.py, with what that makes.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

for key in sorted(crossings - crossed):
    if not update:
        problems.append("%s lists %s, which no longer crosses: tests/checks.sh --update takes it off"
                        % (CROSSINGS, "  ".join(key)))
if update and crossings - crossed:
    with open(CROSSINGS, "w", encoding="utf-8") as f:
        f.writelines(crossings_heading)
        for key in sorted(crossings & crossed):
            f.write("  ".join(key) + "\n")
    print("Checks: saved " + CROSSINGS)
