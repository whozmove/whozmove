# Terminal

macOS's Terminal, as a host that only runs a command: Sign in for your plan's usage, on a Mac without Ghostty or
iTerm2. A session running in it opens by bringing Terminal forward, as any other app's does; the panel never types
into it.

## Its pieces

- `app/TerminalApp.m`: its face for the core (contracts/Module.h), and the host it is (contracts/Host.h): a CommandHost.
  A command runs as a file of commands (`.command`) that Terminal opens in a new window, named for what it runs, kept in
  Whozmove's own folder (`terminal`), which only you may read. It lists Terminal for the panel's back (`appEntries`).

## Rules

- No Apple Events are sent to Terminal, so no permission is asked for.
