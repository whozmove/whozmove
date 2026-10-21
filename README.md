# Whozmove

A small Mac panel that floats above every window and tells you whose move it is: yours or your AI coding
agents'. It lists every Claude Code session running on this Mac, in Claude Desktop and in the terminal,
with what each is doing, so you can see at a glance which one needs you.

<p align="center"><img src="docs/screenshot.png" width="412"
  alt="The Whozmove panel: a session asking to run a command, one working, and one with a reply waiting for you"></p>

- one list, **newest first**, as a chat app's, or grouped by **project**, the projects A to Z so they never move,
  each with its conversations newest first and a ＋ that starts a new conversation there (⌥-click: in the terminal)
- a conversation goes to the top whenever a message comes: Claude's reply, a request or question, or yours, from the
  panel, Claude or a terminal. While Claude works, its row stays where your message put it; its steps never move it.
  A row you've just pressed stays where it is until your pointer has left the panel, then goes to the top. Once a
  conversation is idle (read, with nothing new for a day), it goes below the rest, so a reply you haven't read never
  sits under one you were done with
- its dot says whose move it is: a pulsing red-orange one for a request or question, amber for a reply you haven't
  read, which stays so until you've read it, an empty amber ring once you have, and grey while Claude works or once it
  has been quiet for a day. Opening a session here, being on it in Claude, Ghostty or iTerm2 for a couple of seconds
  after it replied (watching the reply come in counts), or writing to it counts as reading its reply; for a session in
  another terminal, only opening it here or writing to it does
- **the row you're on stays in view**: scroll the list past the session you're on, or let the list move its row out of
  sight (to the top as a message comes in, say), and the row holds on at the top of the list (or at its
  bottom, while it's further down), folding a line at a time until its name, Claude's line and where it runs are left,
  and the rest of the list goes under it. However quickly the list moves, the lines fold one after another, catching
  up within a moment. Back in view it opens out and glides into its place again; press it to scroll back to it.
  Switch to another session and its tint moves over to that one's row as it slides away. A row you're typing in, or
  one too tall to show whole, goes out of sight as any row does
- **more room for the list**: the header stays as you scroll the list down until the row you're on reaches it and has
  folded down there; scrolling on, that row pushes the header away, and it stays away, even part-way, until you've
  scrolled back to the top of the list. While it's gone, Whozmove peeks out beside the panel's top corner, on the side
  facing the middle of the screen: it looks up as your pointer comes near, blinks slowly when you rest on it, and flicks
  an ear when something new needs you. Press it and the panel folds round it right where it is; drag it to move the
  panel. Opened again, the panel grows round it, the header back
- **flick the panel away**: a quick sideways two-finger swipe on the panel pushes it off that side of the screen, and
  Whozmove peeks out from the screen's edge; press it (or **Show / Hide Panel**, or ⌃⌥N) and the panel slides back where
  it was. Up and down still scroll the list, and while you're typing in one of its boxes, a sideways swipe stays the
  box's
- **what needs you comes out beside the folded panel**: while the panel is folded, a request, a question, a plan or a
  reply you haven't read comes out beside it by itself, as its row from the list, so you can answer it there, or press
  it to open its session. Newest first, three at most, each for 45 seconds, the time it has left shrinking along its
  foot; pointing at one, typing in it or being in its session keeps them all out, and nothing new comes out meanwhile.
  The pin keeps one out, × sends it back, and under them it says how many more are waiting
- **rest the pointer on the folded panel** and it opens, headed with how many are waiting on you; move off and it folds
  back. Press it to keep it open. What's out beside it goes into its row as the panel opens, and back out as it folds
- **start a conversation** from the ＋ in the panel's header, or ⌃⌥N from any app: a card opens at the top of the
  panel, under the header; write what Claude should do and press ⌘Return (Return starts a new line). The card is
  shaped like the row it becomes.
  Chips under your words say where it starts: the project (that of the session you're on, at first) and, in a git
  repository, where in it; type **@** in your words, or press the project's chip, to choose another project (or any
  folder), and the line under the box says where it runs. The Start button shows the app it starts in, its icon and,
  once you've written something, its name, saying **Start in Claude** while you hold ⌘; the arrow beside it switches
  between Claude Desktop, Ghostty and iTerm2 (those on your Mac), and the next card starts with the one you chose last.
  Once started, the card turns into that row and moves down to its place in the list, where it says it's starting until
  Claude lists the conversation. A folder Claude hasn't worked in before is asked about on the
  card (**Trust and start**), so neither Claude Desktop nor Claude Code stops to ask again. In Claude Desktop your
  words go into the new conversation's message box, Whozmove chooses the folder's environment among the recent ones
  Claude lists (when Claude hasn't already) and presses Send once Claude shows it. This needs the Accessibility
  permission; without it, if the folder's environment isn't among Claude's recent ones, or if Claude doesn't take the
  press, your words wait there for you to choose it and send. If Claude starts it in another folder anyway, the row
  follows it there and says so. In Ghostty or iTerm2, a new tab runs `claude` with them.
  In a git repository, type **#** (or press the branch's chip) to choose where in it: its own folder, a worktree
  that's there, or a new worktree, a folder of its own, for a branch that's there or a new branch named from your
  words (**#name** names it, and **#name from release** starts it from that branch, else from the repo's main branch as
  this Mac has it, which it then follows). A new worktree is in the worktree colour, with the branch it starts from
  beside it; anything in a worktree starts in a terminal. Nothing ever switches the branch of a folder in use: a branch
  is only checked out in a new folder. When another agent is at work in the project's folder, or changes there aren't
  committed, the card says so, with **Use a new worktree**. A new worktree goes in a folder beside the repo, named after
  it (`~/code/shop-worktrees` for `~/code/shop`), never inside it, or in a folder you choose from the line under the box,
  kept for that repo. Close a card before it starts and the next one comes back as you left it: your words, where it
  starts and the app
- Claude Desktop conversations stay listed after Claude quits (those active in the last 3 days), and so do terminal
  sessions once they've ended (their tab closed, the terminal quit, the Mac restarted): grey, with what they last said.
  Click one and it carries on where it was, in a new tab of the terminal it ran in (else the one New Conversation
  starts in), in its folder, under the same conversation; if Claude Code doesn't carry it on there, the row says so.
  One you left with `/clear` stays gone
- the session **you're on** is marked, and scrolled into view as you switch: the conversation open in Claude, or
  the session in the Ghostty or iTerm2 tab you're looking at, whichever of those apps you were in last
- a conversation open in two places at once (resumed in a second tab while it still runs, or open in Claude Desktop
  and a terminal) is one row, which follows the copy that needs you: one asking you something, then one at work, and
  otherwise the one it followed already. Pressing it opens that copy (in Ghostty, a tab at work is told from one that
  isn't, but two that aren't look alike, so then it may be either), and either of its tabs in front marks it as the
  one you're on. An orange icon of two windows, after the time at its top right, says so (with how many times, past
  two), and pointed at, where else it's open: each copy knows only what was said in it since the second opened, so
  close one when you can. **Close the other copy** on that card closes
  those in other terminal tabs, once Claude isn't working in them. While another copy runs in a terminal, the panel
  types nothing into it; while one is open in Claude Desktop, only its mode can't be changed from the panel. Deploy
  and next steps wait while any copy is at work. A copy paused in its terminal (Ctrl+Z) is named too, but holds
  nothing up
- a session paused in its terminal (Ctrl+Z) gets nothing typed into it: its menus and next steps say to bring it back
  with `fg` first
- a row you press (to open it, answer it, or run a step or Deploy) stays where it is, showing what it does there,
  until you've moved on from the panel: your pointer off it (and moved, when the panel shrank under it or one of its
  menus closed there) and none of its boxes typed in. Then it goes to its place
- the last exchange, as a chat: your message, and below it Claude's line. While Claude works, its "Claude"
  label fades in and out in cream (a warm dark brown on a light panel) and the line says what it's doing, timed
  from your message like Claude's own progress row: the command's description ("Run the tests"), "Reading app.ts",
  "Editing styles.css", "Searching the web: …", "Calendar: list events", and so on. As in Claude, the latest step
  stays up while Claude thinks, and the reply takes its place at the end. Both lines stay from turn to turn, so
  your message, each step and the reply change the text in place, and Claude shows thinking the moment you send.
  New text writes in from the left once the old has erased from the right, and the next step keeps what it shares
  with the one before ("Reading …"), rewriting only the rest. A step shows once it starts running: a hook can't see
  it while Claude is still writing it. A working session's dot fades on and off
- a ring for how full each session's context is. Pointed at, it widens into a **Compact** button that says
  how full it is ("98% · Compact"), filled the same way, and where the session runs makes way for it. A
  click opens a card with how much is left before auto-compact ("427k left") and three ways to compact:
  Compact, Keep details and Keep essentials (the last two are `/compact` with instructions for what the
  summary keeps), or your own focus. It goes in like a model pick, while the session is idle. Claude's line
  says "Compacting the conversation" until it's done. Whenever a conversation compacts, by itself or asked
  for, the ring becomes a short arc going round, and once it's done it fills to the new size.
  When it's a good time to compact, the ring opens by itself and says "98% · Compact now", and why when you
  point at it. That happens only while the session sits idle, once its conversation is nearly full or long,
  or, once it's big, when its work has just been committed or you've been away from it for an hour
- each session's model, effort and permission mode: click one to change it while the session sits idle.
  Never while it's working or asking you something, since a key typed into a permission prompt would
  answer it.
  - In Ghostty or iTerm2, the panel types `/model …` or `/effort …` into the session's tab (a half-typed draft
    is stashed and comes back), or presses Shift+Tab for the mode. In iTerm2, with its Python API switched on
    (iTerm2's Settings ▸ General ▸ Magic ▸ Enable Python API), the keys go into that session alone, whatever
    else its window holds. With it off, the panel types only into a session alone in its window, with no other
    tabs or panes there: iTerm2's Broadcast Input can copy what's typed into the others, and no script can
    tell whether it's on, so for a session that shares its window the menu says so, and offers Turn On
    iTerm2's Python API…, which brings iTerm2 forward with its Settings turned to that box and ticks it;
    iTerm2 asks you to confirm. A switch on iTerm2's page on the panel's back does the same. Those commands
    also save your choice as the default for new sessions, so the panel puts your default back (only that
    setting, and only when the command says it saved it). The mode menu offers only the modes it can reach
    with a known number of presses. Auto isn't in every session's Shift+Tab cycle, so unless the session is in
    Auto now or your settings turn Auto off, the menu offers just the moves that are the same either way, and
    says to change the others in the terminal. When switching model would re-read a cached conversation,
    Claude Code's "Switch model?" is asked on its row in the panel instead (Claude Code 2.1.304 or later, in
    sessions started since Whozmove's hooks were put in place), saying how much the conversation holds: Switch
    goes on, Cancel keeps the model, and with no answer within a minute Claude asks in the terminal. While a
    pick goes in, its row says so ("Switching to Opus 5.5…"); if Claude Code asks anything else first (its
    "Change effort level?", which no hook can answer), the row says Claude is asking in the terminal, with
    Take me there, until it has your answer. The tab doesn't come forward by itself. Meanwhile the other menus,
    Compact and next steps say a change from the panel is still going in.
  - In Claude Desktop, the same slash command goes into the conversation's own message box and is sent with
    its Send button through the Accessibility API, so nothing is typed and no menus open. Return is pressed
    only if Claude shows no Send button, and only while Claude is in front. Claude switches to the
    conversation first if it isn't showing it. The mode menu offers only Plan, since `/plan` is the only
    slash command for a mode, and nothing is sent while you have a message half-written there. Claude's
    "Switch model?" (a model switch re-reads a cached conversation) is asked on its row in the panel
    instead, and your answer goes to Claude's box. This needs the Accessibility permission for Whozmove
- the **next steps** its checkout has to take, as git sees it, at the end of the row's work line, in git checkouts
  only: a commit icon while something isn't committed, **↑2** while the branch is ahead of its copy on GitHub, or a
  cloud for a branch never pushed. Pointed at, each says its step beside it (**Commit**, **Push**, **Publish**);
  pressed, it asks the session's agent in words ("Commit the staged changes."), the way a model pick goes in, only
  while that agent is idle and no other agent is working in that checkout (there, or editing files there; one waiting
  on you doesn't count). A commit takes only what's staged when something is, as git does. A press says, for a few
  seconds in the work line's place, that it's asking, or why it can't go in.
  While the session's agent works, or asks you something along the way, its row has no work line (no pull requests,
  numbers or steps); it comes back once the agent is done.
  While commits wait to go, everything else is committed and no pull request shows, the line's start says where the
  branch stands, in git's words: "Ahead of origin · 2 commits", or "Not published · 3 commits" for a branch never
  pushed; pressing it opens those commits in the changes view (below), on Outgoing.
  After a code review in a session there that reports what it found to Claude Code (as /code-review does), the line's
  start says how it went instead, changes not committed yet and all, on the branch it was run on: "Reviewed · 5 to
  fix", then "Reviewed · all fixed" or "Reviewed · 1 left" once the review reports what became of each, or "Reviewed
  · nothing to fix". With nothing left to fix, a green tick in a ring comes before it, until files there are edited
  again. With something left, a session editing files after it makes it "Changed since the review", until that's
  committed and new work starts. Pointed at, it says so in full, naming the session the review ran in when it isn't
  that row's; pressed with nothing left uncommitted, it opens the commits not on GitHub yet, as "Not published" does.
  It shows only while there's work to go.
  Once everything is pushed, a branch other than the repo's default with no pull request shows **No pull request**
  where its pull requests would be, with **Create PR**: pointed at, it says the branch it goes into, the repo's default
  to begin with; press that to pick another of the repo's branches on GitHub, then **Create PR** or **Create Draft
  PR**. It shows once GitHub has said the branch has none, so it needs `gh`
- **Deploy**, a round play button at the end of the bottom line, after the folder it puts in place, for any project
  Whozmove can work out a deploy command for (a Compose file, a pm2 file, a Makefile `install` target, a package's
  `deploy:local` script or its commands, a Rust or Go program, a Python package with scripts, Whozmove's own
  `./build.sh --now`). It puts that checkout's or folder's code in place on this Mac, so in a worktree it runs that
  worktree's code:
  - The first press shows the command it suggests, to change if you like, and asks you to confirm it twice. When
    you confirm, the card also shows what a package script or Makefile target in the command really runs, and says
    if that looks as if it could deploy to production (Whozmove never suggests one that does). The command is
    saved for that project (in Whozmove's folder, never in the project), and from then on the button is always
    there, for every checkout of the project, with a dot when an agent has edited files or built there since the
    last deploy (a turn that only commits, pushes or runs the tests doesn't count). Until then it's offered only
    after an agent changes something. Projects Whozmove can't work out a command for get no Deploy
  - A press runs the command at the top of the session's checkout (or in its folder, outside git), in your own
    shell as your terminal starts it (so with the PATH your `~/.zshrc` sets, and nothing else of the panel's), and
    never while that session's agent is working or asking you something, or another agent is working in that
    checkout: the button is dimmed then, and says which session it waits for. While it runs, the button shows a
    stop square in a slowly turning arc and the work line says what's running, in its place (a row without one gets
    a line for it); a press then offers **Stop Deploy**, which ends it and everything it started, and its log. A check
    shows once it's done; if it didn't go through, the line says why. Deploy is for commands that finish
  - A right-click (or Control-click) on it shows the command, and offers Change Deploy Command…, Forget Deploy
    Command (back to being offered only after new work) and the last run's log; with only a suggestion, Set Up
    Deploy… and Not This Time

  One session speaks for each checkout, and only its row has the checkout's numbers, next steps and Deploy: of the
  sessions running in that checkout, the one that edited files there last, whatever it has done since, so several
  chats in one checkout don't all show the same. Notes it wrote elsewhere don't count, and a row is always about the
  checkout its session runs in: one that edits files in another checkout doesn't take that checkout's steps or Deploy
  (which wait while its agent works there). When no session there has edited it, the session you used last there
  speaks for it, one still running first, so work left in a checkout keeps its steps. **Git**, on the panel's back,
  turns the next steps and Deploy, or just Deploy, off
- what isn't committed in the session's checkout, at the end of that line ("+245 −42"), on the row of the session
  that speaks for the checkout, counted as git counts it: every change since the last commit, staged or not, new files
  included. Once it's all committed, the numbers go. Pointing at them says how many files that is, and how many are
  staged and not (a file staged and then changed again counts in both, as `git status` lists it under both). Pressing
  them grows the panel beside the list, as for what a session wrote (below), with git status's own tabs: **Changes**
  (what isn't staged, then the files git doesn't track yet), **Staged**, and **Outgoing** (the commits not on GitHub
  yet, one by one, each with what it changed; "Ahead of origin/main by 2 commits", or "Not published" for a branch
  never pushed). Each file is marked as git marks it: M changed, A added, D deleted, R renamed, U not tracked yet.
  Each tab has its step, which asks the session's agent in words, as the row's next steps do: **Commit** (what's
  staged, or every change when nothing is, as git itself does; its ⌄ offers Commit and Push, and Commit and Open a
  Pull Request), **Push**, or **Publish** for a branch never pushed; Git's Show Next Steps, on the panel's back, turns
  them off. Files show one after another or one at a time, and lines inline or side by side, as you pick (kept for
  next time). The view keeps up while the agent works, and lines it has just written light up once. **Open in
  Editor** opens a file at its first changed line: the first time, it asks which editor (Visual Studio Code, Cursor,
  Zed, Xcode, Sublime Text or BBEdit, the ones on your Mac), and the pawn menu's **Open With ▸** changes it.
- a permission prompt waiting, which you can answer on the row, under Claude's line. A card shows exactly
  what the agent wants to do (the command, and whether it would run in the background or outside the
  sandbox; for an edit, the lines it takes out and puts in; the whole of a file being written; the URL and
  what's asked of it; any other tool's input field by field, as Claude's own prompt lists it), with **Deny**
  and **Allow once**, never "always allow". Each part shows up to 100,000 characters; past that the card
  says the content is too large to show in full, and Allow once still allows all of it. Claude's own prompt
  stays usable too, and whichever you answer first counts. Click the card and its keys are the panel's
  until you answer, press Esc or click elsewhere: Return allows once. Sub-agents' requests and sessions that
  aren't interactive (`claude -p`) are left to Claude's own prompt
- what a session wrote for you to read, on a tag on its row, quietly as its icon and how many (in the plan's colour
  while a plan waits for you): press it and the panel grows at once beside the list, which stays where it was, saying
  where what's shown is coming from (the session's transcript, or a file) until it's in, then fits it (up to the
  screen's edges; a long plan scrolls), with the
  session's **Plans**, **Prototypes** (`.html` pages it created) and **Notes** (`.md` files it created) beside it,
  newest first. Drag it by either header to move it, reader and all. Plans and notes read as formatted text; a prototype
  opens from its file once the panel has grown, as it would in a browser: the pictures, scripts and styles beside it,
  fonts from the web, its own links (one to a site or a page elsewhere on your Mac opens in your web browser), what it
  saves, light or dark as the panel is, and nothing in it can reach anything else. Click into it to point and type in it
  (the panel has the keyboard until you click the list again); **Open in Browser** opens it in your web browser, for
  what the panel doesn't do (its own windows, files, downloads, a link to any other file outside its folder), and the
  line above it says when it asked for one of those. It loads again, where you were, when the session changes it. A plan
  Claude is waiting on can be sent back with your notes (**Revise…**: Claude stays in plan mode and writes a new
  version) or stopped; approving it happens in the session, where **Take me there** brings you, as Claude Code takes a
  plan's approval only from its own prompt. ✕ (or the tag again) folds the panel back to the list, where the list is now
- Claude's questions (its question tool) answered on the row, one at a time like Claude's own box: pick an
  option (or several), type your own answer, or enter a number, then Skip, Next, Submit, or × to dismiss.
  Once you've clicked the card, the keys work on it too: 1 to 9, or ↓ and ↑, pick an option, and Return goes
  on to the next question or submits, rather than reaching Claude's own copy of the question in the terminal
- at the end of its bottom line, how the session's agent is set up at its start, and where it runs: the session's
  **branch**, in purple with a worktree icon when it runs in a worktree, or its folder outside git. Pointed at, it says
  its project, that it's a worktree of it and on which branch, its folder and the app it runs in. Short of room, a
  long name shortens first, to about a dozen letters, before the model and effort
- **open PRs** the session created or worked on, at the start of its work line, with a hover card (state, author,
  `+/−`, files)
- click a session to jump to it: Claude Desktop opens it (launching Claude if needed), Ghostty switches to its
  tab (and its split, in a tab with several), and iTerm2 to its window, tab and pane, its hotkey window too (but not
  one that floats over every Space, which iTerm2 doesn't let scripts reach). When iTerm2 has quit while its sessions
  live on, the click starts it, and the next one, once it has taken them back, goes to the session. The keyboard
  goes with it, even right after you've typed in the panel, so you can type there straight away
- your Claude plan's **usage**, on a card under the panel, as wide as it: the same numbers as Claude's own Usage
  page, for the session (five hours) and the week, each with how long until it resets ("2h 59m"; point at it for the
  clock time), coloured as Claude colours them for how close you are, and a note when you're on course to run out
  before the reset, which says the day when it isn't today. Press the card anywhere and it folds away behind the
  panel, a little narrower than it and coloured from the left as far as the session is used (the week, when the week
  is the one running low): only a thin line of it then shows, straight along the panel's bottom edge. Point at that
  line and the card slides out from under the panel, widening a little, with the numbers written on it,
  `Session 40% · 2h 59m left … Week 10%`; press it and it opens again: it grows to the panel's width, its colour
  shrinking into the session's bar as the numbers move to their places and the week's row comes in.
  While the session limit is reached, a vine grows in from the card's corner until it resets, then blooms, its
  leaves fly off, and its stem pulls taut into the session's bar, fills it green and drains as usage starts over.
  It needs the `claude` command signed in once: **Sign in**, on the card, opens a terminal tab running
  `claude auth login`. Signed in with an API key, there's no plan to show, and no card
- **Spotify**, from a round token tucked half under the panel's bottom corner, on the side facing the middle of the
  screen (it travels under the panel to the other corner as you drag the panel across). Bring the pointer near and it leans out
  to meet it; press **Play** and Spotify opens in the background if it's closed and plays what it last had. Paused
  a while, the token wears the song's cover with a ring for how far in it is, and resumes it. Without Spotify on this Mac it
  offers **Download**, Spotify's download page, and turns into Play by itself once Spotify is installed. Signed
  out, Spotify comes forward to sign in, and the music starts once you have. macOS asks once whether Whozmove may
  control Spotify, at the first Play or song
- **now playing**, at the bottom of the panel, while a song plays: the cover, the song and artist, how far in it is (a
  thin line along the top) and the time. Point at it for back, pause and next, and press the line to jump; press the
  strip to bring Spotify forward (once lyrics are on, to read them). A new song rolls in place; paused, it greys and
  offers Play, and after 15 minutes it folds into the token; with the panel folded to its header, the token stands in
  for the strip. **Spotify**, on the panel's back, has **Show the song** (off, the token and the strip go, and
  Whozmove leaves Spotify alone), **Lyrics**, **Its icon at the panel's corner** and **Open Spotify**. macOS's Allow
  stays in System Settings → Privacy & Security → Automation
- **lyrics**, once you say yes to the strip's question (or turn on **Lyrics** on Spotify's page): while a line is sung,
  it takes the place of the song's name in the strip, rolling in as the singer starts it, with the lyrics mark over the
  cover, and the name and the cover come back between verses. Press the strip to read the whole song beside the list,
  the line being sung lit as it plays; press a line to jump there. Pressed before a song's lyrics are here, the strip says "Loading lyrics…" or "Lyrics not
  available" for a moment instead, and they open if they come meanwhile. At their foot, **Show lyrics in the strip**,
  turned off, keeps the strip on the song's name, and **Open Spotify** brings Spotify forward. They come from LRCLIB
  (lrclib.net), a free library of lyrics that says when each line is sung: a song it doesn't have keeps its name in the
  strip, words without timings show beside the list only, and when LRCLIB is busy, Whozmove asks again, a little later
  each time. A song you've played before shows its lyrics at once, as they're kept on this Mac
- **the panel's back**: the four squares in the header turn the whole panel over, and behind the list are the apps
  Whozmove works with: Claude, Ghostty, iTerm2, Terminal, Spotify and Git (the terminals when they're on your Mac).
  Press one for its page: what Whozmove does with it, its switches (whether Claude Desktop's sessions are tracked, the
  terminal new conversations open in, Spotify's song, lyrics and icon, Git's next steps and Deploy), how what Whozmove
  needs there stands, with its button (Whozmove's plugin on Claude's, with **Add Back**, **Turn On**, **Try Again** or
  **Get Claude Code**, and **Get Claude Desktop** on a Mac without it; Apple's command line developer tools on Git's
  page, with **Install**), what macOS lets Whozmove do with it (Accessibility or Automation, with **Open System
  Settings** when it isn't allowed) and **Open**. Claude's page is for Claude as a whole, Claude Code and Claude
  Desktop alike: with **Track Claude Desktop app sessions** off, Claude Desktop's conversations leave the list, and
  new conversations start only in a terminal. The back is the panel's size, scrolling when there's more; its rows,
  where the four squares were, turn the panel back to the list, and its chevron folds it into the cat. An open reader
  folds back first, and ⌃⌥N turns the panel back to start a conversation
- a pawn in the menu bar with a count of sessions waiting on you; its menu switches the grouping, has **New
  Conversation** (⌃⌥N), and turns ⌃⌥N off for other apps (**Use ⌃⌥N in Any App**)
- **Look ▸** in that menu: the panel **Grey** (until you pick otherwise), **Black** (**White** on a light panel), or
  **Glass**, showing what's behind it, blurred; and **Match System**, **Light** or **Dark**. The panel, its cards, the
  usage card and Spotify's token all follow it. While Reduce Transparency is on in System Settings, Glass is grey and
  can't be picked
- for working on Whozmove itself, **Working on Whozmove ▸** in that menu, shown only while you hold ⌥ (Option) as
  you open it: **Show Build in Header** puts, under "Whozmove", which worktree (or branch) the running build came
  from and when it was built, with its folder and commit when you point at it; **Preview the Wait** plays the usage
  card's wait and its reset in 20 seconds, without a limit to wait for

### Colours

A label's colour says whose move it is:

| Colour | Meaning | Labels |
|---|---|---|
| red-orange | blocked or broken: fix it | a request or question waiting |
| amber | your move: a routine next step | a reply you haven't read |
| cream | work underway | "Claude", beside what it's doing |

## Install

Needs macOS 12 or later, with Safari up to date (its engine draws the panel), Xcode Command Line Tools (`clang`, and
the `python3` the hooks run on) and Claude Code.
Optional: `gh`, signed in, for PR status; Claude Desktop, Ghostty and iTerm2, for jumping to and controlling their
sessions (in iTerm2, any session once its Python API is on, else one alone in its window); the `claude` command,
signed in to a Claude plan, for your plan's usage (Claude Desktop's own copy will do). Sessions in other terminals
are listed too, but a click only brings their app forward (not the exact tab), they aren't marked as the one
you're on, and their model, effort and mode can't be changed from the panel.

Tested with Claude Code 2.1.304 (and 2.1.299, Claude Desktop's own copy), Claude Desktop 2.42304.0, Ghostty
1.3.1, iTerm2 3.7.6 and Spotify 1.3.5, with lyrics from LRCLIB's API, and macOS 26.2's installer for Apple's
command line developer tools. Whozmove reads files and labels these apps don't document, Claude Desktop's conversation files and log above
all, and asks Claude Code for your plan's usage a way it doesn't document either, so an update to one of them can
break part of the panel until Whozmove catches up. The fix goes in the module of the app that changed
(`modules/claude-code/app/ClaudeCodeFacts.h`, `modules/claude-desktop/app/ClaudeDesktopFacts.h`,
`modules/ghostty/app/GhosttyFacts.h`, `modules/iterm2/app/ITerm2Facts.h`, `modules/spotify/app/SpotifyFacts.h`, for
LRCLIB `modules/spotify/app/LRCLIBFacts.h`, and for macOS's installer of Apple's developer tools
`modules/install/app/ToolsFacts.h`).

```bash
git clone https://github.com/whozmove/whozmove
cd whozmove
./install.sh   # builds the app, adds Whozmove's hooks to Claude Code, and starts the app now and at every login
```

The hooks are how the panel learns your last prompt, Claude's last reply, requests for your OK and the tool
each agent is using. The app carries them, and each time it opens from an Applications folder it adds them to
Claude Code as a plugin, `whozmove`, or brings them up to date there, with Claude Code's own `claude plugin`
commands, so there's nothing to edit in `~/.claude/settings.json`. It finds `claude` as your terminal does, or uses
Claude Desktop's own copy. Once Claude Code is there, it waits for Apple's command line developer tools, which the
hooks run on, and if you take the hooks out of Claude Code, it leaves them out. Sessions pick up hooks when they
start, so they apply to sessions started (or restarted) after this.

When setting up needs something from you, a line under the header says what, with the button that does it:
**Install** for the developer tools (macOS installs them in its own window; the line stays until they're in, and
carries on by itself once they are), **Get Claude Code** when it isn't on this Mac, **Add Back** or **Turn On** when
Whozmove's plugin was taken out of Claude Code or turned off there, and **Try Again** when connecting failed; and
once it's connected, it says so with a tick for a few seconds, then folds away. Whozmove's plugin turned off or taken out of Claude Code while Whozmove runs shows there
within a few minutes. The line's × puts it away until things change, and Git's and Claude's pages on the
panel's back keep the same buttons.

macOS asks for two permissions the first time they're needed: **Accessibility** for Whozmove (to change settings,
compact, focus the message box and send a new conversation's first message in Claude Desktop), and **Automation** of
Ghostty and of iTerm2 (to switch to and type into their tabs, open new ones, and see which one you're looking at)
and of Spotify (to show its song's cover and control it, asked at the first Play or the first song it plays). Both
can be granted later in System Settings → Privacy & Security. Switching on iTerm2's Python API from the panel uses
Accessibility too, to tick its box in iTerm2's Settings, and asks for nothing more: Whozmove gets each connection's
one-time cookie from iTerm2 through that same Automation, and iTerm2 lists the connection in its Script Console.

After changing anything in `app/`, `modules/`, `panel/`, `icon/` or the hooks, run `./build.sh` again in your
terminal. It puts the app in place and restarts it, and the app brings its hooks up to date as it starts (a hook
change reaches sessions started after that). Run inside Claude Code, by an agent or by you with `!`, the hooks are
left as they are, since every session you start would run them; and once you've set up Deploy for Whozmove in the
panel, it only compiles while the panel runs with Deploy's button showing, and Deploy on the session's row puts it in
place when you press it. Running `./install.sh` again updates the hooks too. `./install.sh --uninstall` removes the
app, its login item and the plugin, and asks before deleting Whozmove's folder.

## How it works

| Shows | Comes from |
|---|---|
| Running sessions and status | `~/.claude/sessions/<pid>.json`, Claude Code's live session registry |
| Claude Desktop conversations, running or not | `~/Library/Application Support/Claude/claude-code-sessions/*/*/local_*.json` |
| Terminal sessions that have ended | `~/Library/Application Support/Whozmove/conversations/<id>.json`, which Whozmove writes while each runs (its folder, name, terminal, transcript and when it last moved; no prompts or replies), listed for 3 days while Claude Code still has its transcript; a click runs `claude --resume <id>` in a new tab there |
| Conversation open in Claude | `setFocusedSession` lines in Claude's `main.log` (instant), else the newest `lastFocusedAt` |
| Session in the Ghostty tab you're looking at | Ghostty's Apple events, once a second while it's in front: the terminals in its front window's selected tab (and the one with the keyboard, when the tab is split), matched to sessions by their folder and tab title, the way a click finds a session's tab. While that can't tell which session it is, the mark stays where it was |
| Session in the iTerm2 tab you're looking at | iTerm2's Apple events, once a second while it's in front: the terminal devices (ttys) of the sessions in its current window's current tab (and of the one with the keyboard, when the tab is split), matched to each session's own, the one iTerm2 gave it, while its `claude` is in its terminal's foreground, the way a click finds a session's tab. A session is iTerm2's when iTerm2, or the server it runs its sessions under (`iTermServer-…`, which keeps them running when iTerm2 quits or crashes), is up its process tree |
| Last prompt / reply / notice | `~/Library/Application Support/Whozmove/sessions/<id>.json`, written by the hook (the folder is yours only: 700) |
| Live line | the same file: the hook describes each tool call as it starts (a command's own description, the file, the query, …) |
| Read, unread, quiet | Unread: a reply (from the hook) you haven't read, however long ago: not opened here since, nor looked at since in Claude, Ghostty or iTerm2 (on it for 2 seconds or more with that app in front, while the screen is awake and unlocked and the keyboard or mouse was used in the last 5 minutes; and Claude's own `lastFocusedAt`), with nothing written to it since. Read: a reply you've read. Quiet: no reply yet, or one you've read with nothing since for a day, the transcript's newest message and the last time you were on it included |
| Order | newest first: your last message, Claude's last reply, when a request came, else the transcript's newest message; a working session by your message, not its steps; a compaction, the summary it leaves included, doesn't count; idle ones below the rest, newest first there too |
| Permission requests | `~/Library/Application Support/Whozmove/asks/<id>.json`, left by the permission hook while it waits; your answer goes back in `<id>.answer.json` |
| Branch and worktree | the session folder's `.git`, read directly (no `git` process) |
| Changing model, effort, mode | Ghostty's AppleScript (`input text`, `send key`, `perform action "text:\x13"` for Ctrl+S); iTerm2's Python API while it's on (`send_text` with `suppress_broadcast`, over its Unix socket in `~/Library/Application Support/iTerm2/private`, opened with a one-time cookie from its AppleScript `request cookie and key`), else its AppleScript (`write text … newline no`), each key as the characters it sends (Return, Backspace, Ctrl+S, and Esc `[Z` for Shift+Tab), into the session found by its own terminal device (tty), and through AppleScript only while it's alone in its window, which the same script checks right before typing; Claude Desktop's message box ("Prompt") and Submit button via the Accessibility API; the result from the transcript's `<local-command-stdout>` or Claude's conversation file |
| PRs | `pr-link` entries in the session transcript; open/merged state from `gh pr view` |
| The next steps | `git status` (which files are staged, partly staged or not, and how far the branch is ahead of its upstream), and per checkout its base branch (`origin/HEAD`'s, else `main` or `master`) and `git rev-list --count` from there; for Create PR's card, the branches on GitHub as this Mac last fetched them (`git for-each-ref refs/remotes/origin`); the PRs from `gh` |
| What isn't committed | per checkout, every 3 seconds at most while something there changes, `git diff` from the last commit, `git diff` alone (not staged), `git diff --cached` (staged) and new files; while there are commits not on GitHub yet, `git log` and `git show` for each; and the edits each session's transcript records (Edit, MultiEdit and Write, with the lines each put in and took out; what Claude Code recorded each shell command changed), with `bashEditDiffEnabled` in the machine's, the project's and your Claude Code settings, which each changed line is matched with |
| Deploy | each project's command, which you confirm in the panel, and each folder's last deploy, in `~/Library/Application Support/Whozmove/deploy.json`; each run's log, exit status and whether you stopped it in `deploys/`; suggestions from the project's own files; when an agent last edited files or built, from the hook (`editedAt`, `builtAt`) |
| The running build | `build.json`, which `build.sh` writes inside the app |
| Now playing | what Spotify tells the whole Mac each time the song or its state changes (`com.spotify.client.PlaybackStateChanged`); the cover and the controls through Apple events to Spotify, only while it's running; Spotify is opened only when you press its token's Play |
| Lyrics | once you've said yes, LRCLIB (`lrclib.net/api/get`, then `/api/search`), asked about each song once it has played a moment, one request at a time, with its name, artist, album and length, then without the album, with its name tidied of what Spotify adds to say which version it is, and by its name and artist (only that, for a song over an hour); asked again when LRCLIB is busy, never sooner than it says; what it finds is kept in `~/Library/Application Support/Whozmove/lyrics/`, for the last 1,000 songs (a song without timed lyrics for a week, then it's asked about again); and while a song's lines follow it, where it is, asked of Spotify every 5 seconds |
| Plan usage | Claude Code itself: every 3 minutes (and just after a reset) Whozmove runs `claude` for a second, with nothing of yours loaded and nothing saved (`--safe-mode --no-session-persistence`), and asks it what its own `/usage` shows (its `get_usage` request); Claude Code signs in and asks Anthropic. When it has no plan to report, `claude auth status` says whether it's signed in |
| New conversations | in Ghostty or iTerm2, a new tab running `claude --session-id <id>` (an id the panel chooses, so the conversation's row is known from the start), with your words read from a file in Whozmove's folder rather than typed (in iTerm2, the tab's own program, through `create tab with default profile command`, is your shell running a file of commands in your temporary folder, which removes itself as it runs, so nothing is typed into the tab for Broadcast Input to copy, and iTerm2 is given only plain words; with zsh, a Claude paused there with Ctrl+Z comes straight back, as only that shell could bring it back); in Claude Desktop, its `claude://code/new?q=…` link (without `folder=`, which Claude loses), then the environment its button beside Send names, the recent environments its page lists (which is which folder from its `ccd-session-presets.json`, only read) and its Send button via the Accessibility API (on its older screen, its folder button and its folder list's Recent folders, by path), and which conversation it started and where from the `LocalSessions.start:` and `Starting local session <id> in <folder>` lines in its `main.log`; whether Claude may work in the folder, from `projects[<folder>].hasTrustDialogAccepted` in Claude Code's `~/.claude.json` |

| File | Role |
|---|---|
| `app/` | the native app's core, one file per job (`core/`: the floating `NSPanel`, the menu bar item, the bridge to the page, the rows, the session you're on, and words typed into a session or sent to Claude Desktop), what modules fill in (`contracts/`) and the helpers that know no app (`shared/`) |
| `modules/` | one folder per module, each with its native code, its page files, its tests and a README: `claude-code/` (Claude Code's sessions, transcripts, details, requests, prompt and usage, and its hooks plugin, put into Claude Code and kept up to date there); the apps sessions run in, `claude-desktop/` (Claude Desktop's conversations, its message box and new conversations), `ghostty/` (sessions' tabs in Ghostty, and typing into them), `iterm2/` (sessions' tabs in iTerm2, and new ones) and `terminal-app/` (macOS's Terminal, for Sign in); and the features, `git/` (each row's checkout, its next steps and Create PR, and its PRs), `deploy/`, `changes/` (a checkout's numbers and the changes view), `reader/`, `usage/` (the usage card), `starts/` (new conversations and ⌃⌥N), `commands/` (the model, effort and mode menus and the Compact card), `spotify/` (the now-playing strip, its lyrics and Spotify's token) and `install/` (the app setting itself up as it opens: where it runs from, Apple's developer tools, and its hooks in Claude Code) |
| `tools/` | `compile.sh`, the one compile line (build.sh, the tests, CI), `page.sh`, which puts the page together with each module's page files, and `bundle.sh`, which makes the app bundle, with the hooks inside it, and signs it (build.sh) |
| `panel/` | the UI's core, rendered in a transparent `WKWebView`: `panel.html` (the markup), `styles/` (`tokens.css`: its colours, text sizes and corners, each named for its job), and `scripts/`, one job each (rows and their places for each feature's parts, animation, hover, presses and typing, the reader; `whose-move.js`: what each session is, where its row goes, and which session speaks for each checkout; `modules.js`: what the modules plug into the page with); each feature's scripts, and its own styles, are in its module |
| `modules/claude-code/plugin/hooks/whozmove-claude.py` | Claude Code hook that records per-session context |
| `modules/claude-code/plugin/hooks/whozmove-claude-permission.py` | Claude Code PermissionRequest hook: asks in the panel as well as in Claude; and its PreModelSwitch hook: asks "Switch model?" in the panel for a switch the panel made |
| `modules/claude-code/plugin/` (`hooks/hooks.json`, `.claude-plugin/`) | the Claude Code plugin that runs both hooks; the app adds it as it opens, from a copy in Whozmove's folder |
| `icon/make-icon.m` | draws `icon/AppIcon.icns` (re-run only to change the icon) |
| `build.sh`, `install.sh`, `app/login-item.plist` | build, and install (the plugin and the login item); they read the app's name and id from `app/Info.plist` |
| `app/swap-in.sh`, `modules/claude-code/plugin.sh` | what puts a build of Whozmove in place and restarts the app, which brings the hooks it carries up to date (every build carries a copy), and the plugin's copy with a version named after its hooks |
| `tests/` | `all.sh` runs every test: `rows.sh` checks the rows the app builds for a sample home folder, when keys may go into each session, its mode menus' Shift+Tab counts, the keys a command is typed with, what its menus say about why nothing can go in, how a command's result is read, what the usage card gets from Claude Code's recorded answers, what a new conversation's start runs and how folder trust is read and recorded, and that this README names the macOS permissions the app asks for and no file names one it doesn't, `panel.sh` the page's labels, colours and row HTML, `build.sh` when a build only compiles and when it goes straight in, against a throwaway home folder, `checks.sh` that the modules stay apart; each compares with its recorded `.expected.txt`, and each module's own tests run too (Claude Code's run both hooks against a throwaway home folder, and put its plugin into a stand-in Claude Code; the install module's check how the app sets itself up as it opens; the usage module's check what the usage card shows and the vine's reset frame by frame) |
| `CONTRIBUTING.md` | how it's built and how to work on it |
| `CHANGELOG.md` | what changed in each release |
| `SECURITY.md` | how to report a security problem, and what happens next |
| `CODE_OF_CONDUCT.md` | how everyone taking part treats each other, and how to report a problem (the Contributor Covenant) |
| `docs/README.md` | the map of the docs, and of every module's README |
| `docs/how-it-works/overview.md` | how the core, the contracts and the modules fit together, and one second of the panel |
| `docs/guides/adding-a-module.md` | adding a new agent, app or feature, step by step |
| `docs/reference/tokens.md` | the panel's colours, text sizes and corners by name, and the checks on them |
| `docs/reference/rows.md` | what the panel knows about each session, field by field, and where each comes from |
| `docs/screenshot.png` | the panel at the top of this page, drawn from sample sessions |

Debug log: `~/Library/Application Support/Whozmove/panel.log`.

## Privacy and security

- The panel's only network traffic is `gh` asking GitHub about your PRs (as you, through your signed-in `gh`)
  and the GitHub avatars on PR cards, and Claude Code's own `claude` command asking Anthropic for your plan's usage
  (as you, through its own sign-in: Whozmove never reads your login, and keeps only the numbers, in memory), and
  the cover of the song Spotify is playing, from Spotify's image server, at the address Spotify gives; and, once
  you've said yes to lyrics, LRCLIB (lrclib.net), told each song's name, artist, album and length to find its lyrics.
  Everything else stays on this Mac.
- What it keeps is in `~/Library/Application Support/Whozmove/`, which only you can read: each session's last
  message and Claude's last reply (their first 280 characters), what it's doing at the moment (a command, a file's
  name, a search) and how far each turn took the work, requests while they wait for your OK, the deploy command
  you've confirmed for each project, with each deploy's log, the words of a conversation you start in a terminal until
  it has started, the lyrics found for the last 1,000 songs you played, until you turn lyrics off, where the app runs
  from and when its hooks first went into Claude Code, and a small log,
  which can hold folder paths, repository and conversation names, and text typed into sessions. A new tab in iTerm2 runs from a file of commands in your own temporary folder, which
  only you can read and which removes itself as it runs.
- The hooks go into Claude Code through its own `claude plugin` commands, which record them in its settings
  (`~/.claude/settings.json`): Whozmove itself doesn't edit that file for them. They record nothing once Whozmove is
  gone, only while the app noted in its folder is there.
- Trusting a folder on the new conversation card records exactly that, the one key for that folder
  (`hasTrustDialogAccepted`), in Claude Code's `~/.claude.json`, where Claude Code and Claude Desktop both look, under
  the same lock Claude Code takes to write it. Nothing else in that file is changed, and only that key is ever read
  from it; it's never logged.
- The permission hook only ever allows once, never "always allow", and never approves a plan, and keys go into a terminal session only
  while it sits idle at its prompt, with no request waiting. The one exception is a single Backspace: when
  Whozmove sends a next step's request into a session, it first sets aside anything you'd typed there, with an "x"
  typed before it (else Claude Code would bring back an older draft), and once Claude Code has put your text back,
  that Backspace takes the "x" out, while Claude has already started on the request. Never while Claude asks
  something or a request waits.
- `build.sh` signs the app ad hoc, with its bundle id as its identity, so that a rebuild keeps the
  Accessibility permission. The catch: any other ad-hoc-signed app that claims the id `com.whozmove.app` would
  get that permission too. Signing with a certificate of your own closes that.
- To report a security problem, follow [SECURITY.md](SECURITY.md) rather than opening a public issue.

Whozmove is an independent project. It isn't made by, affiliated with or endorsed by Anthropic.

## Licence

Copyright (C) 2026 Satyaraj

Whozmove is free software under the [GNU General Public License](LICENSE), version 3 or (at your option)
any later version: you can use, study, change and share it, and anything you share that's built on it must
stay open under the same licence.

The pull-request and branch icons are GitHub's [Octicons](https://github.com/primer/octicons), under the MIT
licence (Copyright (c) 2026 GitHub Inc.); its full notice is beside them, in `panel/scripts/icons.js` and
`modules/git/page/prs.js`.

## Contact

hello@whozmove.com
