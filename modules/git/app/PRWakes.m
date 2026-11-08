// PRWakes: a waiting session's pull request, watched from when its wait began (PRWakes.h).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "PRWakes.h"
#import "PullRequests.h"
#import "GitHub.h"
#import "Row.h"
#import "Files.h"
#import "Log.h"

// How often a watched pull request is asked of gh, in seconds.
static const NSTimeInterval kAskEvery = 60;

// What each kind of event says on the row, after the pull request's number.
static NSString *KindWords(NSString *kind) {
    return @{@"approved": @"approved", @"changes": @"needs changes", @"commented": @"has a comment",
             @"merged": @"merged", @"closed": @"closed"}[kind] ?: kind;
}

@interface PRWakes ()
// By session: {url, number, since, comments}. By pull request: what gh last said ({events, checkedAt}, or {failed,
// checkedAt}), and the ones being asked now. Touched on the main thread only; gh runs on the queue.
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *watched, *activity;
@property (strong) NSMutableSet<NSString *> *asking;
@property (strong) dispatch_queue_t queue;
@end

@implementation PRWakes

- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.watched = [NSMutableDictionary dictionary];
    self.activity = [NSMutableDictionary dictionary];
    self.asking = [NSMutableSet set];
    self.queue = dispatch_queue_create("whozmove.gh-wakes", DISPATCH_QUEUE_SERIAL);
    return self;
}

// The session's pull request: its branch's while it's open (as the checkout last read it), else the newest open one
// it linked. Only an https address, as a PR's is.
- (NSDictionary *)prOf:(Row *)row {
    NSDictionary *branch = AsRecord(row.checkout[@"pr"]);
    NSMutableArray<NSDictionary *> *candidates = [NSMutableArray array];
    if (branch) [candidates addObject:branch];
    [candidates addObjectsFromArray:[self.pullRequests prsFor:row] ?: @[]];
    for (NSDictionary *pr in candidates) {
        NSString *url = AsText(pr[@"url"]), *state = AsText(pr[@"state"]);
        if (![url hasPrefix:@"https://"] || (state && ![@[@"OPEN", @"UNKNOWN"] containsObject:state])) continue;
        NSNumber *number = AsNumber(pr[@"number"]) ?: @(url.lastPathComponent.integerValue);
        return @{@"url": url, @"number": number};
    }
    return nil;
}

- (WaitOn *)waitsOn:(Row *)row {
    NSDictionary *pr = row.sessionId ? self.watched[row.sessionId] : nil;
    pr = pr ?: [self prOf:row];
    if (!pr) return nil;
    NSInteger number = [pr[@"number"] integerValue];
    WaitOn *on = [WaitOn waitOn:@{@"source": @"pull request", @"url": pr[@"url"]}
                           says:[NSString stringWithFormat:@"#%ld", (long)number]
                         spoken:[NSString stringWithFormat:@"pull request %ld", (long)number]];
    if (!GhPath()) on.cant = @"gh isn't on this Mac (install GitHub's gh)";
    else if (self.activity[pr[@"url"]][@"failed"]) on.cant = @"gh may need you to sign in (gh auth login)";
    return on;
}

// The pull request a wait began on, as this source named it then ({source, url}): for a wait read back after a
// restart, before the session's own pull requests have been read again.
static NSDictionary *BeganOn(NSDictionary *options) {
    for (NSDictionary *on in AsList(options[@"on"]) ?: @[]) {
        NSString *url = [AsRecord(on)[@"source"] isEqual:@"pull request"] ? AsText(on[@"url"]) : nil;
        if ([url hasPrefix:@"https://"]) return @{@"url": url, @"number": @(url.lastPathComponent.integerValue)};
    }
    return nil;
}

- (BOOL)watch:(Row *)row since:(double)since options:(NSDictionary *)options {
    NSDictionary *pr = BeganOn(options) ?: [self prOf:row];
    if (!row.sessionId || !pr) return NO;
    NSMutableDictionary *watch = [pr mutableCopy];
    watch[@"since"] = @(since);
    watch[@"comments"] = @([options[@"comments"] boolValue]);
    self.watched[row.sessionId] = watch;
    [self check];
    return YES;
}

- (void)unwatch:(NSString *)sessionId {
    if (!sessionId) return;
    NSString *url = self.watched[sessionId][@"url"];
    [self.watched removeObjectForKey:sessionId];
    BOOL still = NO;
    for (NSDictionary *watch in self.watched.allValues) still = still || [watch[@"url"] isEqual:url];
    if (url && !still) [self.activity removeObjectForKey:url];
}

- (NSArray<Wake *> *)wakesFor:(NSString *)sessionId {
    NSDictionary *watch = sessionId ? self.watched[sessionId] : nil;
    if (!watch) return @[];
    double since = [watch[@"since"] doubleValue];
    BOOL comments = [watch[@"comments"] boolValue];
    NSInteger number = [watch[@"number"] integerValue];
    NSMutableArray<Wake *> *came = [NSMutableArray array];
    for (NSDictionary *event in AsList(self.activity[watch[@"url"]][@"events"]) ?: @[]) {
        NSString *kind = event[@"kind"];
        double at = [event[@"at"] doubleValue];
        if (at <= since || (!comments && [kind isEqual:@"commented"])) continue;
        NSMutableDictionary *facts = [@{@"pr": @(number), @"url": watch[@"url"]} mutableCopy];
        if (event[@"by"]) facts[@"by"] = event[@"by"];
        [came addObject:[Wake wakeFrom:@"pull request" kind:kind
                                  says:[NSString stringWithFormat:@"#%ld %@", (long)number, KindWords(kind)]
                                    at:at facts:facts]];
    }
    // A pull request merged or closed before the wait began (its state read a moment late) wakes it too, when it's
    // first read so: else the wait would watch one that can't change again, for good.
    NSString *state = AsText(self.activity[watch[@"url"]][@"state"]);
    NSString *over = [state isEqual:@"MERGED"] ? @"merged" : [state isEqual:@"CLOSED"] ? @"closed" : nil;
    BOOL told = [came indexOfObjectPassingTest:^BOOL(Wake *wake, NSUInteger i, BOOL *stop) {
        return [wake.kind isEqual:over];
    }] != NSNotFound;
    if (over && !told)
        [came addObject:[Wake wakeFrom:@"pull request" kind:over
                                  says:[NSString stringWithFormat:@"#%ld %@", (long)number, KindWords(over)]
                                    at:since + 1 facts:@{@"pr": @(number), @"url": watch[@"url"], @"before": @YES}]];
    [came sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"at" ascending:YES]]];
    return came;
}

- (void)check {
    NSString *gh = GhPath();
    if (!gh) return;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSMutableSet<NSString *> *urls = [NSMutableSet set];
    for (NSDictionary *watch in self.watched.allValues) [urls addObject:watch[@"url"]];
    for (NSString *url in urls) {
        if ([self.asking containsObject:url]) continue;
        if (now - [self.activity[url][@"checkedAt"] doubleValue] < kAskEvery) continue;
        [self.asking addObject:url];
        dispatch_async(self.queue, ^{
            NSDictionary *activity = FetchPRActivity(gh, url);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.asking removeObject:url];
                if (!activity) PanelLog(@"gh pr view failed for %@, waited on", url);
                [self took:activity for:url];
            });
        });
    }
}

// Only what wakes a session is kept: each event's kind, who and when, never a word of a comment.
- (void)took:(NSDictionary *)activity for:(NSString *)url {
    BOOL watched = NO;
    for (NSDictionary *watch in self.watched.allValues) watched = watched || [watch[@"url"] isEqual:url];
    if (!watched) return;
    NSNumber *at = @(NSDate.date.timeIntervalSince1970);
    // A read that failed keeps what the last one found, so nothing that came is lost to a moment offline.
    NSString *state = AsText(activity[@"state"]);
    self.activity[url] = activity ? @{@"events": PRActivityEvents(activity), @"state": state ?: @"", @"checkedAt": at}
                                  : @{@"events": self.activity[url][@"events"] ?: @[],
                                      @"state": self.activity[url][@"state"] ?: @"", @"failed": @YES, @"checkedAt": at};
}

@end
