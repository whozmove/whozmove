# Tokens

The panel's look comes from one file, [`panel/styles/tokens.css`](../../panel/styles/tokens.css): each colour, text
size and corner that styles use, named for its job. A style writes `var(--button-edge)`, not the value, so a change to
how something looks is made once, in the token, for everything that does that job.

Each colour has two values: the dark panel's, in the file's first block, and the light panel's, in the block under
`@media (prefers-color-scheme: light)`, in the same order. The page takes whichever its window has, which the pawn
menu's **Look ▸** sets (Match System, Light or Dark), and changes over at once when it changes. On the light panel,
words and lines are black where the dark panel's are white, each as far from the panel as it is there; the stages'
colours are deeper, so their words read; the main button is dark, with light words; and the cards over the list are
white.

The panel's own colour, `--panel`, is the one thing the Look menu's **Black** changes (white on the light panel):
what has to match the panel exactly takes it from there, as the cat's eyes do. The page has the menu's choice on its
root element (`data-look`, from `setSwitches`), and the file's last lines give `--panel` for it.

## What's there

The file is grouped, and says beside each token what it's for:

- **Words on the panel**, brightest first: `--bright`, `--text`, `--code`, `--reading-text` (what the reader shows to
  read), `--muted`, `--label`, `--dim`, `--faint`, and some for one kind of words (`--branch-text`, `--read-text`,
  `--line-number`); and `--on-colour`, a mark on a colour or a picture, white on either panel.
- **Whose move it is**: `--needs`, `--busy`, `--turn`, `--pr` and `--idle`; `--turn-words`, amber words; and the same
  for words in a state's colour, the soft fill behind them, and an edge round a card about it (`--needs-text`,
  `--turn-fill`, `--turn-edge`, …).
- **What a session wrote, PRs and git's colours**: `--plan-text` and its fill, `--prototype-text`; a PR's state on its
  card (`--pr-open-text`, …); `--added`, `--removed`, `--changed-text` and their fills; and how full a gauge is,
  `--level-normal` to `--level-limit` (a context ring, the usage card's bars).
- **Lines, edges and fills**: `--rule`, `--edge`, `--surface`, `--track`, `--cover` (a song's cover until it loads),
  `--scrim` (under a mark on a picture), `--tag`, `--picked`; pointed at, `--hover` and firmer ones for smaller things,
  and `--pointed-filter`, a writing's tag.
- **Buttons, switches, text boxes, code and the cards over the list**: `--button`, `--main-button` (a card's main
  button, the panel's opposite: light on the dark panel, dark on the light one), `--tick` and `--switch-off` (a switch
  on and off), `--field`, `--code-fill`, `--card`, `--card-shadow`, `--menu` (a menu the page draws).
- **The cat, the usage card and its vine**: `--cream` and `--cat-feature` (the cat and its eyes), the chats beside it
  (`--chat`, `--chat-edge`, `--chat-shadow`, `--chat-pill`), `--usage-card`, and `--vine-green` to `--vine-heart`.
- **Text sizes**, `--size-chip` to `--size-heading`, and `--size-lyrics` (a song's lines in the reader); **corners**,
  `--radius-bar` to `--radius-pill`.
- **The layout**, `--header`, `--side` and `--above` (the room for the reader beside the list, and for what comes up
  from the folded cat above it), `--column`, and a spring for motion, `--spring`.

## Using them

- A new style takes each colour, text size and corner from a token. When none does that job, add one in its group,
  named for the job, not for its value (`--hover-strong`, not `--white-10`), with a note of what uses it.
- Two jobs that happen to share a value get a token each, so either can change on its own.
- A new colour token gets its light value too, in the light block, at the same place; look at it on both panels.
- A colour a script sets is a token as well: `var(--level-warning)` in a style it writes, or, where a `var()` can't go
  (an animation's keyframes), `tokenColour('--text')` (panel/scripts/util.js), which reads it as the panel's look has
  it then. An SVG's own `fill` and `stroke` don't take a `var()`: set them in its `style`.
- Some text sizes and corners written out only once aren't tokens yet.

## The checks

`tests/checks.sh` keeps styles to the tokens:

- **Every colour has its light value.** A colour token in the dark block with none in the light block fails, and so
  does a light value with no dark one.
- **No value written out that isn't listed.** A colour, text size or corner written out in a style must be one that
  [`tests/styles-by-hand.txt`](../../tests/styles-by-hand.txt) lists for that file, as often as it lists it. That
  list is what's still written out today, and it only gets shorter: once a file no longer writes one out,
  `tests/checks.sh --update` takes it off. It never adds one.
- **No class name styled by two owners.** A class styled on its own (`.name { … }`) by both the core and a module, or
  by two modules, would have each restyling the other's elements, whichever loads later winning. Give one of them a
  name of its own.
