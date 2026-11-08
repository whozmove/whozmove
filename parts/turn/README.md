# Turn

Turning the panel over to its back, and back: about its middle, the glass with its shadow and both sides as one, as a
press at one end pushes it, that edge sinking in. The back is a view the apps module gives it, as wide as the list and
as tall as the panel.

## What it shows

- The panel turning over, seen from in front: the glass, its shadow and its edge, about the panel's middle, gentle at
  both ends and quickest where it's edge-on; and with reduced motion, the two sides fading one into the other.

## What it owns

- `app/PanelWindow+Turn.m`: the window's Turn category. Holding the back (`holdBack:`, `placeBack`), turning over and
  back (`turnOver:then:`, `turnOver:left:then:`, `spin:left:then:`, `fadeSides:then:`, `doneTurning:then:`), a turn
  asked for while the panel was busy (`takePendingTurn`), putting it back at once (`turnBackAtOnce`), its edge
  (`paintEdge`), and who's told (`followTurn:`, `turningBack`). Its flags (`turned`, `turning`) are set only here.
  The room the window takes in while it turns (`TurnRoom`) is checked by tests/edges.sh.
- `app/Turning.h`: the curve and the transforms it turns on (`TurnEased`, `AnchorOf`, `TurnAbout`), for anything else
  that turns about the panel's middle as the panel does, rather than a copy of them.
- `part.json`: who it talks to, and what it provides.

## Who it talks to

It provides `Turning.h`; and what else turns as the panel does builds on its two sides, the page's (`clip`) and the back
(`back`, given by `holdBack:`), in the window's own state, and only follows `turned` (`followTurn:`), never setting it.
The core: the window's own state and the other parts' methods through the private header
(app/core/PanelWindow+Private.h), and its public methods in PanelWindow.h's Turn category, which the apps module, the
page's messages, the edge's icons, the usage card and the starts and storage modules use; and the keyboard, which it has
give the keyboard back as it turns (`dropKeyboard`). The glass, the fold and the flick ask it to turn back or take a
turn that waited. It calls the glass's (parts/glass) `fitHeight:`, from PanelWindow.h's own interface, and `inWindow:`,
`placeStrips`, `setWindowFrame:glass:clip:then:`, `setWindowFrame:showing:then:`, `settle`, from the private header
(app/core/PanelWindow+Private.h). It tells the page as it turns through the bridge's `Page` (`turned:`, parts/bridge),
and has the fold take a fold that waited (`takePending`, parts/fold) once it lands.

## Rules

- **Not while the reader is open, nor folded:** it turns from the list side only.
- **What's held over or under the panel turns with it** and stays out of sight meanwhile (`followTurn:`).
- **The turn is never cut short by another:** one asked for meanwhile waits for it to land (`takePendingTurn`).
