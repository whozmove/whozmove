# One of tests/checks.sh's rules, run in its one Python process after tests/checks/common.py, with what that makes.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

# Each part talks to the core, and to the parts its part.json names in talksTo, which must be there.
for name, spec in part_specs.items():
    for other in spec.get("talksTo", []):
        if other != "core" and other not in part_specs:
            problems.append("parts/%s/part.json names %s in talksTo, which is neither \"core\" nor a part" % (name, other))
