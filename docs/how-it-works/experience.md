# Experience

What a change has to be like for anyone using the panel: its flows, its states, its words and its motion. Each rule
is a check that a walk through the change can fail. Walk every flow a change adds or touches as the user meets it, in
dark and in light, with long words and with reduced motion, and hold it to these. Plain words are CONTRIBUTING's
[Style](../../CONTRIBUTING.md#style), the motion rules it builds on are CONTRIBUTING's
[Animation](../../CONTRIBUTING.md#animation), and the keyboard rules are [the panel's own rules](panel-rules.md).

## The panel

1. **What you approve is what you see.** Before any Allow, Approve, Submit or a step that changes something, its reason
   and the whole of what it does can be read without a press. Nothing on a request's card ends in "…": a title wraps,
   and a command of a few lines shows whole. A request cut short by the hook says so.
2. **Never stuck.** Every "can't" says why, in plain words, and offers a way forward that does it: a button or step
   that does the thing, or that takes you to where it can be done. A reason with nothing to press is a dead end.
   - Every wait says what it's waiting for, and either carries on by itself or offers a way out.
   - Every error has a next step: try again, open the place to fix it, or say what to do.
   - Every card, menu and step can be left without doing anything.
   - Nothing silently does nothing. A press that can't act says why, at once, where the press was. A beep alone is
     silent, and so is a reason left in a menu that has already closed.
   - Every message is true in each state it can show in.
   - An empty list or view says what will show there and how to start it.
3. **One kind of thing, one shape, one name.** Options on a card share one layout. A card's answers sit in the same
   place on every card. One action has one name wherever it shows (on a row's card and in the reader beside it).
   The same look in two places is one shared piece. Before a design adds a place for something to show (a section, a
   line, a button, a card), it says why none of the places the panel has already will do: a row's lines (its note, its
   work line, its bottom line), its ring, the bar at a row's far edge, the strip at the list's edge, a card, the line
   under the header, or One Task. A new place without that reason fails.
4. **Words from your side, the length of a glance.** A question fits in two lines, an option's name in four words and
   its meaning in one line. No markup, code marks or internal names are shown raw: what Claude wrote is drawn, or its
   marks dropped. Name things by what people see, and what a press does.
5. **A press lands on what you saw.** Nothing appears, moves or covers under the pointer just before a press counts:
   something only just shown ignores a press. A card stays with its row as the list moves. What looks like a button
   does what it says, and a button named for an outcome causes it.
6. **Every state is drawn before you meet it.** Each part lists its states (empty, one, many, long words, can't,
   waiting, light, dark, reduced motion), and each has a sample case (`tests/panel-cases.js`, a module's
   `tests/page-cases.js`) from which it can be drawn. In every state, the panel shows no empty room while there are
   rows to show: the list fills the panel up to its height, scrolled or not, and the panel's bottom edge sits at its
   content's end, moving with it as it changes. Room kept for something that hangs below the list is kept only while
   it shows.
7. **Everyone can use it.**
   - Text people must read is at least 4.5:1 against what's behind it, in both looks: `--muted` or stronger.
     `--dim` and `--faint` are for lines, edges and marks.
   - VoiceOver says what each control is and does, and what each state means (a dot's colour, a ring, a count), in
     words.
   - The panel never takes the keyboard by itself, but a card you've clicked into answers its keys there: its numbers,
     Return and Esc.
   - Text sizes come only from the size tokens, so the panel's words can be made larger as a whole.
   - Reduced motion tells the same story without travel.
8. **One press, where you already are.** What you set out to do takes one press from where you are: the row, its
   card, One Task or the reader. It is never done a second time in another place; when another app has to know,
   Whozmove tells it.

## Motion

[Motion](motion.md) says how each part moves. These add what the eye should follow, beside CONTRIBUTING's rules.

- **M1. Nothing just vanishes.** In the first frame after any change, the old thing or the new one is there, never
  empty room. What stays moves from where it was; what goes fades or folds into what takes its place.
- **M2. One thing for the eye at a time.** In each beat, at most one region with words moves. Words write after their
  room has settled, not while it travels.
- **M3. The reason comes before the thing it explains.** The line that says what's wanted is written before the card's
  buttons can be pressed.
- **M4. Your pointer stays on what you aimed at.** After a press changes the layout, what's under the pointer belongs
  to the same row, or nothing pressable is.
- **M5. What moves together never crosses words.** No frame shows one row's text over another's.
- **M6. Timing is measured, not felt.** Each move's length is written down where it's made, and how much of it
  happens early: an ease that does most of its travel at once makes a short move read as a jump.

## How to check

- Draw the states: `tools/page.sh <folder>`, then load its `panel.html` with sample rows, as CONTRIBUTING's "The UI
  has no automated test" describes, in a light and a dark window, and look at each state the change touches.
- Step the motion: with the page's frame loops, timers and animations driven by one clock you control, take a picture
  at each beat of a change (every 40 to 80 ms), and check M1 to M5 frame by frame. A move the app makes natively (the
  panel folding, turning over, the reader growing) needs a recording of the real window.
- Read the words aloud as the user would meet them, in the state they show in.
