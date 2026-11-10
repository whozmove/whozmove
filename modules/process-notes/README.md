# Process notes

How a project works, beside the project's own pages. A session that learns something those pages don't say (what you
told it, what it found the hard way) drafts a short note for the project, and its row asks "Keep this as how acme-web
works?", with the note whole as numbered steps, Keep It and Not Now. Only Keep It keeps it, on this Mac, for the project
and every worktree of it, and every session on the project is handed it. A draft again is shown against the note as
kept, each step new or taken out marked, so Keep It changes exactly what the card shows.

## Its pieces

- `app/ProcessNotesModule.m`: its face for the core (contracts/Module.h).
  - The ask: `process-draft` (`{note64}`): a note as the session drafted it, checked, and shown on its row in place of
    any draft of its own waiting there; answered at once, "shown on your row: …", so the session carries on. It isn't
    shown, and says why, when it's the note as kept already, or holds no line the one you said Not Now to didn't.
    `askShowing:`, as it only shows you something; it logs itself.
  - Each read of the rows (`RowPhaseListed`): the row's `processDraft` (docs/reference/rows.md), its lines marked
    against the note as kept; a draft whose session has ended is taken back.
  - Keep It: the note written on a queue of its own, the card saying "Keeping it…" meanwhile; then every other draft
    waiting for the same project is taken back, as each was drafted against the note before. One that can't be written
    waits on, saying why, with Try Again.
  - How a project works, for other modules (`ProjectWay`, contracts/Module.h): the project's short name, its own pages,
    the note as kept and when, and how this session's last draft stands (`waiting`, `notNow`, `keptElsewhere`).
  - What's kept: `AppDir/process-notes/<hash of the project's folder>.json`, `{project, note, keptAt}`, only you able to
    read it, written only by Keep It. What you said Not Now to is kept only in the panel's memory.
- `app/ProcessNotes.m`: plain functions: the project a folder is in (its repo's main checkout, for a worktree too, from
  its row's `git`; a folder outside git is its own), its short name, its own pages (CONTRIBUTING.md, the files its
  agent's instructions are in (Agent's `instructionPages`), the pull request template, docs/ pages on contributing,
  reviewing or releasing, each a plain file inside the checkout), a draft checked, what changed against the note as
  kept, whether a draft after Not Now holds anything new, the row's card, the way handed to a session, and the record
  kept and read back.
- `app/ProcessNotesPrints.m`: `--print-process`, the module driven step by step with made-up projects, in a throwaway
  home.
- `page/process-words.js`: the card's words and drawing, in plain functions; `page/process-notes.js`, the card on the row
  (`core.rowCards`, after the tickets' cards), its press, and its keys once pressed (`core.keyCards`);
  `page/process-notes.css`, the note as text with a line down its left, from the tokens.
- `plugin/skills/learning-a-process/SKILL.md`: what a note holds and how a session drafts it, collected into Whozmove's
  plugin as `whozmove:learning-a-process`.
- `tests/test.sh`: `--print-process` in homes of their own, `ask-panel.sh process-draft` against a stand-in panel, and
  the page's cases (`page-cases.js`), compared with `notes.expected.txt`, `asks.expected.txt` and `page.expected.txt`.
  tests/all.sh runs it.

## Between the page and the app

- The page sends `processAnswer` (`{sessionId, at, act}`): your Keep It (or Try Again), `keep`, or Not Now, `notNow`,
  for the draft its card showed, by when it was asked.
- A row's `processDraft` (docs/reference/rows.md) is all the page is told.

## Rules

- **Only your Keep It keeps a note.** A session's ask only shows it to you; nothing it sends is written anywhere.
- **What you keep is what you saw:** the card shows the note whole, each change against the note as kept marked in
  words, and Keep It keeps exactly those lines, for the draft that card showed (by when it was asked).
- **You're never asked twice for the same lines:** after Not Now, another session's draft for the project shows only
  with a change the declined one didn't make (a line it didn't add, or a kept line it didn't take out), and any card
  waiting with nothing more goes. The session you said it to may show it again, which it does only when you ask.
- **The project's own pages are only read, never changed,** and only plain files inside the session's checkout are
  listed, so a link to a file elsewhere on the Mac never is.
- **A note is plain text and holds no secret:** a draft with a control character, or anything shaped like a key or a
  token (a provider's own shapes, a password or key's name set to one, a password given to a command or sent as a
  header, a password in a link, a signed token, a webhook's address), is turned away, line by line, saying which line; and a note is checked the same way each time it's read back, so a line changed
  by hand that fails is left out of what's handed on.
- **Nothing of a note is logged:** panel.log says which session asked, for which project (its short name), how many
  lines and how it went, never a word of the note.
- **The note never looks like a choice:** its steps are numbered text, with no box, fill or round mark, and a number
  key does nothing on the card. Only Not Now and Keep It are buttons.
