# Pane

The reader beside the list: pressing a row's tag (or its numbers) grows the panel beside the list, which stays where it
was, and the reader opens there, showing what one of its modes shows of a session (what it wrote, what it changed) or
of none (Spotify's lyrics). And `Browser`, web pages that aren't the panel's own, each in a web view of its own: a
website kept as an app, or a page a session wrote, shown over the reader's body.

## What it shows

- The reader's frame: its header and its ✕, its body, and where what it shows is coming from while it comes in.
- Plans and notes, written in Markdown, as the reader's HTML.

## What it owns

- `app/PanelWindow+Pane.m`: the window's Pane category, growing the panel beside the list for the reader, toward the
  side facing the screen's middle (the glass's `edgeSide`), as far as what it shows needs and the screen allows, and
  folding back (`expandReader:height:`, `collapse:`, `whenStill:`).
- `app/Browser.h`, `app/Browser.m`: `Browser`, which its owner gives a setup (what it may load, whether what it's
  signed in to is kept, where a link that goes somewhere else opens, how it introduces itself), places and sends
  somewhere; `app/BrowserFacts.h`, what it relies on about Safari to introduce itself as this Mac's Safari. Its rules
  are checked by tests/browser.sh.
- `page/reader.js`: opening, filling and closing the reader (`openReader`, `toggleReader`, `closeReader`,
  `drawReader`, `fitReader`, `putHTML`, `readerRefill`, `readerWait`), and the session it's about (`readerSession`),
  each mode drawing itself (the modules' `core.readerModes`); as it's fitted, once its width is set and before what it
  shows is measured, what's drawn at the width it has (`core.readerDrawn`: a diagram).
- `page/markdown.js`: plans and notes as HTML, everything escaped (`markdownHTML`, a plain function, checked by
  tests/panel.sh); a code block in a language a module draws (`core.fences`: a ```mermaid diagram) is drawn by it,
  told whether it's in the reader or on the list; and the code blocks Markdown holds, read as it's drawn
  (`mdFences`).
- `page/reader.css`: the reader's frame.
- `part.json`: its files for tools/page.sh, who it talks to, and what it provides.

## Who it talks to

The core: the window (its public Pane category in PanelWindow.h, and the others' methods through
app/core/PanelWindow+Private.h); the bridge (parts/bridge), for the page (`readerOpened:width:`, `readerClosed`) and its
hooks (`core.readerModes`, `core.readerPresses`); and on the page the header, brought back as the reader opens
(`headerGlideTo`), and the keyboard (`wantKeyboard`, `keepsKeyboard`, `TEXT_BOX`); the list, drawn again as the
reader opens and closes, and the rows you press in it kept in place (`render`, `keepInPlace`, `hangingBelow`,
`linesUnder`, `stillFolded`, `openFromCat`, parts/list); and the morph's `tween` (parts/morph). The modules that have modes in it (the reader's writings, the
changes view, Storage, Spotify's lyrics), Claude Code's requests and the next steps open and fill it through what
part.json provides, the reader's element (`reader`) among it. The core makes a `Browser` for a module that asks
(`Core`'s), and the keyboard asks which are in the panel's window (`inWindow:`). It calls the glass's (parts/glass)
`resendRoom`, from PanelWindow.h's own interface, and `placeStrips`, `reshapeTo:done:`, `roomFor:`, from the private
header (app/core/PanelWindow+Private.h).

## Rules

- **The list stays where it was:** the panel grows beside it, toward the side facing the screen's middle, where a row's
  bar at its far edge says it comes out (the side with more room until the glass has worked that out), and only as
  far as the screen allows (16 points from its edges; a longer page scrolls).
- **A `Browser` never has a bridge:** nothing it shows can send the app a message, and its owner has no way to give it
  one. A page Claude wrote must never answer a request ([the panel's own
  rules](../../docs/how-it-works/panel-rules.md)).
- **A folder's pages can't read the folder's files** (WebKit's own rule for file pages), so they may take parts from
  the web: never turn on WebKit's file access preferences.
