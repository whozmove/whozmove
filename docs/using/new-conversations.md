# Starting a conversation

Write what Claude should do, choose where, and it starts in Claude Desktop, Ghostty or iTerm2.

<p align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="../readme/start-dark.webp"><img src="../readme/start-light.webp" width="100%" alt="A new conversation typed into the card, with #gift-cards making a new worktree; the card turns into its row"></picture></p>

## The card

Start a conversation from the ＋ in the panel's header, a project's ＋, or ⌃⌥N from any app: a card opens at the top
of the panel, under the header; write what Claude should do and press ⌘Return (Return starts a new line). The card is
shaped like the row it becomes. Once started, the card turns into that row and moves down to its place in the list,
where it says it's starting until Claude lists the conversation. Close a card before it starts and the next one comes
back as you left it: your words, where it starts and the app.

## Where it starts

Chips under your words say where it starts: the project (that of the session you're on, at first) and, in a git
repository, where in it. Type **@** in your words, or press the project's chip, to choose another project (or any
folder), and the line under the box says where it runs.

In a git repository, type **#** (or press the branch's chip) to choose where in it: its own folder, a worktree that's
there, or a new worktree, a folder of its own, for a branch that's there or a new branch named from your words
(**#name** names it, and **#name from release** starts it from that branch, else from the repo's main branch as this
Mac has it, which it then follows).

- A new worktree is in the worktree colour, with the branch it starts from beside it; anything in a worktree starts in
  a terminal.
- Nothing ever switches the branch of a folder in use: a branch is only checked out in a new folder.
- When another agent is at work in the project's folder, or changes there aren't committed, the card says so, with
  **Use a new worktree**.
- A new worktree goes in a folder beside the repo, named after it (`~/code/shop-worktrees` for `~/code/shop`), never
  inside it, or in a folder you choose from the line under the box, kept for that repo.

## A ticket

After where it starts, the **Ticket** chip gives the conversation a ticket from Jira: find one as you type, paste its
key or link, or create one, talked through with Claude and made only once you press Create Ticket on its row; or sign
in with Atlassian first. A ticket's link pasted into your words becomes the chip by itself.
[Tickets](tickets.md) has the rest.

### Where a ticket starts

With a ticket on the chip, the card starts it in a worktree of its own, named after its key (PAY-142 in
**pay-142**), so two tickets never work in the same copy of your files, and starts it in your terminal, where
worktrees start. The line under the box says so ("PAY-142's own folder: ~/code/shop-worktrees/pay-142"), and, with
Claude Desktop picked on the card, that worktrees start in your terminal; **Use shop** starts it in the project's own
folder instead, in Claude Desktop when that's the one picked. A ticket you've started before carries on in its
worktree, and one with a branch of its name but no folder gets it in a new folder.

The first time you give a ticket in a git project, a short guide takes the line's place and asks how that project's
tickets should open: in **its own worktree** (recommended), **by** one of its tickets' **fields** (offered only when
one's options match the project's folders by name: a Team field whose checkout option matches `shop-checkout`, say),
or **in the project itself**. Each choice says where this ticket would open. **Start** starts it the lit way and keeps
that way for the project; **Not Now** starts this one in the project's folder, and the guide comes back next time; in
a folder Claude hasn't worked in, Not Now only puts the guide away, and Trust and Start is still yours to press.
**Esc** only puts the guide away, starting nothing, and the card shows the project's folder. Settings ▸ Tickets
changes a project's way later.

- A ticket a conversation already works says "PAY-142 is being worked in pay-142", with **Go to It**, which opens that
  conversation as pressing its row does, carrying an ended one on. Start stays, for a second conversation if you mean
  one.
- Where another ticket's conversation works where this one would start, one notice says so ("PAY-139 is being worked
  here. Two tickets in one folder can clash."), with **Use a new worktree**, which gives this ticket its own.
- With no terminal, the ticket starts in the project's folder, and the line says why. Outside git there's nothing to
  choose, and the card starts it there as it would any conversation.
- By a field, a ticket with no option there, an option with no folder yet, its folder gone, or a ticket Jira couldn't
  read gets its own worktree for now, and the line says which, with **Set It**, **Sign In** or **Try Again** where
  there's one. While its option is read, Start waits.
- Your own pick of where (**@**, **#**, Use <project>) always wins over the ticket's, and taking the ticket off puts
  where it starts back as it was.

## The app it starts in

The Start button shows the app it starts in, its icon and, once you've written something, its name, saying **Start in
Claude** while you hold ⌘; the arrow beside it switches between Claude Desktop, Ghostty and iTerm2 (those on your
Mac), and the next card starts with the one you chose last. With **Track Claude Desktop app sessions** off, on Claude's
page on [the panel's back](the-back-and-look.md), new conversations start only in a terminal.

- **In Claude Desktop** your words go into the new conversation's message box, Whozmove chooses the folder's
  environment among the recent ones Claude lists (when Claude hasn't already) and presses Send once Claude shows it.
  This needs the Accessibility permission; without it, if the folder's environment isn't among Claude's recent ones,
  or if Claude doesn't take the press, your words wait there for you to choose it and send. If Claude starts it in
  another folder anyway, the row follows it there and says so.
- **In Ghostty or iTerm2**, a new tab runs `claude` with them.

## A folder Claude hasn't worked in

A folder Claude hasn't worked in before is asked about on the card (**Trust and start**), so neither Claude Desktop nor
Claude Code stops to ask again.

## ⌃⌥N

⌃⌥N opens the card from any app, and **New Conversation** in Whozmove's menu in the menu bar does the same. **New
Conversation with ⌃⌥N**, in Settings on the panel's back, turns it off for other apps. While the panel is turned over,
⌃⌥N turns it back to start a conversation.

[All of Using Whozmove](README.md) · [Back to the README](../../README.md)
