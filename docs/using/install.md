# Installing

How to install Whozmove, what it needs, what it sets up by itself, the permissions macOS asks for, and how to build it
from source or take it out again.

## With Homebrew

```bash
brew install --cask whozmove/tap/whozmove
```

Whozmove is signed by its developer and notarised by Apple, so macOS only asks, the first time you open it, whether
to open an app downloaded from the internet. Then it sets itself up as it opens, adding its hooks to Claude Code and
opening at every login (below). `brew upgrade` brings each new version, and Whozmove brings its hooks up to date as it
opens.

## New versions

Installed with Homebrew, Whozmove says when a new version is out, on the line under its header ("Whozmove 0.2.1 is
out. Run brew upgrade --cask whozmove/tap/whozmove to update."), with **Copy Command**, which puts that command on the
clipboard: it never runs `brew` or installs anything itself. Named with its tap, Homebrew looks at the tap again first,
so a version just released is found. Its × keeps that version away, and a newer one shows again. Once Homebrew has put
the new one in while Whozmove kept running, the line says so, with **Restart**. It reads the version from the tap's
cask, Homebrew's copy on this Mac and GitHub's, the newer counting, as it opens and every 6 hours; a build from a
checkout never looks.

Installed it from source before? Run `./install.sh --uninstall` in that checkout first, as only one copy of Whozmove
runs at a time.

## What it needs

A Mac with Apple silicon and macOS 15 or later, with Safari up to date (its engine
draws the panel). To follow your sessions, Claude Code or Claude Desktop, and Apple's
command line developer tools (`xcode-select --install`), whose `python3` the hooks run on: Whozmove waits for them, and
building from source needs them too, for `clang`.

Optional:

- `gh`, signed in, for PR status;
- Claude Desktop, Ghostty and iTerm2, for jumping to and controlling their sessions (in iTerm2, any session once its
  Python API is on, else one alone in its window);
- the `claude` command, signed in to a Claude plan, for your plan's usage (Claude Desktop's own copy will do).

Sessions in other terminals are listed too, but a click only brings their app forward (not the exact tab), they aren't
marked as the one you're on, and their model, effort and mode can't be changed from the panel.

## What it's tested with

Whozmove reads files and labels the apps below don't document, Claude Desktop's conversation files and log above all,
and asks Claude Code for your plan's usage a way it doesn't document either, so an update to one of them can break part
of the panel until Whozmove catches up. Each is tested with the version it names, where it has one, and the fix for a
change goes in the file beside it, in the module of the app that changed.

- Claude Code 2.1.304 (and 2.1.299, Claude Desktop's own copy): `modules/claude-code/app/ClaudeCodeFacts.h`
- Claude Desktop 2.42304.0: `modules/claude-desktop/app/ClaudeDesktopFacts.h`
- Ghostty 1.3.1: `modules/ghostty/app/GhosttyFacts.h`
- iTerm2 3.7.6: `modules/iterm2/app/ITerm2Facts.h`
- Spotify 1.3.5: `modules/spotify/app/SpotifyFacts.h`
- LRCLIB's API, for lyrics: `modules/spotify/app/LRCLIBFacts.h`
- Atlassian's server for AI tools (the Rovo MCP server, v2) and its sign-in, for Jira: `modules/jira/app/JiraFacts.h`
- Homebrew 7.0.10, its record of Whozmove and its tap's cask: `modules/install/app/HomebrewFacts.h`
- macOS 26.2's installer for Apple's command line developer tools: `modules/install/app/ToolsFacts.h`
- macOS 26.2's launchd, which opens Whozmove at login: `modules/install/app/LaunchdFacts.h`
- Safari 26.2, which a Browser in the panel presents itself as to websites: `parts/pane/app/BrowserFacts.h`
- macOS 26.2's protected and cloud folders, and the stores tools keep in your home folder, for Storage's map:
  `modules/storage/app/StorageFacts.h`
- Where developer tools keep what they download or build, and the commands that clean it (Docker, Xcode's simulators
  and the rest), for Clean up, not tied to one version of each: `modules/storage/app/CleanUpFacts.h`
- Betterleaks (the version `tools/betterleaks.txt` pins), and where other tools keep keys and their records, for Keys:
  `modules/storage/app/KeyFacts.h`

## Open at Login

Opened from an Applications folder, Whozmove opens at every login from then on, as a login item of its own (macOS says
so with its "Background Items Added" notice). **Open at Login** in Whozmove's menu in the menu bar, just above Quit,
turns that off and on. Turned off in System Settings' Login Items, it shows unticked there, and pressing it opens Login
Items, where only you can turn it back on. The login item restarts Whozmove only after a crash, never after you quit
it.

## Its hooks

The hooks are how the panel learns your last prompt, Claude's last reply, requests for your OK and the tool each agent
is using. The app carries them, and each time it opens from an Applications folder it adds them to Claude Code as a
plugin, `whozmove`, or brings them up to date there, with Claude Code's own `claude plugin` commands, so there's
nothing to edit in `~/.claude/settings.json`. It finds `claude` as your terminal does, or uses Claude Desktop's own
copy. Once Claude Code is there, it waits for Apple's command line developer tools, which the hooks run on, and if you
take the hooks out of Claude Code, it leaves them out.

Sessions pick up hooks when they start, so ones already open show only part of what they do until they reload them: the
line offers **Reload Them**, and each such row says it started before Whozmove's update, with **Reload to see its
steps**, which types Claude Code's `/reload-plugins` into it while it's idle (with the same checks as the panel's
commands, a half-typed message in a terminal kept), one session at a time; one at work is reloaded from its row once
it's done. Its conversation carries on as it was, cache and all. One Whozmove can't type into, or whose reload Claude
Code holds back, says what to type in it, and the line takes you there.

## The setup line

When setting up needs something from you, a line under the header says what, with the button that does it:
**Install** for the developer tools (macOS installs them in its own window; the line stays until they're in, and
carries on by itself once they are), **Get Claude Code** when it isn't on this Mac, **Add Back** or **Turn On** when
Whozmove's plugin was taken out of Claude Code or turned off there, and **Try Again** when connecting failed; and once
it's connected, it says so with a tick for a few seconds, then folds away (or, with sessions open from before, offers
Reload Them). Whozmove's plugin turned off or taken out of Claude Code while Whozmove runs shows there within a few
seconds, or at Whozmove's hourly look when it's turned off in one project's own settings. The line's × puts it away
until things change, and Git's and Claude's pages on
[the panel's back](the-back-and-look.md) keep the same buttons.

## Permissions

macOS asks for two permissions the first time they're needed: **Accessibility** for Whozmove (to change settings,
compact, focus the message box and send a new conversation's first message in Claude Desktop), and **Automation** of
Ghostty and of iTerm2 (to switch to and type into their tabs, open new ones, and see which one you're looking at) and
of Spotify (to show its song's cover and control it, asked at the first Play or the first song it plays). Both can be
granted later in System Settings → Privacy & Security. Storage's map asks for **Full Disk Access** only once it's
missing folders for want of it.

Switching on iTerm2's Python API from the panel uses Accessibility too, to tick its box in iTerm2's Settings, and asks
for nothing more: Whozmove gets each connection's one-time cookie from iTerm2 through that same Automation, and iTerm2
lists the connection in its Script Console.

## From source

```bash
git clone https://github.com/whozmove/whozmove
cd whozmove
./install.sh   # builds the app and opens it: it sets itself up as it opens, its hooks and Open at Login included
```

After changing anything in `app/`, `modules/`, `panel/`, `icon/` or the hooks, run `./build.sh` again in your
terminal. It puts the app in place and restarts it, and the app brings its hooks up to date as it starts (a hook change
reaches sessions started after that). Run inside Claude Code, by an agent or by you with `!`, the hooks are left as
they are, since every session you start would run them; and once you've set up Deploy for Whozmove in the panel, it
only compiles while the panel runs with Deploy's button showing, and Deploy on the session's row puts it in place when
you press it. Running `./install.sh` again updates the hooks too.

The first build fetches Betterleaks, which Storage's Keys looks with, from its GitHub release into
`~/Library/Caches/Whozmove-build`, and later builds use that copy, checked against the SHA-256 `tools/betterleaks.txt`
names each time; the tests fetch the version being readied there too. How to work on it is in
[CONTRIBUTING](../../CONTRIBUTING.md), and how it's built in [How it works](../how-it-works/overview.md).

## Uninstalling

```bash
brew uninstall --cask --zap whozmove
claude plugin uninstall whozmove@whozmove
claude plugin marketplace remove whozmove
```

The first line takes the app, its login item and Whozmove's folder (a plain `brew uninstall --cask whozmove` leaves the
login item and the folder); the other two take its hooks out of Claude Code, or use `/plugin` in a Claude Code session.
The hooks record nothing once the app is gone, but Claude Code lists them until they're taken out. Installed from
source, `./install.sh --uninstall` removes the app, its login item and the plugin, and asks before deleting Whozmove's
folder.

## When something's wrong

Whozmove's log is `~/Library/Application Support/Whozmove/panel.log`.

[All of Using Whozmove](README.md) · [Back to the README](../../README.md)
