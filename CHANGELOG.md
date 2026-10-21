# Changelog

## Unreleased

- **The panel turns over to the apps Whozmove works with.** The four squares in the header turn the whole panel over,
  about its middle, with its back already there as it comes round, at the panel's size. Behind the list are Claude,
  Ghostty, iTerm2, Terminal, Spotify and Git, those on your Mac, each with its own icon; press one for what Whozmove
  does with it, its switches, what macOS lets Whozmove do with it (with Open System Settings when it isn't allowed),
  and Open. The terminal new conversations open in, Spotify's song, lyrics and icon, and Git's next steps and Deploy
  are switched there now: Spotify ▸ and Next Steps ▸ have left the pawn menu. Rows, where the four squares were, turn
  the panel back; its chevron folds it into the cat. With reduced motion, one side fades into the other.
- **Terminal sessions stay listed once they've ended**, as Claude Desktop's conversations do: close a session's tab,
  quit the terminal or restart the Mac, and its row stays, grey, with its last message and reply, for 3 days after its
  conversation last moved. Click it and it carries on in a new tab of the terminal it ran in (Ghostty, iTerm2 or
  Terminal; else the one New Conversation starts in), in its folder, as the same conversation, and the row turns back
  into the running one. Until then its menus say "It isn't running: press its row to open it again", and, like a
  closed Claude Desktop conversation's, its row keeps its checkout's island and its share of the changes. Clicked
  while it's still closing, it says it's opening and opens once it has closed. If Claude Code doesn't carry it on in
  the new tab within half a minute, the row says so, and nothing tries again until you click. One you left with
  `/clear`, or whose transcript Claude Code has cleared away, isn't listed.
- **The row of the session you're on stays in view**, whether you scroll the list past it or the list moves it out of
  sight (down to Working as it starts on your message): it holds on at the top of the list, or at its bottom while it's
  further down, folding a line at a time, the row next to it touching it all the way, until its name, Claude's line and
  where it runs are left. The rest of the list goes under it as under the header. Back in view it opens out into its
  place, and pressing it scrolls back to it. Switch to another session and its tint moves over to that one's row as
  it slides away. A row you're typing in, or one too tall to show whole, goes out of sight as any row does.
- **Your turn** now comes first in the list: the sessions waiting on you, a request or question (a pulsing red-orange
  dot) and a reply you haven't read (amber), first come, first served, so one that comes in joins the end and nothing
  above it moves. A reply waits there until you've read it: opened it here, been on it in Claude, Ghostty or iTerm2 for
  a couple of seconds since it came (watching it come in counts), or written to it. One you've read gets an empty dot
  and stays there while you're on its session, and for 10 minutes after you were last on it; then its row goes to
  **Seen**, below **Working**, and to **Idle** an hour after the last message or the last time you were on it; before,
  a reply went to Idle after 30 minutes, or as soon as you'd read it. A row you press, to answer it, say, stays where
  it is until your pointer has left the panel. The header's line counts what the sections show. **Group by Activity**
  is gone: a panel set to it groups by status.
- Each row's details line ends in what its session changed that isn't committed yet ("+26 −13"), like Claude
  Desktop's own bar, even with other sessions or you working in the same checkout: each changed line goes to whoever
  wrote it, a session's shell commands included, as Claude Code records what they change in auto mode. Pointing at
  the numbers shows how they sit among everything not committed in the checkout; pressing them grows the panel beside
  the list with the session's files and its own changes, or all sessions', as git shows them, and "No changes to
  commit" once there are none. A session that ran a shell command unrecorded shows all sessions' numbers instead, as
  what it changed isn't known. Files one after another or one at a time, lines inline or side by side, kept as you
  pick them. The view keeps up while the agent works. **Open in Editor** opens a file at its first change, in the
  editor you pick the first time; the pawn menu's **Open With ▸** changes it.
- **What a session wrote**, on a tag on its row (**Plan +2**): press it and the panel grows beside the list, which
  stays where it was, with the session's **Plans**, **Prototypes** (`.html` pages it created) and **Notes** (`.md`
  files it created), newest first. Plans and notes read as formatted text; a prototype runs as it would in a browser,
  without reaching anything else. While Claude waits on a plan, its row asks for your OK, with **Read plan** and
  **Take me there**: the plan can be sent back with your notes or stopped, and approving it happens in the session.
  Drag the panel by either header to move it, reader and all.
- **Start a conversation** from the panel: the ＋ in its header, a project's ＋, or ⌃⌥N from any app (New
  Conversation in the pawn menu, which can also turn the shortcut off) opens a card at the top of the panel. Write what
  Claude should do and press ⌘Return: the card turns into the conversation's row and moves down to its place in the
  list, saying it's starting until Claude lists it. Chips under your words say where it starts: **@** in your words (or
  the project's chip) chooses the project, and **#** where in it, its own folder, a worktree that's there, or a new
  worktree, for a branch that's there or a new one (**#name from release** starts it from that branch), in a folder
  beside the repo (`shop-worktrees` for `shop`) or one you choose. Anything in a worktree starts in a terminal, and
  nothing switches the branch of a folder in use. Start names the app, Claude Desktop, Ghostty or iTerm2, with an
  arrow to switch it. A card closed before it starts comes back as you left it. A folder Claude hasn't worked in
  before is asked about on the card, once, for both apps.
- Under each row's details line, while there's work in flight, is the **island**: a glass capsule with a stage for
  each place the work can be, the files changed, commits not on GitHub yet and GitHub, each with its count, the one
  where your next move is brighter. The files stage is a gauge, filled as far as its files are staged; pointing at it
  opens it into **staged**, **partly** (staged, then changed again) and **unstaged**, and pointing at a part lists its
  files in a list that grows out of the pointer and follows it. Pointing at the commits stage shows its menu as a
  card, and a click on it opens what those commits changed, beside the list. A click on another stage opens its menu,
  with what it holds and its steps (Commit, Push, Create PR, Open PR), which ask the session's agent in words, only
  while it's idle and no other agent is working in that checkout (its menus still open meanwhile, saying which
  session the steps wait for). The island stays on one row per checkout for as long as there's work left there: of the
  sessions running in that checkout, the one that edited files there last, or, if none did, the one you used last
  there. A row is always about the checkout its session runs in: editing files in another checkout doesn't bring that
  checkout's island or Deploy to it. The pawn menu's **Next Steps ▸** turns the island and Deploy, or just Deploy, off.
- An **extra stage** on the island for a repo whose own git config names a command for one (`whozmove.stage`): a
  tool that keeps changes on their way to a commit, such as a review queue, shows its count there, with its own list
  and steps in the stage's menu. While it holds something, the files stage counts only the files outside it, and its
  gauge splits and lists just those when the tool names them. Whozmove asks once before it runs the command, and
  again whenever it changes. See [docs/reference/stages.md](docs/reference/stages.md).
- **Deploy**, a round play button on the same row, for any project Whozmove can work out a deploy command for: it
  puts that checkout's code in place on this Mac, so in a worktree it runs that worktree's code. The first press
  suggests the command and you confirm it twice, seeing what a package script or Makefile target in it really runs,
  with a warning if that looks as if it could deploy to production (never suggested); from then on the button is
  always there for that project, with a dot when an agent edited files or built since the last deploy (until then
  it's offered only after new work). It runs in your own shell as your terminal starts it, with nothing else of the
  panel's, never while the agent is working or asking, or another is working there (it's dimmed then), shows a stop
  square in a turning arc while it runs (a press then offers **Stop Deploy**, which ends it and all it started, and
  its log) and a check when it's done; if it didn't go through, the line under the row says why. A right-click changes
  or forgets the command.
  Whozmove's own is `./build.sh --now`: once it's set up, an agent's `./build.sh` only compiles, and Deploy puts the
  build in place.
- Rows no longer show a coloured label for where an idle session's work stands ("Ready to commit", "In review", "Done"
  and the like), or what that work has been through ("built · tested", the audit) at the end of the details line.
- **Working on Whozmove ▸** in the pawn menu, shown while ⌥ is held: **Show Build in Header** says which worktree
  the running build came from and when.
- `./build.sh` puts the hooks in place too, once they're installed as the plugin, and running `./install.sh` again
  now updates them: before, Claude Code kept its first copy of the plugin, so a changed hook never reached sessions.
  A build run inside Claude Code (an agent's, or yours with `!`) leaves the hooks as they are.
- A build restarts Whozmove only if it's running from the app the build replaced, and only once the copy running
  has quit (made to, if it doesn't when asked), the copy you opened yourself after quitting it included; the panel
  fades in when it starts.
- A permission request's card always offers **Allow once**. It used to show each part of a request only up to
  4,000 characters and offer just Deny past that, so most widgets and some long commands and file writes had to be
  allowed in Claude. Each part now shows up to 100,000 characters; past that the card says the content is too large
  to show in full, and Allow once still allows all of it.
- Any tool without a card of its own (a connector's, like a widget or a Slack message) is listed field by field, as
  in Claude's own prompt: each field under its name, the shortest first, code and messages with their line breaks,
  instead of raw JSON.
- Your Claude plan's **usage** on a card under the panel, asked of Claude Code itself every 3 minutes: the session and
  the week, how long until each resets (pointing at one shows the clock time), in Claude's own colours, with a note
  when you're on course to run out. A press folds the card away behind the panel, a little narrower than it, of
  which only a thin line then shows along the panel's bottom edge, coloured as far as the session is used; pointed
  at, the card slides out with the numbers on it, widening a little, and pressed, it opens again, growing to the
  panel's width as its colour shrinks into the session's bar and the rows come in. At the session limit a vine grows from the card's corner until the reset, then pulls taut into the session's bar and
  drains as usage starts over (Working on Whozmove ▸ **Preview the Wait** plays it). Not signed in, **Sign in** opens a
  tab running `claude auth login`. The page is now rounded with the panel's corners.
- **Spotify**, from a round token tucked half under the panel's bottom corner, on the side facing the middle of the
  screen; dragged across the screen, the panel takes it under itself to the other corner. It leans out toward the pointer
  as it comes near. **Play** opens Spotify in the background if it's closed and plays what it last had; paused, the
  token wears the song's cover and resumes it. Without Spotify it offers **Download** and turns into Play by itself
  once Spotify is installed, so it's two presses from nothing to music.
- **Now playing**, at the bottom of the panel, while a song plays: its cover, song, artist and time, with a thin line
  for how far in it is. Pointing at it shows back, pause and next, the line jumps where it's pressed, and pressing the
  strip brings Spotify forward (once lyrics are on, it opens them); paused, it greys and offers Play, and after 15
  minutes folds into the token. The pawn menu's **Spotify ▸** has **Open Spotify**, **Show Lyrics**, **Hide Side Icon**
  and **Remove Spotify** (the token and the strip go, and Whozmove leaves Spotify alone), then **Add Spotify**. With the
  panel folded to its header, the token stands in for the strip.
- **Lyrics** for Spotify's song, from LRCLIB, once you say yes to the strip's question: while a line is sung it takes
  the place of the song's name in the strip, rolling in as the singer starts it, and the name comes back between verses.
  Pressing the strip opens the whole song beside the list, the line being sung lit as it plays; pressing a line jumps
  the song there; pressed before a song's lyrics are here, the strip says "Loading lyrics…" or "Lyrics not available"
  for a moment. **Show lyrics in the strip**, at their foot, turned off keeps the strip on the song's name, and **Show
  Lyrics** in the pawn menu's Spotify ▸ turns them on or off. Nothing is looked up before you say yes; when LRCLIB is
  busy, Whozmove asks again, a little later each time; and the lyrics found are kept on this Mac, so a song played again
  shows them at once, until you turn lyrics off.
- **Light mode**: the panel, its cards, the usage card and Spotify's token follow the Mac's Light or Dark appearance,
  or the one picked in the pawn menu's new **Look ▸**, with colours of their own for each: on a light panel, the stages'
  colours are deeper so their words read, and a card's main button is dark. **Look ▸** also picks the panel's own
  colour: **Grey**, now how it starts, **Black** (white on a light panel), or **Glass**, the see-through panel it was,
  showing what's behind it, blurred. While Reduce Transparency is on in System Settings, Glass is grey.
- The header and the list keep to 640pt, and what opens with them (a new conversation's card, the now-playing strip)
  comes on top: the panel grows to fit it, as far down as the screen goes, and only there does the list give way and
  scroll.
- A click on a terminal session's row switches Ghostty to its tab before bringing Ghostty forward, so it lands on that
  session every time, and the session in the Ghostty tab you're looking at is marked as the one you're on, as Claude
  Desktop's open conversation is.
- A conversation open in two places at once (resumed in a second tab while it still runs, or open in Claude Desktop
  and a terminal) is one row instead of two, following the copy that needs you: one asking you something, then one at
  work, and otherwise the one it followed already, which pressing the row opens; either of its Ghostty tabs in front
  marks it as the one you're on. Its details line says **open twice**, and pointed at, where else it's open, as each
  copy knows only what was said in it since the second opened, with **Close the other copy** for those in other
  terminal tabs. The panel types nothing into it while another copy runs in a terminal, and doesn't change its mode
  while one is open in Claude Desktop. Deploy and next steps wait while any copy is at work.
- Nothing is typed into a session paused in its terminal (Ctrl+Z), where the keys would go to the shell.
- **iTerm2**: a click on a session's row brings forward its window, its tab and its pane, found by the session's own
  terminal, and the session in the iTerm2 tab you're looking at is marked as the one you're on. When iTerm2 has gone
  while its sessions live on (after a crash), the click starts it. A conversation started in iTerm2 opens in a new tab
  of its front window, and the usage card's Sign in goes there too on a Mac without Ghostty.
- When a row comes or goes, the panel's bottom edge eases with the rows instead of jumping to its new height, and the
  panel no longer flashes lighter at its bottom edge as it grows. Moving the pointer over something no longer restarts
  its hover effect with every move.
- A Claude Desktop conversation's row says when it last moved by the later of Claude Desktop's own time and the
  hooks'.
- The panel lets go of what each git read opens as soon as it's done, so with many checkouts it can't run out of files
  it may open, which would make a checkout look as if it had no changes for a few seconds.

## 0.1.0 - 2026-10-11

The first release: a floating Mac panel that lists every Claude Code session on this Mac, in Claude Desktop and in
the terminal, with whose move it is in each. It answers permission requests and Claude's questions, changes a
session's model, effort and mode, compacts it, and jumps to it. The README has the details.
