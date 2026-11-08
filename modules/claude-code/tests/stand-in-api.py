#!/usr/bin/env python3
# A stand-in for Anthropic's Messages API, for the real Claude Code run (real.sh): Claude Code is pointed here with
# ANTHROPIC_BASE_URL and a made-up key, so it runs with no account, and each turn is answered from a script, chosen by
# a marker in what was typed (STEP:bash, say). Only Python's own library.
#   stand-in-api.py <port file> <log file>
# Listens on 127.0.0.1 at a free port, written to <port file>. Every request is written to <log file> as a line of JSON:
# its path, its model, the newest text typed, the results of the tools it ran and what was answered; never a header.
# A path the stand-in doesn't know, or a key but the made-up one, is answered with an error and written down as
# `unknown`, which the run reports as one it couldn't check. With STAND_IN_BODIES naming a folder, each request to
# /v1/messages is kept there whole too, as <n>.json (its body, and its headers but the key), so the run can compare a
# side question's with its session's.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
import json
import os
import re
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT_FILE, LOG = sys.argv[1], sys.argv[2]
# The made-up key real.sh gives Claude Code. Its last 20 characters are what the home's ~/.claude.json approves.
KEY = "sk-ant-api03-stand-in-" + "0" * 60
lock = threading.Lock()
counter = [0]
kept_count = [0]  # the requests kept whole, apart from the ids, so keeping them changes no id


def write(entry):
    with lock, open(LOG, "a") as f:
        f.write(json.dumps(entry, sort_keys=True) + "\n")


def next_id(prefix):
    with lock:
        counter[0] += 1
        return f"{prefix}_standin{counter[0]:04d}"


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(text_of(c.get("text", c.get("content", ""))) for c in content if isinstance(c, dict))
    return ""


def newest(messages):
    """The newest user message's own words (what was typed, without the reminders Claude Code adds), and the results
    of the tools it carries."""
    for message in reversed(messages):
        if message.get("role") != "user":
            continue
        content = message.get("content")
        blocks = [{"type": "text", "text": content}] if isinstance(content, str) else content or []
        said = [b.get("text", "") for b in blocks if isinstance(b, dict) and b.get("type") == "text"]
        said = [re.sub(r"<system-reminder>.*?</system-reminder>", "", s, flags=re.S).strip() for s in said]
        results = [{"id": b.get("tool_use_id"), "error": bool(b.get("is_error")),
                    "text": text_of(b.get("content"))[:400]}
                   for b in blocks if isinstance(b, dict) and b.get("type") == "tool_result"]
        return "\n".join(s for s in said if s), results
    return "", []


def tool(name, **inputs):
    return [{"type": "tool_use", "id": next_id("toolu"), "name": name, "input": inputs}]


def text(words):
    return [{"type": "text", "text": words}]


# The steps real.sh's driver asks for. A tool's result is always answered with a short reply, so each turn ends.
def answer(body):
    said, results = newest(body.get("messages", []))
    if results:
        return "result", text("Done: the step ran.")
    if not body.get("tools"):
        # A request with no tools is one of Claude Code's own on the side (the tab's topic, a compaction's summary):
        # one plain answer does for each.
        if re.search(r"summar", json.dumps(body.get("system", "")) + said, re.I):
            return "summary", text("<summary>A stand-in conversation: a reply, a command, a file and a question."
                                   "</summary>")
        return "side", text("Stand-in topic")
    step = (re.search(r"\bSTEP:(\w+)", said) or [None, "reply"])[1]
    # The file the write step names goes only in the run's own project, never wherever the stand-in was started.
    cwd = os.environ.get("STAND_IN_PROJECT")
    if step == "write" and not cwd:
        return "reply", text("No project folder was given to the stand-in, so it writes nothing.")
    if step == "bash":
        return step, tool("Bash", command="echo stand-in-check", description="Print a word")
    if step == "write":
        return step, tool("Write", file_path=os.path.join(cwd, "notes.txt"), content="one line\n")
    if step == "background":
        return step, tool("Bash", command="sleep 600", description="Wait in the background", run_in_background=True)
    if step == "ask":
        return step, tool("AskUserQuestion", questions=[{
            "question": "Which colour?", "header": "Colour", "multiSelect": False,
            "options": [{"label": "Red", "description": "The red one"},
                        {"label": "Blue", "description": "The blue one"}]}])
    if step == "plan":
        return step, tool("ExitPlanMode", plan="# Plan\n\n1. Say hello.\n")
    return "reply", text("Hello from the stand-in.")


def usage(content):
    return {"input_tokens": 12, "cache_creation_input_tokens": 2000, "cache_read_input_tokens": 30000,
            "output_tokens": 7 + len(json.dumps(content)) // 4}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def reply(self, code, data, kind="application/json"):
        raw = data if isinstance(data, bytes) else json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(raw)

    def refuse(self, why):
        # Only that it came, and why it was refused: never the key or header itself.
        write({"path": self.path.split("?")[0], "method": self.command, "unknown": why})
        self.reply(401 if "key" in why else 404,
                   {"type": "error", "error": {"type": "not_found_error", "message": why}})

    def made_up_key(self):
        return self.headers.get("x-api-key") == KEY and not self.headers.get("authorization")

    def do_HEAD(self):
        # Claude Code's connection check before its first request; it carries no key.
        if self.path.split("?")[0] == "/api/hello":
            return self.reply(200, b"")
        self.refuse("a path the stand-in doesn't know")

    def do_GET(self):
        self.refuse("a path the stand-in doesn't know")

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"{}")
        path = self.path.split("?")[0]
        if not self.made_up_key():
            return self.refuse("a key but the stand-in's made-up one")
        if path == "/v1/messages/count_tokens":
            write({"path": path})
            return self.reply(200, {"input_tokens": 1000})
        if path != "/v1/messages":
            return self.refuse("a path the stand-in doesn't know")
        step, content = answer(body)
        said, results = newest(body.get("messages", []))
        if os.environ.get("STAND_IN_BODIES"):
            with lock:
                kept_count[0] += 1
                kept = os.path.join(os.environ["STAND_IN_BODIES"], f"{kept_count[0]:05d}.json")
            headers = {k.lower(): v for k, v in self.headers.items() if k.lower() not in ("x-api-key", "authorization")}
            with open(kept, "w") as f:
                json.dump({"headers": headers, "body": body}, f)
        write({"path": path, "model": body.get("model"), "said": said[-200:], "results": results, "step": step,
               "answered": [c.get("name") or c["type"] for c in content]})
        stop = "tool_use" if content[0]["type"] == "tool_use" else "end_turn"
        message = {"id": next_id("msg"), "type": "message", "role": "assistant", "model": body.get("model"),
                   "content": content, "stop_reason": stop, "stop_sequence": None, "usage": usage(content)}
        if not body.get("stream"):
            return self.reply(200, message)
        events = [("message_start", {"type": "message_start", "message": dict(
            message, content=[], stop_reason=None, usage=dict(usage(content), output_tokens=1))})]
        for i, block in enumerate(content):
            if block["type"] == "text":
                events += [("content_block_start", {"type": "content_block_start", "index": i,
                                                    "content_block": {"type": "text", "text": ""}}),
                           ("content_block_delta", {"type": "content_block_delta", "index": i,
                                                    "delta": {"type": "text_delta", "text": block["text"]}})]
            else:
                events += [("content_block_start", {"type": "content_block_start", "index": i,
                                                    "content_block": dict(block, input={})}),
                           ("content_block_delta", {"type": "content_block_delta", "index": i, "delta": {
                               "type": "input_json_delta", "partial_json": json.dumps(block["input"])}})]
            events.append(("content_block_stop", {"type": "content_block_stop", "index": i}))
        events += [("message_delta", {"type": "message_delta", "delta": {"stop_reason": stop, "stop_sequence": None},
                                      "usage": {"output_tokens": usage(content)["output_tokens"]}}),
                   ("message_stop", {"type": "message_stop"})]
        self.reply(200, "".join(f"event: {name}\ndata: {json.dumps(data)}\n\n" for name, data in events).encode(),
                   "text/event-stream")


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
with open(PORT_FILE + ".tmp", "w") as f:
    f.write(str(server.server_address[1]))
os.replace(PORT_FILE + ".tmp", PORT_FILE)
server.serve_forever()
