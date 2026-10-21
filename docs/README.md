# Whozmove's docs

How Whozmove is built, for anyone changing it. What it does and how to install it is in the [README](../README.md),
and how to send a change is in [CONTRIBUTING](../CONTRIBUTING.md).

## How it works

- [Overview](how-it-works/overview.md): the core, the contracts and the modules, and what happens in one second of
  the panel.

## Guides

- [Adding a module](guides/adding-a-module.md): a new agent, a new app for sessions to run in, or a new feature, step
  by step.

## Reference

- [Rows](reference/rows.md): every field the panel knows about a session, and where each one comes from.
- [The extra stage](reference/stages.md): how a repo gives its island a stage of its own.
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
| [iterm2](../modules/iterm2/README.md) | sessions in iTerm2: a session's window, tab and pane, which tab it shows, and new tabs |
| [terminal-app](../modules/terminal-app/README.md) | macOS's Terminal, which only runs a command: Sign in on a Mac without Ghostty or iTerm2 |
| [island](../modules/island/README.md) | each row's checkout, its stages and their menus, the extra stage, and the PRs |
| [deploy](../modules/deploy/README.md) | Deploy: each project's command, run on this Mac when you press it |
| [changes](../modules/changes/README.md) | what a session changed, line by line: a row's numbers and the changes view |
| [reader](../modules/reader/README.md) | what a session wrote for you to read: its plans, prototypes and notes |
| [commands](../modules/commands/README.md) | a session's model, effort and mode changed from its row, and Compact |
| [usage](../modules/usage/README.md) | your plan's usage, on a card under the panel |
| [starts](../modules/starts/README.md) | new conversations from the panel's card, and ⌃⌥N |
| [spotify](../modules/spotify/README.md) | the song Spotify is playing, in its strip, its lyrics, and Spotify's token |
