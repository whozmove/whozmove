# Reader

What a session wrote for you to read (its plans, prototypes and notes): its tag on the row, and the reader beside the
list showing one, where a plan waiting for your OK is sent back with your notes, or stopped. A prototype shows from its
file, as it would in your browser, in a browser of its own the app holds over the reader's body
(parts/pane/app/Browser.h). The session's writings, and reading a plan or notes back, are its agent's (the Claude Code
module's `readWriting`), and the reader's frame is the pane part's (parts/pane/page/reader.js).

## Its pieces

- `app/ReaderModule.m`: its face for the core (contracts/Module.h), and the prototype's owner: each listed session's
  writings, kept from its row, where a prototype is found by the session and the writing's id (never by a path the page
  sends); the prototype's Browser, whose setup is its file's folder, read from there, with what its pages take from the
  web, a link you press to a site or a page anywhere else opened in your browser, and nothing kept; its view held over
  the reader's body (PanelWindow's `hold:overPage:`), loaded once the panel has stopped growing (`whenStill:`), so its
  page starts in view, and in view once it has loaded, in the reader's own fade; what it asks (a window, an alert,
  files, a download, another app) refused, and the page told, as it is of a link pressed that goes nowhere; Open in
  Browser; and `--print-prototypes`, the print mode the tests check.
- `page/writings.js`: the tag, and the reader's `writings` mode, a prototype's space and the line above it among it;
  a plan drawn at a glance through `core.plans` (`writingBodyHTML`, with whose picks they are and whether they can be
  made, `planHow`), else as Markdown, and the bar under a waiting plan offering Send Back with My Picks while your
  picks differ from Claude's; and `core.planNotes(sid)`, which it offers the others: the plan Claude waits on in that
  session, opened beside the list with the box for your notes open under your picks (the Claude Code module's plan
  card calls it from Send back… while your picks differ). However the box opens, it takes what you typed on the
  plan's row (`planRowWords`, through the Claude Code module's `core.planRowNotes`), and gives back what's unsent to
  that plan's row, and only that plan's, as the reader closes or turns to another session or view (`planNotesBack`),
  so a note is never lost. Notes for a version Claude no longer waits on (answered elsewhere, or a new version asked
  since, `planNotesStale`) are never sent to another: they're kept by session (`planUnsent`) with their picks' words,
  and shown in the bar to copy until Done with These (`planNotesUnsent`);
  `page/reader.css`: what's its own in the reader (a writing's icon and how it stands, where it is, the space a
  prototype is shown over, and the plan's answer). The reader's frame, its list and Markdown are styled by the pane
  part (parts/pane/page/reader.css), and the tag is the panel's (panel/styles/controls.css), placed on the row
  (the row part's, parts/row/page/rows.css). `module.json` lists them for
  tools/page.sh.

`tests/test.sh` checks where each sample prototype would be shown from, or why it can't be (`--print-prototypes`), and
what the line above a prototype says as it stands, and how a plan is drawn and answered (`page-cases.js`, with the
page's scripts).

## Between the page and the app

- The page sends `readWriting` (`{sessionId, id}`), which the Claude Code module answers with `showWriting(sid, id,
  {text} or {missing})`, and a plan's answer as `answerAsk` with `message` (your notes) or `stop`. While the reader is
  open on a plan Claude waits on, it sends `holdAsk` every 10 seconds, so no session you allow answers it for you
  meanwhile.
- For a prototype it sends `prototype`: `{action: show, sessionId, id, at, rect}` once the reader is laid out at the
  width it asked for (and again once the file's been written since, which loads it again), `{action: place, rect}` as
  its space moves, `{action: hide}` when the reader shows something else or has folded back, and `{action: outside,
  sessionId, id}` (Open in Browser). `rect` is the space's `{x, y, width, height}`, in the page's points from its
  top-left corner. The app calls `prototypeState(sid, id, {loading, problem, asked, keyboard})`: whether it's loading,
  why it can't be shown, what it asked for that the panel doesn't do (`window`, `alert`, `files`, `download`,
  `camera`, `otherApp`, or `link`, a link pressed that goes nowhere), and whether it has the keyboard.

## Rules

- A prototype is shown only from the file its session's row lists, in a Browser, which has no bridge: nothing in it can
  answer a request ([the panel's own rules](../../docs/how-it-works/panel-rules.md)). Its pages can show the other files in its folder, never read them, and
  nothing outside it: a link you press to a page outside it opens in your web browser, and to any other file there goes
  nowhere; a folder too wide to open whole (the home folder itself) isn't opened.
- Open in Browser opens the file in the app that opens web pages, never whichever app `.html` files open in.
- The reader opens the moment its tag is pressed, saying where what it shows is coming from until it's there
  (`readerWait`, the pane part's), never lines standing in for the text.

## Facts

- WebKit runs a page's hover and mouse moves only while its window has the keyboard, and pointer moves passed in
  don't change that: a prototype's hover works once you've clicked into it.
- A page opened from a file can show the files in its folder but not read what's in them.
