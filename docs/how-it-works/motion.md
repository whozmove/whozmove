# Motion

How each part of the panel moves. Every animation also keeps to the rules in CONTRIBUTING's
[Animation](../../CONTRIBUTING.md#animation).

`morph(list, html)` (in `parts/morph/page/morph.js`) snapshots every row and line, swaps the HTML, then animates
the difference: lines grow and fold (`rowParts`, with how a module's part of a line moves from `core.lines`), changed
text cross-fades, rows slide to their new place (FLIP), and the list's own height eases with them, so the now-playing
strip below it and the panel's bottom edge go with the rows.
Your message and Claude's line are written (`rewriteLine`): the old text erases from its end back to its start, then the
new text writes in from there, each by a soft edge, so the two never meet; what they share at their start, by whole
words, stays (the next step's "Reading "). A reply on two lines writes its first line, then its second, and erases the
other way round. Claude's time beside its working text rides just past what shows, as does what a module puts after
Claude's words (a button), the old line's copy of it hidden, and its label changes as the new text starts. A new line writes in as its room opens; one that's gone erases, then folds. When both change at once,
yours goes first and Claude's follows, and going, Claude's goes first. All of it fits in the rebuild's own second
(`chatTimes`), and a line that shrinks keeps its room until its old text has gone, the list's height following that
too (`listFrames`). Any other line of text, a module's own, takes new words the same way, on the same way along it and
at the same pace (`rewriteText`). A row out of the list's sight where it was and where it goes takes its chat lines' new
words at once, their room still easing, as nobody would see them written and writing them draws the panel every frame;
the row you're on always writes in (`outOfSight`). The panel follows the list frame by frame only while something in it
changes size or place.
Rows that keep their order slide underneath; one that passes others glides over them with only a frosted backdrop
(`.row.glide`, `keptInOrder`). Reduced motion (`calm`) skips it all.

A row's details (parts/details) are a line of the row, after its bottom line (`.details`), so they grow in as a new line
does and fold away as one that's gone does, the rows below moving with them on the list's own motion. Where the rows
under the pointer are to stay still as they fold (as far as the list can scroll back), or their row as a reply moves the
rows, the list scrolls by however far that row has gone each frame (`waitingKeep`, with the row named by
`detailsHeldRow`). Where they're to be shown whole, the list eases once they've grown, measured where it ends up
(`showLeast`). Held at the list's edge, they're the first of the row's lines to fold (`foldsFirst`). [The details
part](../../parts/details/README.md#rules) has the rules: when they open and how they fold.

How long a chat line takes goes by how far its text runs (`writeMs` and `eraseMs`, in `parts/morph/page/morph.js`):
writing keeps a steady pace and lands softly, and erasing mirrors it in about two thirds of the time, each with a
shortest and a longest, so a short word still reads and a long line still fits. Your line starts first and Claude's
follows it by `CHAT_STAGGER`; going, Claude's leaves first and yours follows by `CHAT_STAGGER_GONE`.

What a session runs in the background goes round its dot (`orbitHTML`, in `parts/row/page/rows.js`): a 3pt mark for
each job, three at most, spaced evenly round one ring 7.5pt from the dot's middle, which turns once every 2.4s at an
even speed. The ring's phase comes from the page's clock (`phase`), so a rebuild never starts it over, and one ring
turns, not each mark, so they never bunch. A change of count is seen through after the rebuild (`orbitChange`, from
`core.drawn`): one joining, the marks there move apart to their new places (300ms), then it grows in from nothing at
its own (200ms); one leaving shrinks to nothing where it is (200ms), on a copy of the old ring turning in step, then
the rest close up (300ms). The marks lie inside the dot, over a waiting dot's ring, and a working dot's fading is its
fill alone (`::before`), so they never fade with it. With reduced motion the ring stands still, one mark at the top,
and a change fades the old marks out as the new ones fade in. The line that names them, under Claude's or under the card
that follows it, is one of the row's lines, which grows, folds and cross-fades as the others do.

Deploy's round button (`deployHTML`, in modules/deploy/page/deploys.js): its icon comes in whenever it changes, and
while a deploy starts a thin arc turns round it, once every 1.2s (`playTurn`, in parts/morph/page/motion.css), from the
run's start. Once a server's build is up, the arc closes into a steady ring (modules/deploy/page/deploy.css): from the
angle it had reached when the page first saw it up (`--turn`, worked out from the same clock), the arc grows round to
a full ring over 450ms, still turning 34° as it slows, which starts it at the turn's own speed, so it carries on rather
than stopping dead; the stop square stays as it was. Once the ring has closed, the build's address takes its place after
the folder on the bottom line: its room opens to exactly its width (a grid column from nothing, 180ms), the line's gap
with it, then ":3001" fades in, lifting 3px. Each starts `--up-since` after the page saw it up, so a rebuild meanwhile
carries it on; with reduced motion the ring is simply there, and the address fades in, its room already open.

A line folding takes its margin, padding and border with its height (`BOX_KEYS`), so a padded card never stops at a
sliver of padding, and what sits at the panel's bottom edge moves with what's above it. The page paints new room at its
bottom a frame or two after the window grows, so the window's tint, under the page, fills it meanwhile
(`PanelWindow.m`).

The row you're on never leaves the list's visible part (`sticky.js`): whatever takes it past an edge, your scrolling or
the list moving it (to the top as a message comes in, rows above it growing, a shorter list), it holds
on there, at the list's top past its top, at its bottom past its bottom (`stickyHold`). A row that only grows past the
bottom edge, its top staying where it was (a card opening on it), stays as it is, still in view. It never holds on while
one of its boxes is typed in, nor when it's taller than the list's visible part. The row stays in the list, keeping its
place, so nothing in the list moves; a copy of it, laid over the edge, is what holds on, made as the row starts holding
on and gone once it lets go. The copy is as tall as the part of the row's place still in view, so the row next to it
stays touching it, and every point you scroll folds a point off it (`stickyFold`): one line at a time, the one nearest
the moving edge first (from the bottom up at the top edge, so Claude's line comes up under the title last; from the top
down at the bottom edge), until its title line, Claude's line and its bottom line are left. A folding line keeps its
size and gives up its room, the line beside it covering it as it fades (`stickyLineFold`), so nothing in it moves or
squeezes and nothing passes through text. As it attaches, its tint spreads to the list's sides and squares off against
the edge; what's under it is hidden by a mask on the list, as under the header, and attached at the list's top, it meets
the header with no line between them. The row itself is hidden too (`.row.sticky-away`): WebKit scrolls the list a frame
or so ahead of the page laying out the copy and the mask, and in a quick scroll the row's place would otherwise show
past the mask's edge, the row there twice. It follows the scroll position, and every frame anything else moves the list
or the row in it (`reportHeight`), so scrolling back runs it backwards. It follows at once as far as a slow scroll goes
in a frame; what's past that (a quick scroll moves the row tens of points from one frame to the next, as does the list
moving it by itself) it catches up with, all but there in about 0.2 s, without ever passing the row's place
(`stickyEase`), so its lines still fold one after another, and the rows going by meanwhile go under it. Back in view, it
opens out and glides from the edge to the row's place the same way, however far the row came in a frame, and hands back
to the row once it's there. Where it can't take over from the row in place (it starts holding on with the row already
past the edge, or the row's session ends), it fades in or out, the mask fading the other way. When the session you're on
changes while it holds on (you press another row, or switch to another session in Claude or a terminal), it hands its
tint over (`stickyHandOff`): the copy slides off at its edge, out of sight, fading, the list under it uncovered as it
moves off and coming back as it fades, while its tint goes to the new session's row, where that is in each frame, whose
own tint takes over as it lands. The tint is on a layer of its own under the list (`#sticky-under`), so as it goes it's
drawn behind the rows' text, as a row's own tint is. It takes no pointer events, so a scroll over it scrolls the list,
and what the pointer is on there is found by where it is (`stickyAt`); a press on it scrolls back to the row, which
keeps its place meanwhile. Back in view, what's on the row counts as only just shown (`showAgain`), so a card that came
while it was away can't take a press meant for the copy. The copy is inert and has none of the data the page finds a row
by, and leaves out what a module's line has only while it moves (`core.lines`' `still`). Its lines change as the row's
do: what cross-fades on the row does on the copy too, its chat line is written as the row's is, and a copy of other
lines cross-fades in. It
fades with the list as the panel folds into the cat. Under reduced motion it still follows the scroll at once, which is
your own motion, while its fades, text changes and the move back to the row happen at once.

Left near an edge, the row you're on goes the rest of the way (`stickySnap`). Once your scroll has ended, its momentum
too (the list still for `SNAP_QUIET`, 120 ms, as no wheel event says when momentum ends), with the row in view and its
top within `SNAP_PULL` (48 pt) of the list's top, or its foot within that of the bottom, and your scroll taking it
toward that edge, never away from it (`stickySnapBy`), the list itself scrolls the last bit, so everything under the row comes with it and nothing is left open: from rest, speeding
up all the way, about 0.1 s for 48 pt and less for less, then a click with a point of give at most (`pullScroll` and
`clickSpring`, in morph). Where it goes is measured again each frame, so it lands on the edge whatever else moves. It
happens only after a scroll of yours, never while the row is held at an edge, typed in, or the panel folded, and only
where the list can scroll that far; a scroll of yours meanwhile takes over at once, and its point of give past the edge
never makes the row hold on there. Under reduced motion the list is simply there.

While the panel is folded, what needs you comes out beside the cat by itself (`chats.js`): each chat is the session's
row, the list's own (`rowHTML`, its request card and all, drawn through `morph` so its lines change as the list's do;
whole, with Claude's line, where the list shows its rows briefly, as it shows every row; saying a module's
line in Claude's place where that's what's new, a reply in its side chat), on a card of the
panel's colour, with a pin and a ×, the time it has left a ring round the × that empties, as tall as its row,
a request's card and all, up to where the screen ends beside the cat, where its row scrolls. Three at most,
in the order they came (which come out is the notifications module's), toward the screen's
middle: the first level with the cat's top and the rest under it, or, from a cat low on the screen, level with its
foot and the rest above it; a pill under them says how many more wait. A new one comes out after the others, or, with
three out, waits its turn, never taking the place of one out; while you hold one (pointing at it, typing in it, or in
its session's tab once pressing it or its row has put you there, until you leave it), every chat's time stands still and
nothing new comes out. The one you're pointing at or typing in keeps its place, and so do those before it, a gap left where one
before it went, until you move off it (`chatKeptTo`); one of those moves only to keep clear of the chat before it as
that grows, its end nearest the cat staying put. Those after it, and all of them while you're only in a session's tab,
close up after it as one shrinks or goes, as when you hold none. A chat that closes up under a pointer you haven't
moved isn't pointed at while it moves, so the gap closes; once it has stopped there, it holds every chat's time as the
one you'll read next, but keeps no place, going on closing up as the one before it shrinks again (`chatPointed`).
Moving the pointer onto one points at it at once; onto one on its way, as the one before it shrinks and it closes
up, it holds every chat's time but keeps no place till they've got there, so it closes up all the way, and keeps its
place from then on (`chatsSettling`). A chat comes out once those moving have landed and the one going
has faded, so it enters a lane already clear (`chatComesAfter`), hidden and taking no press till then: the first,
nearest the cat, from under the cat, fading in as it slides out; one after it in its own place, fading in as it lifts
3px into it, so it never passes over the one before it (`chatComesFrom`). Going back, it
slides back the way it came, fading; once it has faded, the one below moves up into its place, so none moves over
one still fading (`moveChats`). The window takes in the room
before anything moves, for where they were and where they go, and only what they need once they're there, each
measured as tall as its row is growing to, or as tall as it still gets on its way while it eases (`chatTall`), so the
window's edge never cuts one off (`askChatRoom`), and the pill's own room is kept before the screen's edge. As a chat
grows, the one after it moves clear at once; as it shrinks, those after it close up with it, riding its foot on its
own curve and clock, so each keeps its gap from the one before it all the way and enters room only as it's cleared
(`chatRide`). Where it can't be ridden (two easing at once, or one after it already on its way), they move up once
it's within a point of its end, as it's seen to stop (`chatAhead`); with reduced motion, it just ends. Going up from
the cat, each is placed by its foot, so its foot stays put as it grows or shrinks (`chatTransform`). The gap before a
chat counts as that chat, so going from one to the next never closes them up under the pointer (`chatBefore`).
Dragged, the cat moves once they've gone in (quickly, toward
it), and they come out again where it stops, the way it then faces; a press that moved far enough to be a drag is one,
even if the cat hadn't moved yet, never a click. The panel opening round the cat, from a
press or the pointer resting on it, each is pulled home into its row in the list as one thing (`chatsLand`, in
`landing.js`), as if on
a spring, carrying a little past its row and settling back, the lowest first, so each moves into room already clear,
shedding its card as it nears its row. As the list shows its row briefly (every row's short look), the chat, being
its row whole, takes the row's look on its way: first its lines that the row hasn't fold away together, each as a held
row's line does, and its lines and dot move to where the row has them, so it comes to the row's shape; then the row's
look fades in over it, and only once that's all there does the chat's own go, so what's in both never dims
(`chatLookAt`). One whose row is partly out of the list's sight lands there cut by the list's edge as its row is, and
one whose row is out of sight slides under that edge. The app keeps the room they need till the glass has spread
(`foldMoving`), and the page keeps the rest of the panel out of sight till then, but for the cat and the name; then the
list comes in round them, and each row takes over from its chat, a chat that isn't its row as the list has it (shown
briefly there, or saying a module's line) taking the row's look on its way (`chatLook`). The folded cat's list going
back in as the pointer leaves it, the chats still out are pulled back out on the same spring, top first (`chatsLeave`), taking their card back
as they lift off the list, and one shown briefly there lifting off as its row and turning back into its chat the same
way, while the list fades and the glass closes round the cat; the page names the room they go to with the fold, and the
window keeps it from the start. The chat of the session
you're on, held at the list's edge (`sticky.js`), becomes that held row on its way in, in the same move: it moves and
changes shape as one, on the one spring, its lines folding as the held row's do, its tint spreading across the list
and its corners squaring off against the edge, so it has the held row's shape exactly as it stops; going out, it turns
back into its chat the same way (`chatHeldAt`). Moving off the folded cat's list before they've landed, or pointing
at the cat again before they're back out, each turns back where it is, keeping its speed (`chatTurns`), and the glass
turns back with them from where it is (`foldMoving`), rather than either finishing first. Reduced motion fades them in
and out where they are.

Resting on the folded cat a moment, the panel opens as a press on the cat opens it, where a press opens it (`peek.js`),
but for its header: a head as tall stands in for it, the cat in it as it is folded, where the name's o is, and at its
other end how many are waiting on you. The glass spreads out from behind the cat, the list comes in as it does from a
press, and what's held over or under the panel (Spotify's token, the usage card) comes out once it has opened; the
pointer on one of those is still with the panel. Moving off the panel, it folds back round the cat as from a press, the
cat staying as it is, and its chats come back out; with one of its boxes typed in, it folds once the box lets go of the
keyboard. It doesn't come out while the cat is pressed. Pressing the cat, or the head, only finishes opening it, as an
opening does once the glass has spread: the cat shrinks into the name's o, the name coming in from both its sides, and
the header's buttons come in where the head's words were, once they've gone (`catOpening`). Flicked off the screen's
edge, it finishes opening the same way as it goes (`flickedAway`), so it comes back open, as from a press, rather than
folding while it's away, the pointer being off it. The page always has room above the list (`kAboveRoom`, `--above`), as
it has beside it for the reader, for a cat low on the screen, whose chats go up.

A step's word coming in beside its icon as it's pointed at is CSS (`motion.css`): its room opens, then the word fades
in, lifting 3px as it lands, while what's to its left slides over; pointed away, the word fades first, then its room
closes. It's drawn open as the list is drawn again while it's pointed at (`hoverStep`), so it doesn't come in afresh
each second, as the context ring widening into Compact is.

The usage card moves on its own page (`card.js`), in its own window under the panel, without `morph`: pointed at, it
slides out from under the panel; pressed, it opens as one, growing as its colour shrinks into its row's bar and the
words on it travel to their places in the rows, each measured where it is and where it lands, the rest of the strip
coming in around them; folding runs the other way round (modules/usage/README.md says how). Its wait styles each own a
reset, a function of the time since it started (the vine's is `vineFrame`), so the usage module's tests check its
frames as numbers.

Spotify's token moves natively, as a window of its own under the panel: `EdgeIcon` (parts/edge) holds it under the glass
and takes it across to the other side, and modules/spotify/README.md says how it moves, and how a song's lines roll
into the now-playing strip and follow along beside the list.

The reader's panel grows and folds natively (`reshapeTo:` in PanelWindow.m): the window takes in everything the
panel covers on the way at once, the page is laid out and drawn there once, and then only the glass's and the page's
clip's edges move; it folds back to the list's measured height. Don't animate the window's own size: the page would be
drawn again every frame, a frame behind, and its edge would fill in tile by tile. And the page never changes width: it's
laid out once, as wide as the list with room for the reader on either side (`kReaderRoom`, `--side`), and the window
shows only the part in use, so opening and closing the reader never has WebKit lay the page out and draw it again,
which would flash the whole panel. Only its height follows the window. Don't cover a change of size with a picture of
the page either: WebKit draws its pictures on white, which shows through the panel's tint as a pale flash. The tint
itself is in the glass, so it moves with the glass's edges.

A plan in the reader opens as the panel's lines do (`planTurn`, modules/plans): a choice's options and a section's
body grow in where they are (`growIn`) and fold away (`foldAway`), the chevron turning with them. A section's first line
is part of the move, so nothing below jumps: opening, it fades as its own height eases away while the body grows;
folding, its room grows back as the body folds, and its words come in once the body has gone. Pressed again while it
moves, what's moving is held where it is and turned round from there (`planHeld`), never there twice. Only what was
pressed moves; nothing else is drawn again. Reduced motion fades them, the first line once the body has gone. A
section's diagrams are drawn before it's measured, so it grows to where it ends up.

A diagram (modules/diagrams) is drawn at the width it has as it goes in, before the reader measures what it shows and
before where you were is put back, so it comes in with the page, never after it. Switching Diagram and As written, what
it showed fades (160 ms), then its room eases to what it shows now (the list part's `easeHeight`, 300 ms, the panel
following) as that comes in the panel's way (420 ms); reduced motion fades the one into the other. Pressing a plan's
small flow on its card opens its section and brings it into view once it has grown.

Up next's rows (modules/board, `boardMove`) come and go one after another as sessions start and finish their turns:
one that goes fades (120 ms); those still there then slide once (300 ms), from where they were straight to where they
end up, measured with the ones coming laid out whole but unseen, so a row that goes and one that comes in the same
update never move the rest and then move them back; one that comes then fades in (150 ms). The gear's line, when it's
to be in another gap or say another number, fades out with the rows going and back in with the ones coming, so no row
slides over it. A row whose place among the others changed goes and comes rather
than sliding past them (`boardKept`: only those keeping their order slide), so no row's words cross another's. A
press on one of your gear's seats on the usage card, while Up next shows, moves no row there: every row keeps the gear's line's
room under it. The gear's number turns first (0 to 160 ms, the usage module's), then the line's rule fades from its old
gap (120 ms) and draws in from the left at its new one (200 ms), its number with it, then each row it passed says its
new words, out (80 ms) and in (120 ms), each 60 ms after the one above (`boardGearMove`). A draw meanwhile waits for
them to land, the reader's height is measured once they have, and a row that has only just moved takes no press. Moving
to another goal, or the reader turning to another view, calls it off. Reduced motion tells the same story as a
cross-fade: the rows going fade, then the ones coming fade in, and nothing slides.

Storage's map (modules/storage) moves what's there before and after too. A step in, to a folder drawn on the rings
(pressed there, or as its row beside them, up to three rings out), or out, to a folder whose rings hold the one shown
(`mapStep`), moves its piece (`mapGrow`, `mapGrowPath`): a copy of the old rings and the middle's words stays over the
new while all of them but the piece fade (160 ms), then the piece pressed widens round the middle from its own centre,
its inner edge closing in, so at every moment it's a piece of a ring, easing out, and its colour becomes the middle's,
keeping near its own till late (420 ms); the folder's own rings come in round it from about halfway, and the middle's
words once it's the middle, which is let go of in the frame it lands, the copy gone in that frame too. The list beside
them fades in and lifts 3px as before. Going out, the middle shrinks back the same way into its own piece of the
folder it's in, taking that piece's colour early, as the rest of that folder's rings and its middle come in round it
from the start of the shrink, and its words once the old ones have gone. Until a step lands, the
new rings take no press. The map is drawn again during one only if what it shows really changed, never for what the
pointer is on, whose words are put right in place. Another tab, or any other folder, fades in and lifts as before.
**＋** sends its item's name to what's collected under the map (`mapLand`): what the foot said before goes first
(120 ms), so its line is clear; a copy of the name lifts off its row and fades there as the row's own name comes back
in under it (160 ms); then, measured as the foot is by then, it comes in at the foot where it left the row, after the
chips already on its line, as wide as its chip shows it, and slides along that line to its place (300 ms), where its
chip comes in round it once it has landed (150 ms): never over the list's words, another chip, or its own. The timings
are named at the top of map-view.js. Reduced motion cross-fades the rings and the middle's words, and fades the chip in.

The panel turns over natively too (`turnOver:then:` in PanelWindow+Turn.m), as one card about its middle: the glass, the
list's page, the back's page (a module's view, `holdBack:`) and the panel's shadow are turned together by Core
Animation, as the folded glass's breath is, so nothing is laid out or drawn again on the way. Both sides are always
drawn, so the back is already there as it comes round; each shows only while it faces you, and they swap edge-on, where
a thin edge in the panel's colour stands across its side. It turns as the press pushes it: from the buttons at the
header's right end, that edge sinks in, and turning back from there carries on the same way round, so over and back make
one whole turn; ‹ at the left end of the back's apps turns it back the other way round, its left edge sinking in. The
window first takes in room above and below for the near edge, which comes toward you and is seen taller than the panel,
the glass and the page staying where they are, and is the panel again once it has turned. Near the top of the screen,
macOS keeps the window under the menu bar, lower than the room asked for, so the glass, the clip and the page are each
placed by where the window really is (`setWindowFrame:glass:clip:then:`), and the panel doesn't move. What's held over
or under the panel (the usage card, Spotify's token) goes from sight in the same frame the turn starts (`followTurn:`),
and comes back in the frame it lands on its list side; an open reader folds back first. Reduced motion fades one side
into the other.

A request waiting on you comes into view by itself (`waiting.js`): the list scrolls to its row in one eased move,
measured again each frame and following its card as it grows in, until the row shows whole (`showInListBy`, which
starts a row taller than the list's visible part at its top); what comes into view counts as only just shown. Each
request is brought in once at most, and a scroll by hand stops the move and counts every request waiting as seen, so
the list never pulls you back. The list never moves by itself while you answer a card or the pointer is on the panel.
Whenever a request waits wholly out of sight, a strip at the edge it's past says so, one at each edge with one past it,
naming the one nearest it, on a band of the panel's own colour. Out of sight is past the edge as drawn: a row under the
copy of the row you're on held there, or under a strip already standing there, counts as gone (`waitingGone`,
`waitingStands`), and while any of the row shows there's no strip, so a request never shows twice; nor is the row you're
on named while its copy holds at an edge, as the copy already shows it. The band slides in from under that edge as the
last of the row goes, slowing as it lands (0.24 s), and back under it, speeding up (0.18 s), as soon as any of the row
is back or the request is answered, clipped by the strip's own box, so it never passes over the rows inside it; reduced
motion fades it where it stands. At an edge, the strip and the copy of the row you're on keep the list's order
(`waitingOutside`): where the request comes before your row at the top (after it at the bottom), the strip has the edge,
until it has slid back under it, and the copy holds just inside it, as it holds below the header (`stickyInsets`);
otherwise the strip holds just inside the copy, following its band. As the list scrolls, whichever comes first in that
order reaches the edge first, so the two never pass through each other; as a strip outside the copy comes or goes, the
copy eases from where it is on the screen. And the card you're answering or pointing at keeps its place on the screen as
the rows move: each frame of the list's motion, the list scrolls by however far its row has gone (`waitingKeep`).

The header stays where it is as the list scrolls (`header.js`) until the row you're on, held at the list's top, has
folded all it can there; scrolling on, that copy pushes it away, point for point (`stickyPush`). It stays as far as it
was pushed, part-way too, until the list has scrolled back to its very top, which brings it back with it. It lies over
the list's top, in room the list keeps for it, the list clipped at its edge, so nothing is laid out again as it moves,
and the row you're on holds on at that edge wherever it is (`headerInset`). The drag strip over it covers only what
still shows (`headerShowing:gone:` in PanelWindow.m), so a press on the rows that have come up under it goes to them.

Whozmove beside the panel (`SideCat.m`, an `EdgeIcon` as Spotify's token is) comes out once the header has gone, at the
panel's top corner on the side facing the screen's middle, and goes back once the header has come back a few points. It
reacts with its face, each of its values on a spring worked out exactly for however long a frame was, on the edge icon's
timer, which runs only while something moves; its eyes' drift is Core Animation's. Pressed, it's held over the panel
instead of under it, and the page folds the panel round it where it is (`foldFromSide`): the page stays put, the list
fading in place, and as the glass closes, the cat grows on the glass's own curve into the folded cat there, its head's
middle never moving. Once the fold has finished, the page puts the folded cat's place back on the name's o, the app
moving the page under the glass, out of sight, and the page's own folded cat takes over in the same place at the same
size (`catLanded`, `catShown`). So opening is the ordinary opening: the panel grows round the cat, which stays put.

A sideways two-finger swipe on the panel's list is the panel's (`swiped:` in PanelWindow+Flick.m), taken before the page
gets it; up and down stay the list's, and while one of the page's boxes has the keyboard, the swipe is the box's; one
the panel starts folding during (its list on pointing going back in) is given up where it is. The panel leans with the
fingers, and lifting them fast enough sends it off that edge of the screen at the flick's speed, easing out, fading by
how much of it has gone past the edge, so on a display beside it, it never shows. Whozmove beside the panel stays,
peeking out from the screen's edge, and brings the panel back the way it went. A sideways swipe on Whozmove there, or
just round it, is the panel's too (`swipedAway:`), and nothing under the pointer gets it: once it's taken, the rest of
it and the trackpad's glide after it go to a small window under the pointer that can't be seen and never takes the
keyboard (`holdAway`), whatever moves underneath, until the glide has run out or the pointer leaves it. Toward the
screen's middle, the panel comes out with the fingers, point for point, and let go a third of the way out or flicked, it
carries on to where it was at their speed, else slides back off the edge. Toward the edge, Whozmove goes in with the
fingers, harder the further they go, never all the way, and springs back out with the small bounce it comes out with.
What's held over or under the panel goes as it leaves and comes back as it starts back (`followAway:`). With reduced
motion it fades out and back in, nothing follows the fingers, and a push dims Whozmove. Folded, a swipe is the page's,
as it is in a chat beside the cat.

A row's mark at its far edge (the row part), where a module puts its button (`core.slots.edge`), never moves the row:
only the bar moves. It takes the pointer in the row's last 8 points, its own padding past the end of its lines, so
Deploy and the folder's name at the lines' end are never under it (a next step's pill and Open twice reach into it by
5 and 3 points, past their icon and words). While the row is pointed at, a faint bar shows there, 2 points wide and 40%
of the row's height; pointed at itself, the bar swells a little, to about 52% of the row's height and 3 points wide,
and fully lights, on a loose spring (`--swell`, 350 ms) that carries its ends about a point past where they stop and
back, so you see it answer the pointer. It goes back quietly as the pointer leaves it (150 ms). Lit by the module (a
reply waiting), it's the same bar at the same size in your move's colour, and it swells the same way. Whether it's
swelled is kept in state and drawn so each time the list is drawn again, so a rebuild never plays it twice. With
reduced motion it swells and lights at once.

On a list page on the panel's back (Sessions), the rows a press took off it, moved to the Trash or put back from it,
fold away one after another once the move is done: each row's words fade (120ms), then its room closes (220ms, on
`cubic-bezier(.2, .9, .25, 1)`), each 40ms after the one before, the stagger growing no further after eight rows, so
however many go it's over in well under a second (`foldLeaving`, in modules/apps/page/back.js). A section none of whose
rows stay goes whole, its heading and the line under it with its card. Rows that came onto the page, and a section that
came with them, its heading and line too, fade in lifting 3px over the same time (`growArrived`). The page is drawn
again on a clock, not as the animations end. With reduced motion, the page is just drawn again.

Anything that changes shape does so as one move: where it goes and how big it gets run together, on the same spring or
curve, never its size first and then its place (a chat becoming the held row, `chatHeldAt`). Anything that moves
without end in the open panel (the working words' shine, the turning ring, words breathing) animates only `transform`
and `opacity`, which the graphics chip moves without the page being painted again: an endless `background-position` on
clipped text, an animated `box-shadow` or a moving SVG group's `transform` has WebKit paint the whole page every frame,
so one moving row costs as much as many. Even `transform` and `opacity` are painted again every frame inside a scroller
under sticky bars (a side chat in One Task's view), so the working line is drawn still there (`workLineHTML`'s
`still`). The folded panel's eyes are the one exception, an SVG group that moves only
while they can be seen and holds still while the panel is open (`.cat-drift`).
