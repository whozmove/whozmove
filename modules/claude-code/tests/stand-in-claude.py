#!/usr/bin/env python3
# A stand-in Claude Code, for checking the real Claude Code run's own pieces (real.sh --stand-in-claude) on any Mac
# without running Claude Code: it reads no sign-in and reaches nothing but the stand-in server. It does, in the shapes
# Whozmove reads, the little of Claude Code the run's driver uses: the registry file, the transcript, the plugin's
# hooks (run as its own children, as Claude Code runs them), the prompt with its draft kept through Ctrl+S, Shift+Tab's
# modes, /model, /compact and /exit, `claude plugin` for Whozmove's plugin, the turns, through ANTHROPIC_BASE_URL, and a
# question asked on a session's side (-p --resume <id> --fork-session, each question on its input as a stream-json
# line, kept for the next, nothing saved, its tools as --allowedTools and the PreToolUse hook --settings gives it say).
# It checks the run, not Whozmove: a pass with it says nothing about Claude Code.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
import json
import os
import re
import shutil
import subprocess
import sys
import termios
import time
import tty
import urllib.request
import uuid
from datetime import datetime, timezone

HOME = os.path.expanduser("~")
CONFIG = os.path.join(HOME, ".claude")
PLUGINS = os.path.join(CONFIG, "stand-in-plugins.json")
MODES = ["default", "acceptEdits", "plan"]
ASKS = {"default": {"Bash", "Write", "AskUserQuestion", "ExitPlanMode"}, "acceptEdits": {"Bash", "AskUserQuestion",
        "ExitPlanMode"}, "plan": {"ExitPlanMode", "AskUserQuestion"}}


def now_ms():
    return int(time.time() * 1000)


def iso():
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def load(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def save(path, value):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".tmp", "w") as f:
        json.dump(value, f, indent=2)
    os.replace(path + ".tmp", path)


# `claude plugin …`, for Whozmove's plugin only, as the app runs it (Whozmove --print-plugin-install).
def plugin(args):
    state = load(PLUGINS, {"marketplaces": {}, "installed": {}})
    if args[:2] == ["list", "--json"]:
        print(json.dumps([dict(id=k, version=v["version"], enabled=v["enabled"], errors=[])
                          for k, v in state["installed"].items()]))
        return 0
    if args[:2] == ["marketplace", "add"]:
        folder = args[2]
        name = load(os.path.join(folder, ".claude-plugin", "marketplace.json"), {}).get("name")
        state["marketplaces"][name] = folder
    elif args[:2] == ["marketplace", "update"]:
        pass
    elif args[0] in ("install", "update", "enable"):
        pid, market = args[1].split("@")
        folder = state["marketplaces"][market]
        version = load(os.path.join(folder, ".claude-plugin", "plugin.json"), {})["version"]
        copy = os.path.join(CONFIG, "plugins", "cache", market, pid, version.replace("+", "-"))
        if not os.path.isdir(copy):
            shutil.copytree(folder, copy)
        state["installed"][args[1]] = {"version": version, "enabled": True, "path": copy}
    else:
        print(f"stand-in claude: no plugin command {' '.join(args)}", file=sys.stderr)
        return 1
    save(PLUGINS, state)
    print('{"outcome":"ok"}')
    return 0


class Claude:
    def __init__(self, mode, model):
        self.sid, self.mode, self.model = str(uuid.uuid4()), mode, model
        self.cwd = os.getcwd()
        slug = re.sub(r"[^A-Za-z0-9]", "-", self.cwd)
        self.transcript = os.path.join(CONFIG, "projects", slug, self.sid + ".jsonl")
        os.makedirs(os.path.dirname(self.transcript), exist_ok=True)
        self.registry = os.path.join(CONFIG, "sessions", f"{os.getpid()}.json")
        self.started, self.messages, self.draft, self.stash = now_ms(), [], "", ""
        self.background = None
        self.status("idle")
        self.hooks = {}
        for entry in load(PLUGINS, {"installed": {}})["installed"].values():
            if entry["enabled"]:
                for event, groups in load(os.path.join(entry["path"], "hooks", "hooks.json"), {}).get("hooks",
                                                                                                    {}).items():
                    for group in groups:
                        for hook in group["hooks"]:
                            self.hooks.setdefault(event, []).append((entry["path"], hook))

    def status(self, status):
        if status == "idle" and self.background and self.background.poll() is None:
            status = "shell"
        save(self.registry, {"pid": os.getpid(), "sessionId": self.sid, "cwd": self.cwd, "startedAt": self.started,
                             "procStart": str(self.started), "kind": "interactive", "entrypoint": "cli",
                             "status": status, "statusUpdatedAt": now_ms(), "version": "stand-in", "name": None})

    def record(self, entry):
        entry.setdefault("timestamp", iso())
        entry.setdefault("sessionId", self.sid)
        entry.setdefault("cwd", self.cwd)
        with open(self.transcript, "a") as f:
            f.write(json.dumps(entry) + "\n")

    def hook(self, event, **fields):
        """Runs the plugin's hooks for an event as their own children; a waited-on one's answer, as JSON."""
        answer = None
        data = dict(fields, session_id=self.sid, transcript_path=self.transcript, cwd=self.cwd,
                    hook_event_name=event, permission_mode=self.mode)
        for root, hook in self.hooks.get(event, []):
            argv = [hook["command"]] + [a.replace("${CLAUDE_PLUGIN_ROOT}", root) for a in hook.get("args", [])]
            env = dict(os.environ, CLAUDE_PLUGIN_ROOT=root)
            if hook.get("async"):
                p = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL, env=env)
                p.stdin.write(json.dumps(data).encode())
                p.stdin.close()
                continue
            run = subprocess.run(argv, input=json.dumps(data), capture_output=True, text=True, env=env,
                                 timeout=hook.get("timeout", 60))
            if run.stdout.strip():
                answer = json.loads(run.stdout)
        return answer

    def api(self, body):
        request = urllib.request.Request(os.environ["ANTHROPIC_BASE_URL"] + "/v1/messages", json.dumps(body).encode(),
                                         {"x-api-key": os.environ["ANTHROPIC_API_KEY"],
                                          "content-type": "application/json"})
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)

    def command_result(self, command, output):
        self.record({"type": "user", "message": {"role": "user", "content":
                     f"<command-name>{command}</command-name>\n<command-args></command-args>"}})
        self.record({"type": "system", "subtype": "local_command",
                     "content": f"<local-command-stdout>{output}</local-command-stdout>"})

    def run_tool(self, call):
        name, given = call["name"], call["input"]
        updated = given
        if name in ASKS[self.mode]:
            decision = (self.hook("PermissionRequest", tool_name=name, tool_input=given) or {}).get(
                "hookSpecificOutput", {}).get("decision", {"behavior": "deny", "message": "denied in the terminal"})
            if decision.get("behavior") != "allow":
                return {"error": True, "text": decision.get("message") or "The user doesn't want to proceed."}, {}
            updated = decision.get("updatedInput") or given
        self.hook("PreToolUse", tool_name=name, tool_input=updated)
        if name == "Bash" and updated.get("run_in_background"):
            self.background = subprocess.Popen(["/bin/sh", "-c", updated["command"]])
            out, result = "Started in the background", {"backgroundTaskId": "b1"}
        elif name == "Bash":
            out = subprocess.run(["/bin/sh", "-c", updated["command"]], capture_output=True, text=True).stdout
            result = {"stdout": out, "stderr": ""}
        elif name == "Write":
            with open(updated["file_path"], "w") as f:
                f.write(updated["content"])
            out, result = "File created successfully", {"type": "create", "filePath": updated["file_path"],
                                                        "content": updated["content"], "structuredPatch": []}
        elif name == "AskUserQuestion":
            out = "User has answered your questions: " + ", ".join(
                f'"{q}"="{a}"' for q, a in (updated.get("answers") or {}).items())
            result = {"answers": updated.get("answers") or {}}
        else:
            out, result = "User has approved your plan.", {}
        self.hook("PostToolUse", tool_name=name, tool_input=updated, tool_response=result)
        return {"error": False, "text": out}, result

    def turn(self, said):
        self.status("busy")
        self.hook("UserPromptSubmit", prompt=said)
        self.messages.append({"role": "user", "content": said})
        self.record({"type": "user", "message": {"role": "user", "content": said}, "permissionMode": self.mode})
        while True:
            reply = self.api({"model": self.model, "max_tokens": 1000, "tools": TOOLS, "messages": self.messages})
            self.messages.append({"role": "assistant", "content": reply["content"]})
            self.record({"type": "assistant", "message": reply, "isSidechain": False, "effort": "high"})
            calls = [c for c in reply["content"] if c["type"] == "tool_use"]
            if not calls:
                break
            results = []
            for call in calls:
                out, result = self.run_tool(call)
                results.append({"type": "tool_result", "tool_use_id": call["id"], "content": out["text"],
                                "is_error": out["error"]})
                self.record({"type": "user", "message": {"role": "user", "content": results[-1:]},
                             "toolUseResult": result})
            self.messages.append({"role": "user", "content": results})
        last = "".join(c.get("text", "") for c in reply["content"])
        self.hook("Stop", last_assistant_message=last)
        self.status("idle")

    def slash(self, line):
        name, _, rest = line.partition(" ")
        if name == "/model":
            to = rest.strip()
            answer = (self.hook("PreModelSwitch", from_model=self.model, to_model=to, requested_model=to,
                                prompt_cache_warm=True, context_tokens=32000) or {}).get("hookSpecificOutput", {})
            if answer.get("permissionDecision") == "deny":
                self.command_result(name, f"Kept model as {self.model}")
            else:
                self.model = to
                self.command_result(name, f"Set model to {to} and saved as your default for new sessions")
        elif name == "/compact":
            self.status("busy")
            self.hook("PreCompact", trigger="manual")
            self.api({"model": self.model, "max_tokens": 1000, "system": "Write a summary of the conversation.",
                      "messages": self.messages + [{"role": "user", "content": "Summarize."}]})
            self.messages = []
            self.record({"type": "system", "subtype": "compact_boundary", "compactMetadata": {"postTokens": 1200}})
            self.command_result(name, "Compacted")
            self.hook("PostCompact", trigger="manual")
            self.status("idle")
        elif name == "/exit":
            os.remove(self.registry)
            sys.exit(0)
        else:
            self.command_result(name, f"Unknown command: {name}")

    def loop(self):
        print("stand-in Claude Code  ? for shortcuts\r\n> ", end="", flush=True)
        keys = b""
        while True:
            keys += os.read(0, 64)
            while keys:
                if keys.startswith(b"\x1b[Z"):
                    keys = keys[3:]
                    self.mode = MODES[(MODES.index(self.mode) + 1) % len(MODES)]
                elif keys[:1] == b"\x13":
                    keys = keys[1:]
                    if self.draft:
                        self.stash, self.draft = self.draft, ""
                    else:
                        self.draft = self.stash
                elif keys[:1] == b"\x7f":
                    keys, self.draft = keys[1:], self.draft[:-1]
                elif keys[:1] == b"\r":
                    keys, line, self.draft = keys[1:], self.draft, ""
                    if line.startswith("/"):
                        self.slash(line)
                        self.draft, self.stash = self.stash, ""
                    elif line:
                        self.turn(line)
                elif keys[:1] == b"\x1b" and len(keys) < 3:
                    break
                else:
                    ch = keys.decode("utf-8", "ignore")[:1] or "?"
                    keys = keys[len(ch.encode()):] if ch != "?" else keys[1:]
                    if ch >= " ":
                        self.draft += ch
                print(f"\r\x1b[K[{self.mode}] > {self.draft}", end="", flush=True)


TOOLS = [{"name": n, "input_schema": {"type": "object"}} for n in ("Bash", "Write", "AskUserQuestion", "ExitPlanMode")]


def allowed(call, rules):
    """Whether --allowedTools names a tool call, as Claude Code matches its rules: a tool's own name, or Bash(<words>:*)
    for a command that starts with those words."""
    for rule in rules:
        if rule == call["name"]:
            return True
        if rule.startswith("Bash(") and rule.endswith(":*)") and call["name"] == "Bash":
            if call["input"].get("command", "").startswith(rule[5:-3]):
                return True
    return False


def run_tool(call):
    """A tool the copy may use, run: Read's file, or a Bash command in the session's folder. (Text, refused)."""
    if call["name"] == "Read":
        try:
            with open(call["input"].get("file_path", "")) as f:
                return f.read(), False
        except OSError as why:
            return str(why), True
    if call["name"] == "Bash":
        done = subprocess.run(["/bin/sh", "-c", call["input"].get("command", "true")], capture_output=True, text=True)
        return done.stdout + done.stderr, False
    return f"{call['name']} isn't a tool the stand-in runs", True


def aside(args):
    """A question on a session's side, kept for more: its conversation as its transcript has it since its last
    compaction, sent again with each question after it as the session itself sends it; registered while it runs, and
    nothing written but that. It answers each line its input gives, once the one before has its result, and ends once
    its input closes, as Claude Code does. A tool it reaches for is refused unless --allowedTools names it (dontAsk),
    then goes to --settings' PreToolUse hooks, given the call on their input: exit 2 refuses it, and any other ending,
    or a hook still running at its timeout, lets it run, as Claude Code's do. --max-turns counts each question's
    rounds."""
    sid = args[args.index("--resume") + 1]
    model = args[args.index("--model") + 1] if "--model" in args else "claude-sonnet-5-5"
    settings = json.loads(args[args.index("--settings") + 1]) if "--settings" in args else {}
    rules = args[args.index("--allowedTools") + 1].split(",") if "--allowedTools" in args else []
    turns = int(args[args.index("--max-turns") + 1]) if "--max-turns" in args else 1
    paths = [os.path.join(top, sid + ".jsonl") for top, _, files in os.walk(os.path.join(CONFIG, "projects"))
             if sid + ".jsonl" in files]
    messages = []
    for line in open(paths[0]) if paths else []:
        entry = json.loads(line)
        if entry.get("subtype") == "compact_boundary":
            messages = []
        content = (entry.get("message") or {}).get("content")
        if entry.get("type") in ("user", "assistant") and not str(content).startswith("<command-name>"):
            messages.append({"role": entry["message"]["role"], "content": content})
    registry = os.path.join(CONFIG, "sessions", f"{os.getpid()}.json")
    save(registry, {"pid": os.getpid(), "sessionId": str(uuid.uuid4()), "cwd": os.getcwd(), "startedAt": now_ms(),
                    "procStart": str(now_ms()), "kind": "interactive", "entrypoint": "sdk-cli", "status": "busy",
                    "statusUpdatedAt": now_ms(), "version": "stand-in", "name": None})
    hooks = [h for g in settings.get("hooks", {}).get("PreToolUse", []) for h in g.get("hooks", [])]
    say = lambda line: print(json.dumps(line), flush=True)
    say({"type": "system", "subtype": "init"})

    def refused_by_hook(call):
        given = json.dumps({"session_id": sid, "hook_event_name": "PreToolUse", "tool_name": call["name"],
                            "tool_input": call["input"]})
        for hook in hooks:
            try:
                done = subprocess.run(["/bin/sh", "-c", hook["command"]], input=given, capture_output=True, text=True,
                                      timeout=hook.get("timeout", 60))
            except subprocess.TimeoutExpired:
                continue
            if done.returncode == 2:
                return done.stderr.strip() or "refused by a hook"
        return None

    for question in sys.stdin:
        if not question.strip():
            continue
        messages.append({"role": "user", "content": json.loads(question)["message"]["content"]})
        reply, calls = {}, []
        for _ in range(turns):
            reply = Claude.api(None, {"model": model, "max_tokens": 1000, "tools": TOOLS, "messages": messages})
            say({"type": "assistant", "message": reply})
            messages.append({"role": "assistant", "content": reply["content"]})
            calls = [c for c in reply["content"] if c["type"] == "tool_use"]
            if not calls:
                break
            results = []
            for call in calls:
                why = "dontAsk: not allowed" if not allowed(call, rules) else refused_by_hook(call)
                text, failed = (why, True) if why else run_tool(call)
                results.append({"type": "tool_result", "tool_use_id": call["id"], "content": text, "is_error": failed})
            say({"type": "user", "message": {"role": "user", "content": results}})
            messages.append({"role": "user", "content": results})
        words = "".join(c.get("text", "") for c in reply.get("content", []))
        say({"type": "result", "subtype": "error_max_turns" if calls else "success", "is_error": bool(calls),
             "result": None if calls else words, "usage": reply.get("usage", {})})
    os.remove(registry)
    return 0


def main():
    args = sys.argv[1:]
    if args[:1] == ["plugin"]:
        sys.exit(plugin(args[1:]))
    if "-p" in args and "--fork-session" in args:
        sys.exit(aside(args))
    mode = args[args.index("--permission-mode") + 1] if "--permission-mode" in args else "default"
    model = args[args.index("--model") + 1] if "--model" in args else "claude-sonnet-5-5"
    old = termios.tcgetattr(0)
    tty.setraw(0)
    try:
        Claude(mode, model).loop()
    finally:
        termios.tcsetattr(0, termios.TCSADRAIN, old)


main()
