<!--
Thanks for working on Whozmove. Fill in what applies and delete what doesn't.
For a bigger change, or any new motion idea, open an issue first, so we agree on it before you build it.
How to work on the project, and the rules that keep it safe: CONTRIBUTING.md.
-->

## What changes

<!-- What people will see, in a sentence or two. -->

## Why

<!-- The problem it solves. Link the issue it closes, like "Closes #12". -->

## How you tried it

<!-- What you did in the real app, and with which sessions: Claude Desktop, Ghostty, iTerm2, another terminal.
     For a change you can see, add a screenshot or a short recording made from sample sessions. -->

Tested with: macOS …, Claude Code …, Claude Desktop …, Ghostty …, iTerm2 …

## Front page

<!-- Optional. If you think this belongs on the README's front page, say why in a line; and say if it makes
     anything the README says, or one of its pictures, no longer true. The README itself isn't edited in a pull
     request but for its macOS permissions and Privacy: CONTRIBUTING.md, Pull requests. -->

## Checklist

- [ ] `tests/all.sh` passes
- [ ] `./build.sh` builds with no warnings (CI treats a warning as an error)
- [ ] Tried in the real app, without compacting, switching the model of, or typing into a real session
- [ ] Any `.expected.txt` re-recorded with `--update` differs only where this change meant it to
- [ ] A new label or rule on the page has a case in `tests/panel-cases.js` (or its module's `tests/page-cases.js`)
- [ ] A change people can see has a line in `CHANGELOG.md`'s Unreleased section and in its page in `docs/using/`; a new or changed row field is in `docs/reference/rows.md`
- [ ] A new fact about Claude Code, Claude Desktop, Ghostty, iTerm2 or Spotify (an id, a path, a label, a log line) is in its module's Facts header
- [ ] The safety rules still hold: requests are only ever allowed once, keys go into a session only while it sits idle with nothing waiting, and the panel never takes the keyboard
- [ ] Nothing personal in the diff, screenshots or pasted logs: no real paths, prompts, session ids or tokens

By opening this pull request, you agree to share your change under the project's licence, GPL-3.0-or-later.
