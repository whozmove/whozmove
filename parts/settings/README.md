# Settings

The panel's own settings, which Settings on the panel's back shows before the modules' (the apps module lists them
all): the look, grey, black or glass, and light, dark or as the Mac is; the list's order, with the ways to group
it the modules add; and whether rows show the conversation (Show Conversation Text).

## What it owns

- `app/Settings.h`, `app/Settings.m`: `Settings`, made once at start-up and kept by the core (`Core`'s `settings`):
  the look put on the panel and the app (`start`, following macOS's Reduce Transparency), the order last chosen told to
  a freshly loaded page (`applySavedGrouping`), whether rows show the conversation, told to the page as it loads and
  as it's switched (`applySavedConversation`, the bridge's `setConversationShown`), the modules' groupings
  (`addGrouping:…`), and its rows in Settings (`entries`).
- `part.json`: who it talks to, and what it provides.

## Who it talks to

It talks to the core, the bridge and the glass: the window (`PanelWindow`), for the look; the page (`Page`,
parts/bridge); the setting rows' shape (contracts' `Module.h`); `Appearance` and `Links`. The app's start-up, the core,
and the apps and team modules import its header. It calls the glass's (parts/glass) `look`, from PanelWindow.h's own
interface, and tells the page whether rows show the conversation through the bridge's `setConversationShown`.

## Rules

- **Each choice keeps what you picked across launches** (`panelLook`, `appearance`, `groupBy`,
  `showConversationText`). The first three shipped under these names, so they keep them: a rename would lose what
  someone picked.
- Glass shows as grey while Reduce Transparency is on, and comes back when it's off.
