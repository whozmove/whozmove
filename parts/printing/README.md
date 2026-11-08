# Printing

What the print runs the tests check have in common (main.m's and the modules' own): the rows read once, the way the
panel reads them, and settled; and JSON written so a test can compare it with a recorded copy.

## What it owns

- `app/Printing.h`, `app/Printing.m`: `PrintJSON`, `ReadRows` and `SettledRows`. Plain functions.
- `part.json`: who it talks to, and what it provides.

## Who it talks to

It talks to the core (`Core`, `Files`), the list (`Rows`, parts/list) and the bridge (`Modules`, parts/bridge). main.m
and the modules whose print modes read the rows or print JSON import its header. [Print
runs](../../docs/reference/print-modes.md) lists them.

## Rules

- **A print run depends on neither the network nor the Mac:** the rows come from the home folder in `$HOME`, which the
  tests make a throwaway one, and nothing asks the network.
- **It waits at most 10 seconds** for what's worked out alongside the rows, so a test never hangs.
