// Row: one session as the panel lists it. docs/reference/rows.md says what each field means and where it comes from.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Row.h"
#import "Files.h"

// What comes from outside (the registry, the hook, the page) is checked for its kind once, here, with Files' AsText,
// AsNumber, AsList and AsRecord: anything else counts as missing.

@implementation Row

- (instancetype)initWithFields:(NSDictionary *)fields {
    if (!(self = [super init])) return nil;
    self.sessionId = AsText(fields[@"sessionId"]);
    self.hostSessionId = AsText(fields[@"hostSessionId"]);
    self.cwd = AsText(fields[@"cwd"]);
    self.name = AsText(fields[@"name"]);
    self.entrypoint = AsText(fields[@"entrypoint"]);
    self.status = AsText(fields[@"status"]);
    self.procStart = AsText(fields[@"procStart"]);
    self.pid = [AsNumber(fields[@"pid"]) intValue];
    self.statusUpdatedAt = AsNumber(fields[@"statusUpdatedAt"]);
    return self;
}

- (void)takeHookRecord:(NSDictionary *)record {
    if (record[@"lastPrompt"]) self.lastPrompt = AsText(record[@"lastPrompt"]);
    if (record[@"lastPromptAt"]) self.lastPromptAt = AsNumber(record[@"lastPromptAt"]);
    if (record[@"lastReply"]) self.lastReply = AsText(record[@"lastReply"]);
    if (record[@"lastReplyAt"]) self.lastReplyAt = AsNumber(record[@"lastReplyAt"]);
    if (record[@"notice"]) self.notice = AsText(record[@"notice"]);
    if (record[@"activity"]) self.activity = AsText(record[@"activity"]);
    // The app that keeps the conversation may say when it last moved too (Claude Desktop): the later time stands.
    NSNumber *activityAt = record[@"activityAt"] ? AsNumber(record[@"activityAt"]) : nil;
    if (activityAt && !(self.activityAt.doubleValue > activityAt.doubleValue)) self.activityAt = activityAt;
    if (record[@"stageAt"]) self.stageAt = AsNumber(record[@"stageAt"]);
    if (record[@"outcome"]) self.outcome = AsText(record[@"outcome"]);
    if (record[@"outcomeAt"]) self.outcomeAt = AsNumber(record[@"outcomeAt"]);
    if (record[@"builtAt"]) self.builtAt = AsNumber(record[@"builtAt"]);
    if (record[@"workSteps"]) self.workSteps = AsList(record[@"workSteps"]);
    if (record[@"audit"]) self.audit = AsRecord(record[@"audit"]);
    if (record[@"workRoot"]) self.workRoot = AsText(record[@"workRoot"]);
    if (record[@"editedAt"]) self.editedAt = AsNumber(record[@"editedAt"]);
    if (record[@"permissionMode"]) self.permissionMode = AsText(record[@"permissionMode"]);
    // A compaction under way, by itself or asked for, while the session runs: one quit in the middle of it says
    // nothing, and nor may one stopped with Esc, so one that began 15 minutes ago is taken as over.
    NSNumber *compactingAt = AsNumber(record[@"compactingAt"]);
    if (compactingAt && ![self.status isEqual:@"closed"]
        && NSDate.date.timeIntervalSince1970 * 1000 - compactingAt.doubleValue < 15 * 60 * 1000)
        self.compacting = compactingAt;
}

- (NSDictionary *)json {
    NSMutableDictionary *json = [NSMutableDictionary dictionary];
    json[@"sessionId"] = self.sessionId;
    json[@"hostSessionId"] = self.hostSessionId;
    json[@"cwd"] = self.cwd;
    json[@"name"] = self.name;
    json[@"entrypoint"] = self.entrypoint;
    json[@"status"] = self.status;
    json[@"procStart"] = self.procStart;
    json[@"pid"] = @(self.pid);
    json[@"statusUpdatedAt"] = self.statusUpdatedAt;
    json[@"alsoOpen"] = self.alsoOpen;
    json[@"activityAt"] = self.activityAt;
    json[@"lastFocusedAt"] = self.lastFocusedAt;
    json[@"lastPrompt"] = self.lastPrompt;
    json[@"lastPromptAt"] = self.lastPromptAt;
    json[@"lastReply"] = self.lastReply;
    json[@"lastReplyAt"] = self.lastReplyAt;
    json[@"notice"] = self.notice;
    json[@"activity"] = self.activity;
    json[@"stageAt"] = self.stageAt;
    json[@"outcome"] = self.outcome;
    json[@"outcomeAt"] = self.outcomeAt;
    json[@"builtAt"] = self.builtAt;
    json[@"workSteps"] = self.workSteps;
    json[@"audit"] = self.audit;
    json[@"workRoot"] = self.workRoot;
    json[@"editedAt"] = self.editedAt;
    json[@"permissionMode"] = self.permissionMode;
    json[@"git"] = self.git;
    json[@"workGit"] = self.workGit;
    json[@"checkout"] = self.checkout;
    json[@"ask"] = self.ask;
    json[@"agent"] = self.agent;
    json[@"prs"] = self.prs;
    json[@"writings"] = self.writings;
    json[@"changes"] = self.changes;
    json[@"messageAt"] = self.messageAt;
    json[@"compacting"] = self.compacting;
    json[@"goingIn"] = self.goingIn;
    json[@"switchAsk"] = self.switchAsk;
    json[@"seenAt"] = self.seenAt;
    json[@"opensIn"] = self.opensIn;
    if (self.focused) json[@"focused"] = @YES;
    if (self.noCompact) json[@"noCompact"] = @YES;
    return json;
}

@end
