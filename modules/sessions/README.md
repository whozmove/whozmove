# Sessions

Every conversation Claude Code keeps on this Mac, by project, on each terminal's page and Claude's on the panel's
back. Those you tick go to the Trash, each conversation on its own and ended first while it's still open, with Undo,
and Put Back from In the Trash or from Finder.

## Its pieces

- `app/contracts/Agent.h` (the core's contracts): `AgentConversations`, which the Claude Code module fills: every
  conversation it keeps (`{id, folder, title, movedAt, ranIn, linked}`), the files each is made of (its own records of it
  among them), whether one is open, why one can't be ended now, and ending one.
- `app/contracts/Host.h`: ConversationHost's `keptConversations`, the conversations a host keeps itself (Claude
  Desktop's, whether Track Claude Desktop app sessions is on or off), and its `fullName`. Such a conversation is
  deleted there, never here: it's greyed, "Delete it in Claude Desktop", with Open in Claude Desktop.
- `app/contracts/Module.h`: `AppList`, a list on an app's page, which the apps module draws and whose presses it
  hands back.
- `app/SessionsModule.m`: its face for the core (contracts/Module.h). It gives Sessions to every host's page
  (`core.hosts`, so a terminal added later has it too), reads the conversations on its own queue as the back starts to
  turn over and again every 5 seconds while it's turned, and says, for each one, its line and, when it can't go now,
  why and the way past it (Take me there, through the core's focus; Open in Claude Desktop, through its host; Show in
  Finder for one kept through a link to another folder). Moving checks each one again as it acts, has the agent end
  those still open, then hands each one's files to `Trashed`, each one's row saying how it's getting on as Clean up's
  do (Waiting, Ending it…, Moving to the Trash…, In the Trash, or Stayed and why), the list read again once they've
  all gone; what it did is said with Undo and Show in Finder, what's left out with its reason, and one that couldn't
  go with why and Show in Finder. Every few seconds, and at launch, it has `Trashed` look for a file Finder put back.
  It takes `sessionsUnread` from the page, has the print run `--print-sessions`, and the helper run
  `--helper-trash-item` (Module's `helperRuns`, never a print run), which moves one file to the Trash for `Trashed`.
- `app/Trashed.m`: what went to the Trash, one note per conversation in `AppDir/trashed/<id>.json` (only yours to
  read, in a folder only yours to open), with where each of its files went. Every one of a conversation's files goes,
  or none, each moved by a run of the app's own (`--helper-trash-item`), one after another (one that moved its file
  without finishing counts as moved, where it says it went); Undo and Put Back bring them all back, or none; and a
  note goes once nothing of it is left in the Trash (emptied, or put back by Finder).
- `page/sessions.js`: which listed sessions have a reply you haven't read, as the list counts it (`isRead`), told to
  the app as it changes (`sessionsUnread`), so their lines and the question say so.
- `tests/test.sh`: `--print-sessions` for a sample home with made-up conversations and stand-in processes (ended,
  renamed, open, working, paused, one Claude Desktop keeps, one whose file names another process), moving, Undo, Put
  Back, Finder's Put Back, Put Back with a file there again and the Trash emptied, and what `--helper-trash-item`
  refuses; then, through a stand-in for that run, each row's steps, a refused file, one moved without finishing, one
  moved without saying where, a conversation kept through a linked folder, and Finder's renamed file given its name
  back by the tick; compared with `sessions.expected.txt`; and the page's rules (`page-cases.js`), compared with
  `page.expected.txt`.

## Rules

- **Only to the Trash, never deleted,** each of a conversation's files on its own, so Finder's Put Back works for any
  of them: each is moved by a process of its own, one after another, as macOS records where an item came from (what Put
  Back reads) only for the first item a process moves to the Trash, and two processes writing that record at once can
  lose one. Finder puts a file back under the name it has in the Trash, which renames one of the two a conversation
  has named by its id (its transcript's folder and its edited files' copies, or Whozmove's two notes): Sessions gives
  it its own name back as it next looks, once it's beside its own place with nothing there. Whozmove empties no Trash.
- **The run that moves a file moves only a conversation's,** in a place the agent names for one (AgentConversations'
  `isPlaceOfConversation:`), with only the folders they're kept in resolved: never a link, a path with `..`, or a file
  reached through a folder that's a link to somewhere else; and only in a home folder that's surely yours.
- **All of a conversation, or none of it,** going and coming back: a file that can't move brings back those that did.
  Put Back is refused while a file is there in its place again.
- **Put Back moves only what its note could be:** from a place in the Trash to one of that conversation's own files
  (each named by its id). A note that says otherwise is refused, as anything running as you could have written it.
- **Only what can go now goes.** A conversation working, waiting on you, with agents at work, paused in its terminal,
  open where Whozmove can't end it, or the one you're looking at is left out, saying why, with the way past it. Each
  is checked again as it's moved.
- **An open one is ended only through its agent,** and only once the agent is sure which process it is
  (AgentConversations' `endConversation:done:`); otherwise it's left out.
- **A conversation another app keeps is deleted there,** never here, whether that app is tracked or not. Only which
  conversations it keeps is read, never what they say.
- **What it keeps is where things went,** never what a conversation says: its title, its folder and its files' places.
  Your typed prompts stay in Claude Code's history (`history.jsonl` is never touched).
- **A print run never uses macOS's Trash,** which is your account's whatever HOME says: it moves into a stand-in folder,
  and refuses your own home folder. The helper run that does use it refuses any home folder but your own.
