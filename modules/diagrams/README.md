# The diagrams module

A ```mermaid block wherever the reader shows Markdown (a plan, its At a glance card, notes), drawn as a diagram rather
than as its text ([docs/using/plans.md](../../docs/using/plans.md)). A flow it reads in full is drawn here, in the
panel's own look, at the width it has: a long flow carries on in a second band, as words wrap, and an arrow that jumps
over steps goes round them. Any other block, and a flow whose lines can't keep clear of its steps, shows as written,
with a line saying why. Each diagram drawn has **Diagram** and **As written**. On the list (a request's card)
a block stays code. It has no native code and no messages: the places pass it the text they already have, through the
core.

## Its pieces

- `page/flow.js`, plain functions, checked by the page cases:
  - a block read (`diagramKind`, `flowParse`): a flow only when every part of every line is read (`flowNode`,
    `flowEdge`, `flowGroup`, `flowLabel`), each edge's ends as Mermaid reads them (an arrow, a cross, a circle or none,
    at its end or both ends, never two kinds); groups, a class or a colour, `~~~`, an edge's own name, words left over
    or a shape not closed, and it says why it isn't; and drawn here (`flowRead`) with at most one loop to itself on a
    step;
  - what a diagram says in words (`diagramWords`): a flow's steps along its main path (`flowPath`, its groups passed
    over, so one with groups still says its steps), a sequence's who and how many messages, another kind's name and
    title;
  - a flow laid out (`flowLayout`: ranks by `flowRanks`, a stand-in in each rank an edge jumps over, ordered with the
    steps so it runs beside them, bands filled evenly, loops back round the steps through the gaps, nested shortest
    innermost with room for their words, a loop to itself at its step's side, two edges between one pair of steps moved
    apart (bowed apart when they have words), each edge's words where they meet nothing (a jump's on its own run beside
    the steps it passes, its lane there as wide as they are), `flowOrth` for the square runs), kept clear of its steps
    (`flowClear`, along the points `flowPoints` gives), placed where it keeps clear (`flowPlace`: in bands, else on one
    line, each gap whose words found no place grown, and the ranks beside it parted, until they fit) and drawn
    (`flowSVG`), its sizes from the panel's words (`flowSizes`), measured by what it's given (`flowRoughWidth` where
    nothing can measure, in the page's tests).
- `page/diagrams.js`, the drawing: a block's figure in the reader (`diagramHTML`, its kind and Diagram · As written,
  holding its text until it's drawn; null on the list, so the block stays code), a card's small drawing
  (`diagramSmallHTML`, its words where its smallest words would shrink too far to read), the diagrams Markdown holds as
  the pane's Markdown reads its code blocks (`diagramsIn`, from `mdFences`), what Markdown that's one diagram says
  (`diagramMarkdownWords`), its first flow with something to show on a card, drawn or its steps named
  (`diagramFirstFlow`); each figure drawn at the width it has (`diagramsDraw`, measured with the page's own font at
  `--size-body`), as the reader is fitted (`core.readerDrawn`) and as its width changes, or shown as written, saying
  why, where it can't keep clear at that width (a card's, its steps in words), and tried again as its width changes; and
  Diagram or As written pressed (`diagramShow`): what it showed fades, its room eases to what it shows (the list part's
  `easeHeight`) as that comes in the panel's way, a cross-fade under reduced motion. Its state: the diagrams you've
  turned to As written, by their text's key (`diagramsWritten`).
- `page/diagrams.css`: the figure, the drawing's parts and its edges' ends in the panel's colours (so it follows
  Appearance), the ground
  under an edge's words (the panel's, with what the place lays over it: `--dg-over`, `--dg-over-press`), and the small
  drawing.
- `module.json`: its scripts and style, for tools/page.sh.

It plugs into the core with `core.fences.mermaid` (markdown.js draws a fence through it), `core.readerDrawn` and
`core.diagrams` (`smallHTML`, `words`, `says`, `firstFlow`, `draw`), which the plans module uses for a section
that's only a diagram and for the card's Flow; the reader module runs `core.readerDrawn` as it puts a writing in.

`tests/test.sh` runs `page-cases.js` with the page's scripts under jsc and compares it with `page.expected.txt`.

## Rules

- **Drawn whole or not at all.** A flow is drawn here only when every part of it is read; anything it doesn't read
  leaves the whole block as written, never drawn with a piece missing. A picture with a piece left out could be
  approved as the plan.
- **Never through a step.** A flow is drawn only where every line misses every step but its own two, and no words lie
  on a step, on other words or on another edge's line (`flowClear`): a line through a step reads as a link that isn't
  there, and words on another line read as that line's.
- **Every word is escaped** (`esc`), in the drawing as in the text; a word in angle brackets is a word, and only `<br>`
  breaks a line.
- **Its words come from the text alone,** so a folded section or a card says what a diagram shows before anything is
  drawn, and in a place that never draws it.
- **Nothing leaves the Mac,** and nothing is kept but which diagrams you've turned to As written, in the page's memory.
- **The places meet it through the core only,** and show the block as code when it's absent.
