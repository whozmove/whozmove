# Claude Code

The agent that runs the sessions the panel lists: its running sessions and what its hooks recorded of each, what's new
in each session's transcript (its PRs, what it wrote for you to read, what it edited, its context, its mode), each
session's details, the words of the commands the panel sends (`/model`, `/effort`, `/plan`, `/compact`) and what their
results say, typing a command into a session's prompt while keeping your draft, the requests waiting for your answer in
the panel, your plan's usage asked of `claude`, whether Claude may work in a folder, a new session's command, and its
hooks plugin.

## Its pieces

- `app/ClaudeCode.m`: its face for the core (contracts/Module.h), and the agent it is (contracts/Agent.h), with every
  one of the agent's protocols: AgentWork, AgentCommands, AgentPrompt, AgentUsage and AgentStarts. Its part of each
  row: in the first phase, it starts reading what's new in the transcripts (every 10s) and whether Claude Code records
  shell commands' changes in the sessions' folders (every 5s); then each session's last message and writings; then its
  details, with a pick from the panel the session hasn't confirmed yet; and once the rows are whole, it forgets the
  launch flags of sessions that have ended.
- `app/ClaudeSessions.m`: the running sessions, from Claude Code's registry (leaving out its own usage check), and what
  the hooks recorded of each.
- `app/Transcripts.m`: what's new in each listed session's transcript, read a little at a time on a queue of its own:
  PR links, the context in use, the mode, when it last moved, its topic (which Claude Code also puts in its terminal
  tab's title); and through `Writings.m` and `Edits.m`, what it wrote for you to read and what it edited, its
  sub-agents' edits and its shell commands' changes too, as Claude Code records them.
- `app/AgentDetails.m`: each session's model, effort, mode and context, from the most specific source first (the
  record of the app that keeps it as a conversation, then the hooks', the transcript, its launch flags, the
  settings), and the Shift+Tab cycles it could have.
- `app/Results.m`: a slash command's result in a transcript, and what it says: the value now in effect, whether the
  pick was saved as the default for new sessions, and how a compaction went.
- `app/Prompt.m`: typing a command into a session's prompt through its terminal, keeping your draft (Ctrl+S stashes
  it, and Claude Code puts it back), and when keys may go in at all.
- `app/Asks.m`: the requests the permission hook leaves for the panel, and the answers given there.
- `app/SettingsFile.m`: putting back the defaults `/model` and `/effort` save, key by key.
- `app/Trust.m`: whether Claude may work in a folder, and recording your yes, where Claude Code and Claude Desktop
  both look.
- `app/ClaudeUsage.m`: your plan's usage, asked of `claude` itself, run for a moment in a folder of its own, and the
  command that signs it in. How often it's asked, the strip and its Sign in are the usage module's.
- `app/ClaudeCodeFacts.h`: what the module relies on about Claude Code that it could change: where it keeps things,
  its command and what it's run with, and the model, effort and mode choices. When Claude Code changes, the fix goes
  here. The README's "Tested with" names the version they were last checked with.
- `app/ClaudeCodePrints.m`: its print modes, for the tests.
- `page/agent.js`: what a session's model, mode and context mean (`core.agent`); `page/requests.js`: a request, its
  questions or a plan on a row, and your answers. `module.json` lists them for tools/page.sh.
- `plugin/`: Whozmove's hooks, as the Claude Code plugin `whozmove`: `hooks/whozmove-claude.py` (what each session is
  doing, recorded in Whozmove's folder) and `hooks/whozmove-claude-permission.py` (a request left for the panel, and
  its answer passed back), with `hooks/hooks.json` and `.claude-plugin/`. `plugin.sh` makes the copy install.sh and
  build.sh put in place, with a version named after the hooks' contents. CONTRIBUTING describes the hooks and their
  rules.

`tests/test.sh` runs both hooks against a throwaway home folder and compares what they write and print with
`tests/hooks.expected.txt`. tests/rows.sh checks the rest in its sample home: the rows (`--print-rows`), when keys may
go into each session and the Shift+Tabs its mode menu would type (`--print-mode-moves`), the keys a command is typed
with (`--print-typing`), how a command's result is read (`--print-results`), what the usage strip gets from Claude
Code's answers (`--print-usage`), and folder trust (`--print-trust`).

## Between the page and the app

- The page sends `answerAsk` (`{id, allow, answers, message, stop}`: allow once or deny; a question's answers; a plan
  sent back with your notes, or stopped), which the permission hook passes on, and `readWriting` (`{sessionId, id}`),
  which the app answers with the reader's `showWriting(sid, id, {text} or {missing})`.

## Rules

- A request is only ever allowed once, never "always allow", and a plan is never allowed from the panel (Claude Code
  ignores a hook's approval of one): it's sent back with your notes, or stopped.
- Keys go into a session's prompt only while it sits idle at its prompt with no request waiting (`WhyNotTypeInto`). The
  one key that goes in while Claude works is the Backspace that takes out the filler a request left
  (`WhyNotEditDraft`).
- Claude Code's settings hold secrets: they're read with a JSON parser, key by key, and never logged, and written only
  to put back the `/model` and `/effort` defaults, key by key, through JavaScriptCore's JSON so the rest stays as Claude
  Code wrote it. Its state file holds your account: only a folder's trust is read from it, and written only for a
  folder you trusted on the card, under the lock Claude Code takes.
- The plugin's contents decide its version: a changed hook gets a new one, and reaches only sessions started after it
  goes in.
