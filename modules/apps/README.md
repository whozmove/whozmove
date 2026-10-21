# Apps

The panel's back. The header's four squares turn the panel over, and behind the list are the apps Whozmove works
with, four across: Claude, Ghostty, iTerm2, Terminal, Spotify and Git, those on this Mac (Claude, Spotify and Git
always). Pressing one shows its page: what Whozmove does with it, its switches, its cards (how something Whozmove
needs there stands, with a button for it), what macOS lets Whozmove do with it (Accessibility or Automation, and
System Settings when it isn't allowed), and Open. The header has the list's buttons in the same places: rows, which turn the
panel back to the list, and the chevron, which turns it back and folds it into the cat.

## Its pieces

- `app/AppsModule.m`: its face for the core (contracts/Module.h): the back's page, held on the back of the glass
  (PanelWindow's `holdBack:`), told what's known each time the panel starts turning over, and again each second while
  it's turned, when what it shows has changed; every module's apps (Module's `appEntries`), each with the switches and
  cards other modules add to it, listed while the app is on this Mac; each app's own icon, taken from it; how each
  permission stands, asked of macOS without asking you (Automation off the main thread, every few seconds, and only
  while the app is open); the back's presses, each switch set, and each card's button pressed, by the module whose it
  is; and `--print-apps`, the print mode the tests check.
- `app/BackPage.m`: the back's web view, over the panel's page in the panel's window, as wide as the list and as tall
  as the panel, with a bridge of its own.
- `page/back.html`, the back's page: the panel's tokens, base styles and controls (`styles/controls.css`: its switches
  and buttons), `util` and `icons`, then `page/apps.js` (what an app's permission says, what its cards show, and the
  switches once one is pressed: plain functions) and `page/back.js` (drawing the apps and each one's page, going between them, the pointer
  and presses, and the functions the app calls), with `page/back.css`, its style. `module.json` lists them for
  tools/page.sh, which puts the page together beside the panel's.

Each app is its module's: Claude Desktop's lists Claude, on every Mac, as the page for Claude as a whole (with Track
Claude Desktop app sessions, or Get Claude Desktop without it), Ghostty's, iTerm2's, Terminal's and Spotify's list
their own, the git module lists Git (with Show Next Steps), Deploy and new conversations add their switches to Git's
and the terminals' pages, and the install module adds its cards: Apple's command line developer tools to Git's page,
and Whozmove's plugin, under Claude Code, to Claude's, where Claude Code's settings go. A card with nothing to say
now (its `now` gives nil) isn't sent.

`tests/test.sh` checks what every module lists (`--print-apps`) and what the back's page makes of it (`page-cases.js`,
with the back page's scripts).

## Between the page and the app

The back's page has a bridge of its own, in the same shape as the panel's page's, in the back's web view.

- The page sends `appsTurnBack` (rows), `appsFold` (the chevron), `appsSwitch` (`{app, key, on}`), `appsAction`
  (`{app, key}`: a card's button), `appsOpen` and `appsPrivacy` (`{app}`: Open, and Open System Settings).
- The app calls `setApps(apps, look)`, each app `{id, name, does, icon, open, switches: [{key, title, help, on,
  enabled, group}], statuses: [{key, title, section, said, note, ok, button, busy}], permission: {kind, use, state}}`
  (the icon a data: address, or null; a status one of its cards, `section` the heading over it or null, `said` how it
  stands in a word or two, with a tick while `ok`, `button` its button's title, if it has one now, waiting while
  `busy`; `state` one of `allowed`, `denied`, `ask`, `closed` or `unknown`), with the panel's look from its Look menu; `turned(false)` once the panel is
  back on its list side; and `backPointer({x, y})`, where the pointer is on the back while it's turned over, from its
  top-left corner, or `null` once it has gone.

## Rules

- Nothing here asks you anything: permissions are only looked at, never asked for (`AXIsProcessTrusted`, and
  `AutomationPermission` without asking), and System Settings opens only when you press it.
- A switch changes only through the module whose switch it is, so the same choice set elsewhere (the strip's lyrics
  question, New Conversation's menu) and here are always the same. A card's button, too, only asks its module, which
  does what the same button elsewhere does (the setup line's), and it waits from the press until the module says how
  it went.
- The back's page only ever shows itself: it loads nothing else, and only its own page's messages are answered.
- The back is the list's size: it's never laid out at another width, and scrolls when it's taller than the panel.
