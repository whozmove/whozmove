# One of tests/checks.sh's rules, run in its one Python process after tests/checks/common.py, with what that makes.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
import os, re

# A service knows no domain (docs/how-it-works/modules.md, principle 2), so what decides and delivers in each one reads
# only what's its own: the state its moduleState holds, never another's (state.last, what a session is to you, the
# fold's), nor a row's field (`.ask`, any field docs/reference/rows.md names), the panel's classes
# (document.body.classList) or a part's constant (CHAT_MS). A place it draws itself (the line under the header,
# notice-line.js) reads the panel as every place does, so it isn't held to this. What was still read when the rule
# came is let through by tests/part-crossings.txt ("reads"), and that list only gets shorter.
SERVICES = {"modules/notifications": ["page/decide.js", "page/notices.js"]}

part_constants = set()
for path in sorted(p for s in pages.values() for p in s if p.startswith("parts/")):
    for line in open(path, encoding="utf-8"):
        if line.startswith("const "):
            part_constants |= set(re.findall(r"\b([A-Z][A-Z0-9_]+) =", line))
for service, deciding in SERVICES.items():
    folder = os.path.join(service, "page")
    names = os.listdir(folder) if os.path.isdir(folder) else []
    own = set()
    for name in sorted(name for name in names if name.endswith(".js")):
        text = open(os.path.join(folder, name), encoding="utf-8").read()
        for block in re.findall(r"^moduleState\(\{\n(.*?)^\}\);", text, re.M | re.S):
            own |= set(re.findall(r"^  (\w+):", block, re.M))
    for path in (os.path.join(service, name) for name in deciding):
        for number, line in enumerate(open(path, encoding="utf-8"), 1):
            line = line.split("//")[0]
            reads = ["state." + key for key in re.findall(r"\bstate\.(\w+)", line) if key not in own]
            reads += re.findall(r"\bdocument\.body\.classList\b", line)
            reads += ["." + field for field in re.findall(r"\.(\w+)\b", line) if field in row_fields]
            reads += [name for name in re.findall(r"\b[A-Z][A-Z0-9_]+\b", line) if name in part_constants]
            for what in dict.fromkeys(reads):
                if not crossing("reads", path, what):
                    problems.append("%s:%d reads %s, which isn't its own: a service knows no domain (principle 2 in "
                                    "docs/how-it-works/modules.md)" % (path, number, what))
