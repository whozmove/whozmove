// AnswerFor: what a session you allow may answer for you in a team member's session, each with a switch at the foot of
// its own mode menu: May Send Back Plans sends a plan back with a note; May Answer Questions answers Claude's
// questions, never a request for your OK; May Approve Plans approves a plan, as listed, as Claude's own prompt would,
// so the session goes back to the mode it planned from. It asks with ask-panel.sh (`waiting`, `send-back <id>`, `answer
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
@end
