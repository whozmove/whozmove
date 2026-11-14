# One of tests/checks.sh's rules, run in its one Python process after tests/checks/common.py, with what that makes.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
import os, re

# The project is public, so nothing in it names someone's own tracker: a Jira site's address says whose it is, and a
# ticket's key names their space. Every site in the project, in code, tests and docs alike, is a made-up one (acme,
# beta, and a.b, a nested name that's turned away), and every key is in a made-up space (PAY and WEB in the Jira
# module's tests, ABC in the tickets module's made-up tracker). A word shaped like a key that names a standard (GPL-3,
# SHA-256, UTF-8, CRC-32) isn't a ticket's. And no code decides by a ticket's status or step name, as the tickets
# module's rules say: a ticket's next steps come from its tracker each time, by the ids it gives, so a state's or a
# step's name is only shown, never compared with words written in. The patterns are written so their own text doesn't
# match them.
TRACKER_SITE = re.compile(r"\b((?:[a-z0-9-]+\.)*[a-z0-9-]+)\.(?:atlassian|jira)\.(?:net|com)\b", re.I)
TRACKER_HOSTS = {"atlassian.net", "jira.com"}
MADE_UP_SITES = {"acme", "beta", "a.b"}
TICKET_KEY = re.compile(r"(?<![-\w])([A-Z][A-Z0-9]{1,9})-[0-9]+\b")
MADE_UP_SPACES = {"PAY", "WEB", "ABC"}
NOT_TICKETS = {"GPL", "SHA", "UTF", "CRC"}
NAME_DECIDED = re.compile(r"\b(?:state|step|status)\w*\.name\s*(?:isEqualToString:\s*@\"|[!=]==?\s*['\"])", re.I)
named = set()
for path in sorted(set(listed_files)):
    if not path or not os.path.isfile(path) or os.path.islink(path):
        continue
    with open(path, "rb") as f:
        if b"\0" in f.read(8192):
            continue
    code = os.path.splitext(path)[1] in (".m", ".h", ".c", ".js") and "tests" not in path.split("/")
    for line in open(path, encoding="utf-8", errors="replace"):
        for match in TRACKER_SITE.finditer(line):
            host = match.group(0).lower()[len(match.group(1)) + 1:]
            if host in TRACKER_HOSTS and match.group(1).lower() not in MADE_UP_SITES:
                named.add((path, "the Jira site %s" % match.group(0).lower()))
        for key in TICKET_KEY.findall(line):
            if key not in MADE_UP_SPACES | NOT_TICKETS:
                named.add((path, "tickets in the space %s" % key))
        if code and NAME_DECIDED.search(line):
            named.add((path, "a status or step by its name"))
for path, what in sorted(named):
    problems.append("%s names %s: the project is public, so a site and a key in it are made up (acme.atlassian.net, "
                    "PAY-142), and a ticket's steps are only ever its tracker's, by their ids" % (path, what))
