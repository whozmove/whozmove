# The panel's own rules

Rules the core keeps, whatever module is at work. CONTRIBUTING's [Rules that keep it
safe](../../CONTRIBUTING.md#rules-that-keep-it-safe) names each one.

- **The panel must never take the keyboard.** `FloatingPanel.canBecomeKeyWindow` is `wantsKeyboard`, set only while one
  of the panel's own text boxes is clicked into (`keyboard` message), while the new conversation card is open from ⌃⌥N
  or New Conversation, until it starts or closes, while a side chat's box has the cursor, put there by your press on
  Side Chat, the bar at a row's far edge, until it closes (Esc closes it) or a press anywhere else, or while a site shown in the
  panel (a `Browser`) has been clicked
  into, until a click anywhere else in the panel, the panel folding or turning over, or the site going; and while a
  request or a question in the list, or in a place beside it where rows are drawn (`core.keyPlaces`: the chats beside
  the folded panel, while the chat is out where it can be seen), or a note to keep on how a project works (its Keep It
  card, where Return is Keep It and a number key does nothing), has been pressed (`core.keyCards`, `heldCard` in the
  keyboard part), but where the press answers it, until it's answered or gone, Esc, or a press anywhere else, so
  Return answers it there and not Claude's own copy of it in the app in front. Only the copy pressed has the keys, in
  the place it was pressed in, and shows it. And while the view beside the list (the reader, One Task) has been
  pressed in, not on its ✕ (`viewPressed` in the keyboard part), until it closes, another app takes the keyboard, or a
  press anywhere else. Then Esc closes it, and no other key acts there (`escClosesView`). Opening it, by a row's tag
  or the pawn menu, leaves the keyboard where it was.
  Clicking a row leaves the keyboard with Claude, which is what lets "open
  a conversation, type straight away" work. When the panel lets go of the keyboard, it hands it to an unseen window of
  its own, which goes at once, so macOS gives it back to the app in front (`giveBackKeyboard`): asking that app to come
  forward does nothing while it's in front already. A moment after a press brings a terminal's tab forward, the terminal
  is checked to have it (`keyboardTo:tries:` in Focus.m), and the log says who had it when it hasn't. Don't synthesize
  clicks or move the pointer to focus things in Claude: it makes the mouse pointer jump. When another app takes the
  keyboard, the page lets go of the box or the card that had it (`keyboardGone`): asking for the keyboard makes the
  panel key at once, so a box focused again as the list is redrawn would take it back. Whozmove has no Edit menu, where
  an app's ⌘V and the rest come from, so while the panel has the keyboard, the page's view or a `Browser`'s, whichever
  has it, maps them to its page itself (`DoEditKey`, in app/shared/EditKeys.m): to the box being typed in, or the card
  pressed; dictation apps paste their words in with ⌘V too. It never takes the keyboard for them.
- **Only the panel's own page talks to the app.** The panel's page has no frames: `Page` lets none load in it, and
  ignores every message that doesn't come from its main frame. The reader shows a prototype a session wrote, scripts and
  all, in a `Browser` of its own, only from the file its session's row lists (never a path the page sends). Keep all
  three: a page Claude wrote must never answer a request. A `Browser` has no bridge at all, and no way to be given one:
  what it shows can never send the app a message. A folder's pages in one can't read the folder's files (WebKit's own
  rule for file pages), which is why they may take parts from the web: never turn on WebKit's file access preferences.
- **Hover is pointer polling** (25×/s, `pollPointer`), not mouse events: a non-key panel gets no mouse moves.
  Clicks are handled on `mousedown`, not `click`: the list re-renders whenever what it shows changes, any second. Folded with chats out beside
  the cat, the window holds the room for it, and only the cat and what's drawn there take the
  pointer and clicks (`passClicks:`, from the parts the page names in `catRoom`): everywhere else in that room, clicks
  go through to what's under the panel, decided as the pointer moves (60×/s then), never while a button is held. A
  site shown in the panel (a `Browser`) is passed the pointer only while the panel has the keyboard, once you've
  clicked into it: WebKit follows the pointer only in the window you type in, and the panel never seems to be that
  window when it isn't.
- **Typing into a session only when it's safe.** Ghostty: only while idle at its prompt with no request pending
  (`WhyNotTypeInto`), since a stray Enter would approve a permission prompt, and Shift+Tab would allow all edits. Never
  while it's paused in its terminal (Ctrl+Z), where keys go to the shell, nor while its conversation runs in another
  terminal too (open twice: resumed in a second tab), where a key could land in the other copy, whose tab can look just
  the same; and no Shift+Tab while it's open anywhere else too (Claude Desktop), as the copies share one record of the
  mode. iTerm2: the same, and only into a session alone in its window, no other tab or pane there (`whyNotTypeIn:`, and
  again in the script that types, right before): its Broadcast Input copies scripted typing into the window's other
  sessions, hidden floating panes among them, and nothing in its scripting says whether it's on. While a connection to
  its Python API is open (`ITerm2API`), keys go through that instead, into the session alone (`suppress_broadcast`), so
  the window rule is lifted. The API is turned on only in iTerm2's own Settings, as you would, for a press of yours
  (the button `wayPastIn:` names, which `takeWayPastIn:done:` answers, or its switch on the panel's back), where iTerm2 asks you first; never by writing its settings. A key
  it refuses stops the rest of the command, so none goes in half. Claude Desktop: only while idle (`WhyNotSendTo`) and
  only if its message box is empty; text goes in through the Accessibility API ("Prompt" text area, Submit button), not
  keystrokes. The one exception is a Return when Claude shows no Submit button, and only while Claude is in front
  (`submit:` in modules/claude-desktop/app/DesktopMessageBox.m). A new conversation's first message is sent with
  Claude's Send button, never a key, only in the conversation Whozmove has just opened with your words, once Claude
  shows its page, and only while its box holds exactly those words (`sendFirst:` in DesktopNewConversation.m) and Claude
  shows the folder the conversation is for. Claude loses a folder that comes in its link, so the folder is chosen as you
  would: its environment pressed among the recent ones Claude's page lists, once, which environment is which folder read
  from Claude's own record and never written (`chooseEnvironment:`), or on Claude's older screen its folder button
  pressed and the folder picked from its Recent ones, by path, the one time its list opens (`chooseFolder:`); never
  "Open folder…" or a new environment. Claude can let a press go by while it gets the folder ready, so Send is pressed
  again, a few times, until Claude's log says it's starting the conversation or its box empties (`pressSend:`); the
  words are never taken out of Claude's box. The one key that goes into a terminal session while Claude works is the
  Backspace that takes out the filler of a next step's request (`WhyNotEditDraft`): Claude Code puts the stashed draft
  back the moment a message is sent, and there a Backspace only edits it. Never while Claude asks something or a request
  waits. A step's words are fixed in the app (`StepRequest`); the page only names the step, and the branch a pull
  request goes into, which goes in its words only if it's the repo's default or one of its branches on GitHub as the app
  read them for Create PR's card. Words from a side chat for a session at work are never typed: they wait in the app,
  and its own words hook takes them as its current step ends (`sayBetweenSteps:` in parts/send, `BetweenSteps` in the
  Claude Code module), handed only to a process that session itself started (its hook, or a command it runs, never another session's), each once. Held words go in by
  themselves, once it's idle, only into a terminal that isn't the app in front at all and never the session you're on
  (`WordsGoByThemselves`); else they wait for your Send Now, and a press counts only for going in at once. Compact at
  Breaks (modules/compact-at-breaks), once you've turned it on in Settings, types `/compact` and its one fixed
  instruction by itself, never words from anywhere else, and only into a terminal session at a natural break
  (`compactTime`): idle at its prompt, its turn over for 2 minutes and less than an hour, nothing it runs in the
  background that can change files, not open in Claude Desktop too, Whozmove running for 5 minutes, and nobody on it:
  you haven't been on it in the last 5 minutes (looked at it or written to it, the row's `onItAt`), you haven't used the panel in
  the last few seconds, and either it's where held words would go in by themselves or you're away from the Mac (no key
  or mouse for 5 minutes, or the screen locked or asleep), when the session in front can be compacted too. That's
  asked again before each key, and before its filler's Backspace once the result comes, however late: if you've come
  to it, the rest is left for you. Its tab is looked for only once macOS has let Whozmove control its terminal, so
  nothing asks you with nobody's press.
- **Only your press lets a session do more by itself.** What a session may do (Don't Wait on Me, Let It Deploy) is a
  switch at the foot of its mode menu (`SessionSwitch`, kept by the core's `Allowed` in
  `AppDir/allowed/<session>.json`), turned on only by that menu's own items: no page message reaches them
  (tests/checks.sh holds to it). A switch that isn't shown for a session (Let It Deploy while Deploy is hidden) counts
  as off, so nothing you can't see or turn off goes on working. A switch that lasts only while Whozmove runs (May Move
  Its Ticket) is on only in the panel's memory, so nothing written anywhere turns it on; it ends with the session's
  process, or as Whozmove quits. One kept for a folder (May Send Back Plans, May Answer Questions, May Approve Plans) is
  kept in the panel's memory by the folder you ticked it in, and is on for whichever session there its module lets hold
  it, checked each time against what the system says of its process, not what files say; it ends with your untick, or
  once no session there has held it for 7 days, and a line under the header, kept until you close it, says each time a
  new session holds it. As one changes, the running copy also writes
  what is ticked to `AppDir/ticked.json` (only you able to read it; only the app's copy, never a print run in your
  home), so a restart that stops Whozmove as a Deploy does (SIGTERM), or a crash, leaves it. The copy that starts reads
  it into a list of switches that *wait*, never into the ones that are on, and only for a session whose process still
  runs, started when the file says, or, for one kept for a folder, a folder that's there, named by its whole real path,
  without who ticked it; a Quit takes the rest of the file away, and leaves those kept for a folder to be offered. A waiting switch is turned on only by your press on the
  mode menu's Turn Back On item, which names each switch in its title and checks again what ticking checks (the
  switch shown for the row now, the very process it was ticked in, or for one kept for a folder any session there,
  and the module's `whyNot`); a program that edits the file can at most make the menu offer a switch, for a session or
  folder it chooses, under that name. An untick always holds,
  even when the file can't be written (`Allowed`). A switch that lasts for the process ends with it (its pid and start time), counts
  only for asks from that very process (not the conversation resumed elsewhere), and one given for something (Let It
  Deploy's project and command) ends once that changes. A session asks through `AppDir/ask.sock` (`SessionAsks`, with
  `ask-panel.sh`, in every build), only you able to connect, and which session asks is found from the process that
  connects (macOS's `LOCAL_PEERPID`, walked up to a process its agent says is a listed session), never from what it
  sends. Only the agent's own program speaks for a session: for Claude Code, its build signed by Anthropic, checked from
  the copy of its signature macOS keeps while it runs, so a program that writes a session's record in Claude Code's
  registry is refused, and one Claude Code has updated since it started still counts; a session started from inside
  another session's commands is refused too. An ask that only shows you something comes only from the session's one
  copy of Claude Code: while the process seen as its own runs, only that one, and once that has ended, one working
  where that session was seen working, or inside it (`whyNot:speakFrom:`). Each refusal says why and what to do. Its
  module hears the ask only once that session's switch is on, but for an ask that only shows you something (a task to
  do, One Task's), which needs none: it gives the session no more power, and only you act on it. A deploy
  may be asked for only in the session's own checkout, the one its row is about, where the ask shows while it waits.
  It waits until no other session's agent is at work in that folder (not for the asking session's own turn to end: it
  asks once its change is ready), no run is going, and you've been off the panel 5 seconds (`PanelWindow`'s
  `inUseWithin:`), then is checked again and runs as a press does, only while the command is still the one the switch
  was given for. These are plain files in Whozmove's folder, as `deploy.json` is: any program running as you could
  change them, so they keep a session from doing more than you allowed it, not a program set on doing harm. And
  neither the socket's name nor the script's may name a deploy (CONTRIBUTING's rules).
- **Sorting and grouping** (`classify`, `stillOnIt`, `placeRows` and `movedAt` in whose-move.js; `heldNow`, `noteOnIt`
  and `state.placed` in panel.js; `noteSeen:` in parts/focus/app/Focus.m): what a session is (a request, working, a
  reply you haven't read, however old, one you have, or idle a day after the last message or the last time you were on
  it) is kept apart from where its row is shown. What it is shows on its dot; where it's shown is one view for everyone
  (`listGroups` in whose-move.js): a module's groups on top (`core.topGroups`, a team's chief, its groups and
  its team), then every project, A to Z, so they never move, each group's rows newest message first, as a chat app's: a
  reply, a request coming or your message takes its row to the top of its group, and a working row sorts by when its
  turn began, so its steps never move it and two working agents don't trade places with every step. Only the idle rows
  go below the rest (`quiet`), so a reply you haven't read never sits under one you were done with. Nothing is lifted
  for waiting on you: its bubble, its dot and the count beside the pawn say so. The page keeps when you were last on
  each session while it's yours, across launches (`noteOnIt`): you opened it here, wrote to it, or were on it for 2
  seconds in Claude, Ghostty or iTerm2 in front while at the Mac (the app's `seenAt`); another session writing to it
  isn't you. A reply from before then is read, and so is one a module says went to another session rather than to you
  (`core.repliesElsewhere`: any session's reply to a message another session sent it, known by that session or its
  address, never a name), but for a reply to you you hadn't read when that came, kept to read (`state.toRead`,
  `keepToRead`) until you have. A conversation a module says is wholly not yours (`core.notYoursToRead`: with a team
  file, one that has ended in a member's folder, or the lead's or the front's) has nothing to read meanwhile, kept or
  not, and what's kept stays for if it's resumed: the member's own row stands for it, and only a module's word makes a
  conversation so, never a default.
  Only a row you've pressed (`keepInPlace`) keeps the place it was last shown in, showing what it is now there, until
  you've moved on from the panel: the pointer off it and moved (`hoverEnd`), no box with the keyboard. These are
  deliberate: read the comments in whose-move.js before changing them.
