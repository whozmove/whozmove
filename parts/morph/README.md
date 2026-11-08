# Morph

The list's motion. The list is drawn again from scratch whenever what it shows changes; morph makes that look
continuous, animating from what was there to what is now, and groups slide open and shut.

## What it shows

- A new line growing in from nothing, fading and lifting into place, and one that's gone folding away: a row's
  details (`.details`, parts/details) among them, after its bottom line.
- Your message and Claude's line written: new text writing in from the left, old text erasing from the right; and any
  other line of text, a module's own, taking new words the same way.
- Other changed text cross-fading, a row whose height changed resizing smoothly, and rows sliding past each other to
  their new places, a row moving glides over the others, frosting what's beneath it.
- With reduced motion, the same story told as a cross-fade, or just its end.

## What it owns

- `page/morph.js`: the rebuild's motion (`morph`, with `MORPH_MS` and its curve, `morphOvershoot`
  and `overshootAhead`): every row and line
  measured before (`snapshot`, `place`, `rowParts`, with how a module's part of a line moves from `core.lines`), the
  HTML swapped, and the difference animated (`tween`, `rollLine`, `rewriteLine`, `settleLine`, `writeIn`, `eraseOut`,
  `fadeAway`), the old words erasing and the new writing in on one way for every line (`eraseThenWrite`, where it has
  got to at each moment: `rewriteAt`), a row's chat line's or any other's (`rewriteText`); the panel's height following it (`followHeight`, `atMorphEnd`, `atListEnd`, `keepInStep`); a group
  sliding open or shut (`slideGroup`); and a scroll's last bit, pulled on and ending on a click (`pullScroll`,
  `clickSpring`). A row out of the list's sight, where it was and where it goes, takes its chat lines' new words at
  once, their room still easing (`outOfSight`), and the panel's height is followed frame by frame only while
  something changes size or place.
- `page/motion.css`: the rows' animations, the rebuild's, and reduced motion.
- `part.json`: its files for tools/page.sh, who it talks to, and what it provides.

## Who it talks to

It talks to the core, the bridge and the list (`talksTo` in part.json), and provides `morph` and the motion helpers the
others use, as part.json lists, with the panel's curve (`MORPH_EASE`) and whether motion is reduced (`calm`), which the
folded panel, peek, the header, the pane, the list, the held row and its hand-off, and modules' strips go by (the held
row's lines also fold and write on `tween`, `rewriteLine`, `settleLine`, `partText` and `keepInStep`):

- **The list** draws the list again and has morph animate it (`morph`, parts/list), and the strips under it move on its
  helpers (strips.js); a group slides open or shut on morph's `slideGroup`, which runs what the list gives it once the
  slide is done (the list drawing itself again), and has the panel's height reported as it changes (`reportHeight`).
- **The bridge's hooks** say how a module's part of a line moves, what a module swaps after a rebuild, and what runs
  once the list is drawn (`core.lines`, `core.swaps`, `core.drawn`, parts/bridge).
- **The pane** fades what the reader showed before on morph's `tween` (parts/pane).
- **A module's own view** has a line of its own take new words as a chat line does (`rewriteText`).
- **The held row** has the list go the last bit onto the edge as your scroll ends (`pullScroll`, parts/held).

## Rules

How each part of the panel moves is in [Motion](../../docs/how-it-works/motion.md): read it before changing any motion.

- **Quiet and continuous:** a row never vanishes and reappears; no lifted cards, shadows or dimming of other rows.
- **It lands exactly where the layout ends up,** measured rather than guessed.
- **Reduced motion tells the same story** as a cross-fade, or just the end of it.
