# The inbox module

A team's lead reads what its sessions write to it one message at a time, most pressing first, however the line that
told it went: each message is kept here before that line is sent, with the priority its sender set (urgent,
question, report or note), and marked read and answered by the lead. And Messages, beside the list, behind Working on
Whozmove ▸: every message the sessions sent each other in the last two days, in time order, with how pressing each
one is and whether it was read, answered, held or lost ([docs/using/messages.md](../../docs/using/messages.md)). The
messages themselves come from the agent that records them (`AgentMessages`, app/contracts/AgentMessages.h); the teams
and their leads from the team module (`TeamFacts`).

## Its pieces

- `app/InboxRecord.h` and `app/InboxRecord.m`: what it keeps (`AppDir/inbox/inbox.json`, its shape in
  [docs/reference/inbox.md](../../docs/reference/inbox.md)), as plain functions over the record: a message kept, up
  to a ceiling of a sender's unanswered ones against runaway scripts (`InboxMostWaiting`), and words refused (none,
  past 8,000 characters, or with something shaped like a key in them, `LooksLikeSecret`); the order a lead reads in
  (`InboxWaiting`) and the next for it (`InboxNextFor`: one a lead before it read and nobody answered counts as unread
  for the next); read and answered; the line that tells the lead (`InboxLine`) and the kept id at its start
  (`InboxIdInLine`); what became of that line (`InboxRecordRing`, its `told`), only from the session that kept it; a
  plain message to a lead lost on the way (`InboxRecordLost`); the week's counts of both (`InboxWeekCounts`); and what
  goes once it's old (`InboxRecordPrune`: answered after 7 days, unanswered after 14, a week's counts after 8 weeks).
- `app/InboxModule.m`: its face for the core (contracts/Module.h).
  - The asks (`sessionAsks`), each only keeping or showing words between sessions, so none needs a switch
    (`askShowing:`), and each logging itself (`logsItself`): `message`, kept for the lead of the team the asking
    session's project has (`ProjectRoot` of its folder, its main checkout for a worktree too), then answered with the
    kept id, the lead's address as the agent gives it (`addressOfSession:`) and the line to send there, or why
    there's nothing to ring (the lead isn't running, or no agent says where sessions listen); `inbox`, `inbox-next` and
    `inbox-answered`, only for the session the team module names a team's lead, whatever it asks.
  - What the agent says of its messages (`messagesAfter:change:then:`), from as far back as the window, two days
    (`kWindow`, the one place it's decided, which the agent is told), asked only as its count of changes moves, and
    once at the start: each line's fate joined to its message, a plain message lost on its way to a lead counted, and
    the last two days held in memory only. `KeptMessages`: whether a message is only a line for one kept here (its id
    at the start, from the session that kept it), so a held one asks nothing of you. The page is told the agent's own
    name, or that none records its messages, so nothing here names an agent or its tools.
  - Messages beside the list: Working on Whozmove ▸ Show Messages (`menuEntries`, order 45), ticked while it shows, a
    press opening or closing it (`openMessages`, `closeMessages`); everything sent once as it opens (`messagesOpen`),
    then only the messages new or changed since, with each inbox's unread in its lead's order and the week's counts
    (`setMessages`), and nothing once it's closed (`messagesClosed`). A lost message's words copied (`messagesCopy`),
    found by its id, never words the page sends.
  - Its print runs: `--print-inbox`, the record's rules over made-up messages, and `--print-inbox-asks`, the asks for
    stand-in sessions, with a stand-in agent.
- `page/inbox-words.js`, plain functions, checked by the page cases: the messages held and merged (`mxTake`), each
  session's name, with its folder or "ended" where two share one (`mxNames`), what answers what (`mxAnswers`: a
  message answers the latest earlier one from its receiver to its sender that reached it and nothing answered yet),
  where each stands in words (`mxWhere`), waiting and not delivered (`mxWaiting`, `mxLost`), the filters, one
  session's messages and a pair (`mxShown`, `mxCounts`), the words with nothing to show (`mxEmptyWords`), the week's
  counts (`mxWeekWords`) and the inboxes' strip (`mxStrip`).
- `page/inbox-view.js`, the drawing: the head, the filters, the strip and the channel, each message with its tag, its
  words drawn as the reader draws Markdown (`markdownHTML`, escaped first), and where it stands.
- `page/inbox.js`: the reader's `messages` mode (`core.readerModes.messages`), its presses, and what the app calls.
- `page/inbox.css`.
- `tests/test.sh`: `--print-inbox`, compared with `inbox.expected.txt`; the asks for stand-in sessions in a sample
  home, and ask-panel.sh over a real socket from inside one's process (`--print-inbox-asks`), compared with
  `asks.expected.txt`; and the page's rules (`page-cases.js`), compared with `page.expected.txt`.

## Rules

- **Kept first.** A message is in the record before the line that tells the lead is sent, so a line held in a tab,
  expired or dropped loses nothing: the lead reads the record, never the line.
- **Only an inbox's lead reads or marks it,** found by the session the core found asking and the team module's lead
  for its project, never by anything an ask says. Another session asking is told the lead's name, never its session.
- **No message's words in the log, and none with a key in it kept.** panel.log has each ask, the message's id and its
  priority, never its words, what it's about or an answer's note.
- **Nothing here is your move.** Messages only says where each stands: a held plain message is acted on from its
  session's row alone, and a line for a message kept here asks nothing of you. No amber in the view.
- **The panel's colour meanings:** Urgent a strong neutral tag, Question and Report grey, Note an outline; a message
  lost in red-orange (`--needs-text`), answered in `--done-text`; never git's red.
- **Everything said is escaped first,** drawn as the reader draws Markdown, and never run.
- **Cheap.** The agent is asked only when its count of changes moves; nothing reaches the page while Messages is
  closed; and once it's open, only what changed.
- **Behind Working on Whozmove ▸** until teams are for everyone: the inbox's asks work for any team's sessions, while
  Messages shows only from there.
