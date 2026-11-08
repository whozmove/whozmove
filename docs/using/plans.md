# Plans at a glance

A plan Claude writes for you can run to a hundred lines. Whozmove opens it on a short view that tells the whole plan,
with the rest folded under it, so you can decide without reading every line; or, if you'd rather, exactly as written.

## The card a plan opens on

Beside the list, a plan opens on **At a glance**:

- **What changes for you:** what you'll see or do differently, and sometimes Before and After.
- **You decide:** each choice on one line, with the option Claude recommends, marked Recommended. Press a line to see
  its options and why. Pick another, and the bar under the plan offers **Send Back with My Picks**, which opens the
  box for your notes under your picks in words, to read and add to before **Send to Claude**; while it's open, your
  picks stay as they are (**Cancel** keeps them and your words). **Use Claude's Picks** puts them back. Keeping Claude's picks means there's nothing to send
  back: you approve the plan in its session, as always, with **Take me there**.
- **Could go wrong**, **You'll try**, **What it keeps or sends** (only when the plan stores, reads or sends something
  new) and **Left out**.
- **Flow**, when the plan has a flow diagram: the first one, small, from the section it's in. Press it to open that
  section. A flow Whozmove doesn't draw, or one too big to read that small, names its steps in words instead; one it
  can't read at all isn't on the card.

Past four choices, the rest wait behind "+2 more choices". Only the plan Claude is waiting on takes picks; an older one
shows Claude's picks. Nothing in a slot is ever cut.

Under the card, **the whole plan**, each section folded to its heading and first sentence. Press one to open it, or
**Open All**. When the card can't show every line of the plan's "At a glance" block (a line with a label of its own,
say), the block is the first section, as written, and opens with the plan: named **At a glance, as written**, its
first line the first one the card left out. A block the card can't read at all is the first section too, open.
A section that's only a diagram folds to what it shows: "A flow of 6 steps: Recipe page → … → Cook from it."

## Diagrams

A flow diagram Claude writes into a plan or notes (a ` ```mermaid ` block) is drawn wherever the plan is read: in its
sections, Full version of the plan, and notes. It's drawn in the panel's own colours, at the width there is: a long
flow from left to right carries on in a second band; one too wide for its room shrinks a little, then scrolls sideways.
Above it, **Diagram** and **As written** switch between the drawing and its text. An arrow that jumps over steps goes
round them, beside the steps in between; an arrow can have a head, a cross or a circle at one end or both; a step can
loop back to an earlier one, or to itself. Words on an arrow get room of their own. A left-to-right flow whose second
band would put a line through a step stays on one line and scrolls sideways. A flow is drawn only when every part of it
can be, and with no line through a step: one with groups or colours, or whose lines can't keep clear of its steps,
shows as written rather than with a piece missing. Any other kind of diagram shows as written too. Each says why in a
line above it. In a request's card on the list, a diagram stays its text.

## Skimmed, or the full version

At the top of a plan, choose how to read it. **Skimmed** is the card, with the plan folded under it. **Full version of
the plan** is the plan exactly as Claude wrote it, title and all, as text, with nothing taken out or added: no card, no
folds, only its flows drawn, each with As written. The toggle stays in the same place in both. Picks you made on the
card still count: the bar under the plan says how many you changed, and they go with **Send Back with My Picks**. The
choice is one for every plan, kept on this Mac across launches.

## Where the short view comes from

A session started after Whozmove is set up has its skill, which asks Claude to start every plan with an "At a glance"
block, in one shape. The card says "Written with the plan".

A plan without one (from an older session, say) is read from its headings instead, and the card says "Pulled from the
plan's headings". A slot comes only from a heading that is that slot: Decisions, Could Go Wrong or Risks, Left Out,
What You See, and so on, each slot naming the heading it came from. A slot takes the first line under its heading, and
says "More under" the heading when there's more. Context, Steps and the rest never fill one. When nothing matches, the
plan shows folded by section, with no card.

An earlier version kept under a second title (a second line starting `# `) is folded as one section, so the card is
still the new version's own.

Nothing is summarised by an AI, and nothing about a plan leaves your Mac.

## On the row

The plan card on a session's row shows a few lines from the plan's own short view in place of its first steps: what
changes for you, how many choices there are and whether Claude has picked for each, and what could go wrong, each
at most three lines, ending in "…" when there's more. Once you've picked another option beside the list, it says so:
"3 choices, 1 changed by you". A plan without its own short view shows its steps, as before. **Read the plan** opens
it beside the list. **Send back…** opens a box for your notes on the row; with picks of yours, it opens the plan beside
the list instead, with its box for your notes open under your picks, and what you typed on the row in it; until then
the row says "Your note waits with your picks beside the list". Close the plan unsent and your note waits on the row
again. If the plan is answered in its session, or Claude writes a new version, before you send, your notes and picks
aren't sent to the new one: the bar under the plan shows them, to copy into what you send next, until **Done with
These**. Your picks are kept while Whozmove runs.

## In One Task

A task that asks you to approve a plan can carry the plan's own short view. One Task shows it as the same card: what
changes for you, every choice with Claude's pick and why, what could go wrong and the rest, with nothing to press.
When the short view has a line the card has no place for, One Task shows it as it was written instead, so nothing
above **Approve** is left out. When the task attaches the whole plan, open it: a plan Claude presented in plan mode
opens beside the list on its card with the rest folded under it, or exactly as written, as you read plans, and a plan
in any other file opens as written.
**Approve** answers the task, as always.

[Back to Using Whozmove](README.md)
