// Row: one session as the panel lists it. docs/rows.md says what each field means and where it comes from.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Row.h"

// What comes from outside (the registry, the hook, the page) is checked for its kind once, here: anything else
// counts as missing.
static NSString *Text(id value) { return [value isKindOfClass:NSString.class] ? value : nil; }
static NSNumber *Number(id value) { return [value isKindOfClass:NSNumber.class] ? value : nil; }
static NSArray *List(id value) { return [value isKindOfClass:NSArray.class] ? value : nil; }
static NSDictionary *Record(id value) { return [value isKindOfClass:NSDictionary.class] ? value : nil; }

@implementation Row

- (instancetype)initWithFields:(NSDictionary *)fields {
    if (!(self = [super init])) return nil;
    self.sessionId = Text(fields[@"sessionId"]);
    self.hostSessionId = Text(fields[@"hostSessionId"]);
    self.cwd = Text(fields[@"cwd"]);
    self.name = Text(fields[@"name"]);
    self.entrypoint = Text(fields[@"entrypoint"]);
    self.status = Text(fields[@"status"]);
    self.procStart = Text(fields[@"procStart"]);
    self.pid = [Number(fields[@"pid"]) intValue];
    self.statusUpdatedAt = Number(fields[@"statusUpdatedAt"]);
    return self;
}

- (void)takeHookRecord:(NSDictionary *)record {
    if (record[@"lastPrompt"]) self.lastPrompt = Text(record[@"lastPrompt"]);
    if (record[@"lastPromptAt"]) self.lastPromptAt = Number(record[@"lastPromptAt"]);
    if (record[@"lastReply"]) self.lastReply = Text(record[@"lastReply"]);
    if (record[@"lastReplyAt"]) self.lastReplyAt = Number(record[@"lastReplyAt"]);
    if (record[@"notice"]) self.notice = Text(record[@"notice"]);
    if (record[@"activity"]) self.activity = Text(record[@"activity"]);
    if (record[@"activityAt"]) self.activityAt = Number(record[@"activityAt"]);
    if (record[@"stageAt"]) self.stageAt = Number(record[@"stageAt"]);
    if (record[@"outcome"]) self.outcome = Text(record[@"outcome"]);
    if (record[@"outcomeAt"]) self.outcomeAt = Number(record[@"outcomeAt"]);
    if (record[@"workSteps"]) self.workSteps = List(record[@"workSteps"]);
    if (record[@"audit"]) self.audit = Record(record[@"audit"]);
    if (record[@"workRoot"]) self.workRoot = Text(record[@"workRoot"]);
    if (record[@"permissionMode"]) self.permissionMode = Text(record[@"permissionMode"]);
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
    json[@"activityAt"] = self.activityAt;
    json[@"lastFocusedAt"] = self.lastFocusedAt;
    json[@"summaryStatus"] = self.summaryStatus;
    json[@"lastPrompt"] = self.lastPrompt;
    json[@"lastPromptAt"] = self.lastPromptAt;
    json[@"lastReply"] = self.lastReply;
    json[@"lastReplyAt"] = self.lastReplyAt;
    json[@"notice"] = self.notice;
    json[@"activity"] = self.activity;
    json[@"stageAt"] = self.stageAt;
    json[@"outcome"] = self.outcome;
    json[@"outcomeAt"] = self.outcomeAt;
    json[@"workSteps"] = self.workSteps;
    json[@"audit"] = self.audit;
    json[@"workRoot"] = self.workRoot;
    json[@"permissionMode"] = self.permissionMode;
    json[@"git"] = self.git;
    json[@"workGit"] = self.workGit;
    json[@"checkout"] = self.checkout;
    json[@"ask"] = self.ask;
    json[@"agent"] = self.agent;
    json[@"prs"] = self.prs;
    json[@"messageAt"] = self.messageAt;
    json[@"compacting"] = self.compacting;
    if (self.focused) json[@"focused"] = @YES;
    return json;
}

@end
