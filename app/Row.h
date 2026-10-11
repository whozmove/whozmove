// Row: one session as the panel lists it. docs/rows.md says what each field means and where it comes from.
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

// Claude Desktop's own record of the conversation: when it last did something and was last looked at, Claude's
// verdict on its last turn, and the record itself (the details line reads its model, effort and mode, and a
// command sent from the panel watches it for the change).
@property (strong) NSNumber *activityAt, *lastFocusedAt;
@property (copy) NSString *summaryStatus;
@property (copy) NSDictionary *desktop;

// The hook's record.
@property (copy) NSString *lastPrompt, *lastReply, *notice, *activity, *outcome, *workRoot, *permissionMode;
@property (strong) NSNumber *lastPromptAt, *lastReplyAt, *stageAt, *outcomeAt;
@property (copy) NSArray<NSString *> *workSteps;
@property (copy) NSDictionary *audit;

// What the app adds.
@property (copy) NSDictionary *git, *workGit, *checkout, *ask, *agent;
@property (copy) NSArray<NSDictionary *> *prs;
@property (strong) NSNumber *messageAt, *compacting;
@property (assign) BOOL focused;
@end
