# A stand-in for Atlassian on 127.0.0.1, for Jira's tests: its sign-in (the resource's page, the sign-in service's page,
# registering, the page you'd see, tokens) and its server for AI tools (a session, Jira's tools, with made-up tickets on
# a made-up site), checking what Whozmove sends as Atlassian would: PKCE with S256, the state, the token on every call.
# It writes the port it listens on to <port file>, and what it was asked, one line each, to <log file>, never a token.
# In `noscope`, it refuses every write as Jira refuses a token without the write scope; in `nolist`, it turns away the
# read of a project's priorities, as Jira does for a type you may not create; in `slowtype`, a read leaves the ticket's
# type out, as a view smaller than the full one does, and it asks to slow down only for the search by key that a read
# then makes for it. In `silent`, Jira turns every move away saying
# nothing; in `busy`, Jira answers every move with a 500 that gives reasons all the same (`every` changes nothing: it
# gives a talk about every ticket a home of its own).
# Assumed until a live read confirms them (JiraFacts says so too): that a search takes `project IS NOT EMPTY` and
# pages by `nextPageToken`, and that getJiraIssue with `expand: "changelog"` gives a ticket's history as Jira's own API
# does.
#   python3 -I stand-in.py <port file> <log file> [blocked | slow | slowtype | expired | noscope | nolist | drop |
#   silent | busy | every]
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

# Each state's category, as Jira has three: an issue in a view smaller than v2's full one names its category alone
# ({name}), the full view and a step's target give its key ({key}).
CATEGORIES = {"To Do": ("To Do", "new"), "In Progress": ("In Progress", "indeterminate"),
              "In Review": ("In Progress", "indeterminate"), "Blocked": ("In Progress", "indeterminate"),
              "Done": ("Done", "done")}

def issue_status(name, full=False):
    category = {"key": CATEGORIES[name][1], "name": CATEGORIES[name][0]} if full else {"name": CATEGORIES[name][0]}
    return {"name": name, "statusCategory": category}

def step_target(name):
    return {"name": name, "statusCategory": {"key": CATEGORIES[name][1]}}

# Each state's own next steps, as this made-up project's workflow gives them: ids only Jira reads.
STEPS = {"To Do": [("21", "Start work", "In Progress")],
         "In Progress": [("31", "Send to review", "In Review"), ("11", "Back to To Do", "To Do"),
                         ("41", "Block", "Blocked")],
         "In Review": [("51", "QA sign-off", "Done"), ("61", "Back to In Progress", "In Progress")],
         "Blocked": [], "Done": []}

# The project's priorities, in its scheme's order, with Jira's ids; and one given since that list was read (PAY-151's).
PRIORITIES = [("1", "Highest"), ("2", "High"), ("3", "Medium"), ("4", "Low"), ("5", "Lowest")]
LATER = {"id": "10100", "name": "Blocker"}

# Jira turning a request away, as v2 says it: in the answer's data, with each problem's reason.
def refused(key, reason, field="global0"):
    return {"data": {"error": "TRANSITION_FAILED", "message": "Jira rejected the transition request for issue %s." % key,
                     "problems": [{"field": field, "reason": reason}], "repairHint": "Fix each entry in problems.",
                     "status": 400, "upstreamErrors": {"errorMessages": [reason], "errors": {}}}}

# An issue as v2 gives it. In its full view: the priority's id, the category's key, the type, project, parent, a done
# one's resolution, its comments, and custom fields by name. In any smaller view, or for a list of fields, which
# overrides the view: the priority and category by name, no project, parent or resolution, and a type only in a search.
SPRINTS = [{"id": 7, "name": "Sprint 13", "state": "closed"},
           {"id": 8, "name": "Sprint 14", "state": "active", "startDate": "2030-01-06T06:30:00.000Z",
            "endDate": "2030-01-12T18:29:00.000Z"}]

# A ticket's description, as the full view gives it: Markdown text, with markup to stay as text; or, in mode adf,
# Atlassian's document format; or, in mode longabout, longer than Whozmove hands a session.
def description():
    if MODE == "adf":
        return {"type": "doc", "version": 1, "content": [
            {"type": "heading", "attrs": {"level": 2}, "content": [{"type": "text", "text": "Made-up description"}]},
            {"type": "paragraph", "content": [
                {"type": "text", "text": "The button does nothing on "},
                {"type": "text", "text": "Safari 17", "marks": [{"type": "strong"}]},
                {"type": "hardBreak"},
                {"type": "text", "text": "Seen by "}, {"type": "mention", "attrs": {"id": "made-up", "text": "@Sam Rivera"}},
                {"type": "text", "text": " "}, {"type": "emoji", "attrs": {"shortName": ":eyes:", "text": "👀"}}]},
            {"type": "bulletList", "content": [
                {"type": "listItem", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Open the checkout"}]}]},
                {"type": "listItem", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Press <Pay>"}]}]}]},
            {"type": "codeBlock", "content": [{"type": "text", "text": "TypeError: pay is undefined"}]},
            {"type": "paragraph", "content": [{"type": "inlineCard", "attrs": {"url": "https://example.com/steps"}}]},
            {"type": "mediaSingle", "content": [{"type": "media", "attrs": {"id": "made-up", "type": "file"}}]}]}
    if MODE == "longabout":
        return "Made-up description, line after line.\n" * 600
    return ("Made-up description: the **Login** button does nothing on Safari 17.\n\n"
            "1. Open the checkout\n2. Press <b>Pay</b> & see <script>nothing</script>")

# The made-up project's other tickets, each its title, its state and its priority's id; PAY-142 is the one above, in
# whatever state it's been moved to.
OTHERS = {"PAY-143": ("Receipts show the wrong currency", "To Do", "3"), "PAY-144": ("Refunds take a week", "In Review", "1"),
          "PAY-145": ("Card form forgets the name", "To Do", "4"), "PAY-146": ("Old promo banner", "Done", "5"),
          "PAY-147": ("Split payments", "In Progress", "2")}

def issue(key="PAY-142", searched=False, args=None):
    full = (args or {}).get("view") == "full" and "fields" not in (args or {})
    title, status, priority_id = OTHERS.get(key, ("Login button does nothing on Safari", state["issue"], "2"))
    priority = LATER if key == "PAY-151" else dict(zip(("id", "name"), PRIORITIES[int(priority_id) - 1]))
    fields = {"summary": title, "status": issue_status(status, full),
              "priority": priority if full else {"name": priority["name"]},
              "assignee": {"accountId": "made-up-sam", "displayName": "Sam Rivera"},
              "labels": ["checkout"] if key == "PAY-142" else [], "updated": "2030-01-08T09:15:00.000+0000"}
    if full:
        fields.update({
            "reporter": {"accountId": "made-up-ana", "displayName": "Ana Lima"},
            "issuelinks": [{"id": "1", "type": {"name": "Blocks", "inward": "is blocked by", "outward": "blocks"},
                            "inwardIssue": {"key": "PAY-145", "fields": {"summary": OTHERS["PAY-145"][0],
                                                                         "issuetype": {"name": "Task"}}}}]
                          if key == "PAY-142" else [],
            "issuetype": {"id": "10004", "name": "Bug", "description": "A problem.", "subtask": False, "hierarchyLevel": 0},
            "project": {"id": "10000", "key": "PAY", "name": "Payments"},
            "parent": {"id": "10100", "key": "PAY-100", "fields": {
                "summary": "Checkout on every browser", "status": issue_status("In Progress", True),
                "priority": {"id": "3", "name": "Medium"},
                "issuetype": {"id": "10001", "name": "Epic", "subtask": False, "hierarchyLevel": 1}}},
            "comment": {"comments": [{"id": "10000", "author": {"displayName": "Sam Rivera"}, "body": "Seen on 17.2 too.",
                                      "created": "2001-01-01T00:00:00.000+0000", "jsdPublic": True}],
                        "maxResults": 1, "startAt": 0, "total": 1},
            "description": description(),
            "customFields": {"Sprint": {"id": "customfield_10020", "value": SPRINTS}}})
        if (args or {}).get("expand") == "changelog":
            read_changelog = [
                {"id": "2", "author": {"accountId": "made-up-sam", "displayName": "Sam Rivera"}, "created": "2030-01-07T10:00:00.000+0000",
                 "items": [{"field": "status", "fromString": "To Do", "toString": "In Progress"}]},
                {"id": "1", "author": {"accountId": "made-up-ana", "displayName": "Ana Lima"}, "created": "2030-01-06T08:00:00.000+0000",
                 "items": [{"field": "priority", "fromString": "Medium", "toString": "High"}]}]
            return {"id": "10142", "key": key, "fields": fields, "changelog": {"histories": read_changelog}}
        if state["issue"] == "Done":
            fields["resolution"] = {"id": "10000", "name": "Done", "description": "Work on it is complete."}
    else:
        fields["customfield_10020"] = SPRINTS
        if searched:
            fields["issuetype"] = {"name": "Bug"}
    return {"id": str(10000 + int(key.split("-")[1])), "key": key, "fields": fields}

# Every ticket you can see, as a search for every one gives them: PAY-142 to PAY-147, the most recently changed first;
# `updated >= -Nm`, only PAY-142. Five a page, the next page by its token.
def every(jql, args):
    keys = ["PAY-142"] + sorted(OTHERS)
    if jql.startswith("updated >= -"):
        keys = keys[:1]
    start = int(args.get("nextPageToken", "0") or 0)
    page = keys[start:start + int(args.get("maxResults", 5))]
    more = start + len(page) < len(keys)
    answer = {"isLast": not more, "issues": [issue(k, searched=True, args=args) for k in page]}
    if more:
        answer["nextPageToken"] = str(start + len(page))
    return answer

def tool(name, args):
    if name == "getAccessibleAtlassianResources":
        # As v2 gives them: each site under data's resources, with the products it has; one without Jira is left out.
        return {"data": {"resources": [
            {"cloudId": "11111111-1111-1111-1111-111111111111", "url": SITE,
             "products": [{"access": "read-write", "id": "jira"}]},
            {"cloudId": "22222222-2222-2222-2222-222222222222", "url": "https://beta.atlassian.net",
             "products": [{"access": "read-write", "id": "confluence"}]}]}}
    if args.get("cloudId") != SITE:
        return {"error": True, "message": "Unknown site", "statusCode": 404}
    if name == "searchJiraIssuesUsingJql":
        jql = args.get("jql", "")
        if jql.startswith("project IS NOT EMPTY") or jql.startswith("updated >= -"):
            return {"data": {"appliedContentFormat": "markdown", **every(jql, args)}}
        found = [issue(searched=True, args=args)] if "login" in jql.lower() or "PAY-142" in jql else []
        return {"data": {"appliedContentFormat": "markdown", "isLast": True, "issues": found}}
    if name == "getJiraIssue":
        if args.get("issueIdOrKey") != "PAY-142" and args.get("issueIdOrKey") != "PAY-151":
            return {"error": True, "message": "Issue does not exist or you do not have permission to see it.", "statusCode": 404}
        read = issue(args["issueIdOrKey"], args=args)
        if MODE == "slowtype":
            read["fields"].pop("issuetype", None)
        return {"data": {"appliedContentFormat": "markdown", **read}}
    if name == "executeRead":
        inner, inputs = args.get("name"), args.get("inputs", {})
        if inner == "listJiraIssueTransitions":
            fields = {"resolution": {"required": True, "name": "Resolution", "schema": {"type": "resolution"},
                                     "allowedValues": [{"id": "10000", "name": "Done"}, {"id": "10001", "name": "Won't Do"}]}}
            return {"data": {"transitions": [{"id": i, "name": n, "isAvailable": True, "to": step_target(to),
                                              "hasScreen": to == "Done", "fields": fields if to == "Done" else {}}
                                             for i, n, to in STEPS[state["issue"]]]}}
        if inner == "listJiraProjectIssueTypesMetadata":
            if inputs.get("projectIdOrKey") != "PAY":
                return {"error": True, "message": "No project could be found with key '%s'." % inputs.get("projectIdOrKey"),
                        "statusCode": 404}
            return {"data": {"issueTypes": [{"id": "10001", "name": "Task", "subtask": False},
                                            {"id": "10004", "name": "Bug", "subtask": False},
                                            {"id": "10007", "name": "Story", "subtask": False}],
                             "maxResults": 50, "startAt": 0, "total": 3}}
        if inner == "getJiraIssueTypeMetaWithFields":
            if MODE == "nolist":
                return {"error": True, "message": "You do not have permission to create issues in this project.",
                        "statusCode": 403}
            if inputs.get("projectIdOrKey") != "PAY" or inputs.get("issueTypeId") != "10001":
                return {"error": True, "message": "Issue type not found", "statusCode": 404}
            # As Jira gives a type's create fields: a page of them, the priority field's allowed values in order, a
            # made-up Region that lists its options, and a Team looked up as you type, which lists none.
            return {"startAt": 0, "maxResults": 50, "total": 4, "fields": [
                {"fieldId": "summary", "key": "summary", "name": "Summary", "required": True, "schema": {"type": "string", "system": "summary"}},
                {"fieldId": "priority", "key": "priority", "name": "Priority", "required": False,
                 "schema": {"type": "priority", "system": "priority"},
                 "allowedValues": [{"self": "https://ignored.example", "id": i, "name": n} for i, n in PRIORITIES]},
                {"fieldId": "customfield_10300", "key": "customfield_10300", "name": "Region", "required": False,
                 "schema": {"type": "option", "custom": "select"},
                 "allowedValues": [{"id": "10400", "value": "North"}, {"id": "10401", "value": "South"}]},
                {"fieldId": "customfield_10001", "key": "customfield_10001", "name": "Team", "required": False,
                 "schema": {"type": "team", "custom": "atlassian-team"}}]}
        if inner == "listJiraBoards":
            return {"data": {"isLast": True, "maxResults": 50, "startAt": 0, "total": 1,
                             "values": [{"id": 3, "name": "Payments board", "type": "scrum",
                                         "location": {"projectKey": "PAY", "projectName": "Payments"}}]}}
        return {"error": True, "message": 'Unknown operation "%s". Use discover to find valid operation names.' % inner,
                "statusCode": 400}
    if name == "transitionJiraIssue":
        key = args.get("issueIdOrKey", "")
        steps = {i: to for i, n, to in STEPS[state["issue"]]}
        to = steps.get(args.get("transitionId"))
        if MODE == "silent":
            return {"data": {"error": "TRANSITION_FAILED", "status": 409}}
        if MODE == "busy":
            busy = refused(key, "Something went wrong on our side. Try again in a moment.")
            busy["data"]["status"] = 500
            return busy
        if not to:
            return refused(key, "Can't move (%s). You might not have permission, or the work item is missing required "
                                "information." % key)
        # As Jira does, a step to Done needs its resolution, given as one of the screen's allowed values by its id.
        if to == "Done" and args.get("fields", {}).get("resolution") not in ({"id": "10000"}, {"id": "10001"}):
            return refused(key, "Resolution is required.", "resolution")
        # Block wants a field that isn't on its screen filled in first, as a site's validator can.
        if to == "Blocked":
            return refused(key, "Fill in Blocked by first: what is it waiting on?")
        state["issue"] = to
        return {"data": {"message": "Issue %s transitioned successfully" % key, "statusName": to,
                         "transitionId": int(args["transitionId"])}}
    if name == "addOrEditJiraIssueComment":
        state["notes"].append(args.get("commentBody", ""))
        return {"data": {"appliedContentFormat": "markdown", "body": args.get("commentBody", ""), "commentId": "20001",
                         "message": "Comment added to %s successfully" % args.get("issueIdOrKey", "")}}
    if name == "createJiraIssue":
        if not (args.get("projectKey") and args.get("issueType") and args.get("summary")):
            return {"error": True, "message": "Missing fields", "statusCode": 400}
        # As Jira does, a priority the project doesn't have turns the whole ticket away.
        if args.get("priority") not in (None, "High", "Low"):
            return {"error": True, "message": "Specify a valid priority", "statusCode": 400}
        state["made"] += 1
        # One the test can't read back just after it's made, as a read can fail then.
        if "unread" in args.get("summary", ""):
            return {"data": {"id": "10152", "key": "PAY-152"}}
        return {"data": {"id": "10151", "key": "PAY-151"}}
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
                by_key = name == "searchJiraIssuesUsingJql" and args.get("jql", "").startswith("key = ")
                if MODE == "slow" or (MODE == "slowtype" and by_key):
                    log("POST tools/call %s: asked to slow down" % shown)
                    return self.send(429, {"error": "rate_limited"}, {"Retry-After": "30"})
                writes = name in ("transitionJiraIssue", "addOrEditJiraIssueComment", "createJiraIssue", "executeWrite")
                if MODE == "noscope" and writes:
                    log("POST tools/call %s: refused, the token has no write scope" % shown)
                    value = {"error": True, "message": "Unauthorized; scope does not match", "statusCode": 401}
                    result = {"content": [{"type": "text", "text": json.dumps(value)}]}
                    return self.send(200, {"jsonrpc": "2.0", "id": message["id"], "result": result})
                if MODE == "failreads" and name == "getJiraIssue":
                    # Each read fails another way, every one with words of its own that must never reach a log.
                    state["failed"] = state.get("failed", 0) + 1
                    words = "Made-up server words: <b>nope</b> & more"
                    how = state["failed"]
                    log("POST tools/call %s: failed, way %d" % (shown, how))
                    if how == 1:
                        return self.send(502, {"error": words})
                    if how == 2:
                        return self.send(200, {"jsonrpc": "2.0", "id": message["id"],
                                               "error": {"code": -32603, "message": words}})
                    if how == 3:
                        return self.send(200, ("<html>%s</html>" % words).encode(), None, "text/html")
                    if how == 4:
                        result = {"content": [{"type": "text", "text": words}], "isError": True}
                        return self.send(200, {"jsonrpc": "2.0", "id": message["id"], "result": result})
                    if how == 5:
                        value = {"error": True, "message": words, "statusCode": 503}
                        result = {"content": [{"type": "text", "text": json.dumps(value)}], "isError": True}
                        return self.send(200, {"jsonrpc": "2.0", "id": message["id"], "result": result})
                    if how == 6:
                        result = {"content": [{"type": "text", "text": json.dumps({"error": True, "message": words})}]}
                        return self.send(200, {"jsonrpc": "2.0", "id": message["id"], "result": result})
                    self.close_connection = True
                    return
                if MODE == "drop" and name == "createJiraIssue":
                    # Made, then the answer lost on its way back, as a dropped connection or a timeout loses it.
                    state["made"] += 1
                    log("POST tools/call %s: made, and its answer dropped" % shown)
                    self.close_connection = True
                    return
                log("POST tools/call %s%s%s" % (shown, " with a note" if args.get("commentBody") else "",
                                                " with fields " + json.dumps(args["fields"], sort_keys=True)
                                                if name == "transitionJiraIssue" and "fields" in args else ""))
                if name == "transitionJiraIssue" and "transitionId" not in args:
                    result = {"content": [{"type": "text", "text": "Invalid arguments: transitionId is required"}],
                              "isError": True}
                    return self.send(200, {"jsonrpc": "2.0", "id": message["id"], "result": result})
                value = tool(name, args)
                result = {"content": [{"type": "text", "text": json.dumps(value)}]}
                return self.send(200, {"jsonrpc": "2.0", "id": message["id"], "result": result})
        self.send(404, {"error": "not_found"})

server = HTTPServer(("127.0.0.1", 0), Handler)
with open(PORT_FILE, "w") as f:
    f.write(str(server.server_port))
server.serve_forever()
