# Reader

What a session wrote for you to read (its plans, prototypes and notes): its tag on the row, and the reader beside the
list showing one, where a plan waiting for your OK is sent back with your notes, or stopped. Page only: the session's
writings, and reading one back, are its agent's (the Claude Code module's `readWriting`), and the reader's frame is
the core's (panel/scripts/reader.js).

## Its pieces

- `page/writings.js`: the tag, and the reader's `writings` mode; `page/reader.css`: what's its own in the reader (a
  writing's icon and how it stands, where it is, a prototype's frame, and the plan's answer). The reader's frame, its
  list and Markdown are styled by the core (panel/styles/reader.css), and the tag with the row (panel/styles/rows.css).
  `module.json` lists them for tools/page.sh.

## Between the page and the app

- The page sends `readWriting` (`{sessionId, id}`), which the Claude Code module answers with `showWriting(sid, id,
  {text} or {missing})`, and a plan's answer as `answerAsk` with `message` (your notes) or `stop`.

## Rules

- A prototype runs in a sandboxed frame from its own text, and nothing in it can answer a request (CONTRIBUTING's
  rules).
