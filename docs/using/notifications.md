# What needs you

Whozmove decides in one place what needs you, and where and when it says so: on one line under the panel's header,
and beside the panel while it's folded. With quiet hours on, it says only what's urgent at night.

## The line under the header

One line says the most pressing thing Whozmove has to tell you, with the one button it asks you to press and a × to
put it away.

- **Most urgent first.** Urgent, in red, is something that stops or waits without you; then something to do when you
  can; then something good to know. Among equals, the one showing stays, then the one that came first.
- **+1 and more.** When more are waiting, a **+1** sits before the ×. Each press steps to the next, urgent or not, and
  after the last back to the first. The one you stepped to stays until you put it away, until it goes, or until
  something new and urgent comes.
- **×** keeps it away until what it says changes, or for as long as it says it stays away, and the next one comes in.
- **A line that says all went well** has a tick, and goes by itself once you've had it in sight for 4 seconds.
- **Nothing jumps under you.** While you type in the panel, or a card there has the keyboard, only something urgent
  comes onto the line, or the one you step to with +1. A press just after the line has changed doesn't count.
- **VoiceOver** says each new line once.

## Beside the folded panel

While the panel is folded, a session that needs you comes out beside it by itself: a request, a question, a plan or a
reply you haven't read, in the order they came, three at most, the rest waiting their turn. [The folded
panel](folded-panel.md) has the rest.

After Whozmove restarts (or a new build is put in place), only what's new since comes out beside the folded panel:
what came while it was closed, but nothing it had already shown you.

## Quiet hours

On One Task's page under Tools (Settings ▸ One Task), **Quiet hours** keeps Whozmove quiet at night, for everything
it says, not only tasks. It's off at first; once on, it runs from 22:00 to 08:00, and **Night** changes when it starts
and ends. Use the Recommended Settings on that page puts back 22:00 to 08:00, and leaves it on or off as you set it.

- **Only what's urgent is said at night:** a session stopped on you (a request, a question, a plan, or a wait) and
  anything else urgent, under the header and beside the folded panel. A reply you haven't read, a new version and the
  rest wait. Whozmove beside the panel at the screen's edge stays still for them too.
- **What answers something you just did** is said all the same, as why holding Bring Forward's keys brought nothing
  forward.
- **What waits isn't lost.** It isn't put away or counted as seen: in the morning it's said as it would have been, if
  it's still there.
- **Nothing goes from under you.** The line showing as quiet hours begin stays until it goes, and **+1** counts and
  steps through only what may be said now.

What Whozmove keeps for this, what you put away and until when, and what of each session has already come out
beside the folded panel, is in `~/Library/Application Support/Whozmove/notifications.json`.

[All of Using Whozmove](README.md) · [Back to the README](../../README.md)
