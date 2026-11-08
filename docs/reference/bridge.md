# The bridge

Every message between the panel's page and the app, and the bridges of the usage card's page and the panel's
back. Each type is answered by the core or by one module (`Modules`), as [How the pieces
fit](../how-it-works/architecture.md) describes them.

Bridge, page → native (`type`): `height` (`{value, under}`: the height the panel asks for, and how tall the lines under the header are, which it always keeps room for), `open` (with `carryOn` on a row's own press, when a module's words for a conversation opened again go in; never on Take me there or another press only to look), `pick`, `compact`, `wayPast` (the button past a terminal's reason, on
the Compact card or a step's note, `{sessionId}`: `Send` asks the session's host to take it), `switchAnswer`,
`answerAsk`, `holdAsk` (a request being answered on its card, a plan's notes typed there included, or in the reader
for a plan, `{id}`: no session you allow answers it meanwhile, and one that goes by itself if no one answers gets at
least another minute from its hook),
`openPR`, `keyboard`, `pointer` (`{shape}`: `hand`, `text` or `arrow`, what the pointer looks like where it is, which
the app shows, as WebKit's own shapes don't show in a window you don't type in), `log` (`{text}`: a line the page keeps
in `panel.log`, what it did by itself, as a request it brought into view), `badge` (`{value}`: how many need you, for
the pawn's count), `besideEdge` (`{needs}`: how many need you, for Whozmove beside the panel, through its place, told by notifications: at night, in quiet hours, only those stopped on you), `gitStep` (a
step pressed on a row
or in the changes view, `{step, into}`:
`commit`, `push`, `publish`, `pr` or `draftPR`, asked only if the checkout has it to take; `into`, the branch a pull
request goes into, one of the repo's on GitHub, else its default), `gitWays` (the ways to commit, in a menu under the
view's ⌄), `prBranches` (the branches on GitHub, for Create PR's details), `stepMenu` (Deploy's menu, as `step: "deploy"`),
`deploy`, `checkDeployCommand` (a command on Deploy's set-up card, about to be confirmed), `saveDeployCommand`,
`openAddress` (`{sessionId}`: open the address of the row's build that's up, which the app makes from the port it read),
`deployCard` (`{sessionId, act}`: a press on Deploy's card, `act` one of close, cancel, ports, next or replace; the app
finds the ports itself), `openDeployLog`, `copyInstall`, `checkInstall` and `stopDeploy` (`{sessionId}`: from the
card a run of the row's folder has to say, its log opened, the command that installs its packages copied, or what that
install runs worked out for Install First's second step, as the app finds it from the checkout's lock file, or the run
stopped as Stop Deploy does), `installAndDeploy` (`{sessionId, words, hash}`: Install and Deploy, your press only, with
what that step showed, run once before the deploy only if it's still what the install runs),
`expand`
(the reader's size, `{width, height}`: the panel grows beside the list to fit it, and is asked again as what's shown
changes) and `collapse` (back to the list), `turn` (`{on}`: the header's four squares turn the panel over to its
back), `header` (`{showing, gone}`: how many of the header's points still show as it's pushed away, which the drag
strip covers, and whether it has gone, for Whozmove beside the panel), `catShown` (the page's folded cat has
taken over from Whozmove beside the panel, where the panel folded round it), `catPose` (`{pose}`: the folded cat's
mood, asleep, watch or turn, which Whozmove beside the panel keeps too), `fold` (`{on, instant, room, peek}`: the
panel folds into the cat, or opens out of it; `room`, as `catRoom` names it, is where the chats still out go back to
beside the cat, which the window keeps as it folds; `peek` for the folded cat's list coming out or going back in,
which, asked the other way while it's still moving, turns back from where it is, and isn't kept for next launch),
`keepOpen` (the folded cat's list on pointing kept open by a press: the panel is left open for next launch), `catAt`
(`{x, y}`: where the name's o is, which the folded glass's middle is kept on), `catBreathe` (`{working}`: how many
sessions work, for the folded glass's breath), `catRoom` (`{parts, ask}`: the room beside the folded cat for its
chats, each part `[x, y, width, height]` from the glass's middle, which takes clicks, and `ask`, its number, which
`catRoomTaken` names), `readWriting` (one of a session's
writings, `{sessionId, id}`), `prototype` (the reader's prototype, shown from
its file over its space: `{action: show, sessionId, id, at, rect}`, `{action: place, rect}`, `{action: hide}` or
`{action: outside, sessionId, id}`, Open in Browser), `closeCopy` (from "open twice"'s details: the conversation's other
copies in terminals closed, `{sessionId}`), `readChanges` (one of the changes view's tabs, `{sessionId, scope}`, asked
for ahead as the row's numbers or its numbers are pointed at, so the view opens at once, `scope` being `unstaged`,
`staged` or `outgoing`, the commits not on GitHub yet), `openFile` (one of them in your editor, `{sessionId, path,
line}`, with `editor` when it was just chosen), `getEditor` (with no editor on this Mac, the picker's Get button:
the download page of the one it names, in your browser), `start` (a new conversation, `{startId, folder, app, words,
sessionId, trust, target, with}`: `sessionId` is the one the page chose for a terminal start, `trust` your yes on the card, `target`
where in the folder's repo when not its own folder, `{kind: open, path}`, `{kind: branch, name}` or `{kind: new, name,
base}`, `with` what the card's other parts gave it, by module name, each handed to that module once the start is a
session, as `{tickets: {tracker, site, key}}`, or `{tickets: {tracker, site, create: true}}` from Create a ticket), `checkFolder` (whether Claude may work there), `listBranches` (what a folder's repo has, for the card's #),
`checkWorktreeName` (whether a new worktree can be made, `{folder, name, base}`), the tickets module's: `ticketSearch` (`{words, asked}`: the card's search, as you pause typing), `ticketFind`
(`{text, asked}`: a key or link written or pasted, read for the card's chip), `ticketSignIn`, `ticketCancelSignIn` and
`ticketCopyAsk` (`{tracker}`: signing in with its page in your browser, or Allow while macOS asks first; ending that;
what to ask an admin, copied), `ticketAnswer` (`{sessionId, act}`: Use It or Not Now, `use` or `notNow`, on a row's
"Work on PAY-148 here?"), `ticketRead` (`{sessionId, now}`: its tag's card opened, or Try Again; `now` for Try Now,
past a tracker's wait), `ticketMove` (`{sessionId, key, stepId, at, act}`: Move It, or Try Again, `move`, or Not
Now, `notNow`, on a row's "Move PAY-142 to In Review?", taken only for the move that card showed, by its ticket, its
step and when it was asked), `ticketDraft` (`{sessionId, at, act}`: Create Ticket, or Try Again, `create`, or Not Yet,
`notYet`, on a row's "Create this ticket?", taken only for the draft that card showed, by when it was drafted) and
`openTicket` (`{sessionId}`: the ticket in your browser, at the address made from its site
and key), the waits module's `waitSay` (`{sessionId}`: Resume on a row whose conversation runs again and hasn't asked,
which has the app type Resume's words in, by your press), `startMenu` (the card's small menus,
`{kind}`: `app`, `places` with `repo`, or `choose`), `startWay` (the card's way past having nowhere to start it,
`{kind}`: `track`, Claude Desktop's sessions tracked again, or `getDesktop`, its download page), `spotify` (the now-playing strip's presses, `{action}`:
`playpause`, `next`, `previous`, `seek` with its `fraction`, `open` or `settings`; `folded` once it has folded away;
`collapsed` `{on}`; and `lyrics` `{on}`, your answer about lyrics), `install` (the setup line's button, `{action}`:
`tools`, which has macOS show its own installer for Apple's developer tools, `addBack`, `turnOn`, `retry`, or
`getAgent`, the agent's install page in your browser; `copyUpgrade`, the command that updates Whozmove put on the clipboard, `putAwayUpdate` with `version`, its ×,
`reloadAll`, the line's Reload Them, and `reload` with
`sessionId`, a row's Reload, for the sessions running since before the hooks went in; the app holds the commands and
the address, and does nothing for one that no longer fits), `storageNoteClosed` (the low-disk line's ×, or with
`ready` the map-ready line's), `appsShow` (`{app}`: the page asks the apps module to show that app's page on the back,
then asks to turn), and the map's `storageFolder` (`{id}`, 0 for the disk), `storageMeasure`, `storageTrash` (`{ids,
keep, measuredAt}`, the map's own, the parts taken back out of a folder collected whole, and the map they're on),
`storageReveal` (`{id}`), `storageAllow` (Allow Access, on a row the map couldn't look inside, or Keys' Allow Full Disk
Access), `storageOn` (`{view}`: the low-disk line's press, or Map My Disk, while Storage is off: it turns on and opens
on that tab) and `storageOff` (Turn Off, where Clean up says Storage just turned on), and Clean up's `storageCleanUp`
(its list),
`storageClean` (`{ids, measuredAt}`, the list's own) and `storageOpen` (`{app}`, an app it offers to open), Keys'
`keysLook`, `keysAction` (`{id, action, place, file}`), `keysMenu` (`{id, x, y}`), `keysClosed` (`{ids}`) and
`keysAgain`, Messages' `messagesOpen` and `messagesClosed` (it shows beside the list, or no longer does: only while it
shows is it sent what changed) and `messagesCopy` (`{id}`, a message that didn't get there: the app copies the words
it holds for that id), and the notifications line's `noticePress` (`{id}`, its button: the sender's own press), `noticeAway` (`{id}`, its ×, or a line
that says all went well gone by itself once seen), and One
Task's `taskAnswer` (`{sessionId, id, sent, answer, note}`, your answer to the task in front as it was sent when it
showed, `sent` being when: one its kind has, docs/reference/task.md), `taskLetGo` (`{sessionId, id}`, a task its session took back, let go
once you're not on it), `taskPutBack` (`{sessionId, id, sent}`, Can't
Now), `taskSeen` (`{sessionId, id, sent}`, you've come to a task you've read: kept with it as `seenAt`, the newest,
through its next steps and a restart), `taskCopy` (`{sessionId, id, sent}`, its command put on the clipboard), `taskOpen` (`{sessionId, id, sent, at}`,
the link or page attached at `at`, in your browser; the app takes each from the task as it was checked, never from the
page), `taskSay` (`{sessionId, id, sent, to, words}`, your words about the task in front, to the session it's about:
`to` is `lead` to ask the lead rather than its member, before the talk begins; the app finds the session
itself, and types them in after the words that name the task, once the session can take them), `taskTakeBack`
(`{sessionId, id, sent, at}`, words said at `at` taken back before they go in) and `taskSayNow` (`{sessionId, id, sent,
at}`, held words sent now by your press, into the tab you're in or Claude Desktop), `taskTalkCopy` (`{sessionId, id,
sent, to, words}`, words that couldn't go in, put on the clipboard as the app would type them, for you to paste in the
session yourself), `taskWordsCopy` (`{words}`, your own words about a task taken back while you were away, Copy
Your Words, on one line, never run), `taskReplyCopy` (`{sessionId, id, sent, at, part}`, a code block of the reply to words said at
`at`, by its place among the reply's parts, copied exactly as the app read it, never run) and `taskTalkPermission` (`{}`, Accessibility's pane in System Settings, by your press on the way
past "Whozmove needs the Accessibility permission"), `oneTaskWaiting` (`{count}`, how many wait, for the pawn menu's One Task), side chat's `sideChatSend` (`{sessionId, words, aside}`, your words to a session, going in between its steps while it works, or typed in while it's idle; `aside`, when a side question the copy couldn't answer is sent this way with Send's words, the time it was asked), `sideChatTakeBack` (`{sessionId, at}`, words sent at `at` taken back before they go in), `sideChatSendNow` (`{sessionId, at}`, held words sent now by your press, or words it stopped before reading sent again), `sideChatCopy` (`{sessionId, words}` or `{sessionId, at}`, words put on the clipboard as they'd go in, Copy and Go, never run), `sideChatReplyCopy` (`{sessionId, at, part}`, a code block of the reply to words sent at `at`, copied exactly as the app read it, never run), `sideChatPutBack` (`{sessionId, at}`, words the page has put back in your box, let go of so they're put back once), `sideChatAsk` (`{sessionId, question}`, a question asked on the side, which a copy of the session's conversation answers), `sideChatAskStop` (`{sessionId, at}`, the side question asked at `at` stopped), `sideChatAsideCopy` (`{sessionId, at, what, part}`, a side question's answer, its question or one of its answer's code blocks, `what` answer, question or code, copied as the app read it, never run), `sideChatCopySignIn` (`{sessionId}`, the command that signs Claude Code in, copied) and `sideChatGetAgent` (`{sessionId}`, where to get the session's agent, opened in your browser), and notifications'
`noticeAwayHere` (`{id, since, awayFor}`, a page sender's notice put away by its ×, and for how many seconds at most,
0 for only while it's said the same way), `besideSeen` (`{seen}`, what of each
notice has come out beside the folded panel, by its id, what made it new then, kept for a restart), and Sessions'
`sessionsUnread` (`{ids}`, the listed sessions with a reply you haven't read, as the list counts it, sent as they
change) (each routed
by its type to the core or the module that answers it: `Modules`).
`answerAsk` for a plan carries `message` (your notes) or `stop`; for Claude's questions, `answers`, and with a no,
`clarify` to chat about them (the hook tells Claude so, with the answers picked so far). Native → page:
`update(rows, now)`, `panelSeen` (whether anything of the panel can be seen: false while it's hidden from the menu bar,
or the screen is asleep or locked, when the list isn't drawn; never false while it's flicked off the screen's edge;
said again each time the page loads), `setRoom(room, most)` (how tall the panel can grow where it is, and the most its header and list take on its screen), `hoverAt`/`hoverEnd` (with `still` while the pointer is off the panel
without having moved there: the panel's edge went past it, or one of its menus closed there; `hoverEnd` comes again
once it moves; and `held` while it's on what the panel holds over or under itself, Spotify's token or the usage card),
`keyboardGone` (the panel no longer has the keyboard), `turned` (the panel is turning over to its back, or back on its
list side), `turnToApps` (Settings… in the pawn menu: the panel turns over, an open reader folding back first),
`setGroupBy`, `setConversationShown(on)` (Settings' Show Conversation Text: off, rows show no one's words),
`toggleCollapsed`, `stepNote` (with `quiet` when
it says how something went that worked, and `way`, the button past a terminal's reason, when there is one, or with
`go`, a button that does something on the page instead: `open`, Take me there, opening the session, or a module's own
in `core.noteWays`, as the commands module's `modeMenu` opens the mode menu again),
`setRunningBuild` and `setSwitches` (the bridge's, in `parts/bridge/page/app-calls.js`, but for `turnToApps`, in
`input.js`); `foldFromSide(x, y)`
(Whozmove beside
the panel was pressed: the panel folds round it, there), `catLanded` (it has grown into the folded cat, which takes
over), `catPointer(x, y)` (where the pointer is from the folded glass's middle while it's near, or null), `catGlass`
(the glass is about to spread out from behind the cat as the panel opens), `catWay({right, up, across, tall})` (which
way what comes out of the folded cat goes, and how far there is to the screen's edge), `catRoomTaken(ask)` (the window
has the room asked for beside it, in the ask it names) and `catMoving(moving)` (the folded cat is being dragged with
something out beside it, which goes in meanwhile, and has stopped) (in `cat.js`); `catPressed(down)` (the folded cat
pressed, and let go: its list doesn't come out on pointing meanwhile) and `flickedAway` (the panel was flicked off the
screen's edge: open from pointing, it's kept open) (in `peek.js`); `readerOpened(side, width)` (which side the list
stays on, and the reader's width) and `readerClosed` (in `reader.js`); `readerSide(side)` (the side the reader would
open to now, as the panel moves, where a row's bar at its far edge is) (in `rows.js`); and each feature's, in its own
script:
`compactNote` (why a compaction didn't go in, and the button past it, `(sid, text, way)`) (`commands.js`),
`setDeploys`, `openDeploySetup`, `deployChecked` (what that command really runs,
`{command, production, runs, cut, files, unsure, others}`) and `deployInstallChecked` (what Install First's install
runs in a folder, `(folder, {words, lockfile, makesLockfile, runs, cut, files, unsure, others, hash}, again)`, `again`
when it changed under a press of Install and Deploy) (`deploy-row.js`), `setTicketTrackers` (each tracker's
sign-in, `[{name, signInName, signIn, sites, why}]`, `signIn` one of `out`, `signing`, `in`, `blocked`, `expired` or
`allow`), `ticketsFound(asked, {tickets, end, why})` (what the card's search found, each ticket as a row's
`ticket.bound` has it, or why not: `end` one of `signIn`, `slow` or `failed`) and `ticketPicked(asked, said)` (`{ticket}`,
`{none}` for no tracker's key or link, or `{key, end, site}`, `end` one of `signIn`, `site`, `elsewhere`, `notFound` or
`failed`) (`tickets.js`), `setPRBranches(sid, {base, branches})` (`git-steps.js`),
`openStart`
(⌃⌥N, New Conversation), `folderChecked` (`{trusted}` or `{gone}`), `startUpdate` (how a start went: `{sessionId}`
once it's listed, `{note}` while it waits on you, `{why}` if it didn't start), `startProject` (a folder picked from the
card's chooser), `branchesListed` (`{here, worktrees, branches, base, folder, folderPath}` or `{none, where}`),
`worktreeNameChecked` (`{path, where, name, base}` or `{why}`), `worktreesMoved` (a repo's worktrees go somewhere else
now), `startAppChosen` (from Start's menu) and `setStartOptions` (`{terminal, desktop, installed, choice}`, the
terminal a start can open in, or null, whether Claude Desktop's sessions are tracked, without which nothing starts
there, whether it's on this Mac, and whether Start's menu has another app to pick) (`starts.js`),
`setInstall` (how Whozmove's setting itself up stands, `{state, detail, since, busy, reload}`: the
install module's states, since when it has been so, which a × on the line holds for, whether a press is under
way, and how the sessions running since before the hooks went in stand: `{open, idle, byHand, first, waiting, going,
done, total, since}` (`first`, the first left for you to reload, `{sessionId, name, command, held}`), or `{allSet,
since}` once a press has reloaded the last of them, and `update`, `{version, command}`, a newer Whozmove out
through Homebrew) (`install-line.js`), `setBesideSeen` (what came out beside the folded panel before, by notice id, as the page loads, or null on a first launch, or when the record keeps nothing that's a notice's) (`notices.js`), `setNotices` (what every module has to tell you now, `[{id, level, text,
button, pressedWord, busy, closes, done, tag, answersYou, session, outFor}]`, `level` being `urgent`, `soon` or `know` and `id` the
sender and its key, where the panel is, `{shown, parked, quiet}`: not hidden from the menu bar, flicked off the
screen's edge, and quiet hours (only what's urgent said), and the page senders' notices put away, `{id: since}` or `{id: {since, at, awayFor}}`) (`notices.js`), `setTasks` (the tasks sessions sent that wait, `[{sessionId, task, at, sent, back, pick, for, talk, takenBack, pickAt, pickPriority, seenAt}]`,
whether One Task is on, the kinds' words by kind, from the task's contract (TaskKindWords), and how it works, as
its page under Tools sets it: `{next, why, waitForGo, talk, held, turnedAway}`, what comes after anything urgent
(`picks` or `oldest`), whether each task says why it's where it is, whether something urgent waits for your Go,
whether the talk is under each task, whether words written while a session works go in by themselves (`self`) or
wait for Send Now (`wait`), and the sessions that may not hand you tasks now, what they sent waiting unseen, `pickAt` a pick's place in its lead's
queue, `pickPriority` how pressing its job is there (`critical`, `p0`, `p1` or `p2`), `takenBack` why its session took it back
(`answered`, `parked` or `dropped`), shown without its buttons until you move on, `talk` being
what you asked the session about it: `{to, toLead, says, lead, leadForMember, terminals}`, each of `says` `{at, words,
state, why, way, permission, where, reply}` (`permission` when `way` is Accessibility's, `where` the terminal or Claude
Desktop it couldn't type into), `terminals` the terminal each session it may be with runs in, by session, and `inFront` those whose terminal is the
app in front, where held words wait for your press, `reply` read from the session as its turn ended, the whole reply to the very line typed in, cut into its parts, each
`{prose}` or `{code, lang}` (a code fence, as written between its fences), and `lead` the words that open yours, `pick` for a lead's pick
and `for` the member's session it's for,
and whether One Task is on) and `openOneTask` (the pawn menu's One Task, once the panel is up on its list side)
(`one-task.js`), `setSideChats` (each listed session's side chat, by session: `{says, asides, askWhyNot, agent, hook, frame, front, idleWay}`, your words and how far each got, each reply read, your questions on the side and their answers, held in memory only, why nothing can be asked on the side now, the name of the agent they're asked through, whether its agent's hook hands words in between its steps, the words that open yours while it works, its terminal when that's the app in front, and why nothing can be typed into it while it's idle) (`side-chat.js`), `setNowPlaying` (the song Spotify is playing, or null) and `setLyrics` (what's known of its lyrics:
`{state}`, and for a song's `track`, with `lrc` or `plain` once found, or `none` or `failed` when there are none to be
had) (`spotify.js`), `setGear(facts, pressed, off)` (your gear, as on the usage card's page below, sent to both at once)
(`gear.js`),
`showWriting(sid, id, {text} or {missing})` and `prototypeState(sid, id, {loading, problem, asked, keyboard})`
(`writings.js`), and `showChanges(sid, scope, {scope, v, files} or {missing} or {counting})` (each file `{path,
status, binary, untracked, alsoStaged or alsoUnstaged, hunks: [{oldStart, newStart, lines: [[sign, text]]}]}`, with
`cut` past 30,000 lines; Outgoing's `{scope, v, upstream, commits: [{hash, short, subject, at, files}], more}`) and `setEditors({choice,
apps: [{id, name}], get})` (`get`, the editor to get, by name, while none is on this Mac) (`changes-view.js`),
`setDisk({show, tone, head, sub, free, total, used, fullInDays, lines, on, cleanable})`
(what the low-disk line says, and whether it shows) (`disk-line.js`), and `setStorage({on, scanning, counted, scannedAt,
usualAt, fullDiskAccess, ready, busyAt})`, `showFolder(id, view)`, `storageTrashed({moved, size, refused})` and
`openStorage(view, turnedOn)` (Storage, on its tab,
saying it just turned on: `map-view.js`), `setBoard(teams, kinds, on, working)` (each team as a whole, as
docs/reference/team.md's "Each team as a whole" gives it, each kind of task with its word, `{kind, word}`, in One
Task's order, whether Show Team Board is ticked: sent either way, as Up next shows for any team with a lead; off,
only Up next shows; and the ids of the sessions working now, A to Z, as parts/work's `SessionWorking` counts them,
the rule the gear counts with, sent again whenever they change) and `openBoard(project)` (the team board on that
project's team, on Glance; Up next's All goals, `view` `upnext`, comes only from the board's own page:
`board-view.js`), `setMessages(messages, inboxes, counts, facts, whole)` (Messages,
only while it shows: each message `{id, from, to, at, text, cut, delivery, deliveryAt, canAsk, kept}`, `from` and `to`
`{session, name, folder, ended}`, `kept` what the inbox keeps of one written to a team's lead, `{id, priority, about,
readAt, readBy, answeredAt, note}`, or null; each inbox with messages its lead hasn't read, `{project, lead, unread}`,
the ids in the order it reads them; this week's counts of what didn't reach a lead, `{held, expired, denied, dropped,
failed, lost}`; `{reading, agent, now}`, `agent` the agent's own name, or null while none records its messages; and whether it's all of them or only those new or changed since),
`openMessages()` and `closeMessages()` (`inbox.js`), and `showCleanUp(list)`,
`cleanProgress(step)` (each ticked item's step as it's cleaned) and `storageCleaned({freed, trashed, cleaned, failed,
ran})` (`clean-view.js`), and `setKeys(found)`, `keysActed(id, why)` and `keysAsk(id, place,
file)` (`keys-view.js`; modules/storage/README.md has their shapes). `setDeploys` gets `{projects: {project: {command}}, folders: {folder:
{suggested, port, at, skippedAt, run, asked, card}}}` (`port`, the one a deploy there gets in $PORT; `card`, Deploy's card
for the folder when a press didn't run: `{kind: clash|held, port, other, otherFolder, fixed, old, next, name, minutes,
session, sessionName}`), where a run is
`{startedAt, running, ok, finishedAt, lastLine, lastLines, endedItself, noPackages, stopped, by, port, up}` (`by`, the
session that asked for it, when one did; for one that didn't go through, `lastLines`, the last five lines of its log
with terminal codes and direction marks taken out, `endedItself` when it was up and ended by itself, and `noPackages`
when it couldn't find a program or a package in a checkout with a package.json and no node_modules, with `install`,
the command that would install them, and `lockfile`, the lock file it comes from (none: it makes one); `installing`,
that install's words, while a run installs the packages first, then `installedAt`, when it went through;
`installFailed`, that install's words, for a run whose install didn't go through, so the command never ran; `up`, once it
listens, `{port, at, every, also}`: the port it's up on, since when, whether on every address, and the other ports it
listens on), `asked` a deploy a session asked for there, waiting, `{by,
waits}`, and `kept`, `{sessionId}`, while your press of Deploy there waits for an agent to be done (a press of
`deploy` while the row's Deploy waits keeps one); a project
is a repo's main checkout (or a folder outside git), saved by its real path (symlinks resolved, as `build.sh` finds it),
and a folder is the checkout a session runs in (for one that runs outside any, the one it last edited files in).

The usage card's own page (modules/usage/page/card.html) has a bridge of its own, in the same shape, in its own window
(`UsageCard`): it sends `usageSignIn` (its Sign in), `gearSet` (`{to}`: a press on one of the gear's seats, the gear it
sets, from 1 to 30) and
`usageCard` (`{shown, extent}`: whether there's a card,
and how much of it shows under the panel's edge, in points, where its window takes clicks), which the usage module
answers;
and the app calls its `setUsage` (your plan's usage: `{state, plan, session: {used, resetsAt}, week, limits: [{kind,
percent, severity, resetsAt, model}], extraUsage, checkedAt}`, where `state` is `ok`, `signedOut`, `other` or `none`),
`setHeaviest` (the session that has used the most today, `{name, share, tokens}`: its name, its share of what the
listed sessions used today in percent, and how long its conversation is now, or null while fewer than two have used
any), `setGear(facts, pressed, off)` (your gear, called on the panel's page too, at once, each time it changes and after
your press, `pressed`: `{gear, atWork, counted, over, room, recommended, notYet, limit, bound, forecast, checkedAt}`,
as app/contracts/Module.h's `GearFacts` says, the words for it being usage.js's; null, with `off` true, while the gear
is turned off in Settings), `signInFailed(why)` (its Sign in
couldn't open a terminal, and why, as the terminal says it, with the command to run yourself), `previewWait` (Working
on Whozmove's Preview the Wait), `cardPointer` (where the pointer is in its window, `{x, y}` from
its top-left corner, while it's near, with `from`, `{x, y}` the same way, where it was at the app's look before, even
outside the window, so the card slides out for a quick hand that crossed the panel's edge between two looks; or null
once it has gone: its window is never key, so it gets no mouse moves) and
`cardAppear(drawIn)` (its window has faded in, its fill drawing in with `drawIn`, or come back into sight with the
panel: it looks once, without moving, then its clock runs) and `cardGone` (its window has faded out, or gone from
sight with the panel: its clock stops) (`card.js`).

The panel's back (modules/apps/page/back.html) has a bridge of its own too, in its web view (`BackPage`): it sends
`appsTurnBack` (`{side}`: `right` for its rows, `left` for ‹ on its apps, the way the panel turns back), `appsFold`,
`appsSetting` (`{key, value}`: a setting's switch on or off, or a choice's id),
`appsSettingButton` (`{key}`: the button under a setting's line, its way forward), `appsSwitch` (`{app, key, on}`),
`appsChoice` (`{app, key, value}`: one of a choice's choices on an app's page), `appsTime` (`{app, key, end, x, y}`:
one end of a part of the day, for the app to open its menu of times where it is), `appsUseRecommended` (`{app}`),
`appsOpen` and `appsPrivacy` (`{app}`), which the apps module answers, and `appsAction` (`{app, key}`, a card's
button, or one on a tool's card) and `appsList` (`{app, list, key, ids}`, a press on a list's page: its tray's action,
a row's way or button, or what was said's, with the ids it's for), which the module whose card or list it is answers;
and the app calls its `setApps(apps, look, settings)` (each app `{id, name, does, icon, open, switches, groups,
recommended, statuses, lists, permission, tool, card, hint}`, a group a heading, its rows (switches, choices and parts
of the day) and a line, a status being one of its cards, a list `{key, title, count, intro, loading, empty, sections,
tray, said}` as contracts/Module.h's AppList has it, each setting `{key, kind, title, glyph, group, page, style, foot,
button, on or value, choices, or app and said}`), `showSettings` (Settings… in the pawn menu: Settings, from
whichever page shows, as the panel starts
turning over or while it's turned), `showApp(id)` (the page to be on as the panel turns over to it), `turned(false)`
and `backPointer` (`{x, y}` from its top-left corner while the panel is turned over and the pointer is on it, or null)
(`back.js`). modules/apps/README.md has each one's shape.
