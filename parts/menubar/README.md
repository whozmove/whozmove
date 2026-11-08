# Menu bar

The pawn in the menu bar, its count, and its menu: the panel, Working on Whozmove, and the modules' items (Settings…
among them), each in its section; and the panel's switches: Show Next Steps and Show Deploy, which Git's page on the
panel's back sets, and Show Build in Header, the menu's own item under Working on Whozmove.

## What it owns

- `app/MenuBar.h`, `app/MenuBar.m`: `MenuBar`, made once at start-up and kept by the core (`Core`'s `menuBar`): the
  pawn and its count, its menu and the modules' items in it (`addEntries:`), and the switches, saved and told to a
  freshly loaded page (`applySavedSwitches`).
- `part.json`: who it talks to, and what it provides.

## Who it talks to

The core (the window, `PanelWindow`; the modules' items, contracts' `Module.h`), the folded panel's part, for the pawn's
mark (`CatShape`, parts/cat), the bridge, for the page (`Page`, parts/bridge), and the builds part, for the header's
tooltip on the running build while Show Build in Header is on. The app's start-up, the core, and the deploy and git
modules import its header. It calls the glass's (parts/glass) `followLook:`, `headerTip`, `look`, from PanelWindow.h's
own interface.

## Rules

- **The menu keeps what has to work while the panel is hidden, folded or lost off the screen.** A choice you make once
  and come back to now and then is a row in Settings, not an item here.
- **Preference keys keep their names:** build.sh reads `showNextSteps` and `showDeploy`.
