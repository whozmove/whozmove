# One of tests/checks.sh's rules, run in its one Python process after tests/checks/common.py, with what that makes.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
import os, re

# What each file imports, found as the compiler finds it: beside the file first, then on tools/compile.sh's include
# path. A module may import its own headers and the core's, contracts', shared and parts' ones; the core and the
# parts, no module's; a part, another part's only if it talks to it. A part's header is imported from outside it only
# if its part.json provides it.
def module_of(path):
    parts = os.path.normpath(path).split(os.sep)
    return parts[1] if parts[0] == "modules" and len(parts) > 2 else None
def part_of(path):
    parts = os.path.normpath(path).split(os.sep)
    return parts[1] if parts[0] == "parts" and len(parts) > 2 else None
include_path = [folder for folder in ("app", "app/core", "app/contracts", "app/shared") if os.path.isdir(folder)]
include_path += sorted(os.path.join("parts", name, "app") for name in part_specs
                       if os.path.isdir(os.path.join("parts", name, "app")))
for path in native:
    mine, my_part = module_of(path), part_of(path)
    for name in re.findall(r'^\s*#\s*(?:import|include)\s+"([^"]+)"', open(path, encoding="utf-8").read(), re.M):
        for folder in [os.path.dirname(path)] + include_path:
            found = os.path.normpath(os.path.join(folder, name))
            if os.path.isfile(found):
                theirs, their_part = module_of(found), part_of(found)
                if theirs and theirs != mine:
                    problems.append("%s imports %s, from the %s module" % (path, name, theirs))
                elif (their_part and their_part != my_part
                      and os.path.basename(found) not in part_specs.get(their_part, {}).get("provides", [])
                      and not crossing("imports", path, name)):
                    problems.append("%s imports %s, which parts/%s/part.json doesn't provide"
                                    % (path, name, their_part))
                elif (my_part and their_part and their_part != my_part
                      and their_part not in part_specs.get(my_part, {}).get("talksTo", [])
                      and not crossing("imports", path, name)):
                    problems.append("%s imports %s, from the %s part, which parts/%s/part.json doesn't name in talksTo"
                                    % (path, name, their_part, my_part))
                break
