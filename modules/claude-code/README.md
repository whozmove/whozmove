# Claude Code

The agent that runs the sessions the panel lists: its running sessions, its terminal sessions kept once they've ended,
and what its hooks recorded of each, what's new
in each session's transcript (its PRs, what it wrote for you to read, what it edited, its context, its mode), each
session's details, the words of the commands the panel sends (`/model`, `/effort`, `/plan`, `/compact`) and what their
results say, typing a command into a session's prompt while keeping your draft, the requests waiting for your answer in
the panel, your plan's usage asked of `claude`, whether Claude may work in a folder, a new session's command and an
ended one's, and its hooks plugin, put into Claude Code and kept up to date there.

## Its pieces

- `app/ClaudeCode.m`: its face for the core (contracts/Module.h), and the agent it is (contracts/Agent.h), with every
  one of the agent's protocols: AgentWork, AgentCommands, AgentPrompt, AgentUsage, AgentStarts, AgentInstall,
  AgentVoice (its voice mode: the session's own process recording, or its SoX recorder), AgentRecords (where it
  keeps what its sessions were told and read, which Keys looks in) and AgentConversations (every conversation it keeps,
  the files each is made of, and ending an open one, for Sessions on the panel's back). It registers Don't Wait on
  Me (`sessionSwitches`), and says which session a process of Claude Code's is, from its registry (`sessionOfProcess:`),
  why one can't ask the panel in that session's name, when it doesn't run Claude Code's own program (`whyNotAsker:`,
  ClaudeProgram.m), and why one can't ask for something that only shows you something now (`whyNot:speakFrom:`,
  WhereSeenWorking.m: another copy of Claude Code open for it, or working somewhere it wasn't seen working), for what a
  session asks the panel. Its
  part of each row: in the first phase, it starts reading what's new in the transcripts (every 10s, and at once when a
  compaction its hook recorded ends, as the context's new size is there; one in a session started before the hook
  update ends unheard, so its new size waits for the next 10s read) and whether Claude Code records shell commands'
  changes in the sessions' folders (every 5s); then each session's last message and writings; then its details, with
  a pick from the panel the session hasn't confirmed yet; and once the rows are whole,
  it forgets the launch flags of sessions that have ended, and keeps each running terminal session's record
  (`KeptSessions.m`). Its settings on the panel's back are on Claude's page, which the app that keeps its sessions as
  conversations of its own lists on every Mac (Claude Desktop's module): that page's id is the agent's `appId`, where
  the install module adds how Whozmove's plugin stands.
- `app/KeptSessions.m`: the terminal sessions it ran lately, kept so their rows stay once they've ended, as Claude
  Desktop keeps its conversations: a file for each in Whozmove's folder (`conversations/<id>.json`: its folder, name,
  the terminal it runs in, its process, its transcript and when its conversation last moved), written on a queue of its
  own when one changes, from launch on; read back on the rows' queue as rows with status `closed` and no process, for 3
  days after the conversation last moved, or 30 while its row waits on someone else (its record's `waits`, noted from
  the rows as last listed, `KeptNoting`); pruned once the sessions running now are known, then every hour. A press on
  one runs the agent's `resumeCommand:wordsFile:` (`claude --resume <id>`, with a module's words for it) in a new tab,
  which Focus (parts/focus) opens.
- `app/ClaudeProgram.m`: whether a running process is Claude Code's own program, told by what macOS says of it:
  its native build by Anthropic's signature, read from the copy macOS keeps while the program runs (Signature.m, in
  app/shared), so a session goes on counting after an update deletes the version it started with. npm installs that
  same build from 2.1.113 on (`claude.exe`); an older one from npm runs as Node, its title set over its arguments, so
  it's told only by its path or its own record in the registry. Each process is checked once, by its pid and start
  time, but for that last. It says why one isn't, in words for you: an older one from npm, a program signed in Claude
  Code's name that Whozmove couldn't prove is Anthropic's, or another program.
- `app/WhereSeenWorking.m`: which process is each session's own, and the folder it was seen working in, noted as the
  rows are read from every copy in the registry, so a process that only says it's a session is told from the session's
  own when it asks; the rule for who speaks for a session, a plain function (`WhyNotSpeakFrom`); and a session's other
  copies that run Claude Code (`ClaudeCopiesOf`), which open it twice for both rules.
- `app/SwitchHolder.m`: which session in a folder may hold AnswerFor's switches kept for it, from what the system says
  of its process (where it works, what it runs, its parents, the other Claude Code processes there), never what a file
  says, decided in a plain function (`WhyNotHold`); and the folder they're kept for (`KeptFolderOf`).
- `app/ClaudeSessions.m`: the running sessions, from Claude Code's registry (leaving out its own usage check and the
  copies asked side questions, `NoteAsideProcess`), and what
  the hooks recorded of each (a message another session sent as the last prompt: the message, and who sent it, by its name, its address and its session, found when the message is first read if the process that sent it ran then; and when it last edited files where they landed, the row's `workEditedAt`, from `ClaudeEditedAt` in ClaudeCodeFacts, which an older hook's record that doesn't note when gets from the end of its last turn that changed something). A conversation running in more than one process at once (resumed in a second tab while
  it still runs, or open in Claude Desktop and a terminal) is one row: the copy that needs you most, else the one it
  followed already, naming the others, which its card can close.
- `app/Background.m`: the jobs a session still runs in the background after its turn, from its hooks' record, for the
  row's `background`: leaving out the ones that are plainly over though no event said so (its process gone, noted before
  that process started, a shell command once the registry no longer says `shell`, an agent whose own record says it has
  finished), Claude Code's own housekeeping, and Whozmove's own waits: a shell command that is wholly the plugin's
  ask-panel.sh and one of the waits each module gives for its own asks (`BackgroundWaits`, gathered as it launches;
  `ClaudeJobIsOwnWait`, with the script's name in ClaudeCodeFacts), whose row says what it waits on instead. Each says
  whether it holds the next steps and Deploy (its agents, workflows and teammates, and any kind Claude Code adds later,
  as ClaudeCodeFacts.h decides), which the work part waits for, and what to type in the session to stop it.
- `app/Transcripts.m`: what's new in each listed session's transcript, read a little at a time on a queue of its own:
  PR links, the context in use, the mode, when it last moved, its topic (which Claude Code also puts in its terminal
  tab's title), what its replies and its sub-agents' used today (each reply once, by its message id, as Claude Code
  writes a line for each part of a reply, every one with the whole reply's usage); and through `Writings.m` and
  `Edits.m`, what it wrote for you to read and what it edited, its sub-agents' edits and its shell commands' changes
  too, as Claude Code records them. Asked, it reads Claude's reply to words put into the session's prompt
  (`replyTo:of:since:done:`, ReplyAfter): the last reply of the turn whose prompt is exactly those words, from the
  transcript's last 8 MB, kept nowhere. That and a writing the reader asks for (`readWriting:of:done:`) are read at
  once, on a queue of their own, never behind the reads, which take a while for a transcript read from its start.
  What the reads found is kept across restarts, from launch on: a file for each session in Whozmove's folder
  (`reads/<id>.json`, which only this reader writes), with where it had read to in each file and each reader's part
  of the state (`KeptWritings`, `KeptEdits`), written once it has changed, at most every 30 minutes, and as Whozmove
  quits. A session first read after a start goes on from there while it still applies (`WhyNotGoOnFrom`), so a start
  reads only what's new; else it's read from its start. What's kept is pruned once the sessions listed are known, then
  every hour: once its transcript has gone, is another file or is shorter, or its session hasn't been listed for 3
  days.
- `app/AgentDetails.m`: each session's model, effort, mode and context, from the most specific source first (the
  record of the app that keeps it as a conversation, then the hooks', the transcript, where each reply names its model
  and effort, its launch flags, the settings), its context window (`ClaudeContextWindow` in ClaudeCodeFacts, on the
  row as `agent.window`, which the page's ring and the commands module's CompactTime both read), and the Shift+Tab
  cycles it could have.
- `app/Results.m`: a slash command's result in a transcript, and what it says: the value now in effect, whether the
  pick was saved as the default for new sessions, and how a compaction went.
- `app/Prompt.m`: typing a command into a session's prompt through its terminal, keeping your draft (Ctrl+S stashes
  it, and Claude Code puts it back), and when keys may go in at all.
- `app/HookLine.m`: the panel's end of the hooks' line (`hook.sock` in Whozmove's folder): each request, question,
  plan and "Switch model?", asked over a connection the permission hook opens, taken only from a process that runs in
  the session it names (walked up to one the registry lists, `SessionAbove`), and answered only down that connection;
  and the words hook's ask, answered with what BetweenSteps hands it, then closed.
- `app/BetweenSteps.m`: your words held for a session's words hook (AgentBetweenSteps, for a side chat), each handed
  once, and only to a process the session itself started: one level under the process its row follows, or under a
  shell it started (`BetweenStepsHookOf`); a flag in Whozmove's folder (`words-waiting`) there only while some wait,
  so the hook ends at once otherwise. Whether they've been read, and what Claude wrote after them, comes from the
  transcript (`AfterHandedWords`, Transcripts.m). Which sessions run the hook is `HookPartBetweenSteps`
  (PluginInstall.m). `--print-between-steps` is the print mode the tests check.
- `app/ClaudeAside.m`: a question asked on a session's side (AgentAside, for a side chat): its own `claude`, where
  that's where Claude Code is installed, run in its folder as a throwaway copy of its conversation with its model and
  effort (`ClaudeAsideArguments`, ClaudeCodeFacts), three minutes at most, its process kept out of everything read
  from the registry while it runs (`NoteAsideProcess`, ClaudeSessions.m) and ended by its checked pid on Stop, as its
  session ends, or as Whozmove quits; its stream-json read for the answer and how it ended (`ClaudeAsideAnswer`).
  Whether it can be asked now is found without running anything, and kept a while (Claude Code on this Mac, looked
  for once a minute; the session's transcript there, every 10 seconds); whether it's signed in, by asking.
  `--print-aside` is the print mode the tests check.
- `app/Asks.m`: the requests waiting (those on the line, and, shown but never answered, those an old hook leaves in
  `asks/<id>.json`, for a session started before the hooks asked over their line), the answers given in the panel
  (`AskReply`, shared with AnswerFor), and every request held while it's being answered, so no session you allow
  answers it for you then (sent down its line too for one that goes by itself, as its hook holds it off).
- `app/AnswerFor.m`: what a session you allow answers for you in a team member's session. May Send Back Plans, at the
  foot of the mode menu of the session leading the team (Group by Team), kept only in the panel's memory for that
  session's folder (`SwitchLastsWorkspace`), lets it ask with `ask-panel.sh`: `waiting` (the plans it may send back, as
  one line of JSON) and `send-back <id>` (the note on stdin, base64-encoded on the way). Each send-back is checked
  (another session, a member of the team, in the same project as `ProjectRoot` finds it, still waiting, not being
  answered by you this last minute, with a note) and goes down the request's own line as a deny with the note, marked as
  that session's. May Answer Questions, beside it, adds `answer <id>` (the answers on stdin as JSON, base64-encoded),
  and `waiting` then lists questions too, with their options: every question the request asks is answered, each with one
  of its options (several only where it lets several be picked), or written words where it takes them, and goes down the
  line as the question card's own answers would, each marked as that session's choice and as no OK of the user's for
  anything that needs permission. May Approve Plans adds `approve <id> <digest>` (`waiting` then lists each plan with
  what may be done with it and its digest): the plan approved by an allow marked `approvePlan`, the row saying so in
  your move's colour once the plan's result in its transcript says approved, else that it wasn't taken. The member's row
  says so for 30 minutes (`answeredFor`). Kept for the folder, the three are on for whichever session there may hold
  them (SwitchHolder's `whyNot:`): the team file's lead, its process working in that folder as the system reports it
  (`ProcessFolder`), Claude Code's own program signed by Anthropic (the agent's `programOf:`, npm's from 2.1.113 on
  among them; an older one from npm, told only by its path or record, never holds them, and its cause is ClaudeProgram's
  own, `ClaudeProgramCause`), not open as a second copy that's Claude Code's program, started inside no Claude Code
  session (its parents as the system keeps them, each asked `programOf:`, never a record), and the only Claude Code
  session in that folder (the team's members working in folders of their own inside it aside), with a way past the cause
  when there is one (Take Me There, Get Claude Code); May Approve Plans also never for one that might bypass
  permissions. So a new session there, or a cleared one once the team file names it, has them with no press, and
  `notices` says so each time a session and process other than the one they were ticked in holds them, by its terminal
  app and when its process started, kept until you close it, and logged. A restart or a Quit of Whozmove turns the three
  off: the core offers them back by one press at the foot of the mode menu (Allowed's `waitingFor:`, from `ticked.json`,
  which names only the folder and the switch, and only offers), and `notices` lists one notice for each session whose
  switches wait, naming them, the session and its folder, with no button.
- `app/Records.m`: where Claude Code keeps what its sessions were told and read (the agent's AgentRecords, which Keys,
  in the storage module, looks in): the transcripts, its sub-agents' among them, and its tools' long outputs beside
  them, the history of your messages, long pastes, the copies of files its sessions edited, and what it reads into its
  sessions as their instructions (your CLAUDE.md and rules, skills, agents, commands and output styles, your
  organisation's, each project's memory, your plugins', and those of the folders its sessions ran in and every folder
  above, AGENTS.md where there's no CLAUDE.md, with what they import, four hops deep); what each part of them is about
  (its session and project's folder, and whether you sent it, a line you ran with ! among them, a tool read it, its
  output among them, or Claude wrote it, a prompt to a sub-agent among them; a message you queued while Claude worked
  is yours; a compaction's summary is marked, and it, what Claude Code added and what was queued from elsewhere say
  nobody's; whether it holds a picture or a document, which what Claude writes after it may have been read off; and,
  for a copy of a file it edited, the file it copies, as the session's snapshot lines name it), from a line's own
  fields or the folder a file is in; and `claude purge <folder>`, the command that clears a
  project's, which Keys only ever copies for you to run. It reads none of them itself.
- `app/Conversations.m`: every conversation Claude Code keeps (`projects/*/<id>.jsonl`, a plain id's), read on its
  asker's queue and kept by each file's size and date, so hundreds cost little: its project's folder, its title (the
  name you gave it with /rename, else Claude's newest), when it last moved, and where it ran when Whozmove saw it run;
  and the files it's made of (`ConversationFiles`): its transcript, its sub-agents' and tools' folder beside it, the
  copies of files it edited, and Whozmove's own note of it; and whether a path is where one of them would be
  (`IsConversationPlace`), with only the folders they're kept in resolved, so a project folder that's a link to
  somewhere else isn't one. `ClaudeSessions.m` says why an open one can't be ended now
  (`WhyNotEndConversation`, the open-twice card's checks) and ends it (`EndConversation`): told to quit, as closing its
  tab would, only while its registry file still names that session, then waited for, up to 5 seconds.
- `app/DontWait.m`: the sessions that don't wait on you (Don't Wait on Me in a terminal session's mode menu, a switch
  the core keeps, Allowed): a file for each in Whozmove's folder (`dont-wait/<id>.json`, `{since, after}`), written and
  taken away as the switch goes on and off, which the permission hook reads, so a question or a request for your OK
  that no one answers in 5 minutes goes by itself (one left without the switch's record goes as the app opens, as the
  menu shows the switch off there); and which requests to hold off each second, while you're in their
  session's tab, at the Mac and using it (as Focus last found you there), as Claude's own prompt may be half answered
  there, which no hook can see.
- `app/Switches.m`: a model switch the panel makes, noted for the permission hook's PreModelSwitch part
  (`switches/<session>.panel.json`, a note written by anyone else only making the switch the panel's to ask), its
  question while it waits for the panel, and the answer given there, both over the hook's line.
- `app/SettingsFile.m`: putting back the defaults `/model` and `/effort` save, key by key.
- `app/Trust.m`: whether Claude may work in a folder, and recording your yes, where Claude Code and Claude Desktop
  both look.
- `app/ClaudeUsage.m`: your plan's usage, asked of `claude` itself, run for a moment in a folder of its own, and the
  command that signs it in. With no plan's numbers, why, as read (`noPlan`, `UsageNoPlanReason`: signed in, a key
  your shell sets, its sign-in unreadable, or no `claude` found; never a guess at why), for the log. How often it's
  asked, the strip and its Sign in, and what the log says, are the usage module's.
- `app/ClaudeCommand.m`: where `claude` may be, best first (your terminal's PATH, where its installers put it, then
  Claude Desktop's own copies, newest first), and what it runs with: that PATH and the bare essentials, nothing of this
  app's environment. And whether Claude Code is on this Mac at all, found without running anything, not even your
  shell (`ClaudeCodeOnThisMac`: its command where its installers put it, or its sessions' registry), which the install
  module asks before Apple's developer tools (the agent's `onThisMac`).
- `app/PluginInstall.m`: which sessions run a part of the hooks (`SessionHasHookPart`: the model switch's, Don't
  Wait on Me's), as a session runs the hooks it started with, the hooks dated as they're put in place; and the hooks
  put into Claude Code as its plugin (the agent's AgentInstall, which the install module calls as the app opens):
  copied from the app into Whozmove's folder (`plugin`) when their version differs or the folder has gone, then, as
  `claude plugin list --json` finds them, added (the marketplace from that folder, then
  the plugin), brought up to date (a marketplace update, then a plugin update), turned on again at your press, or left
  as they are, each with Claude Code's own command. Try Again puts it all in again from the start: the hooks copied
  whatever their version, then the marketplace and the plugin brought up to date and the list asked again, so Claude
  Code reads them afresh and says how they stand now. A session that started before they went in runs without them
  (`runsWithoutHooks:since:`: its process started before then, and the hooks' record of it is older than that) until
  `/reload-plugins` is typed into it, which loads them without restarting it; its result says whether it took
  (`ReloadedResult`, in Results.m). Between checks, the agent's `hooksStamp` (`HooksStamp`) says when Claude Code last
  wrote its records of its plugins and your settings, from their dates alone, so the install module lists the plugins
  again once one changes rather than on a timer.
- `app/ClaudeCodeFacts.h`: what the module relies on about Claude Code that it could change: where it keeps things, its
  command and what it's run with, the marks its tab titles show while it works, the recorder its voice mode may start
  (else its own process records), how its registry marks a session run from a terminal, what its registry's statuses
  mean (`ClaudeStatus`), which of its background jobs can change files and which are its own housekeeping
  (`ClaudeJobHolds`, `ClaudeJobShown`), where an agent's own record is and when it says it has finished, the
  `claude plugin` commands that keep Whozmove's plugin and the one that reloads it into a
  running session, the files it keeps its plugins' records in (`installed_plugins.json`, `known_marketplaces.json`),
  where Claude Code is installed from, what else it keeps of what was said and read and the command that clears a
  project's, and the model, effort and mode choices. When Claude Code changes, the fix goes here. docs/using/install.md
  ("What it's tested with") names the version they were last checked with.
- `app/ClaudeCodePrints.m`: its print modes, for the tests.
- `page/request-words.js`: plain functions, with no page in them, for what a request is (`askKind`: a command, an
  edit, a big change of 3 or more edits, a question with one pick, several, and so on) and the words about it: Claude's
  line while it waits (`askLine`, the core's `core.agent.askLine`), a file's folder inside its project, the lines a
  change puts in and takes out, a plan's steps, when it goes by itself (`goesWords`, `goesRing`), what an answer is
  called once given, what a session you allow answered for this one (`answeredForWords`), and the plain words for the
  tools it knows (`TOOL_WORDS`). Claude Code's tool names, and how it names a connected app's server (`claude_ai_` and
  `plugin_<plugin>_`), live here and in the cards below, nowhere else on the page; ClaudeCodeFacts.h says so, with the
  version they were checked with.
- `page/agent.js`: what a session's model, mode and context mean (`core.agent`).
- `page/requests.js`: a tool's request and a plan on a row, each kind in a look of its own (Show all, and a big
  change's ‹ ›, kept by ask id; a plan's few lines at a glance through `core.plans`, else its first steps; a plan sent
  back with your notes; while your picks differ, its box waits, saying so, and the reader's box takes and gives back
  what's typed in it, `core.planRowNotes`), your answers to them, and its hooks: the card under
  the chat, held while it's being answered there (`holdAsk`), and the keys on a pressed card.
- `page/questions.js`: Claude's questions, each kind in a look of its own (one pick answered with one press or its
  number key; several picks; several questions, one at a time; a number with − and +; a typed answer), and the answers
  as Claude's question box sends them.
- `page/answered.js`: the line where a card was once you've answered it (not on a chat beside the folded panel until
  the answer is late, so the chat shrinks once, its Claude's line saying what you answered instead: `answeredLine`,
  the core's `core.agent.answeredLine`), and the card for what a session you allow answered for this one
  (`answeredFor`).
- `page/ended.js`: "Stopped · press to carry on" on the row of a session that has stopped, at its work line's start.
- `page/messages.js`: a reply to a message another session sent, known by its session or address, went back there,
  so it never waits on you (`core.repliesElsewhere`).
- `page/requests.css`: those cards' own pieces, on the cards' shared frame (cards.css) and the kit (controls.css).
  `module.json` lists the scripts and the stylesheet for tools/page.sh.
- `plugin/`: Whozmove's hooks, as the Claude Code plugin `whozmove`: `hooks/whozmove-claude.py` (what each session is
  doing, recorded in Whozmove's folder) and `hooks/whozmove-claude-permission.py` (a request asked of the panel over a
  line it opens to it, and the answer passed back down that line; and Claude Code's "Switch model?" for a switch the
  panel made, asked in the panel when Claude Code would ask it), `hooks/whozmove-claude-words.sh` and
  `hooks/whozmove-claude-words.py` (your words from a side chat, asked of the panel as a session's tool calls finish
  or its turn ends, and handed to Claude as the event's additional context; the shell part looks for Whozmove's flag
  first and ends at once while nothing waits), with `hooks/hooks.json` and `.claude-plugin/`.
  `plugin.sh` makes the copy every build carries (tools/bundle.sh), which the app puts into Claude Code as it opens,
  with every module's skills for Claude Code (`modules/<module>/plugin/skills/<name>/`, each copied whole into its
  `skills/`, which sessions find as `whozmove:<name>`; two of the same name stop the build, naming both), the script a
  session asks the panel with (`app/ask-panel.sh`, copied runnable to `scripts/ask-panel.sh`, so a skill names it as
  `${CLAUDE_PLUGIN_ROOT}/scripts/ask-panel.sh` wherever Whozmove is installed; never in a `bin/`, as claude.ai and
  Cowork skip a plugin with one), and a version named after all of it. This module's own skill,
  `plugin/skills/asking-questions/`, is how a session writes a question for you, so its card reads at a glance. The
  session hook records nothing while the app noted in Whozmove's folder (`app`) isn't there.
  [How the pieces fit](../../docs/how-it-works/architecture.md) describes the hooks and their rules.

`tests/test.sh` runs both hooks against a throwaway home folder and compares what they write and print with
`tests/hooks.expected.txt`, again on the Python in Apple's developer tools when python3 is another one, the permission
hook asking a stand-in panel over its line (`tests/stand-in-panel.py`, which mirrors each request into the test's own
folder and passes the test's answers down the line); then it puts the plugin into a stand-in Claude Code for each case
(`--print-plugin-install`), compared with `tests/plugin.expected.txt`; and it runs the real hook from inside a stand-in
session against the panel's own end of the line (`--print-hook-line`), a request naming its own session taken and one
naming another refused, compared with `tests/line.expected.txt`; and what a session you allow may answer for you
(`--print-answer-for`), with the real hook run from inside stand-in team sessions and ask-panel.sh from inside the one
allowed, compared with `tests/answer-for.expected.txt`; and which session holds the switches kept for a folder
(`--print-switch-holder`), with stand-in sessions of `tests/stand-in.c` (a program that runs a shell as its child under
the name it's copied to: claude, node, other) started, closed, cleared and made the lead in turn, and the rule alone
on made-up facts (`WhyNotHold`), compared with `tests/switch-holder.expected.txt`; and what a sample transcript's
replies and its sub-agent's used today (`--print-spent`), read whole, a line at a time and again as if rewritten,
compared with `tests/spent.expected.txt`; and what a sample session's reads keep across restarts (`--print-reads`):
going on from it as the transcript grows reads only what's new and comes to a read from its start, compared with
`tests/reads.expected.txt`, failing when what the sample keeps changes and `kReadsShape` doesn't; and its part of the
page (`tests/page-cases.js`, run with macOS's jsc): what each request is and what Claude's line says, each kind's card,
what a press or a key sends (a press on a card only just up sending nothing), and what shows once it's answered,
compared with `tests/page.expected.txt`. tests/rows.sh checks the rest in its sample home: the rows (`--print-rows`),
when keys may go into each session and the Shift+Tabs its mode menu would type (`--print-mode-moves`), the keys a
command is typed with (`--print-typing`), how a command's result is read (`--print-results`), what the usage strip gets
from Claude Code's answers (`--print-usage`), folder trust (`--print-trust`), what's kept of each terminal session and
what's dropped (`--print-kept`), and which sample sessions' requests are held as you answer them in their tab
(`--print-held`).

Those all read samples written the way Whozmove expects, so none would notice Claude Code changing its files, hooks
or screen. `tests/real.sh` does: it runs a real Claude Code (a version `tests/claude-code.sh` downloads and checks,
`tests/claude-code.txt` pinning the one Whozmove was last checked with) against a stand-in for Anthropic's servers
(`tests/stand-in-api.py`, so it needs no account and calls no model), puts the plugin in with Claude Code's own
commands, and drives it in a pseudo-terminal (`tests/pty-driver.py`) through what the panel does: a reply, a request
for your OK at the panel's own end of the line, a file, a command typed over a draft, a question, a command left
running, a compaction, folder trust, the mode and a plan. What the app then reads is compared with
`tests/real.expected.txt`. Claude Code reads its sign-in from the Mac's keychain whatever home folder it's given, so it
runs only on a throwaway Mac (`--throwaway-mac`: GitHub's runners, virtual Macs); `--stand-in-claude` checks the run's
own pieces anywhere, with a stand-in Claude Code (`tests/stand-in-claude.py`), compared with
`tests/real-stand-in.expected.txt`. test.sh checks that docs/using/install.md names the version claude-code.txt pins.

## Between the page and the app

- The page sends `answerAsk` (`{id, allow, answers, message, stop}`: allow once or deny; a question's answers; a plan
  sent back with your notes, or stopped), which the permission hook passes on, `holdAsk` (`{id}`: a request being
  answered on its card, or a plan in the reader, every 10 seconds at most), which keeps it from a session you allow,
  and gives one that goes by itself at least another minute, and `readWriting` (`{sessionId, id}`),
  which the app answers with the reader's `showWriting(sid, id, {text} or {missing})`, and `closeCopy` (`{sessionId}`,
  from an "open twice" card), which closes the conversation's other copies in terminals, the row's note saying how it
  went.

## Rules

- **Only Claude Code's own program asks the panel in a session's name:** a process counts as a session's for an ask
  only when it has its record in the registry and runs Claude Code's build signed by Anthropic, as macOS keeps that
  signature (ClaudeProgram.m), npm's from 2.1.113 on among them; an older one from npm, run by Node, shows, but
  doesn't ask. A session started from inside another session's commands is refused (the core walks on to the top), and
  an ask that only shows you something comes only from the session's one copy of Claude Code: while the process seen
  as its own runs, only that one, and once that has ended, one working where the session was seen working, or inside
  it (`whyNot:speakFrom:`, WhereSeenWorking.m). Each refusal says why and what to do. A record blocks no one unless
  its process is Node, which could be an older Claude Code from npm, and then it only holds the session's asks back.
- **What the reads found is kept only for you, and only what the transcript says:** in Whozmove's folder (0700, each
  file 0600), written whole and moved in, only by the Transcripts reader, from launch on, never in a print run but
  `--print-reads` in its own folder; only for a session whose id is plain, as it names the file. Read back, every value
  is checked for its kind (PR links for https), its limits and its place, and a kept read that doesn't fit, or whose
  files aren't the ones read, is read afresh and goes. A session's mode, topic and last move are never taken from a kept
  file, nor is where they were found, as finding its tab, the Shift+Tabs its mode menu types and whether it might bypass
  permissions go by them: each is read again from the transcript, back from where the kept read stopped, and a kept file
  that names any of them is refused. A published page's address is kept without a name and password, its query or its
  fragment, where a signed link's token can be. Nothing is kept with anything shaped like a key in it (LooksLikeSecret),
  and what was kept before for that session goes. Whenever what a read finds changes (a part added to a session's state,
  or one found differently), `kReadsShape` in `Transcripts.m` goes up in the same change, so every copy kept the old way
  is read afresh: the module's test fails until it does.
- **A side question runs nothing and saves nothing:** a copy of the session's conversation, only on your press, with no
  settings files read and the one hook it's given refusing every tool, one turn at most, nothing kept by Claude Code,
  and its process kept out of the rows and ended by its checked pid. Only the side chat's question goes in, after
  `kClaudeAsideLine`; the folder and program are the row's own, never a path from the page.
- **Words from a side chat go into a working session only through its words hook,** handed only by the panel's own
  process, down the line the hook opened, to a process that runs in that session (`SessionAbove`) one level under the
  session's own process or under a shell it started (`BetweenStepsHookOf`), each once; otherwise nothing is handed,
  and nothing can add to or change them. No check on whose child a process is can tell the hook from a command the
  session itself runs, so a program it runs while words wait could take them: they'd show as stopped, never as read,
  and never reach another session. Anything running as you can read the session's transcript anyway, so this exposes
  nothing more.
- Only the panel answers a request, down the line the hook opened, which the hook keeps only with the panel's own
  process at the other end; and the panel takes a request only from a process that runs in the session it names. No
  file answers one, so a session can't approve its own request, or another's, by writing one. A session started
  before this runs a hook that asks in files: its requests show on its row, to answer in Claude, and are never
  answered from the panel. A program written to pose as the panel isn't stopped this way: it would have to stop the
  panel, take its socket and run as Whozmove.
- A request is only ever allowed once, never "always allow", and a plan is approved from the panel only by a session
  you allow, with its own switch (May Approve Plans): the panel's answer then carries `approvePlan`, added only by
  AnswerFor's approve (never `AskReply`, which builds the page's answers), and the hook passes on an allow with an empty
  input, as Claude's own prompt does. Claude Code ignores a bare "allow" for a plan, and the hook drops one, and drops
  `approvePlan` for anything but a plan.
- A card on the row takes no press until it has been up long enough to be seen (`justShown`), so one that comes up
  under the pointer isn't answered by it: one press answers a question with one pick. Allow once allows exactly what
  the request asks, all of it, whatever the card shows in part.
- A session you allow answers for you only with its switch on, kept only in the panel's memory for the folder you
  ticked it in and set only by your press in its mode menu (after a restart or a Quit, by your press on Turn Back On,
  never by a file). The team file and Claude Code's records say only which session in that folder holds it, each
  checked against what the system says of its process (in the folder, Claude Code's own signed program, started by no
  session, alone there), never which folder, and a notice says each time a new session holds it; and only as that switch
  says: May Send Back Plans sends a plan back with a note, never
  approves one, and never stops the turn; May Answer Questions answers Claude's questions, checked against their own
  options, never a request for your OK, a plan or a model switch; May Approve Plans approves only the plan as listed,
  by its digest, never one whose file has changed since, from a session whose hooks can't take it, or that might
  bypass permissions (its own strict check: flags, settings files and --settings, refused when it can't tell), and the
  row says approved only once the transcript does. It answers only a member of the team in the team file, in the same
  project, never its own and never one of yours; the team file is the lead's own, so it keeps mistakes out, not that
  session: the switch and the project are the guard. It never answers what you're answering (`heldAt`), and the
  member's row says what was sent back, answered or approved, and by whom.
- A request goes by itself only in a session you turned Don't Wait on Me on for, and never a plan. It only ever turns
  the request down for now, with words that tell Claude you're away, never allows it and never stops the turn; and it
  can't go while you're answering it, on its row or in the session's own terminal, its tab in front with you at the
  Mac (`AsksToHold`): it waits at least a minute past that.
- Keys go into a session's prompt only while it sits idle at its prompt with no request waiting (`WhyNotTypeInto`),
  never while it's paused in its terminal, where they'd go to the shell, and never while its conversation runs in
  another terminal too, where a key could land in the other copy; a registry file that can't be read counts as one. The
  one key that goes in while Claude works is the Backspace that takes out the filler a request left
  (`WhyNotEditDraft`), into the tab the request went into.
- A copy of a conversation is closed only from its "open twice" card, only in a terminal (never Claude Desktop's, nor
  one paused), only while every copy to close sits idle, with no command Claude started still running in the
  background, and no request waits, and only by its own process as the registry lists it then, told to quit as closing
  its tab would (`CloseOtherCopies`); the copy the row follows stays.
- A conversation is ended for Sessions only once you've asked for it to go to the Trash, by the same checks: only in a
  terminal, never one paused, working, asking you, or with its agents or a command still at work, and only by the
  process its registry file names while that file still names the conversation (`EndConversation`); otherwise it's
  left out, saying why. Its files are only listed for the sessions module, which moves them to the Trash; this module
  moves none of them.
- Claude Code's settings hold secrets: they're read with a JSON parser, key by key, and never logged, and written only
  to put back the `/model` and `/effort` defaults, key by key, through JavaScriptCore's JSON so the rest stays as Claude
  Code wrote it.
- Folder trust is recorded only for a folder you trusted on the card. `~/.claude.json` holds your account and more:
  `Trust.m` reads only `projects[<folder>].hasTrustDialogAccepted` from it, with a JSON parser, and never logs it.
  `TrustFolder` writes that one key for that folder, under the lock Claude Code takes to write the file (the folder
  `~/.claude.json.lock`; one 10s old or more is a dead writer's), through JavaScriptCore's JSON so the rest stays as
  Claude Code wrote it, and keeps who may read it. Claude Desktop's own "Trust workspace" button is pressed only for a
  folder the record already trusts. A terminal start's words go in a file only you can read, never on the command
  line, and the file goes once the session has started.
- The plugin's contents decide its version: a changed hook or skill gets a new one, and reaches only sessions started
  after it goes in, or reloaded after it from the panel.
- The hook's PreModelSwitch part decides only a switch the panel noted right before typing `/model`, for that session
  and that model, and each note is read once and lasts 20 seconds. It allows the switch only while the conversation's
  cache isn't warm, or once you've said Switch on the row; Keep (the model) denies it; and with no answer in a minute it
  steps aside, so Claude asks in the terminal. Any other switch, yours in the terminal among them, is left to Claude
  Code. The panel takes a note back once its command is over, and asks on the row only in a session started after the
  hook was in place, as an older one runs the plugin without it.
- A kept session's record holds no prompt or reply (those stay in the hooks' own record), only you may read it, and
  it's written only from launch on, never in a print run. Only sessions started in a terminal (`cli`) that have a
  transcript are kept; one whose process has gone on to another conversation (`/clear`, or `/resume` of another) is
  dropped, as you left it there; and one goes 3 days after its conversation last moved, or once Claude Code no longer
  has its transcript. One is listed only while no other row has it (Claude Desktop's own row comes first) and its
  folder is there, and a press carries it on only in that folder, as the same conversation. If it doesn't come back
  (no tab opens in its terminal, or Claude Code isn't running in it soon after), its row says so and where to look,
  and nothing tries again by itself (parts/focus).
- Claude Code isn't asked about your plan's usage before Apple's developer tools are installed (`askUsage`): `claude`
  may run git, which offers to install them each time until they are. Nor is its plugin put in before then: the
  install module waits for them.
- Whozmove's plugin is kept with Claude Code's own `claude plugin` commands only, never by editing its settings. One
  taken out is left out unless you press Add Back, one turned off stays off unless you press Turn On, and a copy of it
  from a marketplace of your own is left as it is, with no second one beside it.
- The session hook records nothing while Whozmove isn't installed: no app noted in its folder, or one that isn't there
  2 seconds after it's first missed. So nothing more of your sessions is written down once it's gone, and its folder
  isn't made again.

## Facts

What Claude Code does that this module counts on, each with the version it was seen on. Where the code names one, it's
in `app/ClaudeCodeFacts.h` too.

- Claude Code's native build is signed `com.anthropic.claude-code` by Anthropic's Developer ID (team `Q6L2SF6YDW`),
  from its installer, Homebrew's cask and Claude Desktop's own copy alike, with one code directory, hashed with SHA-256
  (2.1.316). An update deletes the version a running session started with, and the session goes on running it, so its
  program has no path and the system's check of its file fails; macOS still keeps the signature it was started with,
  certificates and all. A background session (`claude --bg`) runs under a helper of Claude Code's, under its daemon,
  under launchd, and only the session's own process has a record in the registry; its process works in the session's
  folder. A session's own process works in its folder too, and moves into a worktree with EnterWorktree and back as it
  leaves; a Bash `cd` moves only the command's shell (2.1.316).
- Claude Code only adds lines to a session's transcript and to its sub-agents' records, a compaction included: the
  file stays the same, and what's there isn't written over (2.1.304). So a read can go on from where the last one
  stopped, and the kept reads do, as long as each file is the same one, by its inode and its last bytes read.
- Every prompt records the mode it was sent in, and Claude Code writes a conversation's topic (`aiTitle`) again as it
  goes: the newest mode is usually found near the end of a transcript, and the newest topic within its last few hundred
  KB (2.1.304). So a start reads both back from where a kept read stopped (the mode 16 MB at most, the topic 256 KB),
  rather than keeping them; a topic not found there is looked for in the transcript's last 4 MB once a tab is looked
  for, as for a session the reads haven't reached.
- Since 2.1.270, Claude Code compares a checkout before and after each shell command Claude runs, and puts the lines
  it changed in the command's result (`bashEditDiff`: each file's hunks, whether it was made or deleted, and how many
  more files changed). It does so by default only in auto and bypass permissions modes (`bashEditDiffEnabled` turns it
  on or off), with the lines of 5 files at most, naming the rest. A git command that brings in work from elsewhere
  (a merge, rebase, checkout or stash, or one it doesn't know) isn't counted as the session's own work (`UsesGit` in
  `Edits.m`), as what it brings in was there already; one like `add`, `mv`, `rm` or `apply` is.
- A PostToolBatch hook's `additionalContext` reaches Claude in the very next request, after every tool call in the batch
  has finished, a denied one included, and stays in the conversation from then on; a Stop hook's carries the turn on,
  Claude answering it before the turn ends. Neither runs for a step you stop with Esc. A sub-agent's hook input carries
  its `agent_id`, which the session's own doesn't. The transcript records what a hook added as a
  `hook_additional_context` attachment, with the hook's event, which is how words handed in are known to be read
  (`AfterHandedWords` in `Transcripts.m`) (2.1.304).
- A typed `/model` and the model picker both run PreModelSwitch hooks, once Claude Code has checked the model with its
  servers, which takes 1 to 3 seconds (2.1.304). The hook is told both models and whether the conversation's cache is
  warm; its allow skips Claude's own "Switch model?", and a deny, or a hook that times out, stops the switch. A change
  of effort asks "Change effort level?" with no hook before it, so that one is answered only in the terminal.
- `claude plugin` commands need no sign-in, ask nothing when given no input, and take about half a second of CPU each
  (2.1.302, and 2.1.304 the same): `plugin list --json` gives each plugin's id, version, scope, whether it's on and,
  for one from a folder, that folder and its version. Adding a marketplace that's there already succeeds ("already on
  disk"); an update picks up a folder marketplace's new version; and with the folder gone, the plugin keeps its
  version but lists a `cache-miss` error until the folder is back. So the plugins are listed again only when Claude
  Code's records of them change (`hooksStamp`), not on a timer.
- `claude --resume <id>` works only in the folder the conversation ran in, and only while Claude Code keeps its
  transcript (`cleanupPeriodDays`, 30 by default). A plain resume of one still running elsewhere starts a second
  process under the same id, both writing one transcript. Each process has a registry file in `~/.claude/sessions`,
  rewritten in place with the new id on `/clear` or a `/resume` of another, and gone when it exits; `claude -p`
  registers as `sdk-cli`, never as a terminal's (2.1.302).
- `claude -p --resume <id> --fork-session --no-session-persistence` answers from a copy of a conversation, even one
  whose own process is mid-step (its unfinished tool call is closed as interrupted), and saves nothing: no transcript,
  no change to `~/.claude.json`. While it runs it registers as an `sdk-cli` session in that folder, and is gone after.
  Its first request starts as the conversation's own last one did, byte for byte up to that request's last cache mark,
  but for the billing line at the system prompt's start (`cc_entrypoint=sdk-cli` where a terminal's says `cli`) and a
  few beta flags. `--max-turns 1` doesn't keep a tool from running: a tool an allow rule lets through runs before the
  run ends (`error_max_turns`), an MCP tool even with `--tools ""`, and `echo` and a background agent even with no
  allow rules. With `--setting-sources ""` no allow rules, plugins, their hooks or MCP servers load, and a PreToolUse
  hook passed in `--settings` that exits 2 is the only hook, and refuses every tool, while the tool list stays the
  session's. Settings files' `env` isn't read then either, so a sign-in or gateway kept only there isn't found
  (2.1.304, against a stand-in API on a virtual Mac).
- A session signed in with a Claude plan marks its cache for an hour (`ephemeral_1h_input_tokens` in a reply's
  usage), so a conversation stays cached while its session works on one long step (2.1.304).
- While Claude works, its tab's title starts with ◐ and ◑ in turn, about once a second, and with ✳ the rest of the
  time; a process sent SIGTERM shuts down as it does when its tab is closed (2.1.302).
- A session's registry file holds its name and where the name came from (`nameSource`): a stand-in made from the
  folder's name at the start, one Claude gives it from a plan you approve, yours from `/rename`, one a hook returns
  (`sessionTitle`), or one changed to stay unique among the sessions running on the Mac; a name given at launch has no
  source. The tab shows the topic Claude writes in the transcript instead. Whozmove shows the name, else the folder,
  and reads the topic only to find the session's terminal tab (2.1.302).
- A permission request carries no `tool_use_id`, so the hook finds the call in the transcript by its tool and input,
  counting only `assistant` lines, as later `api-request-blob` lines repeat calls. A plan's request holds the plan
  file's text, read again, so it differs from the transcript once the file is edited; the plan files are in
  `~/.claude/plans`, whatever `plansDirectory` says. The registry says idle only while no prompt of the session's is
  up, so idle after a request means its prompt has gone (2.1.304).
- A hook's deny reaches Claude with its message exactly as written, and counts for that one call: no rule is saved.
- A plan is approved from a hook only by an allow with an empty `updatedInput`; the session then goes back to the mode
  it planned from, and the plan file isn't written again (2.1.304).
- Claude Code runs sub-agents in the background, and asks the permission hook about a sub-agent's request before it
  shows its own prompt, so a hook that held it would hide it from the terminal: the hook steps aside for sub-agents
  (2.1.302).
- A Stop hook is told every job the session still runs or has waiting in the background (`background_tasks`, each
  with its id, a label for its type, its status and Claude's description of it, and a shell command's command line),
  so a session that's done can be told from one waiting for its background work to wake it; SubagentStop is told
  the same, and fires as any sub-agent ends, one in the background or one interrupted among them. The types are
  `subagent`, `workflow`, `teammate`, `shell`, `monitor`, `MCP task` and `cloud session`, and Claude Code's own
  `dream`, `auto-mode scan` and `memory import`. A job started in the background answers its tool call at once: an
  agent with `async_launched` and its `agentId`, a shell command with its `backgroundTaskId`, also for one moved to
  the background part-way through. The registry's `shell` status counts only shell commands, never agents. Each
  agent's own record beside the transcript (`subagents/agent-<id>.meta.json`) says `finished` once it's done. When a
  job ends, Claude is handed its result as a new turn (a `<task-notification>` prompt) (2.1.304, and the stop hooks'
  list the same in 2.1.308).
- A hook marked async can't turn anything down, so the permission hook is the one that runs synchronously (2.1.304).
- A `claude` started from inside a session takes on `CLAUDE_CODE_CHILD_SESSION`, which turns its transcript off, and
  the session's messaging connection. So Whozmove runs `claude` with a bare environment (`ClaudeCommand.m`),
  with none of them in it (2.1.304).
- Claude Code doesn't record which session started a `claude` in another terminal (2.1.304), so a team is known only
  from its team file (the team module), never worked out from the sessions.
