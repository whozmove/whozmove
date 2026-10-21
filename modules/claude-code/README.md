# Claude Code

The agent that runs the sessions the panel lists: its running sessions, its terminal sessions kept once they've ended,
and what its hooks recorded of each, what's new
in each session's transcript (its PRs, what it wrote for you to read, what it edited, its context, its mode), each
session's details, the words of the commands the panel sends (`/model`, `/effort`, `/plan`, `/compact`) and what their
results say, typing a command into a session's prompt while keeping your draft, the requests waiting for your answer in
the panel, your plan's usage asked of `claude`, whether Claude may work in a folder, a new session's command and an
ended one's, and its hooks plugin.

## Its pieces

- `app/ClaudeCode.m`: its face for the core (contracts/Module.h), and the agent it is (contracts/Agent.h), with every
  one of the agent's protocols: AgentWork, AgentCommands, AgentPrompt, AgentUsage and AgentStarts. Its part of each
  row: in the first phase, it starts reading what's new in the transcripts (every 10s) and whether Claude Code records
  shell commands' changes in the sessions' folders (every 5s); then each session's last message and writings; then its
  details, with a pick from the panel the session hasn't confirmed yet; and once the rows are whole, it forgets the
  launch flags of sessions that have ended, and keeps each running terminal session's record (`KeptSessions.m`).
- `app/KeptSessions.m`: the terminal sessions it ran lately, kept so their rows stay once they've ended, as Claude
  Desktop keeps its conversations: a file for each in Whozmove's folder (`conversations/<id>.json`: its folder, name,
  the terminal it runs in, its process, its transcript and when its conversation last moved), written on a queue of
  its own when one changes, from launch on; read back on the rows' queue as rows with status `closed` and no process,
  for 3 days after the conversation last moved; pruned once the sessions running now are known, then every hour. A
  press on one runs the agent's `resumeCommand:` (`claude --resume <id>`) in a new tab, which the core's Focus opens.
- `app/ClaudeSessions.m`: the running sessions, from Claude Code's registry (leaving out its own usage check), and what
  the hooks recorded of each. A conversation running in more than one process at once (resumed in a second tab while
  it still runs, or open in Claude Desktop and a terminal) is one row: the copy that needs you most, else the one it
  followed already, naming the others, which its card can close.
- `app/Transcripts.m`: what's new in each listed session's transcript, read a little at a time on a queue of its own:
  PR links, the context in use, the mode, when it last moved, its topic (which Claude Code also puts in its terminal
  tab's title); and through `Writings.m` and `Edits.m`, what it wrote for you to read and what it edited, its
  sub-agents' edits and its shell commands' changes too, as Claude Code records them.
- `app/AgentDetails.m`: each session's model, effort, mode and context, from the most specific source first (the
  record of the app that keeps it as a conversation, then the hooks', the transcript, where each reply names its model
  and effort, its launch flags, the settings), and the Shift+Tab cycles it could have.
- `app/Results.m`: a slash command's result in a transcript, and what it says: the value now in effect, whether the
  pick was saved as the default for new sessions, and how a compaction went.
- `app/Prompt.m`: typing a command into a session's prompt through its terminal, keeping your draft (Ctrl+S stashes
  it, and Claude Code puts it back), and when keys may go in at all.
- `app/Asks.m`: the requests the permission hook leaves for the panel, and the answers given there.
- `app/Switches.m`: a model switch the panel makes, noted for the permission hook's PreModelSwitch part, its
  question while it waits for the panel, and the answer given there.
- `app/SettingsFile.m`: putting back the defaults `/model` and `/effort` save, key by key.
- `app/Trust.m`: whether Claude may work in a folder, and recording your yes, where Claude Code and Claude Desktop
  both look.
- `app/ClaudeUsage.m`: your plan's usage, asked of `claude` itself, run for a moment in a folder of its own, and the
  command that signs it in. How often it's asked, the strip and its Sign in are the usage module's.
- `app/ClaudeCodeFacts.h`: what the module relies on about Claude Code that it could change: where it keeps things, its
  command and what it's run with, the marks its tab titles show while it works, how its registry marks a session run
  from a terminal, and the model, effort and mode
  choices. When Claude
  Code changes, the fix goes here. The README's "Tested with" names the version they were last checked with.
- `app/ClaudeCodePrints.m`: its print modes, for the tests.
- `page/agent.js`: what a session's model, mode and context mean (`core.agent`); `page/requests.js`: a request, its
  questions or a plan on a row, and your answers. `module.json` lists them for tools/page.sh.
- `plugin/`: Whozmove's hooks, as the Claude Code plugin `whozmove`: `hooks/whozmove-claude.py` (what each session is
  doing, recorded in Whozmove's folder) and `hooks/whozmove-claude-permission.py` (a request left for the panel, and
  its answer passed back; and Claude Code's "Switch model?" for a switch the panel made, asked in the panel when
  Claude Code would ask it), with `hooks/hooks.json` and `.claude-plugin/`. `plugin.sh` makes the copy install.sh and
  build.sh put in place, with a version named after the hooks' contents. CONTRIBUTING describes the hooks and their
  rules.

`tests/test.sh` runs both hooks against a throwaway home folder and compares what they write and print with
`tests/hooks.expected.txt`. tests/rows.sh checks the rest in its sample home: the rows (`--print-rows`), when keys may
go into each session and the Shift+Tabs its mode menu would type (`--print-mode-moves`), the keys a command is typed
with (`--print-typing`), how a command's result is read (`--print-results`), what the usage strip gets from Claude
Code's answers (`--print-usage`), folder trust (`--print-trust`), and what's kept of each terminal session and what's
dropped (`--print-kept`).

## Between the page and the app

- The page sends `answerAsk` (`{id, allow, answers, message, stop}`: allow once or deny; a question's answers; a plan
  sent back with your notes, or stopped), which the permission hook passes on, and `readWriting` (`{sessionId, id}`),
  which the app answers with the reader's `showWriting(sid, id, {text} or {missing})`, and `closeCopy` (`{sessionId}`,
  from an "open twice" card), which closes the conversation's other copies in terminals, the row's note saying how it
  went.

## Rules

- A request is only ever allowed once, never "always allow", and a plan is never allowed from the panel (Claude Code
  ignores a hook's approval of one): it's sent back with your notes, or stopped.
- Keys go into a session's prompt only while it sits idle at its prompt with no request waiting (`WhyNotTypeInto`),
  never while it's paused in its terminal, where they'd go to the shell, and never while its conversation runs in
  another terminal too, where a key could land in the other copy; a registry file that can't be read counts as one. The
  one key that goes in while Claude works is the Backspace that takes out the filler a request left
  (`WhyNotEditDraft`), into the tab the request went into.
- A copy of a conversation is closed only from its "open twice" card, only in a terminal (never Claude Desktop's, nor
  one paused), only while every copy to close sits idle and no request waits, and only by its own process as the
  registry lists it then, told to quit as closing its tab would (`CloseOtherCopies`); the copy the row follows stays.
- Claude Code's settings hold secrets: they're read with a JSON parser, key by key, and never logged, and written only
  to put back the `/model` and `/effort` defaults, key by key, through JavaScriptCore's JSON so the rest stays as Claude
  Code wrote it. Its state file holds your account: only a folder's trust is read from it, and written only for a
  folder you trusted on the card, under the lock Claude Code takes.
- The plugin's contents decide its version: a changed hook gets a new one, and reaches only sessions started after it
  goes in.
- The hook's PreModelSwitch part decides only a switch the panel noted right before typing `/model`, for that session
  and that model, and each note is read once and lasts 20 seconds. It allows the switch only while the conversation's
  cache isn't warm, or once you've said Switch model on the row; Cancel denies it; and with no answer in a minute it
  steps aside, so Claude asks in the terminal. Any other switch, yours in the terminal among them, is left to Claude
  Code. The panel takes a note back once its command is over, and asks on the row only in a session started after the
  hook was in place, as an older one runs the plugin without it.
- A kept session's record holds no prompt or reply (those stay in the hooks' own record), only you may read it, and
  it's written only from launch on, never in a print run. Only sessions started in a terminal (`cli`) that have a
  transcript are kept; one whose process has gone on to another conversation (`/clear`, or `/resume` of another) is
  dropped, as you left it there; and one goes 3 days after its conversation last moved, or once Claude Code no longer
  has its transcript. One is listed only while no other row has it (Claude Desktop's own row comes first) and its
  folder is there, and a press carries it on only in that folder, as the same conversation.
