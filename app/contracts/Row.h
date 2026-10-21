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
@property (strong) NSNumber *lastPromptAt, *lastReplyAt, *stageAt, *outcomeAt, *builtAt, *editedAt;
@property (copy) NSArray<NSString *> *workSteps;
@property (copy) NSDictionary *audit;

// What the app adds.
@property (copy) NSDictionary *git, *workGit, *checkout, *ask, *agent, *changes;
@property (copy) NSArray<NSDictionary *> *prs, *writings;
@property (strong) NSNumber *messageAt, *compacting, *seenAt;
@property (assign) BOOL focused;
// What was picked for it in the panel and the session hasn't confirmed yet, {field: value, <field>At: when}, which its
// details show until it does. Not sent.
@property (copy) NSDictionary *chosen;
@end
