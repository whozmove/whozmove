#!/usr/bin/env python3
# The permission hook: a request for your OK in Claude Code is asked in the Whozmove panel too, and so is Claude Code's
# "Switch model?" for a switch the panel asked for.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
"""When a tool needs your OK, Claude Code shows its own prompt and runs this hook alongside it, and whichever is
answered first wins. The hook asks the panel over a connection of its own to the panel's socket,
~/Library/Application Support/Whozmove/hook.sock (HookLine.m, in the Claude Code module), once it has checked the
panel's own process is at the other end. The panel shows the request on the session's row, once it has checked the
hook runs in the session the request names, and answers down that connection only: "allow" (this once) or "deny".
Nothing written in a file can answer it. It never grants more than once: no "always allow" rules.

Claude Code doesn't always stop the hook when its own prompt is answered, so the hook watches the session's
transcript too. Once the tool call has its result there (answered, dismissed or interrupted in Claude), there's
nothing left to ask, and the hook goes. It goes when Claude Code's registry says the session has been idle since the
request was made (its prompt can't still be up then), and when the session ends, too.

Claude's questions (the AskUserQuestion tool) come the same way, since Claude's question box is the permission
prompt for that tool. They're answered the way that box answers them: the tool's input, with your answers
added. Only for that tool may an answer change a tool's input. A "no" to the questions may ask to chat about them
(`clarify`): the hook then passes on Claude Code's own words for its Chat about this, made here from the questions as
Claude asked them and any answers picked so far, so Claude asks what you'd like to clarify. The request says the hook
can (`canSayWhy`).

A plan waiting for your OK (the ExitPlanMode tool) comes the same way too. The panel sends it back with your notes,
which Claude gets as it would from its own prompt and so stays in plan mode to rewrite the plan, or stops it, which
stops Claude's turn. Only a session you allow to approve plans for you (May Approve Plans, in the panel) can have one
approved from the panel: the panel's answer then carries `approvePlan`, and the hook passes on an allow with an empty
input, as Claude's own prompt does. Claude Code takes that as your approval, and leaves plan mode for the mode the
session planned from; it ignores a bare allow for a plan (Claude Code 2.1.304). So an "allow" for a plan without
`approvePlan` is never passed on, and `approvePlan` for any other tool is never either: the hook keeps waiting.

If the panel isn't running, the hook steps aside at once and the prompt is answered as usual. So it does
wherever Claude Code wouldn't show its own prompt alongside: for a sub-agent (some wait for the hook before
asking) and a session that isn't interactive (`claude -p`).

For a session you've told not to wait on you (Don't Wait on Me, in its mode menu), the panel leaves a file,
dont-wait/<session>.json, saying since when and how long a request waits for an answer, which the hook reads as the
request is made and every few seconds while it waits. No answer by then, from the panel or Claude's own prompt, and
the hook turns the request down for now, with words that tell Claude the user is away: to carry on with what doesn't
need it and ask again later, never to try another way, nor to guess a question's answers. It never allows, and never
stops the turn. A plan never goes by itself. When it goes is in the request, as expiresAt, for the panel to show, and
sent again down the connection as it changes. While the request is being answered in the panel, or its session's tab
is in front with you at the Mac, the panel sends a hold down the connection, and the request then waits at least a
minute past that.

It's wired in hooks/hooks.json as a synchronous hook, since a hook that returns a decision can't be async, with a
long timeout, so a request can wait for you. Claude's own prompt stays usable meanwhile.

The same hook runs before every switch of a session's model (PreModelSwitch), a /model typed in the terminal too. Only
a switch the panel has just asked for is its business: right before it types /model, the panel leaves a note for the
session in switches/<session>.panel.json, with the model and when, and the hook takes it, once, only within 20
seconds (Claude Code checks the model with its servers first), and only for that model; the panel takes it back once
its pick is over, so a note left by a pick that never went in can't make a later switch the panel's. Any
other switch is left alone: the hook says nothing, and Claude Code asks as usual. For the panel's switch, Claude Code
says whether the conversation's prompt cache is warm, which is when it would ask "Switch model?" (switching re-reads
the whole conversation). While it isn't, the hook allows the switch, and nothing is asked. While it is, the hook asks
in the panel instead, over a connection as a request is asked: the model it's leaving, the one it's switching to and
how much the conversation holds; the panel's answer comes down the connection: allowed, the switch goes on without
Claude's own question; turned down, it's blocked, and the session stays on its model. If the panel isn't
running, or doesn't answer within a minute, the hook says nothing, and Claude asks in the terminal as usual: the hook
never decides on its own to re-read a cached conversation. Its timeout in hooks/hooks.json is longer than that wait, as
Claude Code blocks a switch whose hook times out.
"""
import glob
import json
import os
import re
import select
import signal
import socket
import subprocess
import sys
import time
import uuid

# Whozmove's folder: must match AppDir in app/shared/Files.m (modules/claude-code/tests/test.sh fails if it doesn't).
ROOT = os.path.expanduser("~/Library/Application Support/Whozmove")
HOOK_LINE = os.path.join(ROOT, "hook.sock")  # the panel's end of each request's connection (HookLine.m)
APPROVE_PLAN = True  # a plan is approved from the panel only when its answer carries approvePlan (PluginInstall.m)
SOL_LOCAL, LOCAL_PEERPID = 0, 2  # macOS's <sys/un.h>: who's at the other end of a Unix socket
WAIT_LIMIT = 3500  # seconds; just under the hook's timeout in hooks/hooks.json
LATE_CALL = 30  # seconds a newer call of a plan is looked for, in case the one found is an earlier plan's
DONT_WAIT = os.path.join(ROOT, "dont-wait")
HOLD = 60  # seconds a request waits at least past the panel's last hold of it
SWITCHES = os.path.join(ROOT, "switches")
NOTE_LASTS = 20  # seconds a panel's note that it's switching a session's model counts for (kNoteLasts, Switches.m)
SWITCH_WAIT = 60  # seconds the panel's answer to "Switch model?" is waited for; well under the hook's timeout
# Set by the hook's tests, never by Claude Code: then why it left a request to Claude's own prompt is said on stderr.
SAY_WHY = os.environ.get("WHOZMOVE_HOOK_WHY") == "1"


def stepped_aside(why):
    if SAY_WHY:
        print("stepped aside: " + why, file=sys.stderr)


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def program_of(pid):
    """The program a process runs, by its path, or None: asked of macOS directly (libproc's proc_pidpath, as the app's
    ProcessPath does), so it takes no time however busy the Mac is; /bin/ps only where that can't be loaded."""
    try:
        import ctypes
        libproc = ctypes.CDLL("/usr/lib/libproc.dylib")
        path = ctypes.create_string_buffer(4096)
        length = libproc.proc_pidpath(ctypes.c_int(pid), path, ctypes.c_uint32(4096))
        return path.value.decode(errors="replace") if length > 0 else None
    except (ImportError, OSError, AttributeError):
        pass
    try:
        return subprocess.run(["/bin/ps", "-p", str(pid), "-o", "comm="], capture_output=True, text=True,
                              timeout=5).stdout.strip() or None
    except (OSError, subprocess.SubprocessError):
        return None


def panel_pid():
    """The running panel's pid, or None. A pid left behind by a panel that crashed can belong to some
    other process by now, so it has to be the panel's executable."""
    try:
        with open(os.path.join(ROOT, "panel.pid")) as f:
            pid = int(f.read().strip())
    except (OSError, ValueError) as e:
        stepped_aside("no panel: %s" % type(e).__name__)
        return None
    command = program_of(pid)
    # The app's executable, CFBundleExecutable in Info.plist (modules/claude-code/tests/test.sh names its stand-in
    # from there).
    if not command or os.path.basename(command) != "Whozmove":
        stepped_aside("no panel: pid %d runs %r" % (pid, command))
        return None
    return pid


class PanelLine:
    """A connection to the panel, for one request or one model switch: opened by the hook, and kept only with the
    panel's own process at its other end (the pid it notes, running as Whozmove), so only the panel answers, and only
    down it. JSON lines both ways. `sock` is None when there's no panel to reach."""

    def __init__(self, panel):
        self.sock, self.buffer = None, b""
        try:
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.settimeout(5)
            sock.connect(HOOK_LINE)
            if sock.getsockopt(SOL_LOCAL, LOCAL_PEERPID) != panel:
                stepped_aside("the line's other end isn't the panel")
                sock.close()
                return
            sock.settimeout(None)
            self.sock = sock
        except OSError as e:
            stepped_aside("no line to the panel: %s" % e)

    def send(self, message):
        try:
            self.sock.sendall((json.dumps(message) + "\n").encode())
            return True
        except OSError:
            return False

    def receive(self, wait):
        """The panel's next message, waiting up to `wait` seconds for it: a dict, None while there's none, or False
        once the panel has closed the connection (refused, or gone)."""
        while b"\n" not in self.buffer:
            try:
                ready, _, _ = select.select([self.sock], [], [], wait)
                if not ready:
                    return None
                chunk = self.sock.recv(65536)
            except (OSError, ValueError):
                return False
            if not chunk:
                return False
            self.buffer += chunk
        line, self.buffer = self.buffer.split(b"\n", 1)
        try:
            message = json.loads(line)
        except ValueError:
            return {}
        return message if isinstance(message, dict) else {}

    def close(self):
        if self.sock:
            try:
                self.sock.close()
            except OSError:
                pass


def interactive_copies(session_id):
    """The session's entries in Claude Code's registry while it runs them interactively (where its prompt shows
    alongside this hook): one for each process its conversation is open in, or none."""
    copies = []
    for path in glob.glob(os.path.expanduser("~/.claude/sessions/*.json")):
        try:
            with open(path) as f:
                entry = json.load(f)
        except (OSError, ValueError):
            continue
        if isinstance(entry, dict) and entry.get("sessionId") == session_id and entry.get("kind") == "interactive" \
                and isinstance(entry.get("pid"), int) and alive(entry["pid"]):
            copies.append(entry)
    return copies


def own_copy(session_id):
    """The pid of the Claude Code process this hook runs under (its parent, or one above that), as the registry
    lists it for this session; or None. With the conversation open in two places, its prompt is in that one."""
    pid = os.getppid()
    for _ in range(4):
        if pid <= 1:
            break
        try:
            with open(os.path.expanduser("~/.claude/sessions/%d.json" % pid)) as f:
                entry = json.load(f)
        except (OSError, ValueError):
            entry = None
        if isinstance(entry, dict) and entry.get("sessionId") == session_id:
            return pid
        try:
            pid = int(subprocess.run(["/bin/ps", "-p", str(pid), "-o", "ppid="], capture_output=True, text=True,
                                     timeout=5).stdout.strip())
        except (OSError, ValueError, subprocess.SubprocessError):
            break
    return None


def idle_since(copies, at):
    """Whether Claude Code says every copy given has been idle since `at` (in ms): no prompt of its can still be up,
    though the call's result may never reach the transcript (a plan approved, then the turn stopped). Statuses as
    Claude Code 2.1.304 writes them: busy, idle, shell (idle, with a command it started still running in the
    background), or waiting while it asks you something."""
    return bool(copies) and all(c.get("status") in ("idle", "shell") and isinstance(c.get("statusUpdatedAt"), (int, float))
                                and c["statusUpdatedAt"] > at for c in copies)


def transcript_of(event):
    path = event.get("transcript_path")
    if path and os.path.isfile(path):
        return path
    found = glob.glob(os.path.expanduser("~/.claude/projects/*/%s.jsonl" % event["session_id"]))
    return found[0] if found else None


def find_call(path, event, earlier):
    """The tool call this request is for, in the transcript: (its id, the byte offset just past its line, whether
    it was told by its id or its input), or (None, None, False) while it isn't written yet. Claude Code's id for it if
    the event has one, else the newest call of this tool with this input. A plan's input is read again from its file
    for the request, and the file may have changed since Claude wrote the call (Claude or you editing it), so for a
    plan the newest call of the tool will do, which may be an earlier plan's while this one isn't written yet. A call
    in `earlier` was answered before this request was made, so this one, newer, isn't written yet. Only Claude's own
    lines count: Claude Code writes calls again, after their results, in its record of each request it makes, and a
    call found there would have its result before it."""
    try:
        with open(path, "rb") as f:
            f.seek(0, os.SEEK_END)
            base = max(0, f.tell() - 4 * 1024 * 1024)
            f.seek(base)
            tail = f.read()
    except OSError:
        return None, None, False
    end = len(tail)
    while end > 0:
        start = tail.rfind(b"\n", 0, end - 1) + 1
        line = tail[start:end]
        end = start
        if b'"tool_use"' not in line:
            continue
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if not isinstance(entry, dict) or entry.get("type") != "assistant":
            continue
        content = (entry.get("message") or {}).get("content")
        for item in content if isinstance(content, list) else []:
            if not isinstance(item, dict) or item.get("type") != "tool_use":
                continue
            if event.get("tool_use_id"):
                exact = item.get("id") == event["tool_use_id"]
                loose = False
            else:
                exact = item.get("name") == event.get("tool_name") and item.get("input") == event.get("tool_input")
                loose = item.get("name") == event.get("tool_name") == "ExitPlanMode"
            if (exact or loose) and item.get("id") in earlier:
                return None, None, False
            if exact or loose:
                return item.get("id"), base + start + len(line), exact
    return None, None, False


def has_result(path, call_id, offset):
    """Whether the call's result has been written after `offset`; how far the transcript was read; and the byte
    offset just past the result's line, once there is one."""
    try:
        with open(path, "rb") as f:
            f.seek(offset)
            chunk = f.read()
    except OSError:
        return False, offset, None
    end = chunk.rfind(b"\n") + 1  # complete lines only
    at = 0
    while at < end:
        line_end = chunk.index(b"\n", at) + 1
        line, at = chunk[at:line_end], line_end
        if call_id.encode() not in line:
            continue
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        content = (entry.get("message") or {}).get("content") if isinstance(entry, dict) else None
        if entry.get("type") == "user" and isinstance(content, list) and any(
                isinstance(item, dict) and item.get("type") == "tool_result" and item.get("tool_use_id") == call_id
                for item in content):
            return True, offset + end, offset + line_end
    return False, offset + end, None


def wait_rule(session_id):
    """For a session you've told not to wait on you, since when (ms) and how long (seconds) a request waits for an
    answer, as the panel's file says (kDontWaitMinutes in DontWait.m; less in the tests); else None."""
    if not re.fullmatch(r"[A-Za-z0-9-]{1,128}", session_id):
        return None
    try:
        with open(os.path.join(DONT_WAIT, session_id + ".json")) as f:
            rule = json.load(f)
    except (OSError, ValueError):
        return None
    if not isinstance(rule, dict):
        return None
    since, after = rule.get("since"), rule.get("after")
    if not all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in (since, after)):
        return None
    return since, int(min(max(after, 1), WAIT_LIMIT - 100))


def how_long(seconds):
    if seconds % 60:
        return "%d second%s" % (seconds, "" if seconds == 1 else "s")
    return "%d minute%s" % (seconds // 60, "" if seconds == 60 else "s")


def clarify_words(tool_input, answers):
    """What Claude Code's own Chat about this tells Claude (2.1.304): to ask what the user would like to clarify, then
    each question as Claude asked it, with any answer picked so far. Only the questions' own words and the answers to
    them are used, each answer a line of at most 2,000 characters."""
    questions = (tool_input or {}).get("questions") if isinstance(tool_input, dict) else None
    answers = answers if isinstance(answers, dict) else {}
    asked = []
    for each in questions if isinstance(questions, list) else []:
        words = each.get("question") if isinstance(each, dict) else None
        if not isinstance(words, str):
            continue
        answer = answers.get(words)
        answer = " ".join(answer.split())[:2000] if isinstance(answer, str) else ""
        asked.append('- "%s"\n  %s' % (words, "Answer: " + answer if answer else "(No answer provided)"))
    return ("The user wants to clarify these questions.\n"
            "This means they may have additional information, context or questions for you.\n"
            "Take their response into account and then reformulate the questions if appropriate.\n"
            "Start by asking them what they would like to clarify.\n\n"
            "Questions asked:\n" + "\n".join(asked))


def take_note(session_id, event):
    """Whether the panel left a note that it's switching this session to the model the switch is for, within the
    last NOTE_LASTS seconds. The note is taken as it's read, so it counts once."""
    path = os.path.join(SWITCHES, session_id + ".panel.json")
    try:
        with open(path) as f:
            note = json.load(f)
        os.remove(path)
    except (OSError, ValueError):
        return False
    if not isinstance(note, dict) or not isinstance(note.get("at"), (int, float)) \
            or not isinstance(note.get("to"), str) or not note["to"]:
        return False
    if time.time() * 1000 - note["at"] > NOTE_LASTS * 1000:
        return False
    asked = [m for m in (event.get("requested_model"), event.get("to_model")) if isinstance(m, str)]
    return any(m.startswith(note["to"]) for m in asked)


def switch_decision(decision, reason=None):
    output = {"hookEventName": "PreModelSwitch", "permissionDecision": decision}
    if reason:
        output["permissionDecisionReason"] = reason
    print(json.dumps({"hookSpecificOutput": output}))


def model_switch(event):
    session_id = event["session_id"]
    if not re.fullmatch(r"[A-Za-z0-9-]{1,128}", session_id) or not take_note(session_id, event):
        stepped_aside("no note from the panel that it's switching %s's model" % session_id)
        return
    if event.get("prompt_cache_warm") is False:  # nothing to re-read: Claude Code wouldn't ask
        switch_decision("allow")
        return
    panel = panel_pid()
    line = PanelLine(panel) if panel else None
    if not line or not line.sock:
        return  # panel_pid or PanelLine has said why

    def cancelled(*_):  # stopped by Claude Code
        line.close()
        sys.exit(0)

    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(sig, cancelled)
    tokens = event.get("context_tokens")
    try:
        if not line.send({"switch": {
            "sessionId": session_id,
            "from": event.get("from_model") if isinstance(event.get("from_model"), str) else "",
            "to": event.get("to_model") if isinstance(event.get("to_model"), str) else "",
            "tokens": tokens if isinstance(tokens, int) and tokens > 0 else None,
            "at": int(time.time() * 1000),
            "pid": os.getpid(),
        }}):
            stepped_aside("the switch's question couldn't be sent")
            return
        started = time.time()
        while time.time() - started < SWITCH_WAIT:
            message = line.receive(0.25)
            if message is False:
                return
            reply = (message or {}).get("answer")
            allow = reply.get("allow") if isinstance(reply, dict) else None
            if allow is True:
                switch_decision("allow")
                return
            if allow is False:
                switch_decision("deny", "You kept this model in Whozmove.")
                return
            if not alive(panel):
                return
    finally:
        line.close()


def main():
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return
    # The id names files and is sent to the panel, so one that isn't plain ("../x") is left to Claude's own prompt.
    if not isinstance(event, dict) or not isinstance(event.get("session_id"), str) \
            or not re.fullmatch(r"[A-Za-z0-9-]{1,128}", event["session_id"]):
        return
    if event.get("agent_id"):
        return
    if event.get("hook_event_name") == "PreModelSwitch":
        model_switch(event)
        return
    panel = panel_pid()
    if not panel:
        return
    if not interactive_copies(event["session_id"]):
        stepped_aside("no interactive copy of %s in the registry" % event["session_id"])
        return
    line = PanelLine(panel)
    if not line.sock:
        return
    ask_id = uuid.uuid4().hex

    def clean_up(*_):
        line.close()

    def cancelled(*_):  # stopped by Claude Code: answered in Claude, or the hook timed out
        clean_up()
        sys.exit(0)

    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(sig, cancelled)

    transcript = transcript_of(event)
    try:
        before = os.path.getsize(transcript) if transcript else 0  # a result already there isn't this request's
    except OSError:
        before = 0
    asked_at = int(time.time() * 1000)
    plan = event.get("tool_name") == "ExitPlanMode"
    shown = {
        "id": ask_id,
        "sessionId": event["session_id"],
        "tool": event.get("tool_name", ""),
        "input": event.get("tool_input", {}),
        "cwd": event.get("cwd", ""),
        "at": asked_at,
        "pid": os.getpid(),
    }
    if event.get("tool_name") == "AskUserQuestion":
        shown["canSayWhy"] = True

    def expiry():
        """When the request goes by itself (ms), or None: `after` from when it was made or the session was told not
        to wait on you, whichever is later, and never sooner than a hold allows. Sent with the request as it's asked,
        and again down the connection as it changes."""
        nonlocal waits, sent
        rule = None if plan else wait_rule(event["session_id"])
        at = None
        if rule:
            since, after = rule
            waits = after
            at = int(max(asked_at, since) + after * 1000)
            if held_at:
                at = max(at, int(held_at) + min(HOLD, after) * 1000)
        if not sent:
            if at is not None:
                shown["expiresAt"] = at
            sent = line.send({"ask": shown})
        elif at != shown.get("expiresAt"):
            shown["expiresAt"] = at
            line.send({"expiresAt": at})
        return at

    # Seconds a request waits, as the panel's file last said; whether it has been asked; when the panel last held it.
    waits, sent, held_at = None, False, None
    expires = expiry()
    if not sent:
        stepped_aside("the request couldn't be sent")
        clean_up()
        return
    call_id, read_to, exact, earlier, own = None, None, False, set(), None
    try:
        started, ticks = time.time(), 0
        while time.time() - started < WAIT_LIMIT:
            message = line.receive(0.25)
            if message is False:  # the panel refused it (not this session's) or quit: Claude's own prompt has it
                return
            message = message or {}
            held = message.get("held")
            if isinstance(held, (int, float)) and not isinstance(held, bool):
                held_at = held  # being answered in the panel: it waits at least a minute past this
                expires = expiry()
            reply = message.get("answer")
            behavior = reply.get("behavior") if isinstance(reply, dict) else None
            # A plan's approval only as a session you allow sends it; never for anything else.
            approve = isinstance(reply, dict) and reply.get("approvePlan") is True
            if approve and not (plan and behavior == "allow"):
                behavior = None
            if behavior in ("allow", "deny") and not (plan and behavior == "allow" and not approve):
                question = event.get("tool_name") == "AskUserQuestion"
                if plan and behavior == "allow":
                    # Empty, as Claude's own prompt sends it: never anything of the panel's, nor a mode.
                    decision = {"behavior": "allow", "updatedInput": {}}
                elif behavior == "allow":
                    decision = {"behavior": "allow"}
                    answers = reply.get("answers")
                    if question and isinstance(answers, dict):
                        decision["updatedInput"] = dict(event.get("tool_input") or {},
                                                        answers={str(k): str(v) for k, v in answers.items()})
                elif plan and reply.get("stop") is True:
                    decision = {"behavior": "deny", "interrupt": True,
                                "message": "The user stopped here and doesn't want this plan carried out."}
                elif plan and isinstance(reply.get("message"), str) and reply["message"].strip():
                    decision = {"behavior": "deny", "message": "The user wants changes to the plan: "
                                + reply["message"].strip()[:10000]}
                elif question and reply.get("clarify") is True:
                    decision = {"behavior": "deny", "message": clarify_words(event.get("tool_input"),
                                                                             reply.get("answers"))}
                else:
                    decision = {"behavior": "deny", "message": "The user chose not to answer these questions."
                                if question else "Denied in Whozmove."}
                print(json.dumps({"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": decision}}))
                return
            if expires and time.time() * 1000 >= expires:
                expires = expiry()  # Don't Wait on Me turned off or on since it was last read
                if expires and time.time() * 1000 >= expires:
                    waited = how_long(waits)
                    if event.get("tool_name") == "AskUserQuestion":
                        words = ("No answer in %s: the user is away and hasn't seen these questions. Carry on with "
                                 "whatever doesn't need the answers, then ask them again later, not straight away. "
                                 "Don't guess the answers." % waited)
                    else:
                        words = ("No answer in %s: the user is away and hasn't turned this down. Carry on with "
                                 "whatever doesn't need it, then ask again later, not straight away. Don't try "
                                 "another way to do it." % waited)
                    decision = {"behavior": "deny", "message": words}  # never interrupt: Claude carries on
                    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PermissionRequest",
                                                             "decision": decision}}))
                    return
            if not alive(panel):  # the panel quit: leave it to Claude's own prompt
                return
            ticks += 1
            if transcript and ticks % 4 == 0:  # each second: was it settled in Claude meanwhile?
                # A plan found by its tool alone may be an earlier one still unanswered, so for a while a newer one is
                # looked for too.
                if read_to is None or (not exact and time.time() - started < LATE_CALL):
                    newer, offset, newer_exact = find_call(transcript, event, earlier)
                    if newer and newer != call_id:
                        call_id, read_to, exact = newer, offset, newer_exact
                if read_to is not None:
                    done, read_to, result_end = has_result(transcript, call_id, read_to)
                    if done and result_end <= before:  # an earlier call, answered before this request was made
                        earlier.add(call_id)
                        call_id, read_to = None, None
                    elif done:
                        return
            if ticks % 20 == 0:
                copies = interactive_copies(event["session_id"])
                own = own or own_copy(event["session_id"])
                mine = [c for c in copies if c["pid"] == own]
                if not copies or (own and not mine):  # the session ended, or its process went on to another
                    return
                if idle_since(mine or copies, asked_at):  # nothing waits in it now
                    return
                expires = expiry()  # turned on or off meanwhile
    finally:
        clean_up()


if __name__ == "__main__":
    main()
