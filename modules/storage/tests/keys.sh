#!/bin/bash
# Keys' tests: what a look finds in a sample home folder, with each Betterleaks tools/betterleaks.txt
# names, for builds and for releases (Whozmove --print-keys, compared with keys.expected.txt): a checkout with a key
# already pushed, one in a commit not pushed yet, one not committed, a new file git would add, an MCP settings file,
# Aider's history and a token in a remote's address, a key git ignores (not listed), a key made up for a test's
# recorded output (pushed, and in a worktree too: a sample), a GitHub token in a test's file and a Linear key in a
# test's fixture (both counted all the same: a provider's); another AI tool's records, a key
# right after a line break in one; Claude Code's records (a conversation, with what you sent, what a tool read and a
# sub-agent's, a tool's long output, the history of your messages, a long paste and a copy of a file it edited), each
# tied to its session and its project's folder; credential files other accounts can read (and Docker's settings with no
# sign-in, not listed); a shell history; your shell's settings (~/.zshrc others can read, and ~/.bashrc); Downloads
# (a file that's nothing but a key, the one place Move to Trash is offered, notes holding one, and a token in escaped
# JSON, its last 4 its own); in the shell
# history, a sign-in token that has run out, by its own date, a key after an id and a colon, and one in an address
# with a % in its user name (neither taken for a name); what can't be a key (a GitHub token whose checksum fails or
# too short, variables' names, a file's hash, a placeholder, a user given to curl -u as "$NAME:", a sentence set as a
# password), a key in hex, keys a conversation calls made up, a UUID a lookup sets as `key` (an id) and one set as a
# service's key (counted); what Claude Code reads as instructions (CLAUDE.md files, an import, memory), a sub-agent's
# prompt, a compaction's summary and a line run with !; keys an agent made (folded), and those it wrote that still
# count; a copy cut short, joined to its key, and a Spotify id; and Whozmove's own
# record of a message, masked by the look. Each place's line shows what it offers. Then that no made-up key is
# anywhere whole, in what's printed or in Whozmove's folder; its actions (--print-keys-act), Move to Trash's checks
# among them, and its refusal for a file that holds more than the key; a second look,
# which still lists the key sent to Claude; and one without Full Disk Access, with a project in Documents, which it
# says it couldn't look in; AI tools' records sharing Betterleaks' runs, one it can't get through holding back only
# itself, and a key's header with no end not hiding the next record's key; files sent to Betterleaks by how many and
# how large. And a copy without Betterleaks, with its way to get Whozmove again (again.expected.txt).
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# The keys are made up while it runs, from fixed seeds, so they read the same every time and none is ever written
# whole in the repo, where GitHub and scanners would take them for real ones.
#
# Prints the difference and exits 1 if anything changed.
# modules/storage/tests/test.sh runs it.
#   modules/storage/tests/keys.sh            run and compare
#   modules/storage/tests/keys.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/../../.." || exit 1
. tests/sandboxed.sh "$@"
HERE=modules/storage/tests
. tests/lib.sh
T=$(throwaway keys) || exit 1
leave_nothing "$T"
. tests/compare.sh
APP=$(built_app "$T") || exit 1
# What Keys wrote in a home's panel.log, without its times, how long a look took and Betterleaks' version said as that.
keys_log() {
  python3 -I -c '
import re, sys
try:
    lines = open(sys.argv[1] + "/Library/Application Support/Whozmove/panel.log", errors="replace").read().splitlines()
except OSError:
    lines = []
for line in lines:
    said = line.split("  ", 1)[-1]
    if said.startswith("Keys"):
        said = re.sub(r"looked for [0-9]+ (s|min),", "looked for (its time),", said)
        print(re.sub(r"Betterleaks [0-9][^:]*:", "Betterleaks (its version):", said))' "$1"
}
# git here ignores your personal git settings (signing, hooks, …), so the sample repo's commits always work.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_AUTHOR_DATE=2030-01-01T10:00:00Z GIT_COMMITTER_DATE=2030-01-01T10:00:00Z

# A made-up key of a kind, from a seed: its provider's start, then letters and digits.
key() {
  python3 -I -c '
import random, string, sys, zlib
kind, seed = sys.argv[1], int(sys.argv[2])
r = random.Random(seed)
def pick(chars, n): return "".join(r.choice(chars) for _ in range(n))
alnum = string.ascii_letters + string.digits
# A GitHub token ends with a checksum of the 30 characters before: CRC-32, in base 62.
def github(body, start="p"):
    crc, digits, sum = zlib.crc32(body.encode()), string.digits + string.ascii_uppercase + string.ascii_lowercase, ""
    for _ in range(6): crc, sum = crc // 62, digits[crc % 62] + sum
    return "gh" + start + "_" + body + sum
print({"github": lambda: github(pick(alnum, 30)),
       "github-oauth": lambda: github(pick(alnum, 30), "o"),
       "github-user": lambda: github(pick(alnum, 30), "u"),
       "github-server": lambda: github(pick(alnum, 30), "s"),
       "github-refresh": lambda: github(pick(alnum, 30), "r"),
       "letters": lambda: pick(string.ascii_letters, 16),
       "github-broken": lambda: github(pick(alnum, 30))[:-1] + "0",
       "github-short": lambda: "gh" "p_" + pick(alnum, 30),
       "hex": lambda: pick("0123456789abcdef", 32),
       "github-fine": lambda: "github" "_pat_" + pick(alnum + "_", 82),
       "anthropic": lambda: "sk-" "ant-api03-" + pick(alnum + "-_", 93) + "AA",
       "npm": lambda: "np" "m_" + pick(alnum, 36),
       "gitlab": lambda: "gl" "pat-" + pick(alnum + "-_", 20),
       "huggingface": lambda: "h" "f_" + pick(string.ascii_letters, 34),
       "linear": lambda: "lin" "_api_" + pick(string.ascii_lowercase + string.digits, 40),
       "twilio": lambda: "S" "K" + pick("0123456789abcdef", 32),
       "brave": lambda: "BS" "A" + pick(alnum, 28),
       "password": lambda: pick(alnum, 12) + "#" + pick(string.digits, 4),
       "id": lambda: "-".join(pick("0123456789abcdef", n) for n in (8, 4, 4, 4, 12)),
       "spotify": lambda: pick(alnum, 22),
       "any": lambda: pick(alnum, 32)}[kind]())' "$1" "$2"
}
# A made-up sign-in token (JWT) whose own end date has passed, from a seed.
ended_token() {
  python3 -I -c '
import base64, json, random, string, sys
r = random.Random(int(sys.argv[1]))
part = lambda value: base64.urlsafe_b64encode(json.dumps(value, separators=(",", ":")).encode()).rstrip(b"=").decode()
print(part({"alg": "HS256", "typ": "JWT"}) + "." + part({"sub": "someone", "exp": 1700000000}) + "."
      + "".join(r.choice(string.ascii_letters + string.digits + "_-") for _ in range(43)))' "$1"
}
PUSHED=$(key github 1); COMMITTED=$(key anthropic 2); NEW=$(key npm 3); IGNORED=$(key github 4)
MCP=$(key gitlab 5); AIDER=$(key github 6); REMOTE=$(key github 7); CHANGED=$(key github-fine 8)
CODEX=$(key anthropic 9); GEMINI=$(key huggingface 10); HISTORY=$(key github 11)
SENT=$(key anthropic 12); PASTE=$(key github 13); TOOL=$(key gitlab 14); COPY=$(key huggingface 15)
SAMPLE=$(key any 16); FIXTURE=$(key github 17); ENDED=$(ended_token 18); RECORDED=$(ended_token 19)
LINEAR=$(key linear 20); PAIRED=$(key github 21); PAIR_ID=$(key twilio 22); ESCAPED=$(key github 23)
UNPUSHED_SAMPLE=$(key any 24)
SESSION_ID=$(key id 25); IN_SIGNATURE=$(key brave 26); IN_PICTURE=$(key brave 27); BRAVE=$(key brave 28)
PASSWORD=$(key password 29); AN_ID=$(key id 30); ID_KEY=$(key id 31); REPORTED=$(key github 32)
BROKEN=$(key github-broken 34); SHORT=$(key github-short 35); HASH=$(key hex 36); HEX_KEY=$(key hex 37)
MADE=$(key github 38); MADE_ANY=$(key any 39); NOT_TEST=$(key any 40); NOT_FAKE=$(key any 41)
INSTEAD=$(key any 42); HEX_NAMED=$(key hex 51); LETTERS=$(key letters 44); DOLLAR="\$$(key any 45)!7"
OAUTH=$(key github-oauth 46); USER_TOKEN=$(key github-user 47); SERVER=$(key github-server 48)
REFRESH=$(key github-refresh 49)
ZSHRC=$(key anthropic 52); BASHRC=$(key any 53); UUID_LOOKUP=$(key id 54); HEROKU=$(key id 55)
MIXED="$(key password 58)."; ESCAPED_TOKEN=$(ended_token 60)
MINE=$(key github 61); LOCAL=$(key gitlab 62); IMPORTED=$(key npm 63); MEMORY=$(key huggingface 64)
PROMPTED=$(key any 65); SUMMARY=$(key any 66); SHELL_IN=$(key linear 67); SHELL_OUT=$(key github 68)
BUILT=$(key anthropic 69); FIXTURE_MADE=$(key any 70); READ_FIRST=$(key any 71); ALSO_SENT=$(key any 76)
ALSO_KEPT=$(key any 73); CUT_WHOLE=$(key any 74); SPOTIFY_ID=$(key spotify 75)
PICTURED=$(key any 77); META_ECHO=$(key any 78); QUEUED=$(key any 79); SPOT_OTHER=$(key spotify 80)
SPOT_SECRET=$(key spotify 81); COPIED=$(key npm 82)
ALL=("$PUSHED" "$COMMITTED" "$NEW" "$IGNORED" "$MCP" "$AIDER" "$REMOTE" "$CHANGED" "$CODEX" "$GEMINI" "$HISTORY"
     "$SENT" "$PASTE" "$TOOL" "$COPY" "$SAMPLE" "$FIXTURE" "$ENDED" "$RECORDED" "$LINEAR" "$PAIRED" "$PAIR_ID"
     "$ESCAPED" "$UNPUSHED_SAMPLE" "$SESSION_ID" "$IN_SIGNATURE" "$IN_PICTURE" "$BRAVE" "$PASSWORD" "$AN_ID" "$ID_KEY"
     "$REPORTED" "$BROKEN" "$SHORT" "$HASH" "$HEX_KEY" "$MADE" "$MADE_ANY" "$NOT_TEST" "$NOT_FAKE" "$INSTEAD"
     "$HEX_NAMED" "$LETTERS" "$DOLLAR" "$OAUTH" "$USER_TOKEN" "$SERVER" "$REFRESH" "$ZSHRC" "$BASHRC" "$UUID_LOOKUP"
     "$HEROKU" "$MIXED" "$ESCAPED_TOKEN" "$MINE" "$LOCAL" "$IMPORTED" "$MEMORY" "$PROMPTED" "$SUMMARY" "$SHELL_IN"
     "$SHELL_OUT" "$BUILT" "$FIXTURE_MADE" "$READ_FIRST" "$ALSO_SENT" "$ALSO_KEPT" "$CUT_WHOLE" "$SPOTIFY_ID"
     "$PICTURED" "$META_ECHO" "$QUEUED" "$SPOT_OTHER" "$SPOT_SECRET" "$COPIED")

# A look with one Betterleaks, in a sample home of its own: what it finds, and what its actions do.
look_with() {
local SCANNER=$1 H=$2 W B C D found out aws history again runs sent
W="$H/Library/Application Support/Whozmove"
mkdir -p "$H/code" "$W/sessions"
# A checkout with its own GitHub stand-in: a commit pushed, then one not pushed yet.
git init -q --bare "$H.origin.git"
git init -q -b main "$H/code/shop"
(
  cd "$H/code/shop" || exit 1
  git remote add origin "$H.origin.git"
  printf '.env.local\n.aider*\n' > .gitignore
  printf 'export const app = {\n  name: "shop",\n  token: "%s",\n};\n' "$PUSHED" > app.ts
  printf '# Shop\n' > README.md
  mkdir -p tests
  printf 'request: GET /me\napi_key: "%s"\nstatus: 200\n' "$SAMPLE" > tests/api.expected.txt
  printf 'export const fixture = { token: "%s" };\n' "$FIXTURE" > tests/client.test.ts
  mkdir -p tests/fixtures
  printf '{"token": "%s"}\n' "$LINEAR" > tests/fixtures/linear.json
  git add -A && git commit -qm 'First' && git push -q -u origin main 2>/dev/null
  printf 'const pay = "%s";\n' "$COMMITTED" > pay.ts
  git add -A && git commit -qm 'Pay'
  printf '# Shop\n\nTOKEN=%s\n' "$CHANGED" > README.md
  printf 'NPM_TOKEN=%s\n' "$NEW" > .env
  printf 'NPM_TOKEN=%s\n' "$IGNORED" > .env.local
  printf '{"mcpServers": {"gitlab": {"env": {"GITLAB_TOKEN": "%s"}}}}\n' "$MCP" > .mcp.json
  printf '#### Use my token %s\n' "$AIDER" > .aider.chat.history.md
  git config remote.origin.pushurl "https://x-access-token:$REMOTE@github.com/someone/shop.git"
  git worktree add -q -b fix "$H/code/shop-fix" HEAD~1
  # In the worktree, a commit not pushed yet with another key made up for a test's recorded output: a sample too.
  cd "$H/code/shop-fix" || exit 1
  printf 'request: GET /cli\ntoken: "%s"\n' "$UNPUSHED_SAMPLE" > tests/cli.expected.txt
  git add tests/cli.expected.txt && git commit -qm 'CLI output'
) || exit 1
# Another AI tool's records: a Codex session, a key right after a line break in what was said and a sign-in token
# that has run out, set as SESSION, and the messages you typed, the pushed key among them; and Gemini CLI's log.
mkdir -p "$H/.codex/sessions/2030/01/01" "$H/.gemini/tmp/abc"
python3 -I -c '
import json, sys
codex, pushed, gemini, home, recorded = sys.argv[1:6]
with open(home + "/.codex/sessions/2030/01/01/rollout-1.jsonl", "w") as f:
    f.write(json.dumps({"type": "message", "content": "Hello"}) + "\n")
    f.write(json.dumps({"type": "message", "content": "Use this one:\n" + codex}) + "\n")
    f.write(json.dumps({"type": "message", "content": "export SESSION=" + recorded}) + "\n")
with open(home + "/.codex/history.jsonl", "w") as f:
    f.write(json.dumps({"text": "the token is " + pushed}) + "\n")
with open(home + "/.gemini/tmp/abc/logs.json", "w") as f:
    json.dump([{"message": "my token " + gemini}], f)
' "$CODEX" "$PUSHED" "$GEMINI" "$H" "$RECORDED"
# Claude Code's records of a session in the checkout: what you sent, a key right after a line break in it; what a tool
# read (the .env file's key) after a command took the session into a subfolder, which is still filed under the
# folder it started in; a compaction's summary, which isn't yours; a sub-agent's; a tool's long output beside them;
# the history of your messages; a long paste; and copies of files it edited, which only their folder ties to the
# session: the transcript's snapshot line names the file each copies, one the file no longer holds the key of (an
# earlier copy), and one whose file still holds it (opened at its line there). A project's memory isn't looked in. Claude Code's folder is kept in git too, and listed as a checkout: its
# records are still read only as records, and none of them can go to the Trash.
python3 -I -c '
import json, os, sys
home, sent, new, tool, paste, copy, copied = sys.argv[1:8]
session = "0f0e0d0c-0b0a-4908-8706-050403020100"
shop = home + "/code/shop"
project = home + "/.claude/projects/" + shop.replace("/", "-")
os.makedirs(project + "/" + session + "/subagents")
os.makedirs(project + "/" + session + "/tool-results")
os.makedirs(project + "/memory")
os.makedirs(home + "/.claude/paste-cache")
os.makedirs(home + "/.claude/file-history/" + session)
line = lambda **fields: json.dumps(dict(sessionId=session, cwd=shop, **fields)) + "\n"
with open(project + "/" + session + ".jsonl", "w") as f:
    f.write(line(type="user", message={"role": "user", "content": "Deploy it with this key:\n" + sent}))
    f.write(line(type="assistant", message={"role": "assistant", "content": [{"type": "text", "text": "Reading .env"}]}))
    f.write(json.dumps({"sessionId": session, "cwd": shop + "/src", "type": "user", "toolUseResult": {"type": "text"},
                        "message": {"role": "user", "content": [{"type": "tool_result",
                                                                 "content": "NPM_TOKEN=" + new}]}}) + "\n")
    f.write(line(type="user", isCompactSummary=True, message={"role": "user", "content": "Summary: deployed with " + sent}))
    f.write(json.dumps({"type": "file-history-snapshot", "messageId": "m1", "isSnapshotUpdate": False, "snapshot": {
        "messageId": "m1", "timestamp": "2030-01-01T10:00:00Z", "trackedFileBackups": {
            "notes/hf.env": {"backupFileName": "c3d4@v1", "version": 1, "backupTime": "2030-01-01T10:00:00Z"},
            shop + "/config/app.env": {"backupFileName": "e5f6@v1", "version": 1,
                                       "backupTime": "2030-01-01T10:00:00Z"},
            "notes/new.md": {"backupFileName": None, "version": 1, "backupTime": "2030-01-01T10:00:00Z"}}}}) + "\n")
with open(project + "/" + session + "/subagents/agent-1.jsonl", "w") as f:
    f.write(line(type="assistant", message={"role": "assistant", "content": "Found " + sent}))
with open(project + "/" + session + "/tool-results/call-1.txt", "w") as f:
    f.write("CI log\nGITLAB_TOKEN=" + tool + "\n")
with open(project + "/memory/notes.md", "w") as f:
    f.write("token " + tool + "\n")
with open(home + "/.claude/history.jsonl", "w") as f:
    f.write(json.dumps({"display": "Deploy it with this key: " + sent, "project": shop, "sessionId": session}) + "\n")
with open(home + "/.claude/paste-cache/a1b2.txt", "w") as f:
    f.write("pasted\n" + paste + "\n")
with open(home + "/.claude/file-history/" + session + "/c3d4@v1", "w") as f:
    f.write("HF_TOKEN=" + copy + "\n")
with open(home + "/.claude/file-history/" + session + "/e5f6@v1", "w") as f:
    f.write("# app\nNPM_TOKEN=" + copied + "\n")
os.makedirs(shop + "/config", exist_ok=True)
with open(shop + "/config/app.env", "w") as f:
    f.write("# app\n\nNPM_TOKEN=" + copied + "\n")
' "$H" "$SENT" "$NEW" "$TOOL" "$PASTE" "$COPY" "$COPIED"
# Another session's conversation, with what looks like a key and isn't, beside what is: a text ending "…tokens>" and
# the next one a session's id (each text is matched on its own); a Brave-shaped run inside a reply's signature and
# inside a picture's data (both base64); words taken for passwords (a word, curl's user and password, a default
# password in an address); an id after a line break, set as no name (folded as an id); the same shape set as API_KEY
# (counted); a GitHub token printed in a scanner's report (not set as "full"); and a Brave key and a password said
# plainly (counted).
python3 -I -c '
import base64, json, random, sys
home, session_id, signature, picture, brave, password, an_id, id_key, reported = sys.argv[1:10]
r = random.Random(33)
blob = lambda inside: (base64.b64encode(bytes(r.randrange(256) for _ in range(300))).decode() + "/" + inside + "+"
                       + base64.b64encode(bytes(r.randrange(256) for _ in range(300))).decode())
session = "1f1e1d1c-1b1a-4918-9716-151413121110"
shop = home + "/code/shop"
project = home + "/.claude/projects/" + shop.replace("/", "-")
line = lambda **fields: json.dumps(dict(sessionId=session, cwd=shop, **fields)) + "\n"
said = ("password = \"administrator\"\ncurl -u admin:secret https://api.example.dev\n"
        "postgres://postgres:postgres@localhost:5432/app\nthe start key is a UUID\n  = " + an_id + "\n"
        "API_KEY = \"" + id_key + "\"\n{\"match\": {\"full\": \"" + reported + "\"}}")
with open(project + "/" + session + ".jsonl", "w") as f:
    f.write(line(type="user", message={"role": "user", "content": ["You have 900 tokens left</total_tokens>",
                                                                   session_id]}))
    f.write(line(type="assistant", message={"role": "assistant", "content": [
        {"type": "thinking", "thinking": "Looking", "signature": blob(signature)},
        {"type": "text", "text": "Here it is"}]}))
    f.write(line(type="user", message={"role": "user", "content": [
        {"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": blob(picture)}}]}))
    f.write(line(type="user", toolUseResult={"type": "text"}, message={"role": "user", "content": [
        {"type": "tool_result", "content": said}]}))
    f.write(line(type="user", message={"role": "user", "content": "My search key " + brave + ", and password = \""
                                                                  + password + "\""}))
' "$H" "$SESSION_ID" "$IN_SIGNATURE" "$IN_PICTURE" "$BRAVE" "$PASSWORD" "$AN_ID" "$ID_KEY" "$REPORTED"
# A third session's, with what can't be a key: a GitHub token whose checksum fails, one too short, variables' names, a
# file's hash and a placeholder that counts up (none listed). And what's still counted: a key in hex set as a name in
# capitals, and one set as a key's name in any case; a password that starts with a $, and a long passphrase; a token
# of each of GitHub's other kinds, its checksum right; a GitHub token Claude says it made up (a provider's shape is
# never folded on words alone); keys beside "not a test key", "not fake" and "instead of the placeholder"; and the
# pushed key, which a reply calls a sample, but is in a project's own file too. A key Claude says it made up for a test
# is folded, said to be made up.
python3 -I -c '
import json, sys
home, broken, short, hash, hex_key, made, pushed = sys.argv[1:8]
made_any, not_test, not_fake, instead, hex_named, letters, dollar, oauth, user, server, refresh = sys.argv[8:19]
session = "2f2e2d2c-2b2a-4928-a726-252423222120"
shop = home + "/code/shop"
project = home + "/.claude/projects/" + shop.replace("/", "-")
line = lambda **fields: json.dumps(dict(sessionId=session, cwd=shop, **fields)) + "\n"
read = ("GITHUB_TOKEN=" + broken + "\nexport GITHUB_TOKEN=" + short + "\napi_key = \"R2_SECRET_KEY\"\n"
        "token: ${DEPLOY_TOKEN_2}\nsecret_key = process.env.STRIPE_KEY_2\n\"setting-keys.svg\": \"" + hash + "\"\n"
        "API_TOKEN=\"xk1234567890abcdefQRST\"\nMAILER_API_KEY=" + hex_key + "\n\"billing_api_key\": \"" + hex_named
        + "\"\npassword = \"" + letters + "\"\nDB_PASSWORD=\"" + dollar + "\"\nGH_OAUTH=" + oauth + "\nGH_USER="
        + user + "\nGH_SERVER=" + server + "\nGH_REFRESH=" + refresh)
with open(project + "/" + session + ".jsonl", "w") as f:
    f.write(line(type="user", toolUseResult={"type": "text"}, message={"role": "user", "content": [
        {"type": "tool_result", "content": read}]}))
    f.write(line(type="assistant", message={"role": "assistant", "content": [
        {"type": "text", "text": "A made-up token for the test: " + made}]}))
    f.write(line(type="assistant", message={"role": "assistant", "content": [
        {"type": "text", "text": "It reads like a sample, " + pushed}]}))
    f.write(line(type="assistant", message={"role": "assistant", "content": [
        {"type": "text", "text": "A made-up one for the test: api_key = \"" + made_any + "\""}]}))
    f.write(line(type="user", message={"role": "user", "content": "Here is my real key, not a test key: api_key = \""
                                                                  + not_test + "\""}))
    f.write(line(type="user", message={"role": "user", "content": "It is not fake: secret = \"" + not_fake + "\""}))
    f.write(line(type="user", message={"role": "user", "content": "Use this instead of the placeholder: token = \""
                                                                  + instead + "\""}))
' "$H" "$BROKEN" "$SHORT" "$HASH" "$HEX_KEY" "$MADE" "$PUSHED" "$MADE_ANY" "$NOT_TEST" "$NOT_FAKE" "$INSTEAD" \
  "$HEX_NAMED" "$LETTERS" "$DOLLAR" "$OAUTH" "$USER_TOKEN" "$SERVER" "$REFRESH"
# A fourth session's, what a tool read, as Betterleaks finds it: a variable given to curl -u and a sentence set as a
# password (none listed); a UUID a lookup sets as `key` (folded as an id); and what's still counted: a UUID set as a
# service's key, and a password ending in a full stop. What its rules don't find in a line like these is judged line by
# line in test.sh (judge.expected.txt).
python3 -I -c '
import json, sys
home, uuid_lookup, heroku, mixed = sys.argv[1:5]
session = "1a1b1c1d-2a2b-4c2d-8e3f-404142434445"
shop = home + "/code/shop"
project = home + "/.claude/projects/" + shop.replace("/", "-")
line = lambda **fields: json.dumps(dict(sessionId=session, cwd=shop, **fields)) + "\n"
read = ("cu" "rl -u \"$DEPLOY_SECRET_KEY:\" https://api.example.dev/v1\nkey=\"" + uuid_lookup + "\"\n"
        "PAYMENTS_API_KEY=" + heroku + "\npassword: \"Use the admin panel.\"\npassword = \"" + mixed + "\"")
with open(project + "/" + session + ".jsonl", "w") as f:
    f.write(line(type="user", toolUseResult={"type": "text"}, message={"role": "user", "content": [
        {"type": "tool_result", "content": read}]}))
' "$H" "$UUID_LOOKUP" "$HEROKU" "$MIXED"
# What Claude Code reads into sessions as their instructions: your own CLAUDE.md, a project's CLAUDE.local.md (its
# sessions ran in ~/code/shop) and a notes file it imports, and the project's memory, each opened at the key's line. And
# a fifth session's lines: a sub-agent's prompt (the agent's own words), a compaction's summary (from no one), and a
# line you ran with ! and what it printed (sent, and read).
mkdir -p "$H/.claude" "$H/notes"
printf '# Me\n\nGITHUB_TOKEN=%s\n' "$MINE" > "$H/.claude/CLAUDE.md"
printf 'Local notes\n\n@~/notes/keys.md\nGITLAB_TOKEN=%s\n' "$LOCAL" > "$H/code/shop/CLAUDE.local.md"
printf '# Keys\nNPM_TOKEN=%s\n' "$IMPORTED" > "$H/notes/keys.md"
python3 -I -c '
import json, os, sys
home, memory, prompted, summary, shell_in, shell_out = sys.argv[1:7]
session = "5a5b5c5d-6a6b-4c6d-8e7f-808182838485"
shop = home + "/code/shop"
project = home + "/.claude/projects/" + shop.replace("/", "-")
os.makedirs(project + "/memory", exist_ok=True)
open(project + "/memory/MEMORY.md", "w").write("# Memory\nHF_TOKEN=" + memory + "\n")
line = lambda **fields: json.dumps(dict(sessionId=session, cwd=shop, **fields)) + "\n"
with open(project + "/" + session + ".jsonl", "w") as f:
    f.write(line(type="user", isSidechain=True, message={"role": "user",
                 "content": "Check the config with api_key = \"" + prompted + "\""}))
    f.write(line(type="user", isCompactSummary=True, message={"role": "user",
                 "content": "Summary so far: the service uses api_key = \"" + summary + "\""}))
    f.write(line(type="user", isMeta=True, message={"role": "user",
                 "content": "<bash-input>export LINEAR_API_KEY=" + shell_in + "</bash-input>"}))
    f.write(line(type="user", isMeta=True, message={"role": "user",
                 "content": "<bash-stdout>GITHUB_TOKEN=" + shell_out + "</bash-stdout><bash-stderr></bash-stderr>"}))
' "$H" "$MEMORY" "$PROMPTED" "$SUMMARY" "$SHELL_IN" "$SHELL_OUT"
# A sixth session's, keys an agent made: one its own command builds (a provider's shape) and reads back, and one it
# writes into a fixture and reads back (both folded, made by an agent); and what still counts though the agent wrote it:
# one a tool read first, one you sent too, and one in your own CLAUDE.md too. A copy of a key cut short (its first 24
# characters, as a scanner printed it) joins the whole key, and a value the session also names as a Spotify id is one.
printf 'SERVICE_SECRET=%s\n' "$ALSO_KEPT" >> "$H/.claude/CLAUDE.md"
python3 -I -c '
import json, sys
home, built, fixture, read_first, also_sent, also_kept, cut_whole, spotify_id = sys.argv[1:9]
session = "6a6b6c6d-7a7b-4c7d-8e8f-909192939495"
shop = home + "/code/shop"
project = home + "/.claude/projects/" + shop.replace("/", "-")
line = lambda **fields: json.dumps(dict(sessionId=session, cwd=shop, **fields)) + "\n"
use = lambda text: line(type="assistant", message={"role": "assistant", "content": [
    {"type": "tool_use", "id": "t", "name": "Bash", "input": {"command": text}}]})
result = lambda text: line(type="user", toolUseResult={"type": "text"}, message={"role": "user", "content": [
    {"type": "tool_result", "content": text}]})
with open(project + "/" + session + ".jsonl", "w") as f:
    f.write(use("python3 fake.py <<FAKE\nprint(\"export TOKEN=" + built + "\")\nFAKE"))
    f.write(result("export TOKEN=" + built))
    f.write(use("cat > fixture.py <<EOF\napi_key = \"" + fixture + "\"\nEOF"))
    f.write(result("api_key = \"" + fixture + "\""))
    f.write(result("secret_key = \"" + read_first + "\""))
    f.write(use("echo secret_key = \"" + read_first + "\""))
    f.write(use("echo api_token = \"" + also_sent + "\""))
    f.write(line(type="user", message={"role": "user", "content": "api_token = \"" + also_sent + "\""}))
    f.write(use("echo SERVICE_SECRET=" + also_kept))
    f.write(use("cat > relay.py <<EOF\nAPI_TOKEN = \"" + cut_whole + "\"\nEOF"))
    f.write(result("[src/relay.py 5] ctx=b\u0027API_TOKEN = \"" + cut_whole[:24] + "\u0027"))
    f.write(result("key = \"" + spotify_id + "\""))
    f.write(result("{\"Track ID\": \"spotify:track:" + spotify_id + "\"}"))
' "$H" "$BUILT" "$FIXTURE_MADE" "$READ_FIRST" "$ALSO_SENT" "$ALSO_KEPT" "$CUT_WHOLE" "$SPOTIFY_ID"
# A seventh session's, what still counts though the agent wrote it first: a key its command writes and reads back after
# a picture you pasted (it may have been read off the picture); a value it names as a Spotify id but sets as
# SPOTIFY_SECRET (a name that says it's secret); a key in a sub-agent's line Claude Code added (meta, from no one) that
# the sub-agent then echoes; and one in a message you queued while Claude worked, which it echoes. And a value it names
# as a Spotify id, which an eighth session sets as client_key: counted there, an id only where it was named.
python3 -I -c '
import json, os, sys
home, pictured, spot_secret, meta_echo, queued, spot_other = sys.argv[1:7]
shop = home + "/code/shop"
project = home + "/.claude/projects/" + shop.replace("/", "-")
session = "7a7b7c7d-8a8b-4c8d-8e9f-a0a1a2a3a4a5"
line = lambda **fields: json.dumps(dict(sessionId=session, cwd=shop, **fields)) + "\n"
use = lambda text: line(type="assistant", message={"role": "assistant", "content": [
    {"type": "tool_use", "id": "t", "name": "Bash", "input": {"command": text}}]})
result = lambda text: line(type="user", toolUseResult={"type": "text"}, message={"role": "user", "content": [
    {"type": "tool_result", "content": text}]})
with open(project + "/" + session + ".jsonl", "w") as f:
    f.write(line(type="user", message={"role": "user", "content": [
        {"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": "iVBORw0KGgo="}}]}))
    f.write(use("echo DEPLOY_TOKEN=" + pictured))
    f.write(result("DEPLOY_TOKEN=" + pictured))
    f.write(result("{\"Track ID\": \"spotify:track:" + spot_secret + "\"}"))
    f.write(result("SPOTIFY_SECRET = \"" + spot_secret + "\""))
    f.write(result("{\"Track ID\": \"spotify:track:" + spot_other + "\"}"))
    f.write(line(type="attachment", attachment={"type": "queued_command", "prompt": "and use token = \"" + queued
                                                                                         + "\""}))
    f.write(use("echo token = \"" + queued + "\""))
os.makedirs(project + "/" + session + "/subagents", exist_ok=True)
with open(project + "/" + session + "/subagents/agent-2.jsonl", "w") as f:
    f.write(line(type="user", isSidechain=True, isMeta=True, message={"role": "user",
                 "content": "Context: api_key = \"" + meta_echo + "\""}))
    f.write(line(type="assistant", isSidechain=True, message={"role": "assistant", "content": [
        {"type": "text", "text": "Using api_key = \"" + meta_echo + "\""}]}))
other = "8a8b8c8d-9a9b-4c9d-8eaf-b0b1b2b3b4b5"
with open(project + "/" + other + ".jsonl", "w") as f:
    f.write(json.dumps(dict(sessionId=other, cwd=shop, type="user", toolUseResult={"type": "text"}, message={
        "role": "user", "content": [{"type": "tool_result", "content": "client_key = \"" + spot_other + "\""}]}))
            + "\n")
' "$H" "$PICTURED" "$SPOT_SECRET" "$META_ECHO" "$QUEUED" "$SPOT_OTHER"
git init -q "$H/.claude"
# Credential files: one others can read, one that's yours only; a private key others can read, and its public half.
mkdir -p "$H/.aws" "$H/.ssh" "$H/Downloads"
printf '[default]\n' > "$H/.aws/credentials" && chmod 644 "$H/.aws/credentials"
printf '//registry.npmjs.org/:_authToken=x\n' > "$H/.npmrc" && chmod 600 "$H/.npmrc"
printf 'not a real key\n' > "$H/.ssh/id_ed25519" && chmod 644 "$H/.ssh/id_ed25519"
printf 'ssh-ed25519 AAAA\n' > "$H/.ssh/id_ed25519.pub"
# Docker's settings others can read, with no sign-in in them (only where macOS keeps them): not listed.
mkdir -p "$H/.docker"
printf '{"credsStore": "osxkeychain"}\n' > "$H/.docker/config.json" && chmod 644 "$H/.docker/config.json"
# Your shell's settings: a provider's key set for every terminal in ~/.zshrc, which others can read (so it can be made
# yours only), and one in ~/.bashrc, yours only.
printf '# zsh\nexport PATH=$PATH:$HOME/bin\nalias ll="ls -l"\n\n\nsetopt autocd\nexport ANTHROPIC_API_KEY=%s\n' \
  "$ZSHRC" > "$H/.zshrc" && chmod 644 "$H/.zshrc"
printf 'export SERVICE_TOKEN="%s"\n' "$BASHRC" > "$H/.bashrc" && chmod 600 "$H/.bashrc"
# Your shell history: a key set as a name, a sign-in token that has run out, a key after an id and a colon (the id is
# a value, never what it's set as), and one in an address whose user name has a % (never taken for a name).
printf 'ls\nexport GITHUB_TOKEN=%s\nexport SESSION=%s\ncurl -u %s:%s https://api.example.dev\n' \
  "$HISTORY" "$ENDED" "$PAIR_ID" "$PAIRED" > "$H/.zsh_history"
printf 'git clone https://me%%40corp.example:%s@git.example.dev/shop.git\n' "$ESCAPED" >> "$H/.zsh_history"
# Downloads: a file that's nothing but a key, which can go to the Trash; notes that hold one among other lines, which
# open at the line instead; and one of a kind Keys doesn't look in.
printf '{"token": "%s"}\n' "$GEMINI" > "$H/Downloads/service.json"
printf 'Meeting notes\n\nThe staging token is %s, ask before using it.\n' "$PASTE" > "$H/Downloads/notes.txt"
printf 'token %s\n' "$CODEX" > "$H/Downloads/photo.heic"
# A diagnostics file holding a sign-in token in escaped JSON: its last 4 are the token's, never a "\".
printf '{\\"session\\":{\\"auth\\":\\"%s\\"}}\n' "$ESCAPED_TOKEN" > "$H/Downloads/diagnostics.txt"
# Whozmove's own record of a session, with the commit's key in your last message.
printf '{"lastPrompt": "pay with %s please", "lastReply": "Done."}\n' "$COMMITTED" > "$W/sessions/s1.json"

# Betterleaks, through a stand-in that says how each look's run of it was started (not its version or version 1's
# rules, which read nothing of yours) before it runs: with one thread, and in macOS's background band, which Keys
# sets on it before it runs a single instruction (PROC_FLAG_EXT_DARWINBG, as the kernel tells its own process): the
# stand-in looks at once, as its first thing, however busy the Mac is.
cat > "$T/how.py" <<'EOF'
import ctypes, os
info = ctypes.create_string_buffer(136)
ctypes.CDLL("/usr/lib/libproc.dylib").proc_pidinfo(os.getppid(), 3, ctypes.c_uint64(0), info, 136)
background = int.from_bytes(info.raw[:4], "little") & 0x10000
print("GOMAXPROCS=%s, %s" % (os.environ.get("GOMAXPROCS"), "in the background" if background else "not in it"))
EOF
cat > "$T/how-betterleaks" <<EOF
#!/bin/sh
case "\$1" in version|config) ;; *) python3 -I "$T/how.py" >> "$T/how.txt" ;; esac
exec "$SCANNER" "\$@"
EOF
chmod +x "$T/how-betterleaks"
rm -f "$T/how.txt"
found=$(HOME="$H" "$APP" --print-keys --full-disk-access "$T/how-betterleaks" "$H/code/shop" "$H/code/shop-fix" \
  "$H/.claude") ||
  { echo "$found"; exit 1; }
show() {
  python3 -I -c '
import json, sys
home = sys.argv[1]
found = json.load(sys.stdin)
print("problem: %s · skipped: %s" % (found.get("problem"), found.get("skipped")))
for key in found["keys"]:
    print("%s · %s %s · %s%s · %s, %s%s" % (key["group"], key["name"], key["masked"], " ".join(key["actions"]),
                                           " · it has left the Mac" if key["left"] else "", key["band"],
                                           key["real"], " · its end date kept" if key.get("ends") else ""))
    print("    fix: %s · menu: %s" % (key["ways"][0]["title"], " / ".join(w["menu"] for w in key["ways"][1:])))
    for place in key["places"]:
        # A project folder inside the Claude Code folder, named for this run of the sample home: said as one name.
        where = place["where"].replace((home + "/code/shop").replace("/", "-"), "(shop)")
        print("    %s: %s%s%s%s%s%s%s" % (place["group"], where,
                                      " · project %s, %s" % (place["project"], place["copy"])
                                      if place.get("project") else "",
                                      " · named %s" % json.dumps(place["named"]) if place.get("named") else "",
                                      " · " + " ".join(place["can"]) if place["can"] else "",
                                      " · keeps it: " + place["keep"] if place.get("keep") else "",
                                      " · session " + place["session"][:8] if place.get("session") else "",
                                      " · " + place["clear"].replace(home, "~") if place.get("clear") else ""))' "$H"
}
out=$(echo "$found" | show)
# Keys shown as they're found: how many it had found, and how many counted, as it read each of its places.
out+=$'\n'"as it read: $(echo "$found" | python3 -I -c 'import json, sys
print(" · ".join("%(read)s of %(of)s, %(keys)s found, %(found)s counted" % s for s in json.load(sys.stdin)["soFar"]))')"
out+=$'\n\n'"Whozmove's record: $(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["lastPrompt"])' \
  "$W/sessions/s1.json")"
# What the look wrote in panel.log: how many, never which (the check below finds no key whole in Whozmove's folder).
out+=$'\n'"panel.log: $(keys_log "$H")"
out+=$'\n'"how Betterleaks ran: $(sort -u "$T/how.txt" | paste -sd ';' -)"
# No made-up key whole, in what was printed or anywhere in Whozmove's folder.
for each in "${ALL[@]}"; do
  if grep -qF -- "$each" <<< "$found" || grep -rqF -- "$each" "$W"; then
    out+=$'\n'"A key was kept whole: the one ending ${each: -4}"
  fi
done
# What's kept of the records read before, in an older shape, with a find in it today's rules wouldn't make: not used,
# as every record is read again from its start.
python3 -I -c '
import json, sys
path = sys.argv[1]
kept = json.load(open(path))
first = sorted(f for f in kept["files"] if f.endswith(".jsonl"))[0]
kept["files"][first]["found"].append({"id": "0123456789abcdef", "rule": "generic-api-key", "masked": "…OLDX",
                                      "place": {"group": "claude", "app": "Claude Code", "file": first}})
kept["shape"] = kept["shape"] - 1
json.dump(kept, open(path, "w"))' "$W/keys/records.json"
again=$(HOME="$H" "$APP" --print-keys --full-disk-access "$SCANNER" "$H/code/shop" "$H/code/shop-fix" "$H/.claude")
old=$(python3 -I -c 'import sys; print(sys.stdin.read().count("OLDX"))' <<< "$again")
out+=$'\n'"records kept in an older shape: read again, $old of its old finds listed"
# Its actions: the credential file made yours only, and a key ignored, each then gone from the list.
aws=$(echo "$found" | python3 -I -c 'import json,sys; print([k["id"] for k in json.load(sys.stdin)["keys"] if k["masked"] == "~/.aws/credentials"][0])')
history=$(echo "$found" | python3 -I -c 'import json,sys; print([k["id"] for k in json.load(sys.stdin)["keys"] if k["group"] == "files" and "shell history" in k["places"][0]["where"]][0])')
acted() { python3 -I -c 'import json,sys; a=json.load(sys.stdin); print("why %s · %s left" % (a["why"], len(a["ids"])))'; }
out+=$'\n\n'"private: $(HOME="$H" "$APP" --print-keys-act private "$aws" 0 | acted) · $(stat -f %Lp "$H/.aws/credentials")"
# Move to Trash, only for a file that's nothing but the key (the downloaded service.json), each check refusing: an
# agent at work there; then the file changed since the look (another file at its path). And never for a file that
# holds more: the .env file, whose line opens instead. Nothing goes to the Trash here: macOS's Trash is your account's,
# whatever HOME says.
place_of() {
  echo "$found" | python3 -I -c '
import json, sys
for k in json.load(sys.stdin)["keys"]:
    for i, p in enumerate(k["places"]):
        if sys.argv[1] in p["where"]:
            print(k["id"], i)
            sys.exit()' "$1"
}
read -r dl_key dl_place <<< "$(place_of Downloads/service.json)"
out+=$'\n'"trash, an agent at work: $(HOME="$H" "$APP" --print-keys-act trash "$dl_key" "$dl_place" "$H/Downloads" | acted)"
cp "$H/Downloads/service.json" "$H/Downloads/service.new" && mv "$H/Downloads/service.new" "$H/Downloads/service.json"
out+=$'\n'"trash, another file now: $(HOME="$H" "$APP" --print-keys-act trash "$dl_key" "$dl_place" | acted)"
read -r env_key env_place <<< "$(place_of 'shop · .env:')"
out+=$'\n'"trash, a file that holds more: $(HOME="$H" "$APP" --print-keys-act trash "$env_key" "$env_place" | acted)"
history_key=$(echo "$found" | python3 -I -c 'import json,sys; print([k["id"] for k in json.load(sys.stdin)["keys"] if k["group"] == "files" and "shell history" in k["places"][0]["where"]][0])')
out+=$'\n'"trash, a file that can't go: $(HOME="$H" "$APP" --print-keys-act trash "$history_key" 0 | acted)"
out+=$'\n'"ignore: $(HOME="$H" "$APP" --print-keys-act ignore "$history" | acted)"
out+=$'\n'"ignore again: $(HOME="$H" "$APP" --print-keys-act ignore "$history" | acted)"
# A key that has left the Mac marked replaced, then brought back with Undo, then marked again.
pushed=$(echo "$found" | python3 -I -c 'import json,sys
print([k["id"] for k in json.load(sys.stdin)["keys"] if k["group"] == "pushed" and not k["sample"]][0])')
out+=$'\n'"replaced: $(HOME="$H" "$APP" --print-keys-act replaced "$pushed" | acted)"
out+=$'\n'"undo: $(HOME="$H" "$APP" --print-keys-act undo "$pushed" | acted)"
out+=$'\n'"replaced again: $(HOME="$H" "$APP" --print-keys-act replaced "$pushed" | acted)"
# Looked again: the credential file is yours only now, the ignored key stays ignored, and the key sent to Claude is
# still listed as sent, though Whozmove's record of it is masked now; and Claude Code's copies, not read again, are
# still named by their files.
again=$(HOME="$H" "$APP" --print-keys --full-disk-access "$SCANNER" "$H/code/shop" | python3 -I -c '
import json, sys
found = json.load(sys.stdin)
keys = found["keys"]
ids = [k["id"] for k in keys]
sent = [k for k in keys if any(p["group"] == "claude" for p in k["places"])]
recorded = [k for k in keys if k["real"] == "ended" and any(p.get("app") == "Codex" for p in k["places"])]
print("looked again: %d keys · AWS credentials %s · the ignored key %s · %s" % (
    len(ids), "listed" if sys.argv[1] in ids else "gone", "listed" if sys.argv[2] in ids else "gone",
    "still sent to Claude: %s" % " ".join(k["masked"] for k in sent)))
print("the token in Codex’s record, not read again: %s, %s" % (
    "its end date kept" if recorded and recorded[0].get("ends") else "its end date lost",
    "named %s" % json.dumps(recorded[0]["places"][0].get("named")) if recorded else "gone"))
print("put away: %s" % ", ".join("%s %s (%s)" % (k["name"], k["masked"], k["put"]) for k in found["putAway"]))
print("copies, not read again: %s" % " / ".join(sorted(p["where"].split(" · ")[0].replace(sys.argv[3], "~")
      for k in keys for p in k["places"] if "copy of" in p["where"])))' \
  "$aws" "$history" "$H")
out+=$'\n'"$again"
# A look kept by a build that kept another shape (here, none) isn't shown: nothing is listed until the next look.
python3 -I -c 'import json,sys; f=json.load(open(sys.argv[1])); f.pop("shape", None); json.dump(f, open(sys.argv[1], "w"))' \
  "$W/keys/found.json"
out+=$'\n'"a look an older build kept: $(HOME="$H" "$APP" --print-keys-act ignore "$aws" | acted)"
# Without Full Disk Access, with a project in Documents: neither it nor Downloads is looked in, and what it found
# says so.
mkdir -p "$H/Documents"
cp -R "$H/code/shop" "$H/Documents/kept"
out+=$'\n'"$(HOME="$H" "$APP" --print-keys "$SCANNER" "$H/code/shop" "$H/Documents/kept" | python3 -I -c '
import json, sys
found = json.load(sys.stdin)
print("without Full Disk Access: %d keys · skipped %s · access %s" % (len(found["keys"]), found.get("skipped"),
                                                                     found.get("fullDiskAccess")))')"
# How far reading AI tools' records had got is kept as a look goes: a look stopped once it has read and kept 2 (as a
# restart would stop it), then another, read each record once between them, as many as a whole look reads.
rm -f "$W/keys/records.json"
HOME="$H" "$APP" --print-keys --full-disk-access --keep-every 2 --stop-after 2 "$SCANNER" "$H/code/shop" > /dev/null
second=$(HOME="$H" "$APP" --print-keys --full-disk-access "$SCANNER" "$H/code/shop" |
  python3 -I -c 'import json, sys; print(json.load(sys.stdin)["recordsRead"])')
whole=$(echo "$found" | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["recordsRead"])')
out+=$'\n'"a look stopped after 2 records, then another: $((2 + second)) read in all, of $whole: $(
  [ $((2 + second)) -eq "$whole" ] && echo "each once" || echo "not each once")"
# And settling what's found at each keep, over and over, changes nothing: a look keeping after every record finds the
# same keys, joined and placed alike, as one that keeps only at its end.
keys_and_places() { python3 -I -c '
import json, sys
found = json.load(sys.stdin)
print(sorted((k["id"], k["masked"], len(k["places"])) for k in found["keys"]))'; }
rm -f "$W/keys/records.json"
every=$(HOME="$H" "$APP" --print-keys --full-disk-access --keep-every 1 "$SCANNER" "$H/code/shop" | keys_and_places)
rm -f "$W/keys/records.json"
once=$(HOME="$H" "$APP" --print-keys --full-disk-access "$SCANNER" "$H/code/shop" | keys_and_places)
out+=$'\n'"a look keeping after every record, and one keeping at its end: $([ "$every" = "$once" ] && echo "the same keys" ||
  echo "different keys")"
# AI tools' records share Betterleaks' runs, through a stand-in that notes the records each run was given (by a word
# each holds) and stops on any holding the word its stop-on file names: four sessions' records in one run, not one
# each. A run that doesn't finish is run again in halves, so a record it can't get through holds back only itself: the
# others in its run are kept, the look says it couldn't finish, and the next look gives Betterleaks that record alone.
B="$H-records"
mkdir -p "$B/.claude/projects/-code-shop"
python3 -I -c '
import json, sys
folder, keys = sys.argv[1], sys.argv[2:]
for n, (word, key) in enumerate(zip(["one", "two", "three", "four"], keys)):
    with open("%s/00000000-0000-4000-8000-00000000000%d.jsonl" % (folder, n + 1), "w") as f:
        f.write(json.dumps({"type": "user", "sessionId": "session-%d" % (n + 1), "cwd": "/code/shop", "message": {
            "role": "user", "content": "record-%s %s: api_key = \"%s\"" % (
                word, "STOP-THIS-RUN" if word == "three" else "", key)}}) + "\n")' \
  "$B/.claude/projects/-code-shop" "$(key github 90)" "$(key github 91)" "$(key github 92)" "$(key github 93)"
cat > "$T/runs-betterleaks" <<EOF
#!/bin/sh
case "\$1" in version|config) exec "$SCANNER" "\$@" ;; esac
cat > "$T/fed.txt"
[ -s "$T/fed.txt" ] || exec "$SCANNER" "\$@" < "$T/fed.txt"
words=\$(grep -o 'record-[a-z]*' "$T/fed.txt" | sort -u | paste -sd ',' -)
if [ -s "$T/stop-on" ] && grep -qf "$T/stop-on" "$T/fed.txt"; then echo "\$words (stopped)" >> "$T/runs.txt"; exit 3; fi
echo "\$words" >> "$T/runs.txt"
exec "$SCANNER" "\$@" < "$T/fed.txt"
EOF
chmod +x "$T/runs-betterleaks"
batched() { python3 -I -c '
import json, sys
found = json.load(sys.stdin)
print("%s · problem: %s · keys: %s" % (sys.argv[1], found.get("problem"), ", ".join(sorted("%s %s in %s" % (
    k["name"], k["masked"], " / ".join("record %s" % p.get("session", "?")[-1:] for p in k["places"]))
    for k in found["keys"]))))' "$1"; }
rm -f "$T/runs.txt"
echo STOP-THIS-RUN > "$T/stop-on"
out+=$'\n\n'"$(HOME="$B" "$APP" --print-keys --full-disk-access "$T/runs-betterleaks" |
  batched "records in a run that stopped")"
out+=$'\n'"its runs: $(paste -sd ';' - < "$T/runs.txt")"
rm -f "$T/runs.txt"
out+=$'\n'"$(HOME="$B" "$APP" --print-keys --full-disk-access "$T/runs-betterleaks" |
  batched "looked again")"
out+=$'\n'"its runs: $(paste -sd ';' - < "$T/runs.txt")"
# A match a rule's pattern lets run from one record into the next is no key, and doesn't hide one: half of a made-up
# private key ending one record and the rest starting the next is none, and a key's header with nothing after it
# (cut off in a tool's output) ending a record doesn't hide the whole key the next record holds, found there alone,
# nor the key on the next line of the same record, nor one after a thousand lines that each end that way (more than
# its rounds of running spanned texts again together take, so the last are run one at a time), the record then kept
# as read, so the next look gives Betterleaks none of these records again.
C="$H-spanning"
mkdir -p "$C/.claude/projects/-code-shop"
python3 -I -c '
import base64, json, random, sys
folder = sys.argv[1]
r = random.Random(94)
body = lambda lines: "\n".join(base64.b64encode(bytes(r.randrange(256) for _ in range(48))).decode()
                               for _ in range(lines))
begin, end = "-----BEGIN PRIVATE KEY-----", "-----END PRIVATE KEY-----"
said = [["Its first half:\n" + begin + "\n" + body(2)], [body(2) + "\n" + end + "\nthe rest of it."],
        ["The tool cut it off:\n" + begin + "\nMIIE"], [begin + "\n" + body(4) + "\n" + end],
        ["Cut off again:\n" + begin + "\nMIIE", begin + "\n" + body(4) + "\n" + end],
        ["Line %d of a long output, cut off after a header again, with nothing after it:\n%s\nMIIE" % (i, begin)
         for i in range(1000)] + [begin + "\n" + body(4) + "\n" + end]]
for n, texts in enumerate(said):
    with open("%s/00000000-0000-4000-8000-00000000000%d.jsonl" % (folder, n + 1), "w") as f:
        for text in texts:
            f.write(json.dumps({"type": "user", "cwd": "/code/shop", "message": {"role": "user", "content":
                "record-%s %s" % (["one", "two", "three", "four", "five", "six"][n], text)}}) + "\n")' \
  "$C/.claude/projects/-code-shop"
rm -f "$T/runs.txt" "$T/stop-on"
out+=$'\n'"$(HOME="$C" "$APP" --print-keys --full-disk-access "$T/runs-betterleaks" |
  batched "keys across records")"
out+=$'\n'"its runs: $(paste -sd ';' - < "$T/runs.txt")"
rm -f "$T/runs.txt"
HOME="$C" "$APP" --print-keys --full-disk-access "$T/runs-betterleaks" > /dev/null
out+=$'\n'"looked again: $( [ -s "$T/runs.txt" ] && paste -sd ';' - < "$T/runs.txt" || echo "no runs")"
# Files go to Betterleaks a run's worth at a time, by how many or how large, whichever comes first: nine made-up files
# of about 2 MB in Downloads (more than one run reads) and three small ones go in two runs, not one.
D="$H-large"
mkdir -p "$D/Downloads"
python3 -I -c '
import random, sys
r = random.Random(95)
for n in range(9):
    with open("%s/notes-%d.txt" % (sys.argv[1], n), "w") as f:
        for _ in range(25000):
            f.write("".join(r.choice("abcdefghij klmnop") for _ in range(79)) + "\n")
for n in range(3):
    with open("%s/small-%d.txt" % (sys.argv[1], n), "w") as f:
        f.write("nothing here %d\n" % n)' "$D/Downloads"
cat > "$T/files-betterleaks" <<EOF
#!/bin/sh
case "\$1" in version|config) exec "$SCANNER" "\$@" ;; esac
n=0
for a in "\$@"; do case "\$a" in */Downloads/*) n=\$((n + 1)) ;; esac; done
[ "\$n" -gt 0 ] && echo "\$n" >> "$T/files-runs.txt"
exec "$SCANNER" "\$@"
EOF
chmod +x "$T/files-betterleaks"
rm -f "$T/files-runs.txt"
HOME="$D" "$APP" --print-keys --full-disk-access "$T/files-betterleaks" > /dev/null
runs=$(wc -l < "$T/files-runs.txt" | tr -d ' ')
sent=$(awk '{ s += $1 } END { print s }' "$T/files-runs.txt")
out+=$'\n'"large files in Downloads: $runs runs, $sent files in all"
printf '%s\n' "$out"
}

# With each version tools/betterleaks.txt names (a build's and a release's, the same finished one, and the one being
# readied), and with the one inside the app when the tests run on a release: each finds the same.
status=0
scanners=()
seen=" "
for which in build release next; do
  version=$(tools/betterleaks.sh --version --$which) || exit 1
  case $seen in *" $version "*) continue ;; esac
  seen+="$version "
  scanners+=("$(tools/betterleaks.sh --$which "$T/$which")") || exit 1
done
inside=$(dirname "$APP")/../Helpers/betterleaks
[ -x "$inside" ] && scanners+=("$inside")
n=0
for scanner in "${scanners[@]}"; do
  version=$("$scanner" version) || exit 1
  n=$((n + 1))
  out=$(look_with "$scanner" "$T/home$n")
  compare "What Keys finds, with Betterleaks $version" "$HERE/keys.expected.txt" "$out" "${1:-}" || status=1
done

# A copy of Whozmove without Betterleaks: it says it couldn't look, with the way to get Whozmove again, the install
# module's: a copy Homebrew installed (its record in Homebrew's folder) copies the command that installs it
# again, and another opens the page it comes from. And one whose Betterleaks macOS stops: it says it didn't run, and
# panel.log says why each couldn't look.
card() {
  HOME="$1" "$APP" --print-keys "${2:-$1/no-betterleaks}" | python3 -I -c '
import json, sys
found = json.load(sys.stdin)
print("stopped: %s · again: %s" % (found.get("stopped"), found.get("again")))'
}
G="$T/again"
mkdir -p "$G"
out="not from Homebrew: $(card "$G")"
mkdir -p "$G/opt/homebrew/Caskroom/whozmove/.metadata"
echo '{"source": {"tap": "whozmove/tap", "version": "0.2.0"}}' > "$G/opt/homebrew/Caskroom/whozmove/.metadata/INSTALL_RECEIPT.json"
out+=$'\n'"from Homebrew: $(card "$G")"
# One that macOS stops as it starts, after saying why: the look says it didn't run, and panel.log says why.
printf '#!/bin/sh\necho "dyld[1]: Library not loaded: @rpath/libsample.dylib" >&2\nkill -9 $$\n' > "$G/stopped"
chmod +x "$G/stopped"
out+=$'\n'"one macOS stops: $(card "$G" "$G/stopped")"
out+=$'\n'"panel.log:"$'\n'"$(keys_log "$G")"
compare "Without Betterleaks" "$HERE/again.expected.txt" "$out" "${1:-}" || status=1
exit $status
