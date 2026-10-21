# Changelog

## 0.2.0 - 2026-10-21

### Installing and setting up

- **Install with Homebrew.** `brew install --cask whozmove/tap/whozmove` installs Whozmove on a Mac with Apple silicon
  and macOS 13 or later. It isn't signed by Apple yet, so the first time you open it, press Open Anyway in System
  Settings → Privacy & Security, once. `brew upgrade` brings each new version, and
  `brew uninstall --cask --zap whozmove` takes it out with its login item and its folder. Each release is built on
  GitHub from its version's tagged commit (`tools/release.sh`).
- **Whozmove says when a new version is out**, installed with Homebrew: the line under the header names it, with the
  command that updates it and **Copy Command**. It never runs `brew` itself, and its × keeps that version away until a
  newer one. Once Homebrew has put the new version in while Whozmove kept running, the line says so, with **Restart**.
- **Whozmove sets itself up as it opens**, from an Applications folder, where `./install.sh` used to do it: it adds its
  hooks to Claude Code as the `whozmove` plugin, or brings them up to date there, with Claude Code's own `claude plugin`
  commands, using the `claude` your terminal finds, else Claude Desktop's own copy. It never adds back hooks you took
  out of Claude Code, and the hooks now record nothing while Whozmove isn't installed: once it's gone, nothing more of
  your sessions is written down. `./install.sh` now builds the app and opens it.
- **Whozmove opens at login from its first open**, as a login item of its own, with **Open at Login** in the pawn menu
  to turn it off and on (and, turned off in System Settings' Login Items, a press there opens them). It restarts
  Whozmove only after a crash.
- **A line under the header says when setting up needs you**, with the button that does it: **Install** for Apple's
  command line developer tools, which your sessions are followed with, asked for only once Claude Code is there (the
  line stays until they're in, says so while macOS installs them, and carries on by itself once they are); **Get Claude
  Code** when it isn't on this Mac; **Add Back** or **Turn On** when Whozmove's plugin was taken out of Claude Code or
  turned off there; **Try Again** when connecting failed; and that it's connected, with a tick, for a few seconds once
  it is. Its × puts it away until things change, and the panel's back keeps the same buttons: Git's page for the
  developer tools, Claude's for the plugin.
- **Sessions already open when Whozmove connects to Claude Code catch up without a restart.** They show only part of
  what they do until they reload Whozmove's plugin: the line under the header offers **Reload Them**, and each of their
  rows says it's shown in part, with **Reload**. Whozmove types Claude Code's `/reload-plugins` into each idle one, one
  at a time, keeping a half-typed message in a terminal, and its conversation carries on as it was. One it can't type
  into says what to type there, with **Take me there** on the line.

### The list

- **One list, newest first, as a chat app keeps it**, in place of the Needs you, Working, Your turn and Idle sections. A
  conversation goes to the top whenever a message comes, Claude's reply or a request, and when you send one, from the
  panel, Claude or a terminal. While Claude works, its row stays where your message put it, and compacting doesn't move
  it at all. A row you've just pressed stays put until your pointer has left the panel, then goes to its place. Once a
  conversation is idle, a day after you read its reply, it goes below the rest. In the pawn menu, Group by Status is now
  **Newest First**, and Group by Activity is gone (a panel set to it shows the list newest first). Grouped by project,
  the projects go A to Z and stay put, each with its conversations newest first.
- **The dot says whose move it is**: a pulsing red-orange one for a request or question, and amber for a reply you
  haven't read, which now stays so until you've read it (opened it here, been on it in Claude, Ghostty or iTerm2 for a
  couple of seconds since it came, watching it come in counts, or written to it), rather than for 30 minutes; an empty
  ring once you have. While Claude works, its "Claude" label fades in and out in cream, no longer blue.
- **Rows no longer show a coloured label** for where an idle session's work stands ("Ready to commit", "In review",
  "Done" and the like), or what that work has been through ("built · tested", the audit). The work line (below) shows
  what's left to do instead.
- **The row of the session you're on stays in view**, whether you scroll the list past it or the list moves it out of
  sight (to the top as a message comes in, say): it holds on at the top of the list, or at its bottom while it's further
  down, folding a line at a time, the row next to it touching it all the way, until its name, Claude's line and where it
  runs are left. The rest of the list goes under it as under the header. Back in view it opens out and glides into its
  place, and pressing it scrolls back to it. Switch to another session and its tint moves over to that one's row as it
  slides away. A row you're typing in, or one too tall to show whole, goes out of sight as any row does.
- **Terminal sessions stay listed once they've ended**, as Claude Desktop's conversations do: close a session's tab,
  quit the terminal or restart the Mac, and its row stays, grey, with its last message and reply, for 3 days after its
  conversation last moved. Click it and it carries on in a new tab of the terminal it ran in (Ghostty, iTerm2 or
  Terminal; else the one new conversations start in), in its folder, as the same conversation, and the row turns back
  into the running one. Until then its menus say "It isn't running: press its row to open it again", and its row keeps
  its checkout's changes and next steps. If Claude Code doesn't carry it on in the new tab within half a minute, the row
  says so, and nothing tries again until you click. One you left with `/clear`, or whose transcript Claude Code has
  cleared away, isn't listed.
- **A conversation open in two places at once** (resumed in a second tab while it still runs, or open in Claude Desktop
  and a terminal) is one row instead of two, following the copy that needs you: one asking you something, then one at
  work, and otherwise the one it followed already, which pressing the row opens. An orange icon of two windows after its
  time says so, and pointed at, where else it's open, as each copy knows only what was said in it since the second
  opened, with **Close the other copy** for those in other terminal tabs. The panel types nothing into it while another
  copy runs in a terminal, and doesn't change its mode while one is open in Claude Desktop. Deploy and next steps wait
  while any copy is at work.
- Nothing is typed into a session paused in its terminal (Ctrl+Z), where the keys would go to the shell: its menus and
  next steps say to bring it back with `fg` first.
- A Claude Desktop conversation's row says when it last moved by the later of Claude Desktop's own time and the hooks'.

### The panel

- **More room for the list.** The header stays as you scroll the list down until the row you're on reaches it and has
  folded down there; scrolling on, that row pushes the header away, point for point, and it stays away, even part-way,
  until you've scrolled back to the top of the list. While it's gone, Whozmove peeks out beside the panel's top corner,
  on the side facing the middle of the screen: it looks up as your pointer comes near, blinks slowly when you rest on
  it, and flicks an ear when something new needs you. Press it and the panel folds round it, right where it is; drag it
  to move the panel. The panel opens round it again, with the header back.
- **Flick the panel away.** A quick sideways two-finger swipe on the panel pushes it off that side of the screen, fading
  as it goes, and Whozmove peeks out from the screen's edge; press it, or Show / Hide Panel, or ⌃⌥N, and the panel
  slides back where it was. Up and down still scroll the list.
- **What needs you comes out beside the folded panel.** While the panel is folded, a request, a question, a plan or a
  reply you haven't read comes out beside it by itself, as its own row from the list, so you can answer it there or
  press it to open its session. Newest first, three at most, each for 45 seconds, its time running out along its foot;
  pointing at one, typing in it or being in its session keeps them all out, and nothing new comes out meanwhile. Pin one
  to keep it out, or × to send it back; under them it says how many more are waiting.
- **Rest the pointer on the folded panel and it opens**, headed with how many are waiting on you; move off and it folds
  back, or press it to keep it open. As it opens, what's out beside it goes into its row, and back out as it folds.
- **The panel turns over to the apps Whozmove works with.** The four squares in the header turn the whole panel over,
  about its middle. Behind the list are Claude, Ghostty, iTerm2, Terminal, Spotify and Git, each with its own icon (the
  terminals when they're on your Mac); press one for what Whozmove does with it, its switches, how what Whozmove needs
  there stands, what macOS lets Whozmove do with it (with Open System Settings when it isn't allowed), and Open. The
  terminal new conversations open in, Spotify's song, lyrics and icon, and Git's next steps and Deploy are switched
  there. Claude's page is for Claude as a whole: with **Track Claude Desktop app sessions** off, Claude Desktop's
  conversations leave the list and new conversations start only in a terminal, and on a Mac without Claude Desktop,
  **Get Claude Desktop** opens its download page. Rows, where the four squares were, turn the panel back; its chevron
  folds the panel away. With reduced motion, one side fades into the other.
- **Light mode**: the panel, its cards, the usage card and Spotify's token follow the Mac's Light or Dark appearance, or
  the one picked in the pawn menu's new **Look ▸**, with colours of their own for each: on a light panel, the status
  colours are deeper so their words read, and a card's main button is dark. **Look ▸** also picks the panel's own
  colour: **Grey**, now how it starts, **Black** (white on a light panel), or **Glass**, the see-through panel it was,
  showing what's behind it, blurred. While Reduce Transparency is on in System Settings, Glass is grey.
- The header and the list keep to 640pt, and what opens with them (a new conversation's card, the now-playing strip)
  comes on top: the panel grows to fit it, as far down as the screen goes, and only there does the list give way and
  scroll. When a row comes or goes, the panel's bottom edge eases with the rows instead of jumping to its new height.
- **Your message and Claude's line are written in.** New text writes in from the left once the old has erased from the
  right, and Claude's next step keeps what it shares with the one before ("Reading …"), rewriting only the rest. A reply
  on two lines writes one line, then the next; Claude's time stays just past its text as it goes. With reduced motion,
  the lines change at once.
- Once you've typed in the panel (Compact's words, a plan's notes, a new conversation) or clicked into a prototype in
  the reader, the keyboard goes back to the app you were in as you leave, and pressing a terminal session's row leaves
  it in the terminal, so you can type there straight away.

### Answering and steering sessions

- **Start a conversation** from the panel: the ＋ in its header, a project's ＋, or ⌃⌥N from any app (New Conversation in
  the pawn menu, which can also turn the shortcut off) opens a card at the top of the panel. Write what Claude should do
  and press ⌘Return: the card turns into the conversation's row and moves down to its place in the list, saying it's
  starting until Claude lists it. Chips under your words say where it starts: **@** in your words (or the project's
  chip) chooses the project, and **#** where in it, its own folder, a worktree that's there, or a new worktree, for a
  branch that's there or a new one (**#name from release** starts it from that branch), in a folder beside the repo
  (`shop-worktrees` for `shop`) or one you choose. Anything in a worktree starts in a terminal, and nothing switches the
  branch of a folder in use. Start names the app, Claude Desktop (where it's on this Mac), Ghostty or iTerm2, with an
  arrow to switch it. A card closed before it starts comes back as you left it. A folder Claude hasn't worked in before
  is asked about on the card, once, for both apps.
- **Click a request or a question on a row and the keys work on it**: 1 to 9, or ↓ and ↑, pick an option, Return goes
  on, submits or allows once, and Esc leaves it, answering nothing. Its edge shows it has the keyboard, which goes back
  to the app you were in once you answer, so Return no longer reaches the app in front, where it could answer Claude's
  own copy of the question with a different option.
- A permission request's card always offers **Allow once**, where a request too long to show in full could only be
  denied before. Each part now shows up to 100,000 characters; past that the card says the content is too large to show
  in full, and Allow once still allows all of it. Any tool without a card of its own (a connector's, like a widget or a
  Slack message) is listed field by field, as in Claude's own prompt, instead of raw JSON.
- **Plans in the panel.** While Claude waits on a plan, its row asks for your OK, with **Read plan** and **Take me
  there**: the plan can be sent back with your notes (**Revise…**) or stopped, and approving it happens in the session.
- **"Switch model?" on the row.** Claude Code's question, for a model picked in the panel (switching re-reads a cached
  conversation), is asked on its row, as Claude Desktop's now is too (no longer over the list), saying how much the
  conversation holds, and only when Claude Code would ask it: Switch goes on, Cancel keeps the model, and with no answer
  within a minute Claude asks in the terminal. It takes Claude Code 2.1.304 or later. A pick going into a terminal
  session shows on its row at once ("Switching to Opus 5.5…"), and anything else Claude Code asks in the terminal before
  it goes in (its "Change effort level?") shows there too, with Take me there, until it has your answer, instead of the
  tab jumping forward.
- **Compact now.** When it's a good time to compact a session, its context ring opens by itself and says so ("98% ·
  Compact now"), and why when you point at it: while it sits idle, once its conversation is nearly full or long, or,
  once it's big, when its work has just been committed or you've been away from it for an hour. Pointed at, the ring's
  Compact button says how full the context is too ("98% · Compact").
- **Compacting, shown on the ring.** While a conversation compacts, whether by itself or asked for, its context ring
  becomes a short arc going round, and Claude's line says "Compacting the conversation" with how long it has taken. When
  it's done, the arc fades and the ring fills to the new size.

### Work in a checkout

- **A work line** under a row's last message and reply, while there's work in flight: its pull requests at the start,
  and at the end what isn't committed and the **next steps** its checkout has to take, as git sees it, each an icon: a
  commit icon while something isn't committed, **↑2** while the branch is ahead of its copy on GitHub, a cloud for a
  branch never pushed. Pointed at, each says its step beside it (**Commit**, **Push**, **Publish**); pressed, it asks
  the session's agent in words, only while it's idle and no other agent is working in that checkout (meanwhile the steps
  are dimmed, and a press says what they wait for). A commit takes only what's staged when something is, as git does.
  While commits wait to go, the line's start says where the branch stands ("Ahead of origin · 2 commits", or "Not
  published · 3 commits"), and pressed, opens those commits. After a code review that reports what it found to Claude
  Code, it says how the review went: "Reviewed · 5 to fix", then "Reviewed · all fixed" with a green tick, or "Changed
  since the review" when files are edited after it with something still to fix. Once everything is pushed, a branch with
  no pull request shows **No pull request** and **Create PR**, into the repo's default branch or another you pick, or
  **Create Draft PR**. One row per checkout has its numbers, steps and Deploy: of the sessions running in it, the one
  that edited files there last, else the one you used last there. Git, on the panel's back, turns the next steps and
  Deploy, or just Deploy, off.
- **What isn't committed** in a checkout ("+26 −13"), at the end of the work line, counted as git counts it: every
  change since the last commit, staged or not, new files included. Pointing at the numbers says how many files that is;
  pressing them grows the panel beside the list with git status's own tabs: **Changes**, **Staged** and **Outgoing**
  (the commits not on GitHub yet), each file marked as git marks it, with the tab's step: **Commit** (and, under its ⌄,
  Commit and Push, and Commit and Open a Pull Request), **Push** or **Publish**. Files one after another or one at a
  time, lines inline or side by side. The view keeps up while the agent works. **Open in Editor** opens a file at its
  first change, in the editor you pick the first time; the pawn menu's **Open With ▸** changes it.
- **Deploy**, a round play button at the end of the bottom line, for any project Whozmove can work out a deploy command
  for: it puts that checkout's code in place on this Mac. The first press suggests the command and you confirm it twice,
  seeing what a package script or Makefile target in it really runs, with a warning if that looks as if it could deploy
  to production (never suggested); from then on the button is always there for that project, with a dot when an agent
  edited files or built since the last deploy. It runs in your own shell as your terminal starts it, never while the
  agent is working or asking, or another is working there, shows a stop square in a turning arc while it runs (a press
  then offers **Stop Deploy** and its log) and a check when it's done; if it didn't go through, the work line says why.
  A right-click changes or forgets the command.
- **A bottom line** like an editor's status bar: how the session's agent is set up (its model, effort, mode and context
  ring) at its start, and at its end where it runs, its branch (in purple with a worktree icon in a worktree) or its
  folder outside git, then Deploy. Pointed at, the branch says its project, its folder and the app it runs in. Short of
  room, a long name shortens first, before the model and effort. Rows no longer show the app's icon.
- **What a session wrote**, on a tag on its row: press it and the panel grows beside the list with the session's
  **Plans**, **Prototypes** (`.html` pages it created) and **Notes** (`.md` files it created), newest first. Plans and
  notes read as formatted text; a prototype runs as it would in a browser, without reaching anything else, with **Open
  in Browser**. Drag the panel by either header to move it, reader and all.

### Terminals

- **iTerm2**: a click on a session's row brings forward its window, its tab and its pane, and the session in the iTerm2
  tab you're looking at is marked as the one you're on. With iTerm2's Python API switched on (Settings ▸ General ▸
  Magic), every session takes the model, effort and mode menus, Compact and next steps, the keys going into that session
  alone; with it off, only a session alone in its window does, as iTerm2's Broadcast Input could copy the keys into the
  others, and for one that shares its window, they say so and offer Turn On iTerm2's Python API…, which opens iTerm2's
  Settings at that box and ticks it, for iTerm2 to ask you. When iTerm2 has gone while its sessions live on (after a
  crash), the click starts it. A conversation started in iTerm2 opens in a new tab of its front window.
- **Ghostty**: a click on a session's row switches Ghostty to its tab before bringing Ghostty forward, so it lands on
  that session every time, and the session in the Ghostty tab you're looking at is marked as the one you're on, as
  Claude Desktop's open conversation is.

### Usage and Spotify

- **Your Claude plan's usage** on a card under the panel, asked of Claude Code itself every 3 minutes: the session and
  the week, how long until each resets (pointing at one shows the clock time), in Claude's own colours, with a note when
  you're on course to run out. A press folds the card away behind the panel, where only a thin line shows along the
  panel's bottom edge, coloured as far as the session is used; pointed at, the card slides out with the numbers on it,
  and pressed, it opens again. At the session limit a vine grows from the card's corner until the reset, then pulls taut
  into the session's bar and drains as usage starts over. Not signed in, **Sign in** opens a tab running
  `claude auth login`.
- **Spotify**, from a round token tucked half under the panel's bottom corner, on the side facing the middle of the
  screen; dragged across the screen, the panel takes it under itself to the other corner. **Play** opens Spotify in the
  background if it's closed and plays what it last had; paused, the token wears the song's cover and resumes it. Without
  Spotify it offers **Download**, and turns into Play by itself once Spotify is installed.
- **Now playing**, at the bottom of the panel, while a song plays: its cover, song, artist and time, with a thin line
  for how far in it is. Pointing at it shows back, pause and next, the line jumps where it's pressed, and pressing the
  strip brings Spotify forward (once lyrics are on, it opens them); paused, it greys and offers Play, and after 15
  minutes folds into the token. Spotify's page on the panel's back has **Show the song** (off, the token and the strip
  go, and Whozmove leaves Spotify alone), **Lyrics**, **Its icon at the panel's corner** and **Open Spotify**.
- **Lyrics** for Spotify's song, from LRCLIB, once you say yes to the strip's question: while a line is sung it takes
  the place of the song's name in the strip, and the name comes back between verses. Pressing the strip opens the whole
  song beside the list, the line being sung lit as it plays; pressing a line jumps the song there. **Show lyrics in the
  strip**, at their foot, turned off keeps the strip on the song's name. Nothing is looked up before you say yes; when
  LRCLIB is busy, Whozmove asks again, a little later each time; and the lyrics found are kept on this Mac, so a song
  played again shows them at once, until you turn lyrics off.

### Working on Whozmove

- **Working on Whozmove ▸** in the pawn menu, shown while ⌥ is held: **Show Build in Header** says which checkout the
  running build came from and when, and **Preview the Wait** plays the usage card's wait without a limit to wait for.

### Fixes

- The panel no longer flashes lighter at its bottom edge as it grows, and moving the pointer over something no longer
  restarts its hover effect with every move.
- The panel lets go of what each git read opens as soon as it's done, so with many checkouts it can't run out of files
  it may open, which would make a checkout look as if it had no changes for a few seconds.

## 0.1.0 - 2026-10-11

The first release: a floating Mac panel that lists every Claude Code session on this Mac, in Claude Desktop and in
the terminal, with whose move it is in each. It answers permission requests and Claude's questions, changes a
session's model, effort and mode, compacts it, and jumps to it. The README has the details.
