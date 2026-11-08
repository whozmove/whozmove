# Storage

How full your disk is and what fills it: a line when it's running low, a map of your disk, Clean up, for what comes
back on its own, and Keys, for keys left where they shouldn't be. Storage is among the tools on
[the panel's back](the-back-and-look.md).

## When your disk is running low

A line above your sessions says what's left, and how soon it's full at this week's pace, or that builds and sessions may
fail once it's nearly out (under 5 GB). Pressed, it opens Clean up beside your sessions. If Storage is off, that press
turns it on, and Clean up says so at its top, with **Turn Off**. Once Clean up knows what it can free, the line says how
much ("33 GB can be cleaned up", or "Clean up 33 GB now" once it's nearly out, with how old the map is once it's over an
hour: "· measured 6 hours ago", as Storage's page says too), or "See what's using it" when the usual places hold nothing to
clean; after a clean-up, that what went is in the Trash until you empty it. While Storage is open beside your sessions,
the line says nothing above them. Its × puts it away for a day, or until the disk is a tenth fuller. **Storage**, among
the tools on the panel's back, shows the free space and how fast it's filling, and has **Tell me when space runs low**,
which turns the line off.

## The map of your disk

**Map My Disk** on Storage's page turns it on and opens Clean up beside your sessions, as the line does; after that,
**Open the Map** opens the map, and Storage's **Know your storage** switch turns it off. Storage measures only
sizes, never what's in your files, and keeps them on your Mac.

It's rings beside your sessions, round the folder you're in, each folder in its own colour and what's in it further
out. Point at a piece for its name, size and share; press one to go in (while a folder takes a moment, the middle, its
row and the path above the map say it's opening), and the middle to come back out. Going in, the piece you pressed
grows into the middle, and the folder's own rings come in round it; coming out, the middle shrinks back into its
piece.

Beside the rings, as tall as the panel, is what's in the folder, biggest first. **＋** collects anything that can go,
and the rest have none, and say under their name why they can't: an agent is working there, changes aren't
committed or commits not pushed, a tool keeps it, macOS's own files, or a folder that stays, like your home folder.
Inside a folder you collected, pressing a part takes it back out, and the rest of the folder still goes. What you
collect waits under the map until **Move to Trash** and its **Confirm**, its name going there from its row as you
press **＋**; it comes back once you empty the Trash.

Measuring takes a minute or two the first time, and the map says how far it has got against what's in use ("142 of 476
GB"): you can close it, and a line above your sessions says when it's ready. Without Full Disk Access, Desktop,
Documents, Downloads and other apps' folders show as ones it can't look inside, each row with **Allow Access**, which
opens System Settings there with Whozmove in the list (the row then says what to do there); once you've allowed it, the
map is measured again. Until Apple's developer tools are on your Mac, git can't say what a project holds, so its
folder keeps it all, and the map and Clean up say so, with **Install**.

## Clean up

Storage's first tab (or **Clean Up** on Storage's page) lists what comes back on its own, in groups, with how much
each frees. The first time, it measures the usual places first, so they're listed in a few seconds while the map
measures the rest; each project's built files join at the list's foot, unticked, once your disk is measured:

- Xcode's built files (DerivedData);
- your tools' caches (npm, Yarn, pnpm, Bun, pip, Gradle, Go, Cargo, CocoaPods, Playwright's browsers, installed again
  with `npx playwright install`, and Xcode's support files for older iOS versions);
- space your tools clean up with their own command, shown before it runs (Homebrew's old downloads, Docker's unused
  images and build cache, Xcode's simulators no longer available);
- models (Ollama's, and those Hugging Face has downloaded, leaving its sign-in and settings);
- built files in your projects (`node_modules`, `.next`, an app's `ios/build` and `android/build`, Rust's `target`);
- and worktrees you're done with (merged, nothing uncommitted, no session there, not changed for a week: the folder
  goes to the Trash, and its branch stays).

Tick what you want gone, then **Clean Up** (it says how much) and its **Confirm**: folders go to the Trash, and each
tool's command runs. Each ticked row says how it's going (waiting, moving to the Trash, in the Trash, its command
running, done), and one that stayed says why and what to do, on its own row, while Measure Again waits until the
clean-up is done; the foot counts them ("Cleaning up 8 things · 2 done, 1 stayed"), and once it's over says how many
went, how much is in the Trash until you empty it, and what the tools' commands freed. What went stays on the list,
saying so, until you close Storage. While your disk is still being measured, Clean up's tab says how much it has found
so far ("21 GB so far"). A project changed in the last two weeks, Docker and models start unticked, and nothing an agent
is working in can be ticked (its box is greyed out).

## Keys

Storage's third tab lists keys left where they shouldn't be: API keys, tokens and passwords that Whozmove found in
your projects and their commits, in what Claude Code and other AI tools keep of your conversations, in what Claude
Code reads as its instructions (your CLAUDE.md files, its memory, skills and the rest), in your shell
history and your shell's settings (`~/.zshrc`, `~/.bashrc` and the rest, where a key set for every terminal lives) and,
with Full Disk Access, in Downloads; and credential files other accounts on your Mac can read. It looks by
itself a moment after it opens and once a day, on your Mac only, and keeps no key whole. Each key shows as soon as
it's found, and beside the tabs Keys says how far it has got ("Read 3 of 5 places · 2 keys so far"); while your disk
is being measured, that line says how far the measuring has got instead, as on the other two tabs.

Each key shows once, most urgent first:

- **Do now**: a key that has left your Mac (pushed, or sent to Claude or another AI tool): make a new one where it
  came from, with **Replace at** its provider, then **Mark Replaced**. Or one about to leave (in a commit not pushed
  yet): take it out of that commit before you push.
- **When you can**: a key only on your Mac, in a file, your shell history or settings, or a credential file others
  can read (**Make It Yours Only**, for your shell's settings too); or a sign-in token past its own end date, wherever
  it is.

Each says what it is, with its first and last characters, where it is in one sentence, and whether it looks real:
**Looks real** (its provider's own shape, or you typed it), **Could be real**, **Probably no longer works** (a sign-in
token past its own end date), **Probably made up** (only in tests' files, its conversation calls it made up, or an
agent first wrote it there, a fixture or a demo, and it's nowhere else) or
**Probably not a key** (shaped like an id, and nothing around it calls it a key). Its button is its best fix, and the
⌄ beside it has the rest.
**Show Where** lists each file, its lines, the copies of the project it's in and its commits, each with **Open at the
Line**, **Open the Conversation** or **Show in Finder**. A copy Claude Code kept of a file it edited is named by that
file ("Claude Code's copy of ~/.zshrc"), and opens it at the key's line while the file still holds the key; once it
doesn't, it's an earlier copy, which Claude Code's clear-up command takes out.

A key most likely made up for a test (only in a project's tests' or examples' files), one the conversation it's in calls
made up (a sample, fake, a placeholder; never one with its provider's own shape), or an id, isn't counted: it waits
folded at the foot, with **Not a Key** first. What can't be a key isn't listed at all: a GitHub token whose checksum
doesn't add up, a variable's name (`$API_KEY`, `R2_SECRET_KEY`, `APIKEYS`), words joined by dashes
(`your-api-key-here`), a sentence a match ran into, a file's hash, a placeholder that counts up (`1234567890`), a
private key's first line with no key after it, or Docker's settings with no sign-in in them. **Not a Key** and **Mark
Replaced** put a key away, each with **Undo** at the foot.

The line above your sessions speaks only for keys that have left your Mac or are about to: how many there are to
replace now (or, while none has left, to take out before you push), then where, most exposed first. Its × puts those
away until another one leaves.

[All of Using Whozmove](README.md) · [Back to the README](../../README.md)
