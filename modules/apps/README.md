# Apps

The panel's back. The header's four squares turn the panel over, and behind the list are your apps, four across, with
Settings first, as a phone's home screen has them; Settings… in the pawn menu turns it over straight to Settings.
Settings is as a phone's: cards of rows, each with its coloured tile, its name and what it's set to. A choice's row
opens its page (Appearance, each look a small panel, then light or dark; Session List; Open Files With, the editors with
their icons), and a switch's row has its switch (⌃⌥N in any app). The apps beside Settings are those Whozmove works
with: Claude, Ghostty, iTerm2, Terminal, Spotify and Git, those on this Mac (Claude, Spotify and Git always), and
under them Whozmove's own **Tools** (Storage). Pressing one shows its page: what Whozmove does with it, its switches,
its groups (each a heading over a card of its switches, choices of one among a few, each a name over what it does with
a tick on the one picked, and parts of the day, each end's time pressed for a menu of the day's half hours, with a line
under the card; dimmed while its module says they can't be pressed), Use the Recommended Settings while what's there
isn't, its cards (how something Whozmove needs there stands, with a button for it), what macOS lets Whozmove do with it
(Accessibility or Automation, and System Settings when it isn't allowed), and Open. A tool's page leads with its card,
what it does, and says what macOS has to allow only once the tool needs it, in its card. A row in Settings can open an
app's page too, saying how it's set there, and ‹ there goes back to Settings. ‹ goes back a page, and on
the apps, turns the panel back to the list, its left edge sinking in. The header has the list's buttons in the same
places: rows, which turn the panel back to the list the other way round, its right edge sinking in, and the chevron,
which turns it back and folds the panel away.

## Its pieces

- `app/AppsModule.m`: its face for the core (contracts/Module.h): the back's page, held on the back of the glass
  (PanelWindow's `holdBack:`), told what's known each time the panel starts turning over, and again each second while
  it's turned, when what it shows has changed; Settings' rows, the panel's own (parts/settings: the look and the list's
  order) and every module's (Module's `settingEntries`), by their card and their order on it, a choice that's an app
  with its icon, and a row opening an app's page while that app is listed; every module's apps (Module's `appEntries`),
  each with the switches, groups, cards and lists other modules add to it, the groups in their order, listed while the
  app is on this Mac; each app's own icon, taken from it; how each permission stands, asked of macOS without asking you
  (Automation off the main thread, every few seconds, and only while the app is open); the back's presses, each setting
  set by the one whose setting it is, each switch, choice and part of the day set, each page put back as recommended,
  and each card's button pressed, by the module whose it is, and only while it can be pressed, and each press on a
  list's page handed to its list (AppList's `press`); each part of the day's menu of times, the Mac's own, each written
  as the Mac writes a time; Settings… in the pawn menu, which brings the panel up (opening it first if it's folded),
  puts the back on Settings and turns it over, or takes the back to Settings if it's turned already; and `--print-apps`,
  `--print-settings` and `--print-app-page` (a made-up tool's page with groups, and what each press makes of it), the
  print modes the tests check.
- `app/BackPage.m`: the back's web view, over the panel's page in the panel's window, as wide as the list and as tall
  as the panel, with a bridge of its own.
- `page/back.html`, the back's page: the panel's tokens, base styles and controls (`styles/controls.css`: its switches,
  buttons and tags), `util` and `icons`, then `page/apps.js` (Settings' cards and pages, and the settings once one is
  pressed; what an app's permission says, what its cards show, its groups, the switches and choices once one is pressed,
  and a tool's card: plain functions; and a list's page: what's ticked of it, Tick All's marked ones, its question's
  words and how long what a press did stays said) and `page/back.js` (drawing the apps, the tools, Settings, each
  choice's page and each app's, a choice's rows alike on both, and each of an app's lists', with the list's tray under
  it standing still as it scrolls, going between them, the pointer and presses, and the functions the app calls), with
  `page/back.css`, its style. `module.json` lists them for tools/page.sh, which puts the page together beside the
  panel's.

Each setting is the panel's own or its module's: parts/settings has Appearance and Session List, the changes module
Open Files With, and new conversations ⌃⌥N's switch. Each app is its module's: Claude Desktop's lists Claude, on every
Mac, as the page for Claude as a whole (with Track Claude Desktop app sessions, or Get Claude Desktop without it),
Ghostty's, iTerm2's, Terminal's and Spotify's list their own, the git module lists Git (with Show Next Steps), Deploy
and new conversations add their switches to Git's and the terminals' pages, and the install module adds its cards:
Apple's command line developer tools to Git's page, and Whozmove's plugin, under Claude Code, to Claude's, where Claude
Code's settings go; the notifications module adds Quiet hours, a group of its own, to One Task's page. A card with
nothing to say now (its `now` gives nil) isn't sent. Each tool is its module's too: the storage module lists Storage,
with its card and its tile's hint. Each list is its module's: the sessions module
adds Sessions to every terminal's page and Claude's.

`tests/test.sh` checks what every module lists (`--print-apps`, `--print-settings`), a made-up tool's groups and
presses (`--print-app-page`), and what the back's page makes of it all (`page-cases.js`, with the back page's scripts).

## Between the page and the app

The back's page has a bridge of its own, in the same shape as the panel's page's, in the back's web view.

- The page sends `appsTurnBack` (`{side}`: `right` for rows, `left` for ‹ on the apps, the edge that sinks in as it
  turns), `appsFold` (the chevron), `appsSetting` (`{key, value}`: a setting's switch on or off, or the id of the choice
  picked), `appsSettingButton` (`{key}`: the button under a setting's line, as Open Display Settings under Glass while
  Reduce Transparency is on), `appsSwitch` (`{app, key, on}`: one of an app's own switches or one in its groups),
  `appsChoice` (`{app, key, value}`: the id of one of a choice's choices, picked), `appsTime` (`{app, key, end, x, y}`:
  a part of the day's `from` or `to` time pressed, where its top-left corner is on the back, from the page's, for the
  app to open that end's menu of times over it), `appsUseRecommended` (`{app}`: Use the Recommended Settings, at the
  foot of its page), `appsAction` (`{app, key}`: a card's button, or a button on a tool's card, which its module
  answers), `appsOpen` and `appsPrivacy` (`{app}`: Open, and Open System Settings, or a tool's card's Allow), and
  `appsList` (`{app, list, key, ids}`: a press on a list's page, its tray's action with the ids ticked, or a row's way
  or button, or one under what was said, with the ids it's for, which the list's module answers).
- The panel's page sends `appsShow` (`{app}`): that app's page is the one the back is on as the panel turns over
  (the low-disk line asks for Storage's), told to the back with `showApp(id)`.
- The app calls `setApps(apps, look, settings)`, each app `{id, name, does, icon, open, tool, card, hint, switches:
  [{kind, key, title, help, on, enabled, group, isNew}], groups: [{title, foot, enabled, rows}], recommended, statuses:
  [{key, title, section, said, note, ok, button, busy}], lists: [{key, title, count, intro, loading, empty, sections,
  tray, said}], permission: {kind, use, state}}` (the icon a data: address, or null; a group's rows each a `switch` as
  the app's own are, a `choice` `{kind, key, title, choices: [{id, name, help, isNew, enabled}], value, fixed: {name,
  help} or null, enabled}`, or a `time` `{kind, key, title, help, from, to, fromSaid, toSaid, enabled}`, from and to in
  minutes after midnight and said as the Mac writes them, its group's `enabled` false while none of its rows can be
  pressed; `recommended` false while its page isn't as recommended; a status one of its cards, `section` the heading
  over it or null, `said` how it stands in a word or two, with a tick while `ok`, `button` its button's title, if it has
  one now, waiting while `busy`; `state` one of `allowed`, `denied`, `ask`, `closed` or `unknown`; `tool` for one of
  Whozmove's own, listed under Tools; `card`, what its page shows above its switches, `{figure, of, bar, tone, lines,
  actions: [{id, title, main}], need}`, or null; `hint`, a few words under its name on its tile, or null; a list as
  contracts/Module.h's AppList describes it, `loading` its words while it's still being read, each section `{title,
  tickable, items, foot}` and each item `{id, title, line, why, way, marks, buttons}`), with the panel's look, and each
  setting `{key, kind, title, glyph, group, order, page, style, foot, button}`, with `on` for a `switch`, `value` (the
  id picked, or null) and `choices: [{id, name, help, isNew, icon, enabled}]` for a `choice`, or `app` (the app whose
  page it opens) and `said` (what it says it's set to there, or null) for a `page`; `showSettings()` for Settings…, as
  the panel starts turning over or while it's turned already, which goes to Settings from whichever page shows;
  `turned(false)` once the panel is back on its list side; and `backPointer({x, y})`, where the pointer is on the back
  while it's turned over, from its top-left corner, or `null` once it has gone.

## Rules

- Nothing here asks you anything: permissions are only looked at, never asked for (`AXIsProcessTrusted`,
  `AutomationPermission` without asking, and Full Disk Access by whether macOS's own record of permissions can be
  read), and System Settings opens only when you press it. For Full Disk Access, that press first has macOS refuse
  Whozmove Safari's folder (or Mail's), which it does without asking, as that's what puts Whozmove in its list
  (`ShowFullDiskAccessSettings`, app/shared/Files).
- A tool's permission has no section on its page: it's said in its card (`need`), and only while the tool needs it.
- A tool's page leads with its main button, which starts what the tool does (Storage's Map My Disk). An app
  the panel works with (Claude, Ghostty, iTerm2) keeps its permission's section, as that permission is what lets
  Whozmove work with it.
- A setting changes only through the one whose setting it is (parts/settings, or a module), and a switch, a choice or
  a part of the day on an app's page only through the module whose it is, and only while it can be pressed (its
  group's say too), so the same choice set elsewhere (the strip's lyrics question, New Conversation's menu, the
  changes view's editor) and here are always the same. Use the Recommended Settings asks each module with something on
  that page to put its own back. A card's button, too, only asks its module, which does what the same button elsewhere
  does (the setup line's), and it waits from the press until the module says how it went.
- The back is never typed into, as its window never takes the keyboard: a time is picked from a menu, never typed.
- Settings holds what you choose once and come back to now and then; what has to work while the panel is hidden,
  folded or lost off the screen stays in the pawn menu.
- The back's page only ever shows itself: it loads nothing else, and only its own page's messages are answered.
- The back is the list's size: it's never laid out at another width, and scrolls when it's taller than the panel.
