# Ghostty

Sessions running in Ghostty, a terminal the panel types into: a row's press brings its session's tab forward, the
tab Ghostty shows marks the session you're on, the model, effort, mode and Compact menus type their commands into the
session's tab, and new conversations and the usage strip's Sign in open in a new tab.

## Its pieces

- `app/Ghostty.m`: its face for the core (contracts/Module.h) and the host it is (contracts/Host.h): a TypingHost (a
  session's tab found, text and keys typed into it) and a CommandHost (a command run in a new tab). Ghostty's scripting
  gives each terminal's folder and title but not its tty, so a session's tab is found by its folder, then by the title
  its agent gives it (the agent's `titleOf:now:`, which Claude Code puts in the tab's title), and keys go only into a
  tab that's certainly the session's. Of tabs that fit as well, as one conversation open in two tabs does, the one whose
  title shows its agent at work (`titleShowsWork:`) as the row's copy is, or not, goes first, so pressing the row opens
  the copy it follows. Claude Code marks only a tab at work, so two that aren't (one idle, one asking you something)
  look alike. Either of a conversation's tabs in front marks it as the one you're on, unless more tabs fit it than it's
  open in, when another session's tab could be the one. What it's told goes in AppleScript (app/shared/AppleScript.h),
  on the main thread; which tab it shows is asked with Apple events of Whozmove's own (app/shared/AppleEvents.h), on a
  queue of its own, as it's asked every second while Ghostty is in front. It lists Ghostty for the panel's back, with
  the Automation permission its tabs need (`appEntries`).
- `app/GhosttyFacts.h`: what the module relies on about Ghostty that Ghostty could change: its app id, and the codes
  in its scripting dictionary it's asked with. When Ghostty changes, the fix goes here. The README's "Tested with"
  names the version they were last checked with.

It has no page part, nor tests of its own: tests/rows.sh checks the keys a command is typed with (`--print-typing`),
through a stand-in terminal.

## Rules

- Keys go into a session's tab only while the session is safe to type into (the agent's whyNotTypeInto:, WhyNotTypeInto
  in the Claude Code module), and only into a tab that's certainly its own: a stray Return would approve a permission
  prompt, and Shift+Tab would allow all edits.
- Ghostty is never started by a question: its Apple events go to its running process, and never ask you anything.
