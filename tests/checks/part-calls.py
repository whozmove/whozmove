# One of tests/checks.sh's rules, run in its one Python process after tests/checks/common.py, with what that makes.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
import os, re

# What each part's page scripts define (its functions, and its constants named in capitals), and every use of them by
# name in every other page script, called or passed on (setTimeout(render, …)), comments left out: each one a name
# its part.json provides, and from another part's script, a part it names in talksTo. A function a part gives the app
# (`window.name = …`) counts too, but only where it's called (`name(`), as such names are everyday words elsewhere. A
# name a script declares for itself (a `const`, `let` or `var` inside a function, a loop's, or a function's parameter)
# and never calls is its own, not a use of the part that has a function of that name. Each page's scripts are checked
# against the parts' scripts that page loads, as nothing else is there for them to call.
DEFINED = re.compile(r"^(?:async )?function ([\w$]+)|^const ([\w$]+) = (?:async )?(?:\([^)]*\)|[\w$]+) =>"
                     r"|^const ([A-Z][A-Z0-9_]*) =|^window\.([\w$]+) =", re.M)
part_scripts = {os.path.join("parts", name, file): name for name, spec in part_specs.items()
                for file in spec.get("scripts", [])}
functions, given = {}, set()
for path, name in part_scripts.items():
    for function in DEFINED.findall(open(path, encoding="utf-8").read()):
        functions[next(found for found in function if found)] = name
        if function[3]:
            given.add(function[3])
for name, spec in part_specs.items():
    for function in spec.get("provides", []):
        if function.endswith(".h"):
            if not os.path.isfile(os.path.join("parts", name, "app", function)):
                problems.append("parts/%s/part.json provides %s, which isn't in its app/" % (name, function))
        elif function.startswith("--"):
            # A style variable it gives the others: one of its scripts or styles sets it.
            if not any(re.search(r"""['"]%s['"]|(?:^|[{;])\s*%s\s*:""" % (re.escape(function), re.escape(function)),
                                 open(os.path.join("parts", name, file), encoding="utf-8").read(), re.M)
                       for file in spec.get("scripts", []) + spec.get("styles", [])):
                problems.append("parts/%s/part.json provides %s, which none of its scripts or styles sets"
                                % (name, function))
        elif functions.get(function) != name and not any(
                re.search(r"^(?:(?:(?:async )?function|const|let) %s\b|(?:const|let) [^\n;]*[\s,]%s =)"
                          % (re.escape(function), re.escape(function)),
                          open(os.path.join("parts", name, file), encoding="utf-8").read(), re.M)
                for file in spec.get("scripts", [])):
            # A name it provides may be one of its top-level constants (an element, say, or one named later in a
            # `const` with others) the others use: the calls below don't follow those, so part.json is where they're
            # said.
            problems.append("parts/%s/part.json provides %s, which none of its scripts defines" % (name, function))
PARAMETERS = re.compile(r"function\s*[\w$]*\s*\(([^()]*)\)|(?<![\w$])\(([^()]*)\)\s*=>|(?<![\w$.])([\w$]+)\s*=>"
                        r"|(?<![\w$.])(?!(?:if|for|while|switch|catch|with)\b)[\w$]+\s*\(([^()]*)\)\s*\{")
def declares(text, name):
    word = re.escape(name)
    if re.search(r"(?<![\w$.])%s\s*\(" % word, text):
        return False
    return bool(re.search(r"\b(?:const|let|var)\s+(?:%s\b|[{\[][^}\]=]*\b%s\b)" % (word, word), text)
                or any(re.search(r"(?<![\w$.])%s\b" % word, "".join(params)) for params in PARAMETERS.findall(text)))
loaded_by = {}
for scripts in pages.values():
    on_page = {part_scripts[p] for p in scripts if p in part_scripts}
    for p in scripts:
        loaded_by.setdefault(p, set()).update(on_page)
for path in dict.fromkeys(p for s in pages.values() for p in s):
    mine = part_scripts.get(path)
    text = re.sub(r"/\*.*?\*/", "", open(path, encoding="utf-8").read(), flags=re.S)
    text = re.sub(r"(?<![:\w\"'`])//.*$", "", text, flags=re.M)
    for function in sorted(set(re.findall(r"(?<![\w$.])([\w$]+)\b(?!\s*:)", text)) & set(functions)):
        theirs = functions[function]
        if theirs not in loaded_by[path] or theirs == mine or re.search(r"^(?:(?:async )?function|const) %s\b" % re.escape(function), text, re.M):
            continue
        if function in given and not re.search(r"(?<![\w$.])%s\s*\(" % re.escape(function), text):
            continue
        if declares(text, function):
            continue
        said = "uses %s" % function if function.isupper() else "calls %s()" % function
        if function not in part_specs[theirs].get("provides", []) and not crossing("calls", path, function):
            problems.append("%s %s, which parts/%s/part.json doesn't provide" % (path, said, theirs))
        elif mine and theirs not in part_specs[mine].get("talksTo", []) and not crossing("calls", path, function):
            problems.append("%s %s, from the %s part, which parts/%s/part.json doesn't name in talksTo"
                            % (path, said, theirs, mine))
