# Send

Words into a session, through the app it runs in (its host) and the agent that runs it: typed into its terminal tab
while keeping your draft, or written in its conversation's message box; one of the agent's own commands typed in the
same way, its result watched for; and why words can't go in now, worded as the panel's menus, cards and steps say it,
with a button past the terminal's own reason where there is one.

## What it owns

- `app/Send.h`, `app/Send.m`: `Send`, made once by the core (`Core`'s `send`); a session's reach (`SessionReach`, what
  the wording asks of the hosts and the agent, each found once, when first asked); `say:`, `ask:` and `run:` (words, as
  a message typed once and sent, with no note on its row and nothing of them logged, never words Claude would take as a
  command (`WordsRunACommand`); words with the row saying it's asking, built on it; and one of the agent's commands,
  each only while the session is idle); `takeWayPast:`; `sayBetweenSteps:`, `takeBack:` and `sendNow:` (words for a
  session that may be at work, as a side chat sends them: while it works, held for its agent's hook, which hands them in
  between its steps (the agent's `AgentBetweenSteps`), or, for a session without one, held until its turn ends; typed in
  once it's idle, by themselves only where it's safe (`ReachGoesByItself`, asked again before each key: `stillAway:`),
  else for your press; each told on as it
  goes: held, handed, typing, typed, read once the session's own record shows them, or why not); and the words for why
  not (`WhyNoTab`, `WhyNoWords`, `WhyNoAsk`, `WhyTerminalRefuses`, `WhyNotSendTo`, `WayPast`, `kStillChanging`).
- `part.json`: who it talks to, and what it provides.

## Who it talks to

It talks to the core: the hosts and agents (contracts' `Host.h`, `Agent.h`); to the list, for the rows (`Rows`,
parts/list); and to the bridge, for the page (`Page`, parts/bridge), for a row's note and its step. The modules that put
words in or say why they can't import its header: Claude Code's prompt, the commands module, the next steps (git),
the install module's reloads, side chat and Compact at Breaks.

## Rules

- **Typing into a session only when it's safe:** idle at its prompt, no request waiting, and never where a key could
  land in another copy or another session (a conversation open twice in terminals, a tab it can't be sure is its own).
- **Nothing more goes in while a change from the panel is still going in** (`kStillChanging`), as a key meant for the
  next command could answer what Claude asks about that one.
- **Held words go in by themselves only where it's safe:** into a terminal that isn't the app in front at all, never
  the session you're on, and never Claude Desktop, which comes forward only for your press (`WordsGoByThemselves`).
  Its terminal is the one the panel would type into (`ReachGoesByItself` and `ReachTerminalInFront`, from the reach's
  `typing`), never only an app that keeps it as a conversation of its own (`hostHolding:`, which no terminal answers),
  and Side Chat's and One Task's held words ask these two, so one rule decides for both. Words going in by themselves
  stop at the next key once you've come to the session (`stillAway:`, as `say:`'s `also:`).
- **Every reason offers a way forward where there is one:** a button past the terminal's own reason (`WayPast`), on
  the menu, card or step's note that says it.
