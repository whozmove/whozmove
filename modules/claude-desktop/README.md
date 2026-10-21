# Claude Desktop

Claude Desktop's conversations in the panel: running ones and the ones it keeps that aren't running (listed as
closed), the one it shows marked as the one you're on, a row's press opening its conversation, commands written in its
message box and sent, new conversations started there with your words, and its "Switch model?" asked in the panel. And
Claude's page on the panel's back, for Claude as a whole, on every Mac: Claude Code's settings go there too, and
there you say whether Claude Desktop's sessions are tracked at all.

## Its pieces

- `app/ClaudeDesktop.m`: its face for the core (contracts/Module.h), and the host it is (contracts/Host.h): a
  ConversationHost, an app that keeps sessions as conversations of its own. It holds the rows Claude Code's registry
  marks as Claude Desktop's. As the rows are read, on the sessions' queue, it adds what Claude knows that Claude Code
  doesn't (its own record of each conversation: when it last did something and was last looked at, and its model, effort
  and mode), the conversations it keeps that aren't running, and which one it shows now (from its files and its log,
  whichever is newer). It lists Claude for the panel's back on every Mac (`appEntries`), as the page for Claude as a
  whole, where the Claude Code module's settings go too (the install module's card for Whozmove's plugin), with what
  Whozmove does with Claude Code. While Claude Desktop is on this Mac, its page has **Track Claude Desktop app
  sessions** (`trackClaudeDesktop`, on until you turn it off) and, while that's on, the Accessibility permission its
  message box needs; while it isn't, a card offers **Get Claude Desktop**, its download page. It looks for Claude
  Desktop as the app starts and every 10 seconds after (`tracked`, the host's: its sessions are tracked while it's on
  this Mac and the switch is on). A print run never looks, so it lists as if Claude Desktop were here and tracked.
- `app/DesktopConversations.m`: its conversation files, each parsed only when it changes. `app/DesktopLog.m`: its log,
  which says at once when it shows another conversation, and which conversations it starts.
- `app/DesktopMessageBox.m`: a conversation's message box: a command written there through the Accessibility API
  (app/shared/Accessibility.h) and sent with its Submit button, and the caret put in it when a row opens its
  conversation.
- `app/DesktopNewConversation.m`: a new conversation with your words: opened with its link, the folder chosen in
  Claude (its environment, among the recent ones its page lists, or on its older screen in its folder list), and Send
  pressed once Claude has it ready.
- `app/DesktopSwitchModel.m`: "Switch model?", which Claude asks before re-reading a cached conversation.
- `app/ClaudeDesktopFacts.h`: what the module relies on about Claude Desktop that it could change: its app id, where to
  get it, its files and its log's lines, its links, its environments (its presets file), and how its window's controls
  are labelled. When
  Claude Desktop changes, the fix goes here. The README's "Tested with" names the version they were last checked with.
- `page/claude-desktop.js`: how a row of one of its conversations is named (its icon, "Claude Desktop", "in Claude",
  "Open in Claude now"), and its scratch conversations' group. `module.json` lists it for tools/page.sh. "Switch
  model?" is asked in the panel by the commands module's card.

tests/rows.sh checks its rows in a sample home (`--print-rows`), and the starts module's tests the links it starts
conversations with (`--print-starts`).

## Between the page and the app

- "Switch model?" is the commands module's card on the row (its `switchAsk`), before `/model` goes to a conversation
  whose cache is warm, or when Claude asks anyway. The card sends your answer back as `switchAnswer`,
  `{sessionId, ok, never}`, which the commands answer (they send `/model`, or pass the answer on to Claude's own
  box).

## Rules

- While Claude Desktop's sessions aren't tracked (its switch is off, or it isn't on this Mac), the core lists none of
  them and doesn't ask for its rows, so its files and its log aren't read, and New Conversation offers only the
  terminal.
- Text goes into Claude only while the conversation is idle and its message box is empty, through the Accessibility
  API, never as keystrokes. The one exception is a Return when Claude shows no Submit button, and only while Claude is
  in front (`submit:` in DesktopMessageBox.m).
- A new conversation's first message is sent with Claude's Send button, never a key, only in the conversation it has
  just opened with your words, once Claude shows its page, and only while its box holds exactly those words and Claude
  shows the folder it's for: its environment, or on its older screen its folder button (DesktopNewConversation.m). The
  words are never taken out of Claude's box.
- Claude's presets file, which says which environment is which folder, is only read, never written: an environment
  is chosen as you would choose it, among the recent ones its page lists.
