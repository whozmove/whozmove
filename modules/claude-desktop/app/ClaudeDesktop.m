// ClaudeDesktop: Claude Desktop, the app that keeps sessions as conversations of its own: its part of the rows, opening
// a conversation, and through its pieces, sending in one (DesktopMessageBox), starting one (DesktopNewConversation) and
// answering "Switch model?" (DesktopSwitchModel); and Claude's page on the panel's back, where you say whether its
// sessions are tracked. Its log and its conversation files are read by DesktopLog and DesktopConversations, and what it
// relies on about Claude Desktop is in ClaudeDesktopFacts.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "ClaudeDesktop.h"
#import "ClaudeDesktopFacts.h"
#import "DesktopConversations.h"
#import "DesktopLog.h"
#import "DesktopMessageBox.h"
#import "DesktopNewConversation.h"
#import "DesktopSwitchModel.h"
#import "Row.h"
#import "Core.h"
#import "PanelWindow.h"
#import "Accessibility.h"
#import "Files.h"
#import "Links.h"
#import "Log.h"
#import "Menus.h"

// Conversations with no running process are listed if active this recently.
static const NSTimeInterval kRecentConversationWindow = 3 * 24 * 3600;
// Whether its sessions are tracked, as its switch on Claude's page on the panel's back sets it; and how often it's
// looked for on this Mac, as you may install it, or take it off, while Whozmove runs.
static NSString *const kTrackDesktop = @"trackClaudeDesktop";
static const NSTimeInterval kLookEvery = 10;

@interface ClaudeDesktop ()
@property (weak) Core *core;
// Whether it's on this Mac, and its sessions tracked: as if it were, and they were, until the app looks (a print run
// never does), so what a print run lists doesn't depend on the Mac it runs on.
@property (atomic) BOOL installed;
@property (atomic) BOOL tracked;
@property NSTimeInterval lookedAt;
// Its conversation files, read on the sessions' queue as the rows are; its log, which both sides read; and its pieces.
@property (strong) DesktopConversations *conversations;
@property (strong) DesktopLog *log;
@property (strong) DesktopMessageBox *messageBox;
@property (strong) DesktopNewConversation *starts;
@property (copy) NSString *lastFocusTrace;  // what the log last said about the open conversation; on the queue only
@end

@implementation ClaudeDesktop

+ (NSString *)moduleName {
    return @"claude-desktop";
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.conversations = [DesktopConversations new];
    self.log = [DesktopLog new];
    self.messageBox = [[DesktopMessageBox alloc] initWithLog:self.log];
    self.starts = [[DesktopNewConversation alloc] initWithCore:core log:self.log messageBox:self.messageBox];
    self.installed = self.tracked = YES;
    [NSUserDefaults.standardUserDefaults registerDefaults:@{kTrackDesktop: @YES}];
    return self;
}

- (void)launch {
    [self lookAgain];
}

- (void)tick {
    if (NSDate.timeIntervalSinceReferenceDate - self.lookedAt >= kLookEvery) [self lookAgain];
}

// Its sessions are tracked while it's on this Mac and its switch is on; the log says when that changes.
- (void)lookAgain {
    self.lookedAt = NSDate.timeIntervalSinceReferenceDate;
    self.installed = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:kClaudeDesktopAppId] != nil;
    BOOL tracked = self.installed && SwitchedOn(kTrackDesktop);
    if (tracked == self.tracked) return;
    self.tracked = tracked;
    PanelLog(@"Claude Desktop's sessions: %@", tracked ? @"tracked"
             : self.installed ? @"not tracked, as its switch is off" : @"not tracked, as it isn't on this Mac");
}

- (NSString *)appId {
    return kClaudeDesktopAppId;
}

- (NSString *)name {
    return @"Claude";
}

- (BOOL)holds:(Row *)row {
    return [row.entrypoint isEqualToString:kClaudeDesktopEntrypoint];
}

#pragma mark The rows

// What Claude Desktop's own record of a conversation adds to its row: when it last did something and was last looked at
// (the registry's statusUpdatedAt moves whenever a process merely starts), and the record itself, for its model, effort
// and mode. Running sessions are read here, as rows, on the sessions' queue.
- (NSArray<Row *> *)readRows:(NSArray<Row *> *)running {
    NSArray<NSDictionary *> *conversations = [self.conversations all];
    NSMutableDictionary<NSString *, NSDictionary *> *conversationById = [NSMutableDictionary dictionary];
    for (NSDictionary *c in conversations) if (c[@"sessionId"]) conversationById[c[@"sessionId"]] = c;
    NSMutableSet *runningIds = [NSMutableSet set];
    for (Row *row in running) {
        if (row.sessionId) [runningIds addObject:row.sessionId];
        NSDictionary *c = row.hostSessionId ? conversationById[row.hostSessionId] : nil;
        if (c) {
            [runningIds addObject:row.hostSessionId];
            [self take:c into:row];
        }
    }

    // The conversation open in Claude Desktop right now. Claude stamps lastFocusedAt on a conversation when it's
    // switched to, but saves the file a couple of seconds later, while its log has the switch at once. Whichever
    // is newer wins (the log's clock only has whole seconds).
    NSString *openId = nil;
    double latestFocus = 0;
    for (NSDictionary *c in conversations)
        if ([c[@"lastFocusedAt"] doubleValue] > latestFocus) {
            latestFocus = [c[@"lastFocusedAt"] doubleValue];
            openId = c[@"sessionId"];
        }
    [self.log catchUp];
    if (self.log.loggedFocusAt > 0 && self.log.loggedFocusAt >= latestFocus - 1000)
        openId = self.log.loggedFocusId;  // nil: nothing open
    BOOL claudeRunning =
        [NSRunningApplication runningApplicationsWithBundleIdentifier:kClaudeDesktopAppId].count > 0;
    if (!claudeRunning) openId = nil;

    NSArray<Row *> *stopped = [self stoppedConversations:conversations running:runningIds open:openId];

    BOOL marked = NO;
    for (Row *row in [running arrayByAddingObjectsFromArray:stopped])
        if (openId && [row.hostSessionId isEqual:openId]) { row.focused = YES; marked = YES; }
    NSString *trace = [NSString stringWithFormat:@"%@ %@", openId ?: @"none", marked ? @"marked" : @"no row"];
    if (![trace isEqualToString:self.lastFocusTrace]) {
        PanelLog(@"open in Claude: %@ (log %@, files %@)", trace, self.log.loggedFocusId ?: @"-",
                 @(latestFocus));
        self.lastFocusTrace = trace;
    }
    return stopped;
}

// Recent conversations with no running process, as rows with status "closed" (none are running once Claude Desktop
// quits). The one open in Claude is listed however old it is, because it has no process for a moment after it's
// switched to.
- (NSArray<Row *> *)stoppedConversations:(NSArray<NSDictionary *> *)conversations running:(NSSet *)running
                                    open:(NSString *)openId {
    NSMutableArray *out = [NSMutableArray array];
    double cutoff = (NSDate.date.timeIntervalSince1970 - kRecentConversationWindow) * 1000;
    for (NSDictionary *c in conversations) {
        if (![c[@"sessionId"] isKindOfClass:NSString.class]) continue;
        // `running` holds the running sessions' ids and their Claude Desktop ids. A conversation that's running,
        // in Claude or resumed in a terminal (the same session id), is listed once, as that session.
        if ([c[@"isArchived"] boolValue] || [running containsObject:c[@"sessionId"]]
            || [running containsObject:c[@"cliSessionId"] ?: @""])
            continue;
        if ([c[@"lastActivityAt"] doubleValue] < cutoff && ![c[@"sessionId"] isEqual:openId]) continue;
        NSString *cwd = c[@"cwd"];
        if (![cwd isKindOfClass:NSString.class] || ![NSFileManager.defaultManager fileExistsAtPath:cwd])
            cwd = c[@"originCwd"];  // e.g. a removed worktree
        if (![cwd isKindOfClass:NSString.class]) continue;
        Row *row = [Row new];
        row.sessionId = [c[@"cliSessionId"] isKindOfClass:NSString.class] ? c[@"cliSessionId"] : c[@"sessionId"];
        row.hostSessionId = c[@"sessionId"];
        row.name = [c[@"title"] isKindOfClass:NSString.class] ? c[@"title"] : @"Untitled";
        row.cwd = cwd;
        row.entrypoint = kClaudeDesktopEntrypoint;
        row.status = @"closed";
        // A new conversation has no activity yet.
        row.statusUpdatedAt = [c[@"lastActivityAt"] isKindOfClass:NSNumber.class] ? c[@"lastActivityAt"] : @0;
        row.activityAt = row.statusUpdatedAt;
        [self take:c into:row];
        [out addObject:row];
    }
    return out;
}

- (void)take:(NSDictionary *)c into:(Row *)row {
    if ([c[@"lastActivityAt"] isKindOfClass:NSNumber.class]) row.activityAt = c[@"lastActivityAt"];
    if ([c[@"lastFocusedAt"] isKindOfClass:NSNumber.class]) row.lastFocusedAt = c[@"lastFocusedAt"];
    // Its model, effort and permission mode, for the details line, and when Claude last saved them.
    NSMutableDictionary *details = [NSMutableDictionary dictionary];
    for (NSArray<NSString *> *key in @[@[@"model", @"model"], @[@"effort", @"effort"], @[@"permissionMode", @"mode"],
                                       @[@"savedAt", @"at"]])
        if (c[key[0]]) details[key[1]] = c[key[0]];
    row.hostDetails = details;
}

- (BOOL)isOwnId:(NSString *)sessionId {
    return [sessionId hasPrefix:kClaudeDesktopConversationPrefix];
}

- (NSString *)startedWithoutFolder:(NSString *)folder asked:(NSString *)asked {
    NSString *scratch = RealPath([Home() stringByAppendingPathComponent:kClaudeDesktopScratchFolders]);
    return [folder hasPrefix:[scratch stringByAppendingString:@"/"]]
        ? [NSString stringWithFormat:@"Claude started it with \"%@\", not in %@", kClaudeDesktopNoFolderLabel, asked] : nil;
}

#pragma mark Conversations

- (BOOL)open:(Row *)row {
    // Claude Desktop's handler only accepts its own sidebar id (local_…), not the CLI session id.
    NSString *hostId = row.hostSessionId;
    NSURLComponents *url = [NSURLComponents componentsWithString:kClaudeDesktopOpenLink];
    url.queryItems = @[[NSURLQueryItem queryItemWithName:@"session"
                                                   value:[hostId hasPrefix:kClaudeDesktopConversationPrefix]
                                                             ? hostId : @"last"]];
    // When a text box in the panel had the keyboard, it goes to Claude.
    if ([self.core.window releaseKeyboard]) ActivateClaudeDesktop();
    BOOL opened = [NSWorkspace.sharedWorkspace openURL:url.URL];
    PanelLog(@"open desktop session %@ -> %@", hostId, opened ? @"sent" : @"failed");
    if (opened && [hostId hasPrefix:kClaudeDesktopConversationPrefix]) [self.messageBox focusBoxFor:hostId tries:0];
    return opened;
}

- (void)show:(Row *)row {
    [self.log catchUp];
    if (!ClaudeDesktopPid() || ![self.log.loggedFocusId isEqual:row.hostSessionId]) [self open:row];
    // Claude shows its page to the Accessibility API only while it's the active app, and the panel's menu has just
    // taken that away, so Claude comes forward, as it does when the row is clicked.
    else ActivateClaudeDesktop();
}

#pragma mark A new conversation

- (void)startConversationIn:(NSString *)folder words:(NSString *)words trusted:(BOOL)trusted
                       done:(void (^)(NSString *why))done {
    [self.starts startIn:folder words:words trusted:trusted done:done];
}

- (NSArray<NSDictionary *> *)startedConversations {
    [self.log catchUp];
    return self.log.loggedStarts ?: @[];
}

- (NSURL *)newConversationLink:(NSString *)words {
    return NewConversationLink(words);
}

- (NSUInteger)linkWordsMax {
    return kClaudeDesktopLinkWordsMax;
}

#pragma mark Sending a command

- (BOOL)mayControl {
    return MayUseAccessibility();
}

- (void)send:(NSString *)command toConversation:(NSString *)hostId done:(void (^)(NSString *why))done {
    [self.messageBox send:command toConversation:hostId done:done];
}

#pragma mark "Switch model?"

- (BOOL)mayAskToSwitch:(Row *)row {
    return ClaudeMayAskToSwitch(row);
}

- (void)stopAskingToSwitch {
    StopClaudeAskingToSwitch();
}

- (BOOL)showsSwitchBox {
    return ClaudeShowsSwitchBox();
}

- (BOOL)answerSwitchBox:(BOOL)switchModel dontAskAgain:(BOOL)dontAskAgain {
    return AnswerClaudeSwitchBox(switchModel, dontAskAgain);
}

#pragma mark On the panel's back

// Claude on the panel's back, listed on every Mac, as the page for Claude as a whole: Claude Code's settings go on it
// too (the install module's card for Whozmove's plugin). With Claude Desktop on this Mac, its switch says whether its
// sessions are tracked, and while they are, macOS's Accessibility shows, which its message box needs; without it, a
// card offers to get it.
- (NSArray<AppEntry *> *)appEntries {
    __weak typeof(self) weakSelf = self;
    AppEntry *claude = [AppEntry appWithId:self.appId name:self.name
                                      does:@"Claude Code runs your sessions, in a terminal or in Claude Desktop. "
                                           @"Whozmove's plugin in it says what each one is doing and last said, and "
                                           @"brings its requests to the panel."
                                     order:10];
    claude.present = ^BOOL { return YES; };
    AppSwitch *track = [AppSwitch switchWithKey:@"track" title:@"Track Claude Desktop app sessions"
                                           help:@"Lists its conversations and opens them, puts your words in its "
                                                @"message box, and starts new ones in it"
                                             on:^BOOL { return SwitchedOn(kTrackDesktop); }
                                            set:^(BOOL on) {
                                                SetSwitch(kTrackDesktop, on);
                                                [weakSelf lookAgain];
                                            }];
    track.shown = ^BOOL { return weakSelf.installed; };
    claude.switches = @[track];
    AppStatus *get = [AppStatus statusWithKey:@"desktop" title:@"Claude Desktop"
                                          now:^NSDictionary * {
                                              return weakSelf.installed ? nil
                                                  : @{@"said": @"Not installed",
                                                      @"note": @"Install it if you'd like Whozmove to track its sessions "
                                                               @"too.",
                                                      @"button": @"Get Claude Desktop"};
                                          }
                                        press:^{ OpenLink(kClaudeDesktopDownloadPage); }];
    claude.statuses = @[get];
    if (self.tracked) {
        claude.permission = AppPermissionAccessibility;
        claude.permissionFor = @"Puts your words in its message box, and presses its buttons";
    }
    return @[claude];
}

@end
