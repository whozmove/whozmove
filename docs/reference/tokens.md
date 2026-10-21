# Tokens

The panel's look comes from one file, [`panel/styles/tokens.css`](../../panel/styles/tokens.css): each colour, text
size and corner that styles use more than once for the same job, named for that job. A style writes
`var(--button-edge)`, not the value, so a change to how something looks is made once, in the token, for everything that
does that job.

## What's there

The file is grouped, and says beside each token what it's for:

- **Words on the glass**, brightest first: `--bright`, `--text`, `--code`, `--reading-text` (what the reader shows to
  read), `--muted`, `--label`, `--dim`, `--faint`.
- **Whose move it is**: `--needs`, `--busy`, `--turn`, `--pr` and `--idle`, which the app's icon matches, and the same
  for words in a stage's colour and the soft fill behind them (`--busy-text`, `--busy-fill`, …).
- **What a session wrote, and git's colours**: `--plan-text`, `--prototype-text`; `--added`, `--removed` and their
  fills.
- **Lines, edges and fills**: `--rule`, `--edge`, `--surface`, `--track`, `--cover` (a song's cover until it loads),
  `--scrim` (under a mark on a picture), `--tag`, `--picked`; pointed at, `--hover` and firmer ones for smaller things.
- **Buttons, switches, text boxes, code and the cards over the list**: `--button`, `--light` (a card's main button),
  `--tick` and `--switch-off` (a switch on and off), `--field`, `--code-fill`, `--card`, `--card-shadow`.
- **Text sizes**, `--size-chip` to `--size-heading`, and `--size-lyrics` (a song's lines in the reader); **corners**,
  `--radius-bar` to `--radius-pill`.
- **The layout**, `--header`, `--side`, `--column`, and the gauge's spring, `--spring`.

## Using them

- A new style takes each colour, text size and corner from a token. When none does that job, add one in its group,
  named for the job, not for its value (`--hover-strong`, not `--white-10`), with a note of what uses it.
- Two jobs that happen to share a value get a token each, so either can change on its own.
- Colours a script sets on a row, and the values each written out only once, aren't tokens yet.

## The checks

`tests/checks.sh` keeps styles to the tokens:

- **No value written out that isn't listed.** A colour, text size or corner written out in a style must be one that
  [`tests/styles-by-hand.txt`](../../tests/styles-by-hand.txt) lists for that file, as often as it lists it. That
  list is what's still written out today, and it only gets shorter: once a file no longer writes one out,
  `tests/checks.sh --update` takes it off. It never adds one.
- **No class name styled by two owners.** A class styled on its own (`.name { … }`) by both the core and a module, or
  by two modules, would have each restyling the other's elements, whichever loads later winning. Give one of them a
  name of its own.
