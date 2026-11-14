# Side chat

A conversation with a session beside the list while it works: what you send it, how far each got, and its replies.
Point at a session's row and a thin bar shows at its far edge, the edge facing the open screen. Bring the pointer onto
that bar and it swells a little and lights; press it, and the chat comes out of that side beside the list, the list
staying where it was, with the cursor in its box. The row never moves, and the bar sits past the end of the row's
lines, so Deploy and the folder's name at their end are pressed where they are. While that chat is open, its row's bar
stays lit. The bar is there while a card is open on the row too, a request for your OK, a question or a plan among
them: past the card's edge, its buttons further in, and a press on it counts only once a request has been seen a
moment, so you can ask about it before you answer. A screen reader finds Side Chat on the row of every session that's
running, as "Side Chat with" the session's name.
Its head names the session and its project; under it, in a word or two, whether it's working or compacting, waiting for
you or asking for your OK; then the conversation, and the box at its foot. While the session works, the conversation
ends with the same line its row shows, under its name: "Thinking" until its first step, then each step as it runs (a
command, a file it reads or edits, a search), with the turn's time going; its reply comes in that line's place. What
Claude thinks in words isn't there: Claude Code doesn't pass it on, only the step it's on. The way you chose last, Send
or Ask Without Interrupting, is the dark button, and Return goes that way until you press the other (Send is dark until
you choose; Add to Message and Send's words under a question choose Send); ⌥Return goes the other way. Ask stays the
way only where a question can be asked: while a copy is still answering, Return says so and keeps your words, and
where Ask can't go, Send is the way. Esc or its ✕ closes it, keeping what you wrote. Side Chat on another row turns
the chat to that session's, each keeping its own conversation and what you'd started writing.

The same chat shows under a task in [One Task](one-task.md#talk-with-the-agent), for the session that handed it to
you: what you send or ask from either place shows in both, and what you'd started writing goes with it. Words sent from
there open with a few words naming the task and its step, shown quietly over yours here; Esc there leaves the box, and
One Task stays open.

## How your words go in

- **Send says when your words go in:** **Send After This Step** while the session works, **Send After Its Turn** when
  it has no hook to take them between steps, **Send After You Answer** while it waits on your answer, and plain
  **Send** while it's idle.
- **While the session works,** your words wait in Whozmove, and go in when its current step ends: Whozmove's own hook
  in that session hands them to Claude, with a line that says they're from you, and Claude reads them before its next
  move, so it can change course. If its turn ends first, they go in as it ends, and the turn carries on. Nothing is
  typed while it works, so no key can land in a request, and it works in Terminal too.
- **While it's idle,** they're typed in as your next message, as Whozmove types anything, into a terminal tab or a
  Claude Desktop conversation (which comes forward).
- **A request for your OK comes first:** while one waits on its row, the chat says so, with **Show It**, and your
  words go after you've answered it. **Ask Without Interrupting** about it first, and a copy of the session answers
  without it seeing.
- What will go in shows whole under the box before you send. Until it's read, **Take Back** puts your words back in
  the box. "Read" shows only once the session's own record shows them.

## When they can't go in yet

Every "can't" says so before you send, with the way forward in Send's place:

- **Copy and Go** where Whozmove can't type (macOS's Terminal), at idle or for words that waited for its turn to end:
  your words copied, and the session brought forward to paste them. Words copied this way say "Copied for you to
  paste", and Whozmove no longer sends them itself.
- **Close the Other Copy** for a conversation open in two terminals, at idle.
- **Open Again** for a session that has ended.
- **Open Accessibility Settings** for a Claude Desktop conversation, when Whozmove doesn't have the Accessibility
  permission to type into it: your words are back in the box, and the button opens that pane in System Settings.
- A session started before this version of Whozmove has no hook to take words between steps: they go in when its turn
  ends, by themselves into a terminal that isn't the app in front, else for your **Send Now**.
- Stopped with Esc before its step ended, a session never read them: they go in once it's idle, or say "Wren stopped
  before reading this", with **Send Now**.

## Asking without interrupting

**Ask Without Interrupting**, beside Send, asks a question the session itself never sees: a copy of its conversation
so far answers it in the chat, while the session works on, untouched. Your question shows marked "Without
interrupting", quieter than the rest of the conversation, with **Stop** in Ask's place until it's answered. In its
answer's place, under "A copy of Wren", is the line a working session's row shows, on one line, a long step ending in
"…": "Thinking", then each step the copy takes as it starts ("Reading cart.ts", "Running git log"), naming no file
outside the session's folder, and, with a version of Claude Code Whozmove was tested with, the first line of what it's
thinking. Then the answer, with **Add to Message** and **Copy**. One question at a time for each session.

- **Add to Message** puts "I asked a copy of you “…” and it said: " and the answer into your box, after
  anything you'd written there, cut to the room the box has: read it, trim it, and Send passes it on to the session as
  your words.
- A follow-up remembers your earlier side questions and their answers, until the session compacts; in a long side chat,
  only the newest that fit, about 4,000 words. While the session hasn't moved since your last side question, the
  follow-up goes to the same copy; once it has, a fresh copy of the session as it is now is told your earlier side
  questions, so it knows both. A quiet line, "A copy no longer knows the questions above", marks where its memory
  starts. The copy ends 5 minutes after its last answer, and when the session ends or compacts.
- The copy may read: the project's files in the session's folder, and, when that folder is the top of a git checkout,
  git's status, log, diff and show there. It changes nothing, messages no one, and never reads outside the session's
  folder. It never opens a file where keys are kept: Claude Code's own settings and sign-in, and every file Storage's
  Keys knows holds keys (ssh's and the cloud tools' folders, MCP settings such as `.mcp.json` or `.cursor/mcp.json`,
  and files named as keys are, such as `.env`, `.npmrc`, `id_rsa`, `.pem` or `.key`); nor, in a git checkout, a file
  git ignores. A search or git won't show one either: a search shows matching lines from one file at a time, and
  over a folder only which files match, and only a folder with no such file in it; git shows no change to such a
  file, even one your project committed long ago. A session started in your home folder has a copy that reads
  nothing, and so does any copy while Whozmove can't find where keys are kept. Each read is one more round of its
  answer, up to 12, so an answer that reads files takes longer. When it wants to read more than a side question may,
  it says so, with **Ask Again** and Send's own words for the session now.
- **Send's words** (**Send After This Step**, **Send After Its Turn**, **Send After You Answer** or **Send**), on any
  question the copy couldn't answer, send the same question the normal way, as Send does: the session itself sees it,
  and it goes in as Send's words say (straight away while it's idle). Nothing goes in without that press, and a second
  press sends nothing more. The question then says "Sent to Wren", and your words follow below it, "Goes in once … step
  ends" while it works; **Take Back** there puts the question back as it was, with Ask Again and Send's words.
- Each one counts toward your plan's usage, as the session's own work does. The copy asks Anthropic just as the
  session last did, so while the session works, or soon after its last step, it can read the conversation from
  Anthropic's cache rather than all over again; a session left idle a long while is read again whole.
- Not yet on a Claude Desktop conversation: "Not in Claude Desktop yet", with **Take Me There** to ask it there.
- Every other "can't" says so in Ask's place, or under the box before you've written anything: Claude Code not on this
  Mac (**Get Claude Code**), nothing said in the session yet, or its conversation not found (**Take Me There**). After
  you've asked, in the answer's place: "Took too long", "Didn't answer" or "Claude Code couldn't answer just now", for
  an error Anthropic sent back (**Ask Again** or Send's words), signed out (**Copy the Sign-In Command**), your plan's
  limit reached (**Copy the Question**), or too long to read again (Send's words). One more can't be asked while another
  is being answered.
- The copy reads none of Claude Code's settings files, so if you've set Claude Code's sign-in or a gateway in its
  `settings.json` `env` rather than in your shell, it can't reach Anthropic, and says it didn't answer.
- Side questions and their answers are held in memory only: they go when the session ends or Whozmove quits, and a
  question still being answered then is stopped. With the chat closed, an answer you haven't seen lights the row's bar
  as a reply does, and comes out beside the folded panel as "Asked without interrupting:" and its first words.

## Replies

Its reply shows under its name, a command in it on a line of its own with **Copy** (copied, never run). While the chat
isn't open, a reply you haven't seen lights that row's bar in your move's colour, the same bar at the same size, and
comes out beside the folded panel and counts at the panel's edge, as any reply does, until you've seen it, in the chat
(here or under a task in One Task) or the session's tab. A reply or a side answer that comes in while the chat is in
front is said to VoiceOver.

What you send in a side chat, and how far each got, is kept in Whozmove's folder, which only you can read, until the
session's process ends; replies are only held in memory.

[Back to Using Whozmove](README.md)
