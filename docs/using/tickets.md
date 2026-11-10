# Tickets

Give a conversation one ticket from Jira, and it works that ticket by its own next steps, what it's part of and its
board. Its row shows the ticket while it works. Or have it make a new ticket, talked through with you and shown whole
for your yes before it's made in Jira.

## Signing in

Jira's page on [the panel's back](the-back-and-look.md), or the Ticket chip's list on the new conversation card, says
**Sign In with Atlassian**. Atlassian's own page opens in your browser: pick your site there and press Accept. The
browser's tab then says "Signed in. You can close this tab.", and the panel says which site you're signed in to.

- **Signing in** waits for Atlassian's page, with **Cancel**.
- **Blocked by an admin:** a Jira site's admin can keep apps like Whozmove from signing in. The panel says so, with
  **Copy What to Ask**, the words to send them; they can allow it once, for everyone.
- **Run out:** a sign-in not used for 90 days runs out. A line under the header says so, with **Sign In Again**.
- **After an update:** macOS gives the sign-in only to the build of Whozmove that kept it, so the first time an updated
  Whozmove needs it, the panel says so, with **Allow**. Press it, then **Always Allow** in macOS's box. Nothing asks by
  itself: macOS's box only ever follows your press.
- **Changed by another app:** a sign-in kept on this Mac that another app could read, or changed since Whozmove kept
  it, is never used. The panel says so, with **Sign In Again**, which keeps a new one only Whozmove can read.
- **Reading only:** a sign-in that may only read, as Atlassian says when a move is turned away, still finds and reads
  tickets. Jira's page says "Sign in again to let Whozmove move tickets", with **Sign In Again**.
- **Sign Out**, on Jira's page, forgets the sign-in.

## Giving a conversation a ticket

On the [new conversation card](new-conversations.md), after where it starts, press the **Ticket** chip. Its list,
under your words, has a line to type words, a ticket's key (PAY-142) or its link, and the tickets found: each with its
key, its title, where it stands and its board, and its site when you're signed in to more than one, then **Create a
ticket**, always last. With nothing typed, it shows your own open tickets. **↑↓** and **Return** pick one, and **Esc**
closes the list.

A ticket's link pasted into your words becomes the chip by itself. The chip then shows the ticket's key, with × to
take it off, and the box says "Anything to add about PAY-142? Or just Start". Start adds one line to your words, which
you can see in the conversation: "Work on Jira ticket PAY-142: <its link>", naming Whozmove's skill for working one.

When the list can't find any: it says no ticket matches, that Atlassian couldn't be reached (with **Try Again**), that
Atlassian asked Whozmove to slow down, or that the link is for a site you haven't signed in to (with **Sign In with
Atlassian**). The card still starts conversations, and Create a ticket stays, either way.

## Where each project's tickets open

A ticket given to a new conversation starts where its project's way says: its own worktree (the way recommended), the
project's own folder, or the folder of its option in one of its fields. The first ticket in a project asks, with a
guide on the card ([New conversations](new-conversations.md#where-a-ticket-starts)). **Settings ▸ Tickets**, shown
once a project's way is set, changes it: a heading marked Important over each project, saying its way, with ›. A
project's page ticks its way; picking another shows before and after first ("A new ticket → its own worktree", then
"A new ticket → shop, beside PAY-150", warning that two tickets in one folder can clash), with **Keep It** and
**Change**; only Change changes it. A change counts only for new tickets: tickets started already keep their
folders. For a way by a field, each of its options is one row there, its folder on a button that opens a menu of the
project's own folders, or its own worktree; a folder that has gone says so.

## On its row

After the conversation's name, a small tag shows the ticket's key and where it stands, coloured by its kind: to do,
under way, done or dropped. It shows while Claude works too.

- **Pointing at it** shows the ticket: where it stands, its type and priority, its title, what it's part of (its
  epic) when Jira says, its project and boards with their sprints, and where it can go next, with a step the conversation stopped
  at marked as a person's. Its last move shows there too. It's read again as the card opens.
- **Pressing it** opens the ticket in your browser, at the address made from its site and key.
- **When it can't be read,** the tag turns red and says so ("couldn't read it now", "sign in again" or "allow its
  sign-in"), and its card says why, with **Try Again**, **Sign In Again** or **Allow**. When Atlassian asks Whozmove to
  slow down, the card says when it reads again, with **Try Now**.

The ticket is read when it's given, each time the conversation asks for it (at most once a minute), as its card opens,
and every five minutes while the conversation runs, a ticket that couldn't be read too; and at once when you press Try
Again, or sign in again.

## A ticket a conversation asks for

A conversation can ask to work on a ticket itself: one you mention, or one it found. Its row then asks "Work on
PAY-148 here?" (or "instead?", when it has one already), with **Use It** or **Not Now**. Only your Use It gives it the
ticket: one conversation works on one ticket. The card reads the ticket as it asks, and says what it is ("PAY-148 · To
Do: Login button does nothing on Safari"), or why it couldn't be read, and offers the same two buttons either way.

After Whozmove starts again, a conversation still running asks "Work on PAY-142 here again?" for the ticket it had,
with the same two buttons.

## Moving its ticket

At a milestone, such as starting, a pull request ready for review, or done, a conversation asks to move its ticket by
one of the ticket's own next steps. Its row then asks "Move PAY-142 to In Review?", with the note it adds to the ticket
("The fix is in pull request #57…") and every field the step sets, with its value, each shown whole. It offers
**Move It** or **Not Now**. The conversation doesn't wait for your answer: it carries on, and hears how it went the
next time it reads its ticket.

- **Move It** moves the ticket and adds the note, as you. While it moves, the card says "Moving it…". Afterwards the
  tag shows where the ticket stands now, and its card says "Moved to In Review when you pressed Move It", with when.
- **Couldn't move it:** the card says why. When Jira couldn't be reached, it offers **Try Again** or **Not Now**. When
  Jira turned the move away, the card shows what Jira said, word for word ("Fill in Blocked by first"), if it said
  anything, and offers
  **Open in Jira** first, to put it right on the ticket there, then **Try Again** or **Not Now**; the conversation is
  told what Jira said too. When it's the sign-in that stopped it,
  the card says so ("Couldn't move it: This sign-in may only read tickets", or "The sign-in has run out") and offers
  **Sign In Again** instead, or
  **Allow** after an update, and the card asks again as it was once you're signed in.
- **Already moved:** when someone has moved the ticket on since, the card closes as you press Move It, the tag shows
  where it stands, and the ticket's card says "PAY-142 is In Review already, so there's nothing to move" until it's
  next read.
- **Asked again:** a second move the conversation asks for takes the first's place, and its card says so ("Asked
  again: this takes the place of moving it to Done").
- **Not Now** takes the card away, and the conversation hears the ticket wasn't moved.
- **The conversation ends:** its card goes.

**May Move Its Ticket**, at the foot of the conversation's mode menu, lets it move its ticket without asking: "It moves
its own ticket at its milestones, adds its note and sets the fields its step asks for, without asking each time". It
shows only for a running conversation with a ticket, can be turned on once you're signed in (until then it offers **Sign
In…**), and says how many times it has moved it. The ticket's card says "Moved to In Review by this conversation". It
lasts while that conversation and Whozmove run, and ends once the conversation works on another ticket. A move it makes
by itself that the sign-in stops comes to its row as a move card, with **Sign In Again**, then **Move It**.

**A person's step:** when the ticket's next step is someone's, such as QA's sign-off or an approval, the conversation
stops there and says so in its reply, which makes the row your move. The ticket's card marks that step "a person's",
with the conversation's why under it, until the ticket moves or no longer has that step.

## Creating a ticket

Pick **Create a ticket** at the foot of the chip's list. The chip says **New ticket**, and the box asks "What's the
ticket about? A line is enough: Claude asks the rest". Write a line and Start: it adds "Create a Jira ticket from this"
to your words. The conversation's row says **New ticket** after its name until the ticket is made; pointing at it says
nothing is made in Jira before your yes. A conversation you're already in can make one too, when you ask it to.

Claude asks what it needs: what happens and where, since when, and which project it goes in. Then its row asks
"Create this ticket?", with its title, project, type, priority, what it's part of and its whole description. Whozmove
checks with Jira first that the project is there and takes that type: one that isn't goes back to the conversation to
put right, and never shows. The card offers **Create Ticket** or **Not Yet**.

- **Create Ticket** makes it, as you. While it's made, the card says "Creating it…". Then the conversation works on the
  new ticket: its row shows its key, and the conversation hears its key and link, with nothing typed into it.
- **Not Yet** takes the card away, and the conversation asks what to change. To change anything, say so in the
  conversation: it shows the ticket again, in the first one's place, saying it was drafted again.
- **Couldn't check or create it:** the card says why, with **Try Again** or **Not Yet**, or **Sign In Again**, or
  **Allow** after an update, when it's the sign-in that stopped it. The conversation waits for you meanwhile, and
  hears once it's made.
- **Couldn't tell whether it was made:** when Jira didn't answer after it was sent, the ticket may be there all the
  same. The card says to look in the project first, and offers **Create Again** for when it isn't, so it's never made
  twice by a press meant to try again.
- **Jira turned it away:** a priority, a parent or a field the project wants that the ticket hasn't got right. The card
  goes, and the conversation hears so, to put it right with you and show it again.
- **Signed in to more than one site:** the card says which one it's made on.
- **A conversation with a ticket already:** the card says the new ticket takes its place once it's made.
- **The conversation ends:** its card goes, and nothing is made, unless it was being made already: that finishes.

## How a conversation works it

Whozmove's plugin carries a skill, `whozmove:working-a-ticket`, that says how: read the ticket, what it's part of and
its board's rules; choose only from the ticket's own next steps, and move it at its milestones with a short note; at a
step that's a person's, such as QA's sign-off or an approval, stop and say so, which makes the row your move; and for a
new ticket, ask what's missing, look for the same ticket first, then show it on its row and wait for your answer. It
reads its ticket from the panel, as you, so what it reads is what the row shows, and its description too, which only
that conversation gets: the panel never shows it, keeps it or logs it. A very long description comes cut short, with
a line saying the rest is on the ticket's own page.

What a project's own pages don't say about how work is done there, a conversation can draft as a note for the project,
which its row asks you to keep: [How a project works](process-notes.md).

What goes to Atlassian, and what stays on your Mac, is in the README's Privacy.

[Back to Using Whozmove](README.md)
