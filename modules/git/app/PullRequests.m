// PullRequests: the PRs each session made or worked on, and their state.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "PullRequests.h"
#import "Log.h"
#import "Core.h"
#import "Row.h"
#import "GitHub.h"

@interface PullRequests ()
// PR url -> what gh said about it, and when. Touched on the main thread only; gh runs on the queue.
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *status;
@property (strong) NSMutableSet<NSString *> *checking;  // the PRs being asked about now
@property (strong) dispatch_queue_t queue;
@end

@implementation PullRequests

- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.status = [NSMutableDictionary dictionary];
    self.checking = [NSMutableSet set];
    self.queue = dispatch_queue_create("whozmove.gh", DISPATCH_QUEUE_SERIAL);
    return self;
}

// A session's PR links, by address, as its agent recorded them.
- (NSDictionary<NSString *, NSDictionary *> *)linksOf:(Row *)row {
    id agent = row.sessionId ? [self.core agentOf:row] : nil;
    return [agent conformsToProtocol:@protocol(AgentWork)] ? [agent prLinksOf:row.sessionId] : nil;
}

// Asks GitHub (through gh) for the state of each PR: open ones every 5 minutes, ones it couldn't answer for every
// 2, and merged or closed ones once. A PR no listed session links to any more is forgotten.
- (void)check {
    NSMutableSet *linked = [NSMutableSet set];
    for (Row *row in self.rows) [linked addObjectsFromArray:[self linksOf:row].allKeys];
    for (NSString *url in self.status.allKeys)
        if (![linked containsObject:url]) [self.status removeObjectForKey:url];
    NSString *gh = GhPath();
    if (!gh) return;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    for (Row *row in self.rows) {
        for (NSString *url in [self linksOf:row].allKeys) {
            if ([self.checking containsObject:url]) continue;
            NSDictionary *known = self.status[url];
            NSString *state = known[@"state"];
            if ([state isEqual:@"MERGED"] || [state isEqual:@"CLOSED"]) continue;
            if (known && now - [known[@"checkedAt"] doubleValue] < ([state isEqual:@"OPEN"] ? 300 : 120)) continue;
            [self.checking addObject:url];
            dispatch_async(self.queue, ^{
                NSDictionary *status = FetchPRStatus(gh, url);
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.checking removeObject:url];
                    NSMutableDictionary *entry = [self.status[url] mutableCopy]
                                               ?: [NSMutableDictionary dictionary];
                    if (status) [entry addEntriesFromDictionary:status];
                    else PanelLog(@"gh pr view failed for %@", url);
                    if (!entry[@"state"]) entry[@"state"] = @"UNKNOWN";  // shown dimmed rather than hidden
                    entry[@"checkedAt"] = @(NSDate.date.timeIntervalSince1970);
                    self.status[url] = entry;
                });
            });
        }
    }
}

// A PR with no state yet is still being checked; the page hides those. Without gh there is
// nothing to check against, so they're reported as UNKNOWN and shown dimmed.
- (NSArray *)prsFor:(Row *)row {
    BOOL canCheck = GhPath() != nil;
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *link in [self linksOf:row].allValues) {
        NSMutableDictionary *pr = [link mutableCopy];
        NSDictionary *status = self.status[link[@"url"]];
        for (NSString *key in [kPRFields componentsSeparatedByString:@","])
            if (status[key] && ![@[@"url", @"number", @"statusCheckRollup", @"reviewDecision"] containsObject:key])
                pr[key] = status[key];
        if (status) {
            pr[@"checks"] = ChecksState(status[@"statusCheckRollup"]);
            pr[@"review"] = status[@"reviewDecision"] ?: @"";
        }
        if (!pr[@"state"] && !canCheck) pr[@"state"] = @"UNKNOWN";
        [out addObject:pr];
    }
    [out sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"at" ascending:NO]]];
    return out;
}

@end
