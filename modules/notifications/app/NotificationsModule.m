// NotificationsModule: its face for the core (contracts/Module.h). Each time the rows are read it gathers what every
// module has to tell you (their `notices`), leaves out what you put away and what its sender says you're looking at,
// and sends the rest to the page with where the panel is and whether it's quiet hours (setNotices), where the decider
// picks what shows. It keeps
// what must outlast the page (AppDir/notifications.json, NoticeRules.h), runs a press through the sender's own
// `press`, and has Working on Whozmove's Preview Notices and the print run --print-notices.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import "Module.h"
#import "Core.h"
#import "Files.h"
#import "Log.h"
#import "Menus.h"
#import "Modules.h"
#import "NoticeGathering.h"
#import "NoticeRules.h"
#import "PanelWindow.h"
#import "Page.h"
#import "Text.h"

// Preview Notices: a made-up notice every 8 seconds, then all of them gone a minute or so after the last came.
static const NSTimeInterval kPreviewEvery = 8, kPreviewFor = 60;

// Quiet hours, kept in the app's defaults: off at first, and from 22:00 to 08:00 once on (minutes after midnight).
static NSString *const kQuietHours = @"quietHours", *const kQuietFrom = @"quietHoursFrom",
                *const kQuietTo = @"quietHoursTo";
static const NSInteger kQuietFromFirst = 22 * 60, kQuietToFirst = 8 * 60;

// One end of quiet hours as kept, or `first` while none is (or what's kept isn't a time of day).
static NSInteger QuietEnd(NSString *key, NSInteger first) {
    id kept = [NSUserDefaults.standardUserDefaults objectForKey:key];
    NSInteger minute = [kept isKindOfClass:NSNumber.class] ? [kept integerValue] : -1;
    return minute >= 0 && minute < 24 * 60 ? minute : first;
}

// Whether it's night now, by the Mac's own clock.
static BOOL QuietNow(void) {
    NSDateComponents *now = [NSCalendar.currentCalendar components:NSCalendarUnitHour | NSCalendarUnitMinute
                                                           fromDate:NSDate.date];
    return NoticeQuietAt(now.hour * 60 + now.minute, SwitchedOn(kQuietHours), QuietEnd(kQuietFrom, kQuietFromFirst),
                         QuietEnd(kQuietTo, kQuietToFirst));
}

@interface NotificationsModule : NSObject <Module>
@property (weak) Core *core;
@property (copy) NSDictionary *record;
@property (copy) NSDictionary<NSString *, Notice *> *listed;  // what the page was last sent, by id
@property (copy) NSString *sent;                              // as JSON, so it's sent again only when it changes
@property (copy) NSArray<Notice *> *previews;                 // Preview Notices' so far
@property (strong) NSTimer *previewTimer;
@end

@implementation NotificationsModule

+ (NSString *)moduleName {
    return @"notifications";
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.previews = @[];
    return self;
}

- (void)launch {
    NSDictionary *record = AsRecord(ReadJSON(AppDir(@"notifications.json")));
    self.record = record;
    [self keep:record ?: @{}];
    __weak typeof(self) weakSelf = self;
    [self.core.window followAway:^(BOOL away) { [weakSelf send]; }];
}

- (void)keep:(NSDictionary *)record {
    if ([record isEqual:self.record] && [NSFileManager.defaultManager fileExistsAtPath:AppDir(@"notifications.json")])
        return;
    self.record = record;
    NSData *json = [NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingSortedKeys error:nil];
    [NSFileManager.defaultManager createDirectoryAtPath:AppDir(nil) withIntermediateDirectories:YES attributes:nil
                                                  error:nil];
    if (![json writeToFile:AppDir(@"notifications.json") atomically:YES])
        LogProblem(@"notifications: couldn't keep its record");
}

- (void)pageLoaded {
    self.sent = nil;
    [self send];
    // What was seen beside the folded panel before, so a restart brings out only what's new (none on a first launch).
    // Within the same bounds as it's kept, whatever is on disk.
    [self.core.page call:@"setBesideSeen" with:@[NoticeSeenKept(self.record) ?: NSNull.null]];
}

- (void)rows:(NSArray<Row *> *)rows phase:(RowPhase)phase {
    if (phase == RowPhaseListed) [self send];
}

// What's listed now, as the page gets it: each module's, then Preview Notices'.
- (void)send {
    if (self.core.printing || !self.record) return;
    NSArray<Notice *> *all = [self.core.modules.notices arrayByAddingObjectsFromArray:self.previews];
    double now = NSDate.date.timeIntervalSince1970 * 1000;
    NSMutableArray *page = [NSMutableArray array];
    NSMutableDictionary *listed = [NSMutableDictionary dictionary];
    __weak typeof(self) weakSelf = self;
    for (Notice *notice in all) {
        NSString *id = NoticeId(notice);
        if (listed[id] || notice.seenNow || NoticeKeptAway(self.record, notice, now)) continue;
        notice.whenPutAway = ^(Notice *gone) { [weakSelf putAway:gone]; };
        listed[id] = notice;
        NSMutableDictionary *one = [@{@"id": id, @"level": @[@"know", @"soon", @"urgent"][notice.level],
                                      @"text": notice.text ?: @""} mutableCopy];
        one[@"button"] = notice.button;
        one[@"pressedWord"] = notice.pressedWord;
        one[@"tag"] = notice.tag;
        if (notice.busy) one[@"busy"] = @YES;
        if (notice.closes) one[@"closes"] = @YES;
        if (notice.done) one[@"done"] = @YES;
        if (notice.answersYou) one[@"answersYou"] = @YES;
        if (IsPlainId(notice.session, 128)) one[@"session"] = notice.session;
        if (isfinite(notice.outFor) && notice.outFor > 0) one[@"outFor"] = @(notice.outFor);
        [page addObject:one];
    }
    self.listed = listed;
    PanelWindow *window = self.core.window;
    NSDictionary *where = @{@"shown": @(window.shown), @"parked": @(window.parked), @"quiet": @(QuietNow())};
    // And the page senders' notices put away, which the page leaves out of its own.
    NSDictionary *awayHere = AsRecord(self.record[@"awayHere"]) ?: @{};
    NSData *json = [NSJSONSerialization dataWithJSONObject:@[page, where, awayHere] options:NSJSONWritingSortedKeys
                                                     error:nil];
    NSString *text = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    if (!self.core.page.ready || [text isEqualToString:self.sent]) return;
    self.sent = text;
    [self.core.page call:@"setNotices" with:@[page, where, awayHere]];
}

- (void)putAway:(Notice *)notice {
    double now = NSDate.date.timeIntervalSince1970 * 1000;
    [self keep:NoticePutAway(self.record, notice, now)];
    [self send];
}

// The page's messages (page/notices.js), each naming a notice by its id as it was sent.
- (NSDictionary<NSString *, void (^)(NSDictionary *)> *)messages {
    __weak typeof(self) weakSelf = self;
    return @{
        // Its button: the sender's own press.
        @"noticePress": ^(NSDictionary *msg) {
            Notice *notice = weakSelf.listed[AsText(msg[@"id"]) ?: @""];
            if (!notice) return;
            [notice pressButton];
            [weakSelf send];
        },
        // Its ×, or a line that said all went well gone by itself once seen.
        @"noticeAway": ^(NSDictionary *msg) {
            Notice *notice = weakSelf.listed[AsText(msg[@"id"]) ?: @""];
            if (notice) [notice putAway];
        },
        // What's been seen beside the folded panel, or was out there, by notice id, as it changes: kept for the next
        // launch.
        @"besideSeen": ^(NSDictionary *msg) {
            double now = NSDate.date.timeIntervalSince1970 * 1000;
            [weakSelf keep:NoticeSeen(weakSelf.record, AsRecord(msg[@"seen"]), now)];
        },
        // A page sender's notice put away by its × (`since`, what made it new then; `awayFor`, how long it's away at
        // most, in seconds).
        @"noticeAwayHere": ^(NSDictionary *msg) {
            NSString *noticeId = AsText(msg[@"id"]);
            if (!noticeId.length || noticeId.length > 200) return;
            NSString *since = AsText(msg[@"since"]);
            id awayFor = msg[@"awayFor"];
            double asked = [awayFor isKindOfClass:NSNumber.class] ? [awayFor doubleValue] : 0;
            NSTimeInterval seconds = isfinite(asked) && asked > 0 ? asked : 0;
            [weakSelf keep:NoticePutAwayHere(weakSelf.record, noticeId, since ? Clip(since, 200) : nil, seconds,
                                             NSDate.date.timeIntervalSince1970 * 1000)];
            [weakSelf send];
        },
    };
}

// Quiet hours on One Task's page under Tools, as a group of notifications' own there (its keys, its rule): a switch,
// and the part of the day they run, which can be changed once they're on. Turning them on is a choice of yours, as One
// Task's own switch is, so only the times count for Use the Recommended Settings, which puts back 22:00 to 08:00.
- (NSArray<AppEntry *> *)appEntries {
    __weak typeof(self) weakSelf = self;
    AppSwitch *on = [AppSwitch switchWithKey:kQuietHours title:@"Quiet hours"
                                        help:@"At night, only what's urgent is said: under the header, beside the "
                                             @"folded panel and beside the panel at the screen's edge. The rest waits "
                                             @"for the morning."
                                          on:^BOOL { return SwitchedOn(kQuietHours); }
                                         set:^(BOOL value) {
                                             SetSwitch(kQuietHours, value);
                                             [weakSelf send];
                                         }];
    AppTime *night = [AppTime timeWithKey:@"quietHoursTimes" title:@"Night" help:@"When quiet hours start and end."
                                     from:^NSInteger { return QuietEnd(kQuietFrom, kQuietFromFirst); }
                                       to:^NSInteger { return QuietEnd(kQuietTo, kQuietToFirst); }
                                      set:^(NSInteger from, NSInteger to) {
                                          // The same start and end would never be quiet, so it isn't kept.
                                          if (from == to || from < 0 || to < 0 || from >= 24 * 60 || to >= 24 * 60)
                                              return;
                                          [NSUserDefaults.standardUserDefaults setInteger:from forKey:kQuietFrom];
                                          [NSUserDefaults.standardUserDefaults setInteger:to forKey:kQuietTo];
                                          [weakSelf send];
                                      }];
    night.enabled = ^BOOL { return SwitchedOn(kQuietHours); };
    AppGroup *group = [AppGroup groupWithTitle:@"Quiet hours" rows:@[on, night]
                                          foot:@"For everything Whozmove says, not only tasks." order:35];
    AppEntry *entry = [AppEntry groups:@[group] forApp:@"one-task"];
    entry.recommended = ^BOOL {
        return QuietEnd(kQuietFrom, kQuietFromFirst) == kQuietFromFirst
            && QuietEnd(kQuietTo, kQuietToFirst) == kQuietToFirst;
    };
    entry.useRecommended = ^{
        for (NSString *key in @[kQuietFrom, kQuietTo]) [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
        [weakSelf send];
    };
    return @[entry];
}

// Made-up notices through the real path, to try the line without waiting for real ones: one Soon with a button that
// says Copied, one Urgent, one that says all went well, and one tagged New, one every 8 seconds.
- (NSArray<MenuEntry *> *)menuEntries {
    NSMenuItem *preview = [[NSMenuItem alloc] initWithTitle:@"Preview Notices" action:@selector(previewNotices)
                                              keyEquivalent:@""];
    preview.target = self;
    return @[[MenuEntry entryIn:MenuSectionWhozmove order:30 item:preview]];
}

- (NSArray<Notice *> *)previewNotices:(NSUInteger)count {
    Notice *soon = [Notice noticeWithKey:@"preview-soon" level:NoticeSoon
                                    text:@"Whozmove 9.9.0 is out. Copy the command to update."];
    soon.button = @"Copy Command";
    soon.pressedWord = @"Copied";
    soon.closes = YES;
    Notice *urgent = [Notice noticeWithKey:@"preview-urgent" level:NoticeUrgent
                                      text:@"Couldn't reach a made-up service, so this line is urgent."];
    urgent.button = @"Try Again";
    urgent.closes = YES;
    __weak typeof(self) weakSelf = self;
    __weak Notice *weakUrgent = urgent;
    urgent.press = ^{ [weakSelf previewDrop:weakUrgent]; };
    Notice *done = [Notice noticeWithKey:@"preview-done" level:NoticeGoodToKnow
                                    text:@"All set: this line goes by itself once you've seen it."];
    done.done = YES;
    done.closes = YES;
    Notice *feature = [Notice noticeWithKey:@"preview-new" level:NoticeGoodToKnow
                                       text:@"A made-up feature says what it does."];
    feature.tag = @"New";
    feature.button = @"Try It";
    feature.closes = YES;
    __weak Notice *weakFeature = feature;
    feature.press = ^{ [weakSelf previewDrop:weakFeature]; };
    NSArray *all = @[soon, urgent, done, feature];
    for (Notice *notice in all) notice.from = self.class.moduleName;
    return [all subarrayWithRange:NSMakeRange(0, MIN(count, all.count))];
}

- (void)previewNotices {
    [self.previewTimer invalidate];
    // What a preview before put away is forgotten, so each preview shows them all.
    NSMutableDictionary *record = [self.record mutableCopy];
    NSMutableDictionary *away = [AsRecord(record[@"away"]) mutableCopy] ?: [NSMutableDictionary dictionary];
    for (Notice *notice in [self previewNotices:4]) [away removeObjectForKey:NoticeId(notice)];
    record[@"away"] = away;
    [self keep:record];
    __block NSUInteger count = 1;
    self.previews = [self previewNotices:count];
    [self send];
    __weak typeof(self) weakSelf = self;
    self.previewTimer = [NSTimer scheduledTimerWithTimeInterval:kPreviewEvery repeats:YES block:^(NSTimer *timer) {
        if (++count <= 4) {
            NSArray *kept = weakSelf.previews;
            NSArray *next = [weakSelf previewNotices:count];
            // A preview already pressed away stays away; only the newest is added.
            weakSelf.previews = [kept arrayByAddingObject:next.lastObject];
        } else if ((count - 4) * kPreviewEvery >= kPreviewFor) {
            weakSelf.previews = @[];
            [timer invalidate];
        }
        [weakSelf send];
    }];
}

- (void)previewDrop:(Notice *)notice {
    if (!notice) return;
    NSMutableArray *kept = [self.previews mutableCopy];
    [kept removeObject:notice];
    self.previews = kept;
}

+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return @{@"--print-notices": ^int(Core *core, NSArray<NSString *> *arguments) { return PrintNotices(arguments); }};
}

@end
