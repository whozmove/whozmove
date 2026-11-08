#!/usr/bin/env python3
# A stand-in for the panel's end of the hooks' line (HookLine.m), for the hooks' tests: the compiled stand-in
# named as the app is listens on the socket and accepts each line itself, so the hook finds the panel's own process at
# the other end, and opens a line of its own for each to this, listening as file 3, passing the bytes on. Each request,
# or "Switch model?", it's asked is mirrored into a folder of the test's own (asks/<id>.json,
# switches/<session>.ask.json), where the test reads it, and what the test writes beside it there is sent down the line
# as the panel would: <id>.answer.json or <session>.answer.json as the answer, and a touch of <id>.held as a hold. The
# files go once the hook closes its line, but each request for your OK also stays in seen/, numbered in the order it
# came (seen/<n>.json), so a test on a busy Mac still finds one whose hook was done with it before the test looked.
# Nothing here reads Whozmove's own folder: an answer written there is one no panel sends. What became of each line,
# with its time, goes in the folder's log (with the stand-in app's own notes), which the test shows when a request it
# waited for never came.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
import json
import os
import select
import socket
import sys
import time

MIRROR = sys.argv[1]
ASKS, SWITCHES, SEEN, WORDS = (os.path.join(MIRROR, name) for name in ("asks", "switches", "seen", "words"))
LOG = os.path.join(MIRROR, "log")
for folder in (ASKS, SWITCHES, SEEN, WORDS):
    os.makedirs(folder, exist_ok=True)
listener = socket.socket(fileno=3)
parent = os.getppid()


def write(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, path)


def note(what):
    with open(LOG, "a") as f:
        f.write("%.3f panel: %s\n" % (time.time(), what))


def remove(*paths):
    for path in paths:
        try:
            os.remove(path)
        except OSError:
            pass


class Line:
    def __init__(self, sock):
        self.sock, self.buffer, self.asked, self.request, self.answer, self.held = sock, b"", None, None, None, 0

    def send(self, message):
        try:
            self.sock.sendall((json.dumps(message) + "\n").encode())
        except OSError:
            pass

    def heard(self, message):
        if self.asked is None:
            if isinstance(message.get("ask"), dict):
                self.asked = message["ask"]
                self.request = os.path.join(ASKS, self.asked["id"] + ".json")
                self.answer = os.path.join(ASKS, self.asked["id"] + ".answer.json")
            elif isinstance(message.get("words"), dict):
                # The words hook asks once: what the test left for its session (words/<session>.txt) goes down the
                # line, then the line closes, as the panel answers. What it asked is mirrored beside it.
                asked = message["words"]
                session = str(asked.get("sessionId"))
                note("line %d asked words for %s at %s" % (self.sock.fileno(), session, asked.get("event")))
                write(os.path.join(WORDS, session + ".asked.json"), asked)
                left = os.path.join(WORDS, session + ".txt")
                try:
                    with open(left) as f:
                        words = f.read()
                    os.remove(left)
                except OSError:
                    words = ""
                self.send({"words": words})
                self.sock.shutdown(socket.SHUT_RDWR)
                return
            elif isinstance(message.get("switch"), dict):
                self.asked = message["switch"]
                self.request = os.path.join(SWITCHES, self.asked["sessionId"] + ".ask.json")
                self.answer = os.path.join(SWITCHES, self.asked["sessionId"] + ".answer.json")
                remove(self.answer)  # one left from an earlier question isn't this one's
            else:
                return
            what = self.asked.get("id") or self.asked.get("sessionId")
            note("line %d asked %s, at %s by the hook's clock" % (self.sock.fileno(), what, self.asked.get("at")))
            write(self.request, self.asked)
            if self.request.startswith(ASKS):
                write(os.path.join(SEEN, "%d.json" % (len(os.listdir(SEEN)) + 1)), self.asked)
        elif "expiresAt" in message and self.request.startswith(ASKS):
            if message["expiresAt"] is None:
                self.asked.pop("expiresAt", None)
            else:
                self.asked["expiresAt"] = message["expiresAt"]
            write(self.request, self.asked)

    def look(self):
        """What the test wrote since the last look: an answer, or a new hold."""
        if not self.answer:
            return
        try:
            with open(self.answer) as f:
                reply = json.load(f)
            os.remove(self.answer)
            self.send({"answer": reply})
        except (OSError, ValueError):
            pass
        if self.request.startswith(ASKS):
            try:
                held = os.path.getmtime(self.request[:-len(".json")] + ".held")
            except OSError:
                held = 0
            if held and held != self.held:
                self.held = held
                self.send({"held": int(held * 1000)})

    def closed(self):
        note("line %d closed, %s" % (self.sock.fileno(), "after its request" if self.asked else "nothing asked"))
        self.sock.close()
        if self.request:
            remove(self.request, self.answer, self.request[:-len(".json")] + ".held")


lines = []
while os.getppid() == parent:
    ready, _, _ = select.select([listener] + [each.sock for each in lines], [], [], 0.1)
    for sock in ready:
        if sock is listener:
            client, _ = listener.accept()
            note("line %d opened" % client.fileno())
            lines.append(Line(client))
            continue
        line = next(each for each in lines if each.sock is sock)
        chunk = sock.recv(65536)
        if not chunk:
            line.closed()
            lines.remove(line)
            continue
        line.buffer += chunk
        while b"\n" in line.buffer:
            text, line.buffer = line.buffer.split(b"\n", 1)
            try:
                message = json.loads(text)
            except ValueError:
                continue
            if isinstance(message, dict):
                line.heard(message)
    for line in lines:
        line.look()
    time.sleep(0.02)
