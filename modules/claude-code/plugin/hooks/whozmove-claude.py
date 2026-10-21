#!/usr/bin/env python3
# The session hook: records what each Claude Code session is doing, for the Whozmove panel.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
"""Wired to UserPromptSubmit, Notification, Stop, PreToolUse, PostToolUse and PostToolUseFailure. Keeps
~/Library/Application Support/Whozmove/sessions/<session_id>.json up to date with your last message, Claude's
last reply, any notice waiting (a permission prompt, say), the permission mode, a live line for the step Claude
is on ("Run the tests", "Reading app.ts", …) and, once Claude stops, how far its turn took the work ("Committed",
"Tested", "PR raised", …).
"""
import fcntl
import json
import os
import re
import sys
import time

# Whozmove's folder: must match AppDir in app/shared/Files.m (modules/claude-code/tests/test.sh fails if it doesn't).
ROOT = os.path.expanduser("~/Library/Application Support/Whozmove")
BASE = os.path.join(ROOT, "sessions")
# Where the app runs from, which it notes in its folder each time it opens (modules/install): nothing is recorded
# while it isn't there, so once Whozmove is removed nothing more of your sessions is written down, and its folder isn't
# made again.
APP_NOTE = os.path.join(ROOT, "app")
SNIPPET = 280

# How a shell line is read (command_segments): what's dropped from it, what separates its commands, and the
# words that only run the command after them.
HEREDOC = re.compile(r"<<-?\s*(['\"]?)(\w+)\1[^\n]*\n.*?\n\s*\2[ \t]*(?=\n|$)", re.S)
QUOTED = re.compile(r"'([^']*)'|\"((?:\\.|[^\"\\])*)\"")
SEPARATOR = re.compile(r"&&|\|\||[;|\n`]|\$\(|\)")
WRAPPERS = {"sudo", "time", "env", "exec", "nohup", "command", "npx", "bunx"}

# Shell commands are matched on their command heads only (see command_heads): "cd app && npm test" is Tested,
# "git add -A && git commit" is Committed.
GIT = r"\bgit\s+(?:-c\s+\S+\s+)?"  # commands are lowercased, so -C (and -c) is "-c"
TESTS = r"\b(pytest|jest|vitest|mocha|rspec|phpunit)\b|\b(go|cargo|npm|yarn|pnpm|bun|swift)\s+(run\s+)?test\b"
CHECKS = r"\b(eslint|tsc|prettier|ruff|flake8|mypy|golangci-lint|swiftlint)\b|--noemit"
BUILDS = (r"\b(make|gradle|gradlew|mvn|xcodebuild|clang|gcc|swiftc|webpack)\b|\b(go|cargo|swift)\s+build\b"
          r"|\b(npm|yarn|pnpm|bun)\s+(run\s+)?build\b|\bbuild\.sh\b")

# Where a turn left the work, most advanced first. Each successful tool call can reach one of these;
# when Claude stops, the session's outcome is the most advanced one its turn reached.
OUTCOMES = ["Deployed", "On staging", "Merged", "PR raised", "Pushed", "Committed", "Reviewed", "Tested", "Validated",
            "Built", "Implemented", "Documented", "Planned", "Researched"]
CHANGES = {"Implemented", "Documented", "Built", "Tested", "Committed"}  # a turn that changed something
UNCOMMITTED = {"Implemented", "Documented", "Built", "Validated", "Tested"}  # changes still sitting in the checkout
FOLLOW_UP_MS = 2 * 3600 * 1000  # how long a look-up turn counts as a follow-up to the work before it
COMPACT_END_AFTER_MS = 1000  # how long after a compaction starts the next step can say it has ended
PROOF = ("Built", "Tested", "Validated")  # what the work's been through, shown beside its state

# A deploy counts only when it names its environment: production is "Deployed", staging is "On
# staging"; anything else (local runs, unnamed targets) isn't a deploy. Reads like `kubectl get` or
# `kubectl rollout status` aren't deploys either.
DEPLOY_COMMAND = re.compile(r"^kubectl\s+(apply|create|replace|patch|set\s+image|scale|rollout\s+(restart|undo))\b"
                            r"|^helm\s+(install|upgrade|rollback)\b|^terraform\s+apply\b")
# Any other deploy is a command named for it (./deploy.sh, deploy-prod) or one given it as its task (`fly
# deploy`, `npm run deploy:prod`, `make deploy-staging`). A file that merely mentions it, read by
# `cat deploy/prod.yaml`, isn't one.
READS = re.compile(r"^(cat|less|more|head|tail|ls|grep|rg|find|wc|vim?|nano|code|open|echo|printf|diff|stat|file|tree"
                   r"|sed|awk|jq|yq|git|gh|cp|mv|rm|mkdir|touch|chmod)\b")
INTERPRETERS = {"bash", "sh", "zsh", "python", "python3", "node", "ruby", "perl", "pwsh"}
PRODUCTION = re.compile(r"\bprod(uction)?\b")
STAGING = re.compile(r"\b(staging|stage|stg)\b")
KUBE_GLOBAL_FLAGS = {"--context", "--kube-context", "-n", "--namespace", "--kubeconfig", "--cluster"}

# Other shell commands, in OUTCOMES order (the first match is the most advanced the command reaches).
COMMAND_OUTCOMES = [
    (r"\bgh\s+pr\s+merge\b", "Merged"),
    (r"\bgh\s+pr\s+create\b", "PR raised"),
    (GIT + r"push\b", "Pushed"),
    (GIT + r"commit\b", "Committed"),
    (r"\bgh\s+pr\s+(review|comment)\b", "Reviewed"),
    (TESTS, "Tested"),
    (CHECKS + r"|\bcurl\b.*\b(localhost|127\.0\.0\.1)\b", "Validated"),
    (BUILDS, "Built"),
    (r"\b(gh|psql|mysql|sqlite3|curl|wget|grep|rg|find|cat|head|tail|ls)\b|\bgit\s+(log|diff|show|blame|status)\b",
     "Researched"),
]
DOC_FILE = re.compile(r"\.(md|mdx|txt|rst|adoc)$|(^|/)(readme|changelog|license)[^/]*$", re.I)

# For MCP tools (mcp__<server>__<tool>): where the call goes, as the live line names it. Browser tools and
# GitHub's get a plain name whatever their server is called. A plugin's server (plugin_<plugin>_<server>) and a
# claude.ai connector in the terminal (claude_ai_<name>) go by their own name. In Claude Desktop a connector's
# server name is only an id, which names nothing, so the line shows just the tool.
MCP_SOURCES = [
    (r"browser|chrome|navigate|screenshot", "Browser"),
    (r"github|pull_request", "GitHub"),
]
MCP_PREFIX = re.compile(r"^(plugin_[^_]+|claude_ai)_")
MCP_ID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", re.I)


def unquote(match):
    """A quoted single word ("./deploy.sh", 'prod') stays as that word. Quoted text with spaces (a commit
    message, an inline script, test data) goes, so what it mentions can't pass for a command."""
    text = match.group(1) if match.group(1) is not None else match.group(2)
    return "" if re.search(r"\s", text) else text


def command_segments(command):
    """The commands a shell line actually runs, as (head, full) pairs: its first few words, and all of it.

    Heredoc bodies and quoted strings are dropped first, so text a command merely contains (a commit
    message, a script fed on stdin, test data) can't pass for a command: `python3 - <<'EOF' … git commit
    … EOF` is just "python3 -".
    """
    command = QUOTED.sub(unquote, HEREDOC.sub("", command))
    segments = []
    for segment in SEPARATOR.split(command):
        words = segment.split()
        while words and (("=" in words[0] and not words[0].startswith("-")) or words[0] in WRAPPERS):
            words.pop(0)  # FOO=bar, sudo, npx, …
        if words:
            segments.append((" ".join(words[:6]), " ".join(words)))
    return segments


def command_heads(command):
    """What the outcome patterns match against: each command's head, joined by " ; "."""
    return " ; ".join(head for head, _ in command_segments(command))


def names_deploy(head):
    words = head.split()
    if not words or READS.match(head) or words[0] == "kubectl":
        return False
    if os.path.basename(words[0]) in INTERPRETERS and len(words) > 1:  # `bash scripts/deploy-prod.sh`
        return "deploy" in os.path.basename(words[1])
    return "deploy" in os.path.basename(words[0]) or any(
        word.startswith("deploy") for word in words[1:4] if "/" not in word and not word.startswith("-"))


def without_global_flags(full):
    """`kubectl --context prod apply …` -> `kubectl apply …`, so the verb is where DEPLOY_COMMAND looks."""
    words, kept = full.split(), []
    while words:
        word = words.pop(0)
        if word in KUBE_GLOBAL_FLAGS:
            words = words[1:]  # and its value
        elif word.split("=")[0] not in KUBE_GLOBAL_FLAGS:
            kept.append(word)
    return " ".join(kept)


def deploy_outcome(command):
    reached = None
    for head, full in command_segments(command):
        if head.startswith(("kubectl", "helm")):
            head = without_global_flags(full)
        if DEPLOY_COMMAND.search(head) or names_deploy(head):
            if PRODUCTION.search(full):
                return "Deployed"
            if STAGING.search(full):
                reached = "On staging"
    return reached


def outcome_for(tool, tool_input):
    """The work stage a successful tool call reaches, or None. "_browsed" is settled at Stop."""
    tool, tool_input = tool or "", tool_input or {}
    if tool in ("Bash", "PowerShell"):
        raw = str(tool_input.get("command", "")).lower()
        command = command_heads(raw)
        return deploy_outcome(raw) or next(
            (word for pattern, word in COMMAND_OUTCOMES if re.search(pattern, command)), None)
    if tool in ("Edit", "MultiEdit", "Write", "NotebookEdit"):
        path = str(tool_input.get("file_path") or tool_input.get("notebook_path") or "")
        return "Documented" if DOC_FILE.search(path) else "Implemented"
    if tool in ("Read", "Glob", "Grep", "LS", "WebSearch", "WebFetch"):
        return "Researched"
    if tool in ("EnterPlanMode", "ExitPlanMode", "TodoWrite", "TaskCreate", "TaskUpdate"):
        return "Planned"
    if tool in ("Agent", "Task"):
        # Exploring and planning are what those sub-agents do; any other sub-agent's work shows up
        # through its own tool calls. Skill names only say what's intended (a "review" skill may post
        # nothing), so skills reach no stage by themselves either.
        kind = str(tool_input.get("subagent_type") or "").lower()
        return "Researched" if kind == "explore" else "Planned" if kind == "plan" else None
    if tool.startswith("mcp__"):
        name = tool.lower()
        if "merge_pull_request" in name:
            return "Merged"
        if "create_pull_request" in name:
            return "PR raised"
        # Posting a review or a comment; reading them (get_pull_request_reviews, …) is research.
        if re.search(r"review|comment", name) and re.search(r"pull_request|_review", name) \
                and re.search(r"create|add|submit|reply|write|post", name):
            return "Reviewed"
        if re.search(r"browser|chrome|navigate|screenshot", name):
            return "_browsed"  # validation after changes, research otherwise
        return "Researched"
    return None


def git_root(path):
    """The checkout a file belongs to (the folder holding its .git), or None."""
    folder = os.path.dirname(os.path.abspath(os.path.expanduser(path)))
    while folder != os.path.dirname(folder):
        if os.path.exists(os.path.join(folder, ".git")):
            return folder
        folder = os.path.dirname(folder)
    return None


def turn_outcome(reached):
    reached = set(reached)
    if "_browsed" in reached:
        reached.discard("_browsed")
        reached.add("Validated" if reached & CHANGES else "Researched")
    return next((word for word in OUTCOMES if word in reached), None)


def audit_of(tool_input):
    """A local code review's result, from its report (the ReportFindings tool): how many findings, and how
    many are still left. The first report lists them; a later one gives each an outcome, and only "fixed"
    or "no_change_needed" settles one ("skipped" is a known open item)."""
    findings = [f for f in (tool_input or {}).get("findings") or [] if isinstance(f, dict)]
    settled = any(f.get("outcome") for f in findings)
    left = sum(1 for f in findings if f.get("outcome") not in ("fixed", "no_change_needed"))
    return dict(found=len(findings), left=left, settled=settled)


def branch_of(cwd):
    """The branch checked out where a session runs, read from its checkout's HEAD as the app reads it (GitInfo, in
    app/shared/Git.m), without running git: its name, or for a detached HEAD the first 7 characters of its commit;
    None outside git."""
    if not cwd:
        return None
    try:
        root = git_root(os.path.join(cwd, "-"))  # git_root starts from a file's folder
        if not root:
            return None
        git_dir = os.path.join(root, ".git")
        if os.path.isfile(git_dir):  # a linked worktree or a submodule: its .git names the real git folder
            with open(git_dir) as f:
                pointer = f.read()
            if "gitdir:" not in pointer:
                return None
            git_dir = os.path.normpath(os.path.join(root, pointer.split("gitdir:", 1)[1].strip()))
        with open(os.path.join(git_dir, "HEAD")) as f:
            head = f.read().strip()
    except (OSError, ValueError):
        return None
    if head.startswith("ref: refs/heads/"):
        return head[16:]
    return head[5:] if head.startswith("ref: ") else head[:7] or None


def humanize(name):
    """"getPageContent" / "pull_request_read" -> "get page content" / "pull request read"."""
    words = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", " ", name).replace("_", " ").replace("-", " ").split()
    return " ".join(w if w.isupper() else w.lower() for w in words)


def clip(text):
    text = " ".join((text or "").split())
    return text if len(text) <= SNIPPET else text[: SNIPPET - 1] + "…"


def shorten(text, limit):
    """Text for the live line: on one line, and cut to `limit` characters, with "…" where it's cut."""
    text = clip(str(text or ""))
    return text[:limit].rstrip() + ("…" if len(text) > limit else "")


def file_name(tool_input, key="file_path"):
    """The name of the file a tool works on, or "a file"."""
    return os.path.basename(str(tool_input.get(key) or "")) or "a file"


def activity_for(tool, tool_input):
    """A short live line for what the agent is doing, like Claude's own "Running a command"."""
    tool, tool_input = tool or "", tool_input or {}
    if tool in ("Bash", "PowerShell"):
        return shorten(tool_input.get("description"), 80) or "Running a command"
    if tool == "Read":
        return "Reading " + file_name(tool_input)
    if tool in ("Edit", "MultiEdit", "NotebookEdit"):
        return "Editing " + file_name(tool_input, "file_path" if tool != "NotebookEdit" else "notebook_path")
    if tool == "Write":
        return "Writing " + file_name(tool_input)
    if tool == "Grep":
        return f"Searching for \u201c{shorten(tool_input.get('pattern'), 30)}\u201d"
    if tool == "Glob":
        return "Finding files " + shorten(tool_input.get("pattern"), 30)
    if tool == "WebSearch":
        return "Searching the web: " + shorten(tool_input.get("query"), 50)
    if tool == "WebFetch":
        host = re.sub(r"^https?://(www\.)?", "", str(tool_input.get("url") or "")).split("/")[0]
        return "Reading " + (host or "a web page")
    if tool in ("Agent", "Task"):
        return "Sub-agent: " + (shorten(tool_input.get("description"), 60) or "working")
    if tool == "Skill":
        return "Using " + (str(tool_input.get("skill") or "a skill"))
    if tool in ("TodoWrite", "TaskCreate", "TaskUpdate", "EnterPlanMode", "ExitPlanMode"):
        return "Updating the plan"
    if tool == "AskUserQuestion":
        return "Asking you a question"
    if tool == "ToolSearch":
        return "Loading tools"
    if tool.startswith("mcp__"):
        parts = tool.split("__")
        action = humanize(parts[-1])
        source = next((word for pattern, word in MCP_SOURCES if re.search(pattern, tool.lower())), None)
        server = MCP_PREFIX.sub("", parts[1]) if len(parts) > 2 else ""
        if not source and (not server or MCP_ID.match(server)):
            return action.capitalize() or "Working"
        return f"{source or humanize(server).capitalize()}: {action}"
    return humanize(tool).capitalize() or "Working"


def last_assistant_text(transcript_path):
    """Claude's newest reply in the last 512 KB of the transcript, for a Stop event that doesn't carry it."""
    try:
        with open(transcript_path, "rb") as f:
            f.seek(0, os.SEEK_END)
            f.seek(max(0, f.tell() - 512 * 1024))
            lines = f.read().decode("utf-8", "replace").splitlines()
    except OSError:
        return ""
    for line in reversed(lines):
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if entry.get("type") != "assistant":
            continue
        content = (entry.get("message") or {}).get("content") or []
        texts = [c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text"]
        if any(t.strip() for t in texts):
            return "\n".join(texts)
    return ""


def app_installed():
    """Whether the app noted in Whozmove's folder is there. A build or an upgrade swapping it in can leave a moment
    without it, so it's looked for again 2 seconds later before it counts as gone: this hook runs in the background,
    so no session waits."""
    try:
        with open(APP_NOTE) as f:
            app = f.read().strip()
    except OSError:
        return False
    if not app:
        return False
    if os.path.isdir(app):
        return True
    time.sleep(2)
    return os.path.isdir(app)


def main():
    now = int(time.time() * 1000)  # taken first: hooks run async, so this orders racing events
    event = json.load(sys.stdin)
    session_id = event.get("session_id")
    name = event.get("hook_event_name")
    if not session_id or not app_installed():
        return

    update = {}              # the fields this event sets
    activity = None          # a new live line, when this event starts a step or the turn
    reached = None           # a work stage this event reached (PostToolUse only)
    audit = None             # a local code review's report (PostToolUse of ReportFindings)
    if name == "UserPromptSubmit":
        prompt = str(event.get("prompt") or "")
        if prompt.lstrip().startswith(("<task-notification>", "<agent-message")):
            # A background task or another agent reporting back: Claude's turn, but not something you said.
            update = dict(turnReached=[])
        else:
            update = dict(lastPrompt=clip(prompt), lastPromptAt=now, notice=None, turnReached=[])
        activity = "Thinking"
    elif name == "Notification":
        update = dict(notice=clip(event.get("message")), noticeType=event.get("notification_type"), noticeAt=now)
    elif name == "Stop":
        reply = event.get("last_assistant_message") or last_assistant_text(event.get("transcript_path", ""))
        update = dict(lastReply=clip(reply), lastReplyAt=now, notice=None)
    elif name == "PreToolUse":
        # The live line follows the main agent: a sub-agent's own steps (events carrying its agent_id)
        # leave it on "Sub-agent: …", as Claude does.
        if not event.get("agent_id"):
            activity = activity_for(event.get("tool_name"), event.get("tool_input"))
    elif name == "PostToolUse":
        reached = outcome_for(event.get("tool_name"), event.get("tool_input"))
        if event.get("tool_name") == "ReportFindings":
            # Noted with the branch it was run on, so a checkout switched to another branch doesn't show it.
            audit = audit_of(event.get("tool_input"))
            branch = branch_of(event.get("cwd") or "")
            if branch:
                audit["branch"] = branch
        # Remember which checkout the session's edits land in (it can differ from the folder it runs in), and when it
        # last edited there: the session that edited a checkout last is the one its next step goes to.
        tool_input = event.get("tool_input") or {}
        edited = tool_input.get("file_path") or tool_input.get("notebook_path")
        if event.get("tool_name") in ("Edit", "MultiEdit", "Write", "NotebookEdit") and edited:
            root = git_root(edited)
            if root:
                update = dict(workRoot=root, editedAt=now)
    elif name == "PostToolUseFailure":
        pass  # a step ended: only its time is kept (stageAt, below)
    elif name in ("PreCompact", "PostCompact"):
        pass  # a compaction started or ended, by itself or asked for (compactingAt, below)
    else:
        return

    if event.get("permission_mode"):  # every event carries the session's current permission mode
        update = dict(update, permissionMode=event["permission_mode"])

    # Your prompts and Claude's replies: readable by you only, as Claude Code keeps its own files.
    os.umask(0o077)
    os.makedirs(BASE, exist_ok=True)
    for folder in (ROOT, BASE):
        if os.stat(folder).st_mode & 0o077:
            os.chmod(folder, 0o700)
    path = os.path.join(BASE, session_id + ".json")
    # A tool's Pre and Post hooks can run at the same moment; serialise the read-modify-write.
    with open(path + ".lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            with open(path) as f:
                state = json.load(f)
        except (OSError, ValueError):
            state = {}
        state.update(update)
        # When a step or the turn last started or ended (any event but a notification): the app takes it as the
        # session's last event.
        if name != "Notification":
            state["stageAt"] = max(state.get("stageAt", 0), now)  # never let an older event win
        # The live line changes only when a step starts (or the turn starts or ends), like Claude's own:
        # after a step finishes it stays up, timed from when that step began, while Claude thinks on.
        if (activity is not None or name == "Stop") and state.get("activityAt", 0) <= now:
            state.update(activity=activity, activityAt=now)
        # While the conversation is compacting, by itself or asked for: from its start until it ends. One stopped
        # with Esc says nothing, so Claude's own work going on, your next message, the turn ending or Claude saying it
        # waits for you means it has ended too, if that comes a second or more after the start: each hook runs on its
        # own, so the step just before a compaction can come in a moment after it. A sub-agent's steps go on while the
        # main conversation compacts, and don't count. A start is never taken from before the last end, as the two
        # compaction hooks can come in either order too.
        compacting_at = state.get("compactingAt")
        ends = (name in ("UserPromptSubmit", "Stop")
                or (name == "PreToolUse" and not event.get("agent_id"))
                or (name == "Notification" and event.get("notification_type") == "idle_prompt"))
        if name == "PreCompact" and now > state.get("compactedAt", 0):
            state["compactingAt"] = now
        elif name == "PostCompact":
            state.update(compactingAt=None, compactedAt=now)
        elif compacting_at and ends and now - compacting_at >= COMPACT_END_AFTER_MS:
            state["compactingAt"] = None
        if reached and reached not in state.setdefault("turnReached", []):
            state["turnReached"].append(reached)
        # What the current piece of work has been through (built, tested, validated, audited), kept until it's
        # committed and the next piece of work starts: its first change after that commit.
        if reached in ("Implemented", "Documented") and state.get("workCommitted"):
            state.update(workSteps=[], workCommitted=False)
            state.pop("audit", None)
        if reached in PROOF and reached not in state.setdefault("workSteps", []):
            state["workSteps"].append(reached)
        # When the work was last built: the panel offers Deploy for a build newer than the last deploy.
        if reached == "Built":
            state["builtAt"] = now
        if reached == "Committed":
            state["workCommitted"] = True
        if audit is not None:
            state["audit"] = dict(audit, at=now)
            # A review of work already committed that leaves something to fix starts a round of its own on it: its
            # fixes are that work still, so the first of them mustn't count as the next piece of work and take the
            # review away. One with nothing left is done with once that work changes.
            if audit["left"]:
                state["workCommitted"] = False
        if name == "Stop":
            # The furthest stage this turn reached. A turn that only talked keeps the previous outcome:
            # answering a question doesn't move the work back. Nor does one that only looked things up
            # soon after changes that aren't committed yet: those changes are still where the work stands.
            # (Later, a look-up turn is new work of its own, and the session lets go of that checkout.)
            outcome = turn_outcome(state.get("turnReached", []))
            turn = set(state.get("turnReached", []))
            if "_browsed" in turn and turn & CHANGES and "Validated" not in state.setdefault("workSteps", []):
                state["workSteps"].append("Validated")  # checked in a browser after changing something
            previous = state.get("outcome")
            follow_up = (outcome == "Researched" and previous in UNCOMMITTED
                         and now - state.get("outcomeAt", 0) < FOLLOW_UP_MS)
            if (outcome and not follow_up) or not previous:
                state.update(outcome=outcome or "Answered", outcomeAt=now)
            state["turnReached"] = []
        tmp = path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(state, f)
        os.replace(tmp, path)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass  # never let the panel's bookkeeping disturb a session
