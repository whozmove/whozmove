# Energy

What Whozmove costs your Mac while it runs, what keeps that low, the targets it's held to, and how to measure it. Where
each part of the panel is read from, and how often, is in [Where it reads from](where-it-reads.md).

## What holds the work back

Whozmove runs all day, so anything it does again and again counts more than anything it does once.

- **Git runs only for a checkout something changed in.** macOS's file system events say which checkouts changed
  (CheckoutWatch); a quiet checkout is looked at again only now and then, in case an event was missed.
- **Claude Code's plugin is checked when its records change** (the agent's stamp), and otherwise hourly, since each
  check starts the `claude` command, a large program.
- **The usage card asks the agent only while you're at the Mac,** less often while nothing works, and never while
  you've been away a while.
- **A transcript is read from where the last read stopped,** across restarts too, so a start reads only what's new.
- **Animations that never end move by transform and opacity,** which the graphics chip runs without redrawing the
  page.

## Targets

For Whozmove's whole group: the app, its web pages, and every program it starts.

| | Target |
|---|---|
| Overnight, nothing at work | under 5% of a core |
| Panel shown, agents at work | under 15% of a core |
| Graphics | under 10% of the time |
| Disk reads over a day | under 0.3 GB an hour |
| A launch | under 100 MB read |
| git, agents at work | under 30 runs a minute |
| Writes | under 20 MB an hour |
| Wakeups | under 150 a second |
| The app's memory | under 600 MB |

The weekly reading shows graphics' energy too, in joules an hour, beside its share of the time.

## Before a change

Every change is read against these questions, in review and in its plan:

1. Does it add work that comes back by itself, such as a timer, a poll, an animation or a program run on a clock? How
   often does it run, and does it stop when nothing shows its answer (the panel hidden, the screen asleep, the Mac
   idle)?
2. Does each outside program run when something changes, rather than on a clock alone?
3. Does it read a whole file where only what's new would do, or read again after a restart what it read before?
4. Does an animation that never ends move only by transform and opacity?
5. Does it rewrite a large file whole, and how often?
6. Is it within the targets above?

## Measuring

`tools/energy.sh` reads the running Whozmove and writes nothing but a temporary folder:

- `tools/energy.sh now 5`: over the next 5 minutes:
  - the app's, its pages' and its whole group's share of a core, wakeups, and disk reads and writes, and the app's and
    its pages' memory;
  - anything else still running in its group;
  - the programs it started, by name, and the folder each git and gh ran in;
  - whether agents were at work meanwhile.
- `tools/energy.sh launch`: the running copy since it started, and its group's reads in each of macOS's power log
  intervals since, up to when they settled. Take it a few minutes after a build is put in place.
- `tools/energy.sh week`: the last 7 days of macOS's power log, per hour the Mac was awake. Hours with nothing at
  work in a terminal, an editor or Claude Desktop are kept apart from busy ones. Hours it was awake under 30 minutes
  are left out, and so are the hours a Deploy ran, as far as Whozmove still knows them.

Each one ends with its figures beside the targets above, each marked first "over" or "under" its target.
`week` and `launch` read macOS's power log, which a sandboxed run can't: run them in your own Terminal.

The group is what macOS's power log counts as one app (its resource coalition), so it includes the programs that have
ended, and a Deploy's runs, for any project. Reading the group uses calls macOS doesn't publish: where it refuses
them, the tool says so and gives the app's own figures. The programs it lists show only their names, and the folder
for git and gh: never another argument.
