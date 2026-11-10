# The plans module

A plan at a glance: a long plan opens on a short view (what changes for you, what you decide with Claude's pick, what
could go wrong, what you'll try, what it keeps or sends, what's left out), with the whole plan folded by section under
it; or, as you choose to read plans, as the plan exactly as written ([docs/using/plans.md](../../docs/using/plans.md)).
It has no native code and no messages: the places that show a plan (the reader beside the list, the plan card on a row,
One Task's task about a plan) pass it the text they already have, through `core.plans`, and draw what it gives back.

## Its pieces

- `page/glance.js`, plain functions, checked by the page cases:
  - the plan in parts (`planParts`: its title, what's before its sections, its sections at the shallowest level under
    the title, and each later top heading a section of its own, with everything under it) and in blocks (`planBlocks`:
    items, paragraphs, code, tables), never reading a `#` inside a code block;
  - its short view (`planGlance`): its own "## At a glance" block, each "**Label:**" item in the slot that label names
    (`PLAN_SLOTS`), a choice read by `planChoice`; or, without one, each slot pulled from a heading that is that slot:
    its first item, and the heading named when there's more under it; or null;
  - the sections to fold (`planSections`), each with its first sentence (`planFirstWords`), the block among them unless
    every line of it is on the card (`planBlockWhole`, each part of it `planOnCard`), starting open (`opens`), named
    "At a glance, as written" when the card reads it in part, with the first line it left out; a section that's only a
    diagram folds to what it shows (`planFoldWords`, `core.diagrams`);
  - the plan's first flow, for its card (`planFlow`): the section it's in and its text;
  - the notes a send-back carries for your picks (`planPicksNote`), and what the plan card says of its choices
    (`planDecideWords`: how many you've changed, or how many come with Claude's pick).
- `page/glance-view.js`, the drawing: the card (`planCardHTML`, What Changes for You with Before and After
  `planChangesHTML`, its choices `planChoicesHTML` and `planChoiceHTML`), the folds (`planFoldsHTML`), the reader's
  whole view (`planReaderHTML`: Skimmed, the title with the toggle, `planLooksHTML`, then the card and the folds; or
  Full version of the plan, the toggle above the plan exactly as written, drawn as the reader draws any writing), the
  plan card's lines (`planCardLinesHTML`) and a task's view (`planTaskHTML`: the card bare, every choice as lines,
  `planChoiceLinesHTML`); the card's Flow (`planFlowHTML`: the flow small, `core.diagrams`); its presses in the reader
  (`core.readerPresses`): the card's Flow opens its section and brings it into view; Skimmed or Full version of the
  plan draws the view again, read that way; a choice, a fold or Open All opens or folds in place, growing in and
  folding away as the panel's lines do (`planTurn`, with the list part's `growIn` and `foldAway`; a fade under reduced
  motion; a section's diagrams drawn before it's measured to grow, `core.diagrams.draw`), while an option picked or
  more choices draws its view again from what it was last drawn from, then the reader (`drawReader`, the pane part's)
  for the answer bar; and `core.plans`, what the places call (the reader's `writingBodyHTML` and answer bar, which
  asks `folded` whether the plan it's under is shown folded, the plan card's `planAskHTML`). A view drawn held shows
  your picks but takes none, while the notes they go back in are open. The plan card's lines come only from the plan's
  own block. Its state: your picks by the request's id (`planPicks`), what's open (`planOpen`, a section that starts
  open kept as folded by you, `planFoldOpen`) and what each view was drawn from (`planDrawn`) by session, each
  forgotten with its session (`core.forgotten`); and how you read a plan (`planReadAs`), one choice for every plan,
  kept across launches (`store`, the page's own). The plan card's lines say how many picks you've changed on the
  request it's given.
- `page/plans.css`: how to read the plan (on the title's line, or on a line of its own above the plan as written, in the
  same place), the card, the choices, the folds and the plan card's lines. The labels, choices, tabs, tags and buttons
  are the kit's (panel/styles/controls.css); a section opened is the reader's Markdown (parts/pane/page/reader.css).
- `plugin/skills/plan-at-a-glance/SKILL.md`: the skill (`whozmove:plan-at-a-glance`) that asks a session to start its
  plan with the block, in the shape `planGlance` reads.

`tests/test.sh` runs `page-cases.js` with the page's scripts under jsc and compares it with `page.expected.txt`.

## Rules

- **A slot only ever holds what it is.** Its label in the block, or a heading that is that slot; Context, Steps,
  Pieces and Tests never fill one. Pulled, the card says so, and each slot names the heading it came from. What
  Changes for You with no heading for it says it wasn't written and where to read.
- **One screen, nothing cut.** A slot shows whole, never ending in "…"; pulled, it's its section's first item, then
  "More under" its heading; choices past the fourth wait behind "+2 more choices", but in a task's view, which shows
  them all. Only the plan card on a row, which stands in for a few steps, keeps each line to three, ending in "…", the
  whole in the reader behind Read the plan.
- **Nothing left out above Approve.** A task's view shows the card only when every line of the block is on it
  (`planBlockWhole`); otherwise One Task shows the block as it was written.
- **The block is never hidden.** The whole plan under the card leaves the block out only when every line of it is on
  the card (`planBlockWhole`); a block read in part, or not at all (labels of its own), is the first section, as
  written, and starts open. Read in part, it's "At a glance, as written", its first line the first one the card left
  out, so it isn't taken for the card again.
- **Picks only on the plan Claude waits on now,** kept by its request's id; any other plan's choices show Claude's
  pick and can't be pressed.
- **No AI, and nothing leaves the Mac.** The short view is what the plan says, and nothing new is kept but how you
  read a plan, Skimmed or Full.
- **Approving stays in the session.** Keeping Claude's picks means there's nothing to send back; a pick that differs
  goes back as the notes of a send-back, through the place's own answer.
- **Everything a plan says is escaped** (`esc`, `mdInline`, `markdownHTML`), its id too.
- **The places meet it through `core.plans` only,** and draw as before when it's absent or gives null.
