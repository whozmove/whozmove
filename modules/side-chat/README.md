# Side Chat

A conversation with a session beside its main one, while it works: your words, how far each got, its replies, and a box.
Side Chat, the bar at the far edge of the session's row, which swells a little as the pointer comes onto it, opens it beside the list, in the
reader's place (parts/pane), with the list staying where it was and the cursor in its box. While the session works, your
words wait in Whozmove, and its own hook hands them in as its current step ends, or as its turn ends, which then carries
on; while it's idle, they're typed in as Whozmove types today. Send's own button says when they go in (Send After This
Step, Send After Its Turn, Send After You Answer, or Send). Ask Without Interrupting asks a question the session never
sees: a copy of its conversation answers it in the chat (its agent's AgentAside), and Add to Message puts the answer in
your box to send.

## Its pieces

- `app/SideChatModule.m`: its face for the core (contracts/Module.h). It sends your words through Send
  (`sayBetweenSteps:`, parts/send) and keeps how far each got, in a record per session in Whozmove's folder that only
  you can read, until the session's process ends. Words that hadn't gone in when Whozmove last stopped come back to
  your box. It reads each reply through the session's agent (AgentWork's `replyTo:` for words typed in,
  AgentBetweenSteps' `wordsState:` for words its hook handed in, once that turn has ended), cuts it into prose and
  code (`ReplyParts`, app/shared/Text.h) and holds it in memory only. Your questions asked without interrupting go to
  the session's agent (AgentAside's `ask:aside:earlier:step:done:`, one at a time for each session, never a Claude
  Desktop conversation's yet), with the ones answered before it (`SideChatAsidesEarlier`), as the agent keeps one side
  conversation for each session and owns it; Side Chat keeps the questions and answers, each held in memory with its
  answer, how many of the earlier ones the side conversation knew (`remembered`) and, while it's being answered, the
  step the agent last said it's on (`step`, so the page shows the line its row shows while it works, in the answer's
  place), until its session goes, stopped
  then if it's still being answered; only the tokens each read go in the log. It tells the page each listed session's
  chat (`setSideChats`), and `--print-side-chat` is the print mode the tests check.
- `app/SideChatRecord.h`, `app/SideChatRecord.m`: what a session's record keeps as your words move on, as plain
  functions: words said, how far they got, taken back, read and answered, back in your box after a restart, and let
  go once the page has put them back; and the questions asked on its side, kept in memory only: asked, answered, and
  what the page is told of them.
- `page/side-chat-words.js`: what it says, as plain functions over a session as the list has it and its chat as the
  app keeps it:
  - whom it's with (`sideChatName`), and what Send's button says by when your words go in (`sideChatSendWord`);
  - what's said before you send: why nothing can go in from here, with the way forward in Send's place, or how your
    words will go (`sideChatBefore`);
  - exactly what goes in and the room left (`sideChatOpening`, `sideChatRoom`, `sideChatGoes`);
  - how far each of your words got, and its presses (`sideChatSaid`), and why words are back in the box
    (`sideChatBack`);
  - a reply as it's shown (`sideChatReply`), a reply or side answer you haven't seen (`sideChatUnseen`) and Side
    Chat's bar on the row (`sideChatEdge`);
  - asking without interrupting: why it can't now, in Ask Without Interrupting's place (`sideChatAskBefore`), how far a
    side question got and its presses, Send's words for a failed one among them (`sideChatAsideSaid`), where the side
    conversation's memory starts (`sideChatForgotAbove`, from the newest answer's `remembered`), its answer added
    to your box (`sideChatAddAnswer`) or its question (`sideChatQuestionInBox`), and what a key in the box does
    (`sideChatKeyAct`): Return goes the way you chose last, which `sideChatWayNow` says (Ask Without Interrupting only
    while it, or Stop for a copy still answering, is in Ask's place, else Send), and ⌥Return the other way;
  - the line under its head (`sideChatLive`), whether the conversation ends with the line the session's row shows while
    it works (`sideChatWorking`) and that line as it reads, so it's drawn again only when that changes
    (`sideChatWorkKey`), and an empty chat (`sideChatEmpty`).
- `page/side-chat-view.js`: the same as HTML: its head (`sideChatHeadHTML`), the live line (`sideChatLiveHTML`), the
  conversation (`sideChatLinesHTML`), a side question and its answer (`sideChatAsideHTML`), the box with Ask Without
  Interrupting and Send and the line under it (`sideChatBoxHTML`, `sideChatUnderHTML`), and Side Chat's button in the
  strip at the row's far edge, with no words (`sideChatEdgeHTML`).
- `page/side-chat.js`: Side Chat at every running session's row's far edge (the row part's `edge` slot), opening the
  chat as the reader's `sideChat` mode with the cursor in its box, what you write kept per session, the presses in it,
  Return going the way you chose last (kept per session, in memory only; `sideChatWayNow`), which is the dark button,
  ⌥Return the other way, and Esc to close, and what the app tells it (`setSideChats`).
  While the session works, the conversation's foot is the row part's own line (`workLineHTML`, under the session's
  name), drawn again only when its step changes and its time ticked (`tickTimes`) in between, so it reads as the row
  does and a reply you're selecting text in isn't drawn again each second.
- `page/side-chat.css`: its look, One Task's talk's in side chat's own classes, from the kit's tokens; on the row, a clear button
  filling the strip, the row's bar its look: kept lit while its chat is open (`keep`), in your move's colour while a
  reply waits that you haven't seen (`lit`).
  `module.json` lists the page files for tools/page.sh.

`tests/test.sh` checks what the record keeps as words move on, whether held words go in by themselves, what's kept of
questions asked without interrupting, and a reply cut into prose and code (`--print-side-chat`, compared with
`record.expected.txt`); then what the page says in every state and the HTML it's drawn as
(`page-cases.js`, with the page's scripts, compared with `page.expected.txt`).

## Between the page and the app

- The page sends `sideChatSend` (`{sessionId, words, aside}`, `aside` when a side question is sent with Send's words),
  `sideChatTakeBack` and `sideChatSendNow` (`{sessionId, at}`), `sideChatCopy` (`{sessionId, words}` or
  `{sessionId, at}`), `sideChatReplyCopy` (`{sessionId, at, part}`) and
  `sideChatPutBack` (`{sessionId, at}`), `sideChatAsk` (`{sessionId, question}`), `sideChatAskStop`
  (`{sessionId, at}`), `sideChatAsideCopy` (`{sessionId, at, what, part}`), `sideChatCopySignIn` and
  `sideChatGetAgent` (`{sessionId}`), and the app calls `setSideChats(chats)`: each listed session's chat, by
  session, `{says, asides, askWhyNot, agent, hook, frame, front, idleWay}`.

## Rules

- **Nothing is typed while a session works.** Words for a working session wait in Whozmove, and its own hook takes
  them between its steps; a session without the hook, or one stopped before its hook took them, gets them typed only
  once it's idle at its prompt, under the panel's own typing rule, and by themselves only where it's safe (Send's
  `ReachGoesByItself`), else for your Send Now, or Copy and Go in a terminal Whozmove can't type into.
- **Every "can't" says so before you press,** with the way forward in Send's place: Copy and Go, Open Again, or Close
  the Other Copy.
- **Everything said is escaped,** a reply's prose drawn from its Markdown, and a command in it only ever copied, as
  the app read it, never run.
- **"Read" only once the session's own record shows the words;** until then, Take Back.
- **Nothing goes in that you can't see:** words that hadn't gone in when Whozmove stopped come back to your box.
- **A reply waiting is your move's colour,** never a count and never red: red is for words that didn't go in.
- **A side question never reaches the session:** it's asked of a copy of its conversation, which may read the project's
  files and git in the session's folder but changes nothing and saves nothing, only by your press, one at a time, and
  it's drawn quieter than the conversation, never outlined (an outline is words held for the session). Its answer goes
  to the session only as your own words, once you've read them in your box (Add to Message, then Send).
