# Usage

How much of your Claude plan you've used, in the five-hour session and the week: the strip at the bottom of the panel,
asked of the agent every few minutes, its wait at the session limit, and its Sign in.

## Its pieces

- `app/UsageModule.m`: its face for the core (contracts/Module.h): a check when one is due, on every tick; Sign in; and
  Working on Whozmove's Preview the Wait.
- `app/Usage.m`: when to ask (every 3 minutes, soon after a window resets, often after Sign in, less often while asking
  fails, never while the screens sleep or the panel is hidden), what the page is told, and Sign in, run in the first
  terminal on this Mac that runs a command (Ghostty, else macOS's Terminal).
- `page/usage.js` (what the strip shows: plain functions), `page/strip.js` (drawing it, folding it into one row and
  back, the line on the collapsed header), `page/waits.js` (its wait styles, chosen by name) and `page/wait-vine.js`
  (the first, whose shape and reset are plain numbers too), and `page/usage.css`, the strip's style, with its reduced
  motion. `module.json` lists them for tools/page.sh.

tests/panel.sh checks what the strip shows and the vine's reset frame by frame; the Claude Code module's `--print-usage`
checks what's taken from Claude Code's answers.

## Between the page and the app

- The page sends `usageSignIn`.
- The app calls `setUsage({state, plan, session, week, limits, extraUsage, checkedAt})` and `previewWait()`.

## Rules

- Nothing about your account reaches the page: only what the strip needs.
