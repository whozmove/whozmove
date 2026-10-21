# iTerm2

Sessions running in iTerm2: a row's press brings its session's window, tab and pane forward, the tab iTerm2 shows
marks the session you're on, the model, effort, mode and Compact menus and next steps type their commands into a session
alone in its window, and a new conversation started in iTerm2 from the card opens in a new tab, as the usage card's
Sign in does on a Mac without Ghostty.

## Its pieces

- `app/ITerm2.m`: its face for the core (contracts/Module.h) and the host it is (contracts/Host.h), one the panel types
  into (a TypingHost) and one that runs a command in a new tab (a CommandHost). It lists iTerm2 for the panel's back,
  with the Automation permission its tabs need (`appEntries`).
  - iTerm2 runs its sessions under a server of its own, which it starts and stays above while it runs. After a crash,
    an update or a quit that keeps them, the server lives on with them and iTerm2 takes them back as it starts. So a
    session is iTerm2's when iTerm2 or its server is up its process tree (`runsProcess:`), which the core asks when no
    ordinary app is: when only the server is, or when iTerm2 is kept out of the Dock.
  - iTerm2's scripting gives each session's tty, so a session is found by its own terminal device: the one iTerm2 gave
    it, which the session's first process holds, so a `claude` on a terminal of its own inside it (under `script`, say)
    is found by the session's. Its `claude` must be in its terminal's foreground, so one suspended in its shell isn't
    taken for the shell (`ProcessTerminal`, app/shared/Processes.h). Devices are compared as numbers: only a press
    names one by its path, as finding that looks through /dev.
  - What it's told goes in AppleScript (app/shared/AppleScript.h), on the main thread, and only while iTerm2 is
    running. Each question waits 2 seconds at most, and a press asks several. macOS's question whether Whozmove may
    control iTerm2 is asked before the first press's script, or the first new tab's, off the main thread, as it waits
    for your answer, where a script would give it only those 2 seconds; iTerm2 comes forward meanwhile, and the session
    or the new tab once you've allowed it.
  - A new tab goes in iTerm2's frontmost window that isn't a hotkey window, which may be hidden, else in a window of
    its own; iTerm2 is started first if it isn't running. Its command isn't typed into it, where Broadcast Input could
    copy it into the window's other sessions: the tab's own program is your shell (zsh or bash, as Whozmove runs
    commands), running a file of commands that runs the command in the folder and leaves your shell in the tab once it
    ends. bash takes the file as its startup file, after your login files, and is your shell afterwards, so Ctrl+Z
    pauses the command and `fg` brings it back, as in any tab. zsh, started as your terminal starts it, reads the file
    and then gives its place to a new zsh; only the zsh that started the command could bring it back from a pause, so
    it brings it back at once, and Ctrl+Z there only makes Claude Code draw itself again. iTerm2 reads a command it's
    given as text of its own first, where backslashes are escapes and `$$NAME$$` is asked of you, so it's given only
    plain words, the shell's path and the file's, and the file goes in your temporary folder, whose path is plain,
    unlike Whozmove's own folder's. Only you can read the file, and it removes itself as it runs. As every new tab
    does, the tab gets the text your default profile sends at start (Settings ▸ Profiles ▸ General, Send text at
    start), which here goes to Claude Code. iTerm2 says whether the tab opened, so a start that can't open one says
    why at once.
  - Keys go in with its `write text`, as typed (`newline no`, so iTerm2 adds no Return of its own), each key as the
    characters a terminal sends for it (so a control character in a /compact's focus, which would be pressed, goes in as
    a space), into the session held by iTerm2's own id for it (`tabFor:`), which it keeps for its life, where its
    terminal device can pass to a later one. iTerm2 sends a script's text through Broadcast Input, which can copy it
    into the other sessions in its window, hidden floating panes among them, and never beyond the window, and nothing in
    its scripting says whether it's on. So the panel types only into a session alone in its window: finding its tab says
    whether it is, and the menus say why not when it isn't (`whyNotTypeIn:`), and each script that types asks again
    right before it does, and types nothing if it isn't. A key refused there refuses the rest of what goes into that tab
    until it's looked for again, so a command never goes in half: no command after a refused stash would send your draft
    with it. A key pressed several times (Shift+Tab, for a mode) is checked once, then all its presses go in, 0.05s
    apart, as part of a count would land in another mode. Until macOS has let Whozmove control iTerm2, a menu asks it,
    off the main thread, and says so meanwhile.
  - A hotkey window is shown as its hotkey shows it. One that floats over every Space isn't among the windows iTerm2's
    scripting lists, so a press on one of its sessions only brings iTerm2 forward.
  - Which tab it shows is asked with Apple events of Whozmove's own (app/shared/AppleEvents.h), on a queue of its own,
    as it's asked every second while iTerm2 is in front.
- `app/ITerm2Facts.h`: what the module relies on about iTerm2 that iTerm2 could change: its app id, its server's
  name, what it makes of a command it's given (so which characters it takes as they are), the characters each key
  sends, and the codes in its scripting dictionary it's asked with. When iTerm2 changes, the fix goes here. The
  README's "Tested with" names the version they were last checked with.
- `tests/test.sh`: what a new tab for a new conversation and for Sign in would run, from folders whose names need
  quoting, and what iTerm2 would be told to open it with, or that it wouldn't be, when a path isn't plain
  (`--print-iterm2-tab`, `tabs.expected.txt`); and what iTerm2 would be told to find a session's tab, how its answers
  would be read, and what it would be told to type and press there, with text that needs quoting and has control
  characters in it, or that it wouldn't be, for a name a script can't take (`--print-iterm2-typing`,
  `typing.expected.txt`). Nothing is written or sent to iTerm2, so it needn't be on the Mac. tests/all.sh runs it.

It has no page part.

## Rules

- iTerm2 is never started by a question: its Apple events go to its running process and never ask you anything, and
  its scripts run only while it's running. Only a press on one of its sessions' rows starts it, when the sessions have
  outlived the app (Focus, in the core), or a new tab, and only those bring up macOS's question about controlling it.
- Nothing is typed into a new tab: its command is the tab's own program, and iTerm2 is given only plain words.
- Keys go only into a session alone in its window, where no copy Broadcast Input makes can reach another, checked by
  the script that types them, right before; and once one is refused, nothing more goes into that tab until it's looked
  for again.
- A new tab's file of commands is only yours to read, and goes as the tab runs it, once a tab can't open, or a minute
  after it was made when the panel next starts.
- A command a new tab runs is never left paused where nothing could bring it back.
- A tab is reported open only once iTerm2 has opened it, so a start is taken for the session you're on only then.
- A session that isn't in its terminal's foreground has no tab, so its shell's tab is never taken for it.
- Nothing is written to iTerm2's settings.
