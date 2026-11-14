// TaskRecord: what One Task keeps for one session, as plain functions over its record (AppDir/one-task/<session>/
// record.json): the tasks it has sent that wait, and the answers you've given. One session's record is only ever read
// or changed for that session: as the core found it asking, or, for a team's lead, from the picks it sends itself
// (TaskRecordPick), so no session sees or replaces another's. Checked by --print-tasks, with no window.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// The record, in the shape it's kept in:
//   { pid, processStart,                          the session's process that sent them: they go once it ends
//     tasks: [ { task, at, sent, back, pick, for, seenAt } ],   what waits, in the order it came (`at`, ms since
//                                                 1970), and when it was last sent (`sent`), which an answer names so
//                                                 it never lands on words sent after the ones you read; `back` once
//                                                 you've said Can't Now, which puts it at the back of your line;
//                                                 `pick` for the lead's pick, and `for`, the member's session;
//                                                 `seenAt`, when you were last on it in One Task, once you'd read it
//     answers: { "<id>": { id, step, answer, note, at, firstAt } },   your answer to each, until its next step
//                                                 comes, and when the task first came, so that step keeps its place
//     pickTasks }                                 each lead's pick sent, by id, kept after it goes so the same
//                                                 one sent again stays as it was
// Every function returns a new record, and takes nil for none.

// How many of one session's tasks may wait at once: not a limit anyone meets, only a ceiling so a script that sends in
// a loop can't fill the record and the page. Nothing waiting is ever dropped to make room; the one past it is refused.
// docs/reference/task.md says the number, once.
extern const NSUInteger TaskMostWaiting;

// A checked task (TaskFrom) sent by the session's process `pid`, which started at `started`, at `now`. With an id
// that's waiting or answered, it's that task's next step: it keeps its place in the line, and the answer to the step
// before goes.
// Returns the new record, and what to say back (`said`); or nil, with why it can't be taken (`why`).
NSDictionary *TaskRecordSend(NSDictionary *record, NSDictionary *task, pid_t pid, long long started, double now,
                             NSString **said, NSString **why);
// Your answer to the task with `id`: it no longer waits, and the answer is kept for the session to ask for. `answer`
// is the choice picked, Comment among them; `note` what you typed with Comment, or nil.
NSDictionary *TaskRecordAnswer(NSDictionary *record, NSString *taskId, NSString *answer, NSString *note, double now);
// A pick a team's lead sends itself (ask-panel.sh task --pick-for), for its member's session `member`, the one home of
// a pick's member: kept in the lead's record as its pick (`pick`, `for`), not counting toward TaskMostWaiting, shown
// only once the team file's queue names it (TaskRecordQueue), and waiting until it's answered or taken back, whatever
// the lead sends next. Sent again under its id with something new, it's its next step, in the place it had;
// unchanged, it stays as it was (each pick sent is remembered by its id, `pickTasks`).
// Nil with why past TaskMostWaiting picks, or when it shares an id with one of the lead's own tasks waiting.
NSDictionary *TaskRecordPick(NSDictionary *record, NSDictionary *task, NSString *member, pid_t pid, long long started,
                             double now, NSString **said, NSString **why);
// The lead's queue, as its team file names it (row.team.queue's ids, in its order, and `priorities`, each id's job's
// priority): each pick it sent is marked as named there (`pickAt`, where) with its job's priority (`pickPriority`,
// which places it when its member has no ticket), and shows from then on (`shown`), from `now` the first time it's
// named (`shownAt`, when it waits its turn from); one no longer named keeps waiting, with neither, until it's answered
// or taken back. An id it names but never sent is kept, so task-answer can say so.
NSDictionary *TaskRecordQueue(NSDictionary *record, NSArray<NSString *> *ids,
                              NSDictionary<NSString *, NSString *> *priorities, double now);
// Can't Now: the task goes to the back of your line, and the session is told when it asks.
NSDictionary *TaskRecordPutBack(NSDictionary *record, NSString *taskId, double now);
// You're on the task with `id` in One Task, and have read it: `seenAt` is now. It's the task's, not its step's, so it
// stays through its next steps (a lead rewording its pick, a session sending what's new), and One Task keeps it in
// front through them, and after Whozmove restarts. A task taken back and sent again is new to you, and loses it.
NSDictionary *TaskRecordSeen(NSDictionary *record, NSString *taskId, double now);
// The session taking back a task of its own, or a lead its pick, because `why` (TaskTakenBackWhys: answered elsewhere,
// its job parked or dropped): marked `takenBack` with why, no longer answerable, and kept only until the page lets it
// go (TaskRecordLetGo), which it does at once unless it's the one you're pointing at or typing in. task-answer then
// says it was taken back, and the same task named again unchanged stays gone; sent again changed, it's its next step.
// Nil with why when no task of that id waits.
extern NSArray<NSString *> *const TaskTakenBackWhys;
NSDictionary *TaskRecordTakeBackTask(NSDictionary *record, NSString *taskId, NSString *why, double now, NSString **said);
NSDictionary *TaskRecordLetGo(NSDictionary *record, NSString *taskId);
// Whether `answer` is one the task's kind has: Comment, its plain answer (Works for a try, Approve, Done, Seen), or
// its choices' ids (one; two joined with "+" for a pick that mixes them; any
// joined with "," for an answer that takes several), or More Options for a pick.
BOOL TaskRecordFits(NSDictionary *task, NSString *answer);
// The longest note you may send with an answer.
extern const NSUInteger TaskMostNote;
// What ask-panel.sh task-answer says of `id`: "answered: " and the answer as one line of JSON; "waiting", "can't now"
// once it's been put back, or "gone" when no task of that id waits or was answered.
NSString *TaskRecordSays(NSDictionary *record, NSString *taskId);
// The tasks waiting, each { task, at, sent, back }, in the order they came.
NSArray<NSDictionary *> *TaskRecordWaiting(NSDictionary *record);

// The talk about a task is its session's own chat (Side Chat's). What One Task keeps for it: the words that open yours
// there, and the most that Copy Your Words copies of what you wrote about a task that no longer waits.
extern const NSUInteger TaskMostTalkLine;
// The words that open your words in the session, naming the task as kept: "About your task “Search as you type” (step 2
// of 3, On a phone): ". For the lead's pick sent to its member (`lead`, the lead's name), none of the lead's words:
// "About the task Atlas gave me on your work (step 2 of 3): ", the lead's name only when it's a short plain name
// (TaskTalkName), else "your lead", as a team file could name a lead with a sentence. One plain line, starting with a
// letter and ending in its one space, within Task.h's limits (at most about 200 characters), so your words never start
// a command (/, ! or #), and nothing another session wrote reads as yours.
NSString *TaskTalkLead(NSDictionary *task, NSString *lead);
// A name as it may open your words to a member: TaskMostTalkName characters at most, only letters, digits, spaces and
// hyphens, else nil.
extern const NSUInteger TaskMostTalkName;
NSString *TaskTalkName(NSString *name);

// --print-tasks: each case, what the shape's check and the record's rules make of it.
int PrintTasks(NSArray<NSString *> *arguments);
