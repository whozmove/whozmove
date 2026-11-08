// Row: one session as the panel lists it. docs/reference/rows.md says what each field means and where it comes from.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@interface Row : NSObject
// A row from Claude Code's registry entry for a running session, or from a row the page sent back.
- (instancetype)initWithFields:(NSDictionary *)fields;
// Adds what the hook recorded for the session. Its fields win: where it has one, it's the newest word.
- (void)takeHookRecord:(NSDictionary *)record;
// The row as the page gets it.
- (NSDictionary *)json;

// Claude Code's registry.
@property (copy) NSString *sessionId, *hostSessionId, *cwd, *name, *entrypoint, *status, *procStart;
@property (assign) pid_t pid;
@property (strong) NSNumber *statusUpdatedAt;
// The conversation's other copies, when it's open more than once (resumed in a second tab while it still runs, or open
// in Claude Desktop and a terminal): each {entrypoint, paused, busy, hostSessionId}, `paused` for one stopped in its
// terminal (Ctrl+Z), `busy` for one at work, and Claude Desktop's id for one there. The row is the copy that needs you
// most; these are the rest.
@property (copy) NSArray<NSDictionary *> *alsoOpen;

// What the app that keeps the conversation knows of it (Claude Desktop's own record): when it last did something and
// was last looked at.
@property (strong) NSNumber *activityAt, *lastFocusedAt;
// Its setup as that app shows it, {model, effort, mode, at (when the app last saved it, in ms since 1970)}, which the
// details line goes by first, and a command sent from the panel watches for the change. Not sent.
@property (copy) NSDictionary *hostDetails;

// The hook's record.
@property (copy) NSString *lastPrompt, *lastReply, *notice, *activity, *outcome, *workRoot, *permissionMode;
// Who sent the last prompt when it wasn't you: another session, by its name, its address (its messaging socket), and
// its session's id, found the first time the message is read, if the process that sent it ran then and started before
// it came.
@property (copy) NSString *promptFrom, *promptFromAddress, *promptFromSession;
@property (strong) NSNumber *lastPromptAt, *lastReplyAt, *stageAt, *outcomeAt, *builtAt, *editedAt;
@property (copy) NSArray<NSString *> *workSteps;
@property (copy) NSDictionary *audit;
// The jobs its agent still runs in the background after its turn, each {what, command, step, startedAt, holds, stop}:
// what it is, a shell command's command line, the step an agent among them is on, when it was first noted, `holds` for
// one that can change files in its folder, which its next steps and Deploy wait for, and what typed in the session
// stops it, as its agent says. Missing while there are none. Its agent's module makes it from the hook's record,
// leaving out the ones that are plainly over.
@property (copy) NSArray<NSDictionary *> *background;

// What the app adds.
@property (copy) NSDictionary *git, *workGit, *checkout, *ask, *agent, *changes;
// Why its next steps and Deploy wait for the jobs it runs in the background that hold them, as the work part words it
// ("until “Review the native side” is done in the background …"), for its Deploy's tip; nil when none do.
@property (copy) NSString *backgroundWait;
@property (copy) NSArray<NSDictionary *> *prs, *writings;
@property (strong) NSNumber *messageAt, *compacting, *seenAt;
// A pick from the panel on its way into the session, {field, value, inTerminal}: `inTerminal` once Claude Code is
// asking about it in the session's terminal before it goes in.
@property (copy) NSDictionary *goingIn;
// "Switch model?" asked on its row, {from, to, tokens, never}: before /model goes to a Claude Desktop conversation, once
// Claude's own box asks it there, or while a terminal session's hook waits for the answer.
@property (copy) NSDictionary *switchAsk;
@property (assign) BOOL focused;
// A compaction from the panel certainly couldn't go in now, as far as can be told without asking its terminal: it runs
// in no terminal the panel can type into, or it's open twice. The page doesn't suggest compacting it then.
@property (assign) BOOL noCompact;
// Whether now is a natural break to compact it, and why, {why, kind}, or nil (the commands module's CompactTime): its
// ring says "Compact now" then, and Compact at Breaks compacts it by itself at a `saved` or `full` break.
@property (copy) NSDictionary *compactTime;
// What Compact at Breaks did for it, until its next message (the compact-at-breaks module): {at, why, before, after}
// once it compacted it, {at, stopped} once it stopped part-way, {at, failed} once it didn't go through.
@property (copy) NSDictionary *compactedFor;
// Why a compaction from the panel can't go in, as a module says it, {text, way}: its words in full, and the words of
// the Compact card's button past it, or null. The ring's tip says it, and its card opens saying it.
@property (copy) NSDictionary *compactNote;
// Worked out from the fields above as they're read, so the page and the app go by one rule, sent as `onItAt`: when you
// were last on the session, in ms since 1970 (on it in Claude, Ghostty or iTerm2, `seenAt` and Claude Desktop's
// `lastFocusedAt`, or writing to it, not another session writing to it, `promptFrom`).
@property (readonly) double onItAt;
// When it last edited files where its edits last landed (`workRoot`), in ms since 1970, or 0, as its agent's module
// works it out from what the agent's hooks recorded, so the page and the app go by one rule: sent as `workEditedAt`,
// only with `workRoot`.
@property (assign) double workEditedAt;
// A running session that started before Whozmove's hooks went into its agent, and runs without them until it reloads
// them: {state}, `needed`, `waiting` (its turn), `reloading`, or `byHand` with `why`, `command` and `held`, left for
// you to type in it: the panel can't type into it, or Claude Code held the reload back (`held`).
@property (copy) NSDictionary *reload;
// Its place in the team the session leading it keeps, if there's one (the team module): {role, name, part, job,
// counts}, or {inFolderOf} for another session open where one of the team works, with {duplicate, earlier, seat} for
// one running in a member's own workspace while another holds the member's seat.
@property (copy) NSDictionary *team;
// The ticket it works on, from a tracker, as the tickets module last read it ({bound, offer}: docs/reference/rows.md).
@property (copy) NSDictionary *ticket;
// What it waits on while it waits on someone else, the waits module's alone (docs/reference/rows.md): {says, spoken,
// on, came, cameSpoken, cameFirst, cameMore, held, closed}: its words for the row, the same for VoiceOver, what it
// waits on as each source named it ({source, url} for a pull request), what came, the same for VoiceOver, the first
// that came and how many more, whether that waits for a seat in the gear, and whether its conversation has closed (kept
// for Resume). Missing while it doesn't wait. The Claude Code module reads only whether a row has one at all, as the
// rows were last listed (noteWaitsAsListed), to keep a closed row listed while it waits, and, on the page, whether it's
// `closed` (ended.js), to say it stopped only once.
@property (copy) NSDictionary *wait;
// What a session you allow last answered for you on this session's behalf, for a while after (its agent's module):
// {by, what, title, note, at}, `what` sentBack.
@property (copy) NSDictionary *answeredFor;
// When its agent's hooks last wrote their record of it, in seconds since 1970, read with the record. Not sent.
@property (strong) NSNumber *hookRecordedAt;
// For a terminal session that has ended: the app id of the terminal it last ran in, as its agent kept it (not sent),
// and the name of the terminal a press on its row opens it again in.
@property (copy) NSString *ranIn, *opensIn;
// What was picked for it in the panel and the session hasn't confirmed yet, {field: value, <field>At: when}, which its
// details show until it does. Not sent.
@property (copy) NSDictionary *chosen;
@end
