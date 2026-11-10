// AnswerFor: what a session you allow may answer for you in a team member's session, each with a switch at the foot of
// its own mode menu: May Send Back Plans sends a plan back with a note; May Answer Questions answers Claude's
// questions, never a request for your OK; May Approve Plans approves a plan, as listed, as Claude's own prompt would,
// so the session goes back to the mode it planned from. Your own press on Approve under a plan beside the list goes
// through the same check (approveShown:). It asks with ask-panel.sh (`waiting`, `send-back <id>`, `answer
// <id>`, `approve <id> <digest>`), which the core takes from the process that connects, never from what's sent
// (SessionAsks); the answer goes down the request's own line (HookLine), as your own would.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// Each switch is kept only in the panel's memory, for the lead's folder (SwitchLastsWorkspace), so nothing written
// anywhere turns it on: any session there holds it while it's the team file's lead and SwitchHolder lets it, by what
// the system says of its process (it works in that folder, is Claude Code's own program signed by Anthropic, wasn't
// started by another session, and is the only Claude Code session in the folder, the team's members in folders of their
// own inside it aside). The team file and Claude Code's records say which session may hold it, never which folder: a
// notice under the header says each time a session other than the one ticked in holds them. A restart or a Quit turns
// them off; what was ticked is offered back by one press at the foot of the mode menu (Allowed's waitingFor:), and said
// in a notice under the header until then. It answers only a member of the team in the team file, in the same project,
// never its own: the team file is the lead's own, so it keeps mistakes out, not a session you allow; the switch, set
// only by your press, and the project are the guard.
#import <Foundation/Foundation.h>
#import "Module.h"
#import "ClaudeProgram.h"

@class Core, Row, Notice;

extern NSString *const kSendBackKey, *const kAnswerQuestionsKey, *const kApprovePlansKey;

@interface AnswerFor : NSObject
// `programOf` says what program a process runs, as far as Claude Code goes (its agent's one check, which counts a print
// run's stand-ins), and `mayBe` whether a process's short name could be Claude Code's, so only those are looked at
// further: for which session may hold the switches (SwitchHolder).
- (instancetype)initWithCore:(Core *)core program:(ClaudeProgram (^)(pid_t pid))programOf
                       mayBe:(BOOL (^)(NSString *name))mayBe;
// Why a session's process might bypass permissions, or nil once that's ruled out (its agent's strict check): a plan of
// one that might is never approved from here.
@property (copy) NSString *(^bypassWhy)(Row *row, pid_t process);
// How long since the Mac last had keyboard or mouse input, for whether an Approve pressed beside the list is yours: the
// system's (SecondsIdle) unless a print run gives its own.
@property (copy) NSTimeInterval (^secondsIdle)(void);
// Forgets what the system last said of each session's process, so the next ask checks again at once: for a print run
// whose stand-in processes change between its steps.
- (void)forgetHolds;
// The switches, at the foot of the mode menu of the session leading the team, and what a session asks with them.
- (NSArray<SessionSwitch *> *)switches;
- (NSDictionary<NSString *, SessionAsk *> *)asks;
// One notice for each session whose switches went off as Whozmove restarted and wait for a press, naming them, the
// session and its folder: no button, as nothing here turns a switch on; its × puts it away. And one each time a session
// and process other than the one they were ticked in holds the switches kept for a folder, naming its terminal app and
// when it started, with Take Me There while it runs.
- (NSArray<Notice *> *)notices;
// What was last answered for you on each row's session, for 30 minutes, or until it asks something new
// (Row.answeredFor).
- (void)markRows:(NSArray<Row *> *)rows;
// What the page needs with a plan Claude waits on in `row` (its ask as the row shows it), before your press on Approve
// beside the list: {digest} of the whole plan, and `approveWhyNot` when it's known already that it can't be approved
// from here; after your press, `approval` when it didn't approve it ({why, at}, `again` where a second press may yet);
// nil for any other request.
- (NSDictionary *)approvalOf:(NSDictionary *)ask row:(Row *)row;
// Your press on Approve beside the list, {sessionId, id, digest}: checked as a session's approval is (the one check
// both go through), and that you were at the Mac, then sent as Claude's own prompt sends it, kept on the row as yours.
// {approved} or {why}, in words for the page, with `again` where a second press may yet approve it.
- (NSDictionary *)approveShown:(NSDictionary *)msg;
// Your press on Send under a plan beside the list that has stopped asking in the panel, {sessionId, planId, words}:
// your notes typed into its session as a message, led by Claude Code's words for them (kClaudeCodePlanChangesWords),
// through the send part's say:, only while WhyNotTypePlanNotes finds nothing in the way, as it's asked again before
// each key. How it went is on the row as yours (`answeredFor`: sent back, `state` typing, typed or notTyped, with `why`
// and `way` past it). Nil once the words are on their way, else why not, in words for the page.
- (NSString *)typePlanNotes:(NSDictionary *)msg;
@end

// The plan a session's Claude still waits on with no request for it in the panel: its newest plan, as the transcript
// lists it, while that plan has no answer there; or nil.
NSDictionary *PlanLeftWaiting(Row *row);
// Why notes can't be typed into a session for its plan `planId` now, or nil: a request waits in it, it isn't idle at
// its prompt (held at the plan's own prompt among them, which a key would answer), the plan isn't its newest left
// waiting, or something has been typed into it since the plan was asked.
NSString *WhyNotTypePlanNotes(Row *row, NSString *planId, NSDictionary *pending);
