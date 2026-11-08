# A stand-in for Atlassian on 127.0.0.1, for Jira's tests: its sign-in (the resource's page, the sign-in service's page,
# registering, the page you'd see, tokens) and its server for AI tools (a session, Jira's tools, with made-up tickets on
# a made-up site), checking what Whozmove sends as Atlassian would: PKCE with S256, the state, the token on every call.
# It writes the port it listens on to <port file>, and what it was asked, one line each, to <log file>, never a token.
# In `noscope`, it refuses every write as Jira refuses a token without the write scope.
#   python3 -I stand-in.py <port file> <log file> [blocked | slow | expired | noscope]
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
import base64, hashlib, json, sys, urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT_FILE, LOG_FILE = sys.argv[1], sys.argv[2]
MODE = sys.argv[3] if len(sys.argv) > 3 else ""
SITE = "https://acme.atlassian.net"

state = {"client": None, "challenge": None, "redirect": None, "code": None, "access": None, "refresh": None,
         "turned_once": False, "issue": "In Progress", "notes": [], "made": 0}

def log(line):
    with open(LOG_FILE, "a") as f:
        f.write(line + "\n")

def status(name, key, cid):
    return {"name": name, "statusCategory": {"key": key, "id": cid}}

STATES = {"To Do": status("To Do", "new", 2), "In Progress": status("In Progress", "indeterminate", 4),
          "In Review": status("In Review", "indeterminate", 4), "Done": status("Done", "done", 3)}
# Each state's own next steps, as this made-up project's workflow gives them: ids only Jira reads.
STEPS = {"To Do": [("21", "Start work", "In Progress")],
         "In Progress": [("31", "Send to review", "In Review"), ("11", "Back to To Do", "To Do")],
         "In Review": [("51", "QA sign-off", "Done"), ("61", "Back to In Progress", "In Progress")],
         "Done": []}

def issue(key="PAY-142"):
    return {"id": "10142", "key": key, "self": "https://ignored.example/rest/api/3/issue/10142", "fields": {
        "summary": "Login button does nothing on Safari", "status": STATES[state["issue"]],
        "issuetype": {"name": "Bug", "avatarUrls": {}}, "priority": {"name": "High"},
        "assignee": {"displayName": "Sam Rivera", "accountId": "abc"},
        "project": {"key": "PAY", "name": "Payments"}, "resolution": None,
        "parent": {"key": "PAY-120", "fields": {"summary": "Checkout works in every browser", "issuetype": {"name": "Epic"}}},
        "customfield_10020": [{"id": 7, "name": "Sprint 13", "state": "closed"}, {"id": 8, "name": "Sprint 14", "state": "active"}]}}

def tool(name, args):
    if name == "getAccessibleAtlassianResources":
        return [{"id": "11111111-1111-1111-1111-111111111111", "url": SITE, "name": "acme", "scopes": ["read:jira-work"]},
                {"id": "11111111-1111-1111-1111-111111111111", "url": SITE, "name": "acme", "scopes": ["read:confluence"]}]
    if args.get("cloudId") != SITE:
        return {"error": True, "message": "Unknown site", "statusCode": 404}
    if name == "searchJiraIssuesUsingJql":
        found = [issue()] if "login" in args.get("jql", "").lower() or "PAY-142" in args.get("jql", "") else []
        return {"issues": {"totalCount": len(found), "nodes": found, "pageInfo": {"hasNextPage": False}},
                "context": {"endpoint": "v2:streamable-http"}}
    if name == "getJiraIssue":
        if args.get("issueIdOrKey") != "PAY-142" and args.get("issueIdOrKey") != "PAY-151":
            return {"error": True, "message": "Issue does not exist or you do not have permission to see it.", "statusCode": 404}
        return {"data": {"appliedContentFormat": "html", **issue(args["issueIdOrKey"])}}
    if name == "executeRead":
        inner, inputs = args.get("name"), args.get("inputs", {})
        if inner == "listJiraIssueTransitions":
            fields = {"resolution": {"required": True, "name": "Resolution", "schema": {"type": "resolution"},
                                     "allowedValues": [{"id": "10000", "name": "Done"}, {"id": "10001", "name": "Won't Do"}]}}
            return {"transitions": [{"id": i, "name": n, "isAvailable": True, "to": STATES[to],
                                     **({"fields": fields} if to == "Done" else {})}
                                    for i, n, to in STEPS[state["issue"]]]}
        if inner == "listJiraProjectIssueTypesMetadata":
            if inputs.get("projectIdOrKey") != "PAY":
                return {"error": True, "message": "No project could be found with key '%s'." % inputs.get("projectIdOrKey"),
                        "statusCode": 404}
            return {"issueTypes": [{"id": "10001", "name": "Task"}, {"id": "10004", "name": "Bug"},
                                   {"id": "10007", "name": "Story"}]}
        if inner == "listJiraBoards":
            return {"values": [{"id": 3, "name": "Payments board", "type": "scrum"}]}
        return {"error": True, "message": 'Unknown operation "%s". Use discover to find valid operation names.' % inner,
                "statusCode": 400}
    if name == "transitionJiraIssue":
        steps = {i: to for i, n, to in STEPS[state["issue"]]}
        to = steps.get(args.get("transition", {}).get("id"))
        if not to:
            return {"error": True, "message": "Transition is not valid", "statusCode": 400}
        # As Jira does, a step to Done needs its resolution, given as one of the screen's allowed values by its id.
        if to == "Done" and args.get("fields", {}).get("resolution") not in ({"id": "10000"}, {"id": "10001"}):
            return {"error": True, "message": "Resolution is required.", "statusCode": 400}
        state["issue"] = to
        return {"success": True}
    if name == "addOrEditJiraIssueComment":
        state["notes"].append(args.get("commentBody", ""))
        return {"id": "20001"}
    if name == "createJiraIssue":
        if not (args.get("projectKey") and args.get("issueType") and args.get("summary")):
            return {"error": True, "message": "Missing fields", "statusCode": 400}
        # As Jira does, a priority the project doesn't have turns the whole ticket away.
        if args.get("priority") not in (None, "High", "Low"):
            return {"error": True, "message": "Specify a valid priority", "statusCode": 400}
        state["made"] += 1
        # One the test can't read back just after it's made, as a read can fail then.
        if "unread" in args.get("summary", ""):
            return {"key": "PAY-152", "id": "10152", "self": "https://ignored.example"}
        return {"key": "PAY-151", "id": "10151", "self": "https://ignored.example"}
    return {"error": True, "message": "Unknown tool", "statusCode": 400}

def challenge_of(verifier):
    return base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip("=")

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def base(self):
        return "http://127.0.0.1:%d" % self.server.server_port

    def send(self, code, body=None, headers=None, kind="application/json"):
        data = b"" if body is None else (body if isinstance(body, bytes) else json.dumps(body).encode())
        self.send_response(code)
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        if body is not None:
            self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        q = dict(urllib.parse.parse_qsl(url.query))
        if url.path == "/.well-known/oauth-protected-resource/v2/mcp":
            log("GET the resource's page")
            return self.send(200, {"resource": self.base() + "/v2/mcp", "authorization_servers": [self.base() + "/auth"]})
        if url.path == "/.well-known/oauth-authorization-server/auth":
            log("GET the sign-in service's page")
            b = self.base() + "/auth"
            return self.send(200, {"issuer": b, "authorization_endpoint": b + "/authorize", "token_endpoint": b + "/token",
                                   "registration_endpoint": b + "/register", "code_challenge_methods_supported": ["S256"],
                                   "token_endpoint_auth_methods_supported": ["none", "client_secret_post"]})
        if url.path == "/auth/authorize":
            right = (q.get("client_id") == state["client"] and q.get("code_challenge_method") == "S256"
                     and q.get("redirect_uri") == state["redirect"] and q.get("state") and q.get("code_challenge")
                     and q.get("resource") == self.base() + "/v2/mcp" and "offline_access" in q.get("scope", "").split())
            log("GET the page you'd see: %s" % ("as Atlassian wants it" if right else "NOT as Atlassian wants it"))
            state["challenge"] = q.get("code_challenge")
            state["code"] = "code-1"
            back = q.get("redirect_uri", "") + "?" + urllib.parse.urlencode({"code": "code-1", "state": q.get("state", "")})
            return self.send(302, b"", {"Location": back})
        self.send(404, {"error": "not_found"})

    def do_POST(self):
        url = urllib.parse.urlparse(self.path)
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        if url.path == "/auth/register":
            client = json.loads(body or b"{}")
            redirect = (client.get("redirect_uris") or [""])[0]
            ok = redirect.startswith("http://127.0.0.1:") and client.get("token_endpoint_auth_method") == "none"
            log("POST register %s, %s" % (client.get("client_name"), "a 127.0.0.1 return, no secret" if ok else "NOT as asked"))
            if MODE == "blocked":
                return self.send(400, {"error": "invalid_redirect_uri", "error_description": "blocked by your admin"})
            state["client"], state["redirect"] = "client-1", redirect
            return self.send(201, {"client_id": "client-1"})
        if url.path == "/auth/token":
            f = dict(urllib.parse.parse_qsl(body.decode()))
            if f.get("grant_type") == "authorization_code":
                proven = (f.get("code") == state["code"] and challenge_of(f.get("code_verifier", "")) == state["challenge"]
                          and f.get("client_id") == state["client"] and f.get("redirect_uri") == state["redirect"])
                log("POST token for a code: %s" % ("proven with its verifier" if proven else "NOT proven"))
                if not proven:
                    return self.send(400, {"error": "invalid_grant"})
                state["access"], state["refresh"] = "access-1", "refresh-1"
                return self.send(200, {"access_token": "access-1", "refresh_token": "refresh-1", "expires_in": 3600})
            if f.get("grant_type") == "refresh_token":
                right = f.get("refresh_token") == state["refresh"] and f.get("client_id") == state["client"]
                log("POST token for a refresh: %s" % ("the latest refresh token" if right else "NOT the latest"))
                if MODE == "expired" or not right:
                    return self.send(400, {"error": "invalid_grant"})
                n = int(state["refresh"].split("-")[1]) + 1
                state["access"], state["refresh"] = "access-%d" % n, "refresh-%d" % n
                return self.send(200, {"access_token": state["access"], "refresh_token": state["refresh"], "expires_in": 3600})
        if url.path == "/v2/mcp":
            message = json.loads(body or b"{}")
            method = message.get("method")
            given = self.headers.get("Authorization", "")
            if given != "Bearer %s" % state["access"]:
                log("POST %s without a token it takes" % method)
                return self.send(401, {"error": "invalid_token"},
                                 {"WWW-Authenticate": 'Bearer resource_metadata="%s"' % (
                                     self.base() + "/.well-known/oauth-protected-resource/v2/mcp")})
            if method == "initialize":
                log("POST initialize")
                answer = {"jsonrpc": "2.0", "id": message["id"], "result": {
                    "protocolVersion": "2025-06-18", "capabilities": {"tools": {}}, "serverInfo": {"name": "stand-in"}}}
                # Its answer comes as server-sent events, as Streamable HTTP lets it.
                events = ("event: message\ndata: %s\n\n" % json.dumps(answer)).encode()
                return self.send(200, events, {"Mcp-Session-Id": "session-1"}, "text/event-stream")
            if method and method.startswith("notifications/"):
                return self.send(202)
            if self.headers.get("Mcp-Session-Id") != "session-1":
                log("POST %s outside the session" % method)
                return self.send(400, {"error": "no session"})
            if method == "tools/call":
                params = message.get("params", {})
                name, args = params.get("name"), params.get("arguments", {})
                shown = name + (" " + args.get("name", "") if name.startswith("execute") else "")
                if MODE == "expired" and not state["turned_once"]:
                    # A token that has run out early: Whozmove refreshes it, which this mode turns away.
                    state["turned_once"] = True
                    state["access"] = "gone"
                    log("POST tools/call %s: turned away, the token has run out" % shown)
                    return self.send(401, {"error": "invalid_token"})
                if MODE == "slow":
                    log("POST tools/call %s: asked to slow down" % shown)
                    return self.send(429, {"error": "rate_limited"}, {"Retry-After": "30"})
                writes = name in ("transitionJiraIssue", "addOrEditJiraIssueComment", "createJiraIssue", "executeWrite")
                if MODE == "noscope" and writes:
                    log("POST tools/call %s: refused, the token has no write scope" % shown)
                    value = {"error": True, "message": "Unauthorized; scope does not match", "statusCode": 401}
                    result = {"content": [{"type": "text", "text": json.dumps(value)}]}
                    return self.send(200, {"jsonrpc": "2.0", "id": message["id"], "result": result})
                if MODE == "drop" and name == "createJiraIssue":
                    # Made, then the answer lost on its way back, as a dropped connection or a timeout loses it.
                    state["made"] += 1
                    log("POST tools/call %s: made, and its answer dropped" % shown)
                    self.close_connection = True
                    return
                log("POST tools/call %s%s%s" % (shown, " with a note" if args.get("commentBody") else "",
                                                " with fields " + json.dumps(args["fields"], sort_keys=True)
                                                if name == "transitionJiraIssue" and "fields" in args else ""))
                value = tool(name, args)
                result = {"content": [{"type": "text", "text": json.dumps(value)}]}
                return self.send(200, {"jsonrpc": "2.0", "id": message["id"], "result": result})
        self.send(404, {"error": "not_found"})

server = HTTPServer(("127.0.0.1", 0), Handler)
with open(PORT_FILE, "w") as f:
    f.write(str(server.server_port))
server.serve_forever()
