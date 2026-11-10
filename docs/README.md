# Whozmove's docs

How to use Whozmove, part by part, and how it's built, for anyone changing it. The [README](../README.md) is the short
version, and how to send a change is in [CONTRIBUTING](../CONTRIBUTING.md).

## Using Whozmove

- [Using Whozmove](using/README.md): everything the panel does, a page for each part of it, and how to install it.

## How it works

- [Overview](how-it-works/overview.md): the core, the contracts and the modules, and what happens in one second of
  the panel.
- [Where it reads from](how-it-works/where-it-reads.md): what the panel shows, and where each part of it comes from.
- [How the pieces fit](how-it-works/architecture.md): each piece of the app and the page, file by file.
- [Modules](how-it-works/modules.md): how a module plugs into the core, natively and on the page.
- [The panel's own rules](how-it-works/panel-rules.md): the keyboard, the page and the app, the pointer, typing
  into a session, and the list's order.
- [Motion](how-it-works/motion.md): how each part of the panel moves.
- [Experience](how-it-works/experience.md): what every flow is held to, its states, words and motion, and how to check.

## Guides

- [Adding a module](guides/adding-a-module.md): a new agent, a new app for sessions to run in, or a new feature, step
  by step.

## Reference

- [Rows](reference/rows.md): every field the panel knows about a session, and where each one comes from.
- [The bridge](reference/bridge.md): every message between the page and the app.
- [Print runs](reference/print-modes.md): what each of the app's print runs prints, and which test checks it.
- [Tests](reference/tests.md): each test on its own, and what it checks.
- [A task's shape](reference/task.md): what a session sends to hand you a task, and what it hears back.
- [The team file](reference/team.md): the file a session leading a team of sessions can keep, and how the list reads
  it for the team's groups.
- [Tokens](reference/tokens.md): the panel's colours, text sizes and corners by name, and the checks that keep styles
  to them.

## The modules

Each module's README is beside its code: its pieces, the facts it relies on about the app it works with, the messages
between the page and the app, and its rules.

| Module | What it is |
|---|---|
| [claude-code](../modules/claude-code/README.md) | the agent: Claude Code's sessions, transcripts, details, commands, requests and usage, and its hooks |
| [claude-desktop](../modules/claude-desktop/README.md) | Claude Desktop's conversations, its message box, new conversations, and "Switch model?" |
| [ghostty](../modules/ghostty/README.md) | sessions in Ghostty: a session's tab, which tab it shows, and typing into it |
| [iterm2](../modules/iterm2/README.md) | sessions in iTerm2: a session's window, tab and pane, which tab it shows, typing into a session through its Python API, or alone in its window, and new tabs |
| [terminal-app](../modules/terminal-app/README.md) | macOS's Terminal, which only runs a command: Sign in on a Mac without Ghostty or iTerm2 |
| [git](../modules/git/README.md) | each row's checkout, its next steps and Create PR, and the PRs |
| [deploy](../modules/deploy/README.md) | Deploy: each project's command, run on this Mac when you press it |
| [changes](../modules/changes/README.md) | what a session changed, line by line: a row's numbers and the changes view |
| [reader](../modules/reader/README.md) | what a session wrote for you to read: its plans, prototypes and notes |
| [side-chat](../modules/side-chat/README.md) | a conversation with a session beside the list while it works: your words, how far each got, and its replies |
| [plans](../modules/plans/README.md) | a plan at a glance: its short view and the whole plan folded by section, for the places that show a plan |
| [diagrams](../modules/diagrams/README.md) | a ```mermaid block drawn as a diagram wherever Markdown is shown, with Diagram and As written |
| [commands](../modules/commands/README.md) | a session's model, effort and mode changed from its row, and Compact, with when it's a good time to compact |
| [compact-at-breaks](../modules/compact-at-breaks/README.md) | Compact at Breaks: a long conversation compacted for you at a natural break, and its row saying so |
| [process-notes](../modules/process-notes/README.md) | how a project works, beside its own pages: a session's draft of what they don't say, kept only by your Keep It |
| [waits](../modules/waits/README.md) | a session waiting on someone else (a review, a merge), holding no seat, carried on when that comes |
| [usage](../modules/usage/README.md) | your plan's usage, on a card under the panel |
| [starts](../modules/starts/README.md) | new conversations from the panel's card, and ⌃⌥N |
| [bring-forward](../modules/bring-forward/README.md) | held keys that bring a session you pick forward from any app |
| [attention](../modules/attention/README.md) | Keep App Switches: what you turn to (apps coming to the front, away and back, sessions looked at), kept on this Mac to measure how much of you your agents take |
| [spotify](../modules/spotify/README.md) | the song Spotify is playing, in its strip, its lyrics, Spotify's token, and its music quieter while you talk to Claude |
| [install](../modules/install/README.md) | Whozmove setting itself up as it opens: where it runs from, Apple's developer tools, and its hooks in the agent; the line under the header that says what it needs from you, and its cards on the panel's back |
| [notifications](../modules/notifications/README.md) | what needs you, from every part, decided in one place: the line under the header, most urgent first, and what comes out beside the folded panel |
| [needs-you](../modules/needs-you/README.md) | what's new in each session that needs you (a request, a wait, a reply you haven't read, a side chat's reply), as a notice for beside the folded panel |
| [storage](../modules/storage/README.md) | how full your disk is and what fills it: the line when it's running low, the map, Clean up, Keys (keys left where they shouldn't be, found with the Betterleaks the app carries), and Storage among the tools on the panel's back |
