# Focus

The session you're on, marked in the list: the conversation Claude Desktop shows, or the session in the tab a
terminal shows, whichever of those apps you were in last; when you last looked at each; and opening a session from its
row, which makes it the one you're on, an ended terminal session too, opened again in a new tab.

## What it owns

- `app/Focus.h`, `app/Focus.m`: `Focus`, made once by the core (`Core`'s `focus`). Following which app comes to the
  front (`start`), marking the session you're on among the rows once they're whole (`mark:`), opening a session from
  its row (`open:`), with the first message a module has for one opened again (`ReopenWords`: in a terminal, as
  the resumed conversation's first message, read from a file in Whozmove's folder only you can read, taken away once
  the tab has read it; in Claude Desktop, sent as you'd send it, by that press), and naming which terminal an ended
  session opens again in (`nameReopens:`), the session in the
  terminal's tab in front (`terminalSessionInFront`, `tabCameForward:session:`), whether an app's window is on top
  (`FrontWindowOnTop`, a plain function, checked by tests/rows.sh), whether you're at the Mac (`AtTheMac`), and
  handing the keyboard to the app a session runs in once it's in front (`keyboardTo:tries:`).
- `part.json`: who it talks to, and what it provides.

## Who it talks to

It talks to the core: the row a session has (`Row`, contracts), the window (`PanelWindow`), the hosts (contracts'
`Host.h`) and the shared helpers; to the list, for the rows (`Rows`, parts/list); to the bridge, for the page (`Page`,
parts/bridge); and to the keyboard, which it has give the keyboard back as a session opens (`releaseKeyboard`,
`keptKeyboard`, the keyboard part's methods in PanelWindow.h); to send (`Send`, parts/send), for a module's words into a
Claude Desktop conversation opened from its row; and, through the contracts' `ReopenWords` (Module.h), to whichever
module has words for a conversation opened again. The app's start-up, the core, the rows, `Talking`, the
print runs (main.m) and the starts, bring-forward, commands, compact-at-breaks, attention, claude-code, sessions,
storage and waits modules import its header.

## Rules

- **The panel never keeps the keyboard from the app it opens a session in:** it gives the keyboard back as it opens
  one, and bringing a terminal's tab forward gives that terminal the keyboard once it's in front, checked to have it,
  the log saying who had it when it hasn't ([the panel's own rules](../../docs/how-it-works/panel-rules.md)).
- **A session's tab is the one the terminal says it is,** and a terminal's answer about a tab before the one it has just
  brought forward isn't taken.
