// DesktopNewConversation: opening a new conversation in Claude Desktop, choosing its folder, and sending its first
// message.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "DesktopNewConversation.h"
#import "DesktopLog.h"
#import "DesktopMessageBox.h"
#import "ClaudeDesktopFacts.h"
#import "Accessibility.h"
#import "Core.h"
#import "PanelWindow.h"
#import "Files.h"
#import "Log.h"

// What has a name in the message box's column of Claude's window, in order, as {element, role, name}, up to `most`:
// the column leaves out the list of conversations beside it, and the box's own text. Nil if the box isn't on screen.
static NSArray<NSDictionary *> *NamedInColumn(id box, NSUInteger most) {
    CGRect column;
    CFTypeRef window = NULL;
    if (!ElementFrame((__bridge AXUIElementRef)box, &column)
        || AXUIElementCopyAttributeValue((__bridge AXUIElementRef)box, kAXWindowAttribute, &window) != kAXErrorSuccess
        || !window)
        return nil;
    NSMutableArray *seen = [NSMutableArray array];
    CollectElements((AXUIElementRef)window, 0, ^BOOL(AXUIElementRef el) {
        NSString *label = seen.count < most ? ElementLabel(el) : nil;
        CGRect at;
        if (!label.length || !ElementFrame(el, &at) || CGRectContainsRect(column, at)
            || CGRectGetMidX(at) < CGRectGetMinX(column) - 40 || CGRectGetMidX(at) > CGRectGetMaxX(column) + 40)
            return NO;
        [seen addObject:@{@"element": (__bridge id)el, @"role": ElementText(el, kAXRoleAttribute) ?: @"", @"name": label}];
        return NO;
    }, [NSMutableArray array]);
    CFRelease(window);
    return seen;
}

// What Claude's window shows in the message box's column, as role "name" in order: for the log, when a start goes
// somewhere it shouldn't.
static NSString *ScreenAround(id box) {
    NSArray<NSDictionary *> *named = NamedInColumn(box, 120);
    if (!named) return @"(its message box isn't on screen)";
    NSMutableArray *seen = [NSMutableArray array];
    NSString *last = nil;  // a button's name is often its text's too
    for (NSDictionary *one in named) {
        if (seen.count >= 60 || [one[@"name"] isEqualToString:last]) continue;
        last = one[@"name"];
        NSString *role = [one[@"role"] stringByReplacingOccurrencesOfString:@"AX" withString:@""];
        [seen addObject:[NSString stringWithFormat:@"%@ \"%@\"", role.lowercaseString, Clip(one[@"name"], 60)]];
    }
    return seen.count ? [seen componentsJoinedByString:@", "] : @"nothing with a name";
}

// Claude's folder button for the conversation it's about to start, and the branch box beside it, as {button, folder,
// branch}: the button named for the folder wanted, "No folder" or "Select folder…", else the one just before the
// branch box (which only a folder in a git repository has). Nil if there's none in the message box's column.
static NSDictionary *FolderShown(id box, NSString *wanted) {
    NSArray<NSDictionary *> *named = NamedInColumn(box, 200);
    // A button's own text comes after it, so what's beside it is looked for past that.
    NSInteger (^next)(NSInteger, NSInteger) = ^NSInteger(NSInteger from, NSInteger step) {
        for (NSInteger i = from + step; i >= 0 && i < (NSInteger)named.count; i += step)
            if (![@[@"AXStaticText", @"AXImage", @"AXGroup"] containsObject:named[i][@"role"]]) return i;
        return -1;
    };
    NSArray *names = @[wanted, kClaudeDesktopNoFolderLabel, kClaudeDesktopSelectFolderLabel];
    NSInteger button = -1;
    for (NSInteger i = 0; i < (NSInteger)named.count && button < 0; i++)
        if ([named[i][@"role"] isEqual:@"AXPopUpButton"] && [names containsObject:named[i][@"name"]]) button = i;
    for (NSInteger i = 0; i < (NSInteger)named.count && button < 0; i++) {
        NSInteger before = next(i, -1);
        if ([named[i][@"role"] isEqual:@"AXComboBox"] && before >= 0 && [named[before][@"role"] isEqual:@"AXPopUpButton"])
            button = before;
    }
    if (button < 0) return nil;
    NSMutableDictionary *shown = [@{@"button": named[button][@"element"], @"folder": named[button][@"name"]} mutableCopy];
    NSInteger after = next(button, 1);
    if (after >= 0 && [named[after][@"role"] isEqual:@"AXComboBox"]) shown[@"branch"] = named[after][@"name"];
    return shown;
}

// Claude's newer screen: the button beside Send that names the environment a new conversation will start in, as
// {button, name}, with `path` when the page shows that environment's folder too (the chosen one of the recent
// environments it lists shows its name and then its folder). Nil on its older screen, or until the button shows.
static NSDictionary *EnvironmentShown(id box) {
    NSArray<NSDictionary *> *named = NamedInColumn(box, 200);
    NSUInteger at = [named indexOfObjectPassingTest:^BOOL(NSDictionary *one, NSUInteger i, BOOL *stop) {
        return [one[@"role"] isEqual:@"AXPopUpButton"] && [one[@"name"] hasPrefix:kClaudeDesktopEnvironmentPrefix];
    }];
    if (at == NSNotFound) return nil;
    NSString *name = [named[at][@"name"] substringFromIndex:kClaudeDesktopEnvironmentPrefix.length];
    NSMutableDictionary *shown = [@{@"button": named[at][@"element"], @"name": name} mutableCopy];
    for (NSUInteger i = 0; i + 1 < named.count; i++) {
        NSString *text = named[i + 1][@"name"];
        if ([named[i][@"role"] isEqual:@"AXStaticText"] && [named[i][@"name"] isEqualToString:name]
            && [named[i + 1][@"role"] isEqual:@"AXStaticText"] && ([text hasPrefix:@"~/"] || [text hasPrefix:@"/"])) {
            shown[@"path"] = text.stringByExpandingTildeInPath;
            break;
        }
    }
    return shown;
}

// The names Claude gives a folder's environments: those in its presets for this Mac whose folder is this one. Claude
// keeps the file; it's only read. Empty when there's none, or it can't be read.
static NSArray<NSString *> *EnvironmentsFor(NSString *folder) {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:kClaudeDesktopPresets];
    NSData *data = [NSData dataWithContentsOfFile:path];
    NSDictionary *all = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSDictionary *accounts = [all isKindOfClass:NSDictionary.class] ? all[@"byAccount"] : nil;
    if (![accounts isKindOfClass:NSDictionary.class]) return @[];
    NSString *wanted = RealPath(folder);
    NSMutableArray *names = [NSMutableArray array];
    for (NSDictionary *account in accounts.allValues) {
        NSArray *presets = [account isKindOfClass:NSDictionary.class] ? account[@"presets"] : nil;
        for (NSDictionary *preset in [presets isKindOfClass:NSArray.class] ? presets : @[]) {
            NSDictionary *target = [preset isKindOfClass:NSDictionary.class] ? preset[@"target"] : nil;
            NSString *name = [preset isKindOfClass:NSDictionary.class] ? preset[@"name"] : nil;
            if (![target isKindOfClass:NSDictionary.class] || ![name isKindOfClass:NSString.class]
                || ![target[@"kind"] isEqual:kClaudeDesktopLocalTarget]
                || ![target[@"cwd"] isKindOfClass:NSString.class])
                continue;
            if ([RealPath([target[@"cwd"] stringByExpandingTildeInPath]) isEqualToString:wanted]
                && ![names containsObject:name])
                [names addObject:name];
        }
    }
    return names;
}

// Whether the environment Claude shows is the folder's: one its presets give that folder, or the one the page shows
// that folder for.
static BOOL EnvironmentIsFor(NSDictionary *shown, NSString *folder, NSArray<NSString *> *environments) {
    return [environments containsObject:shown[@"name"]]
        || (shown[@"path"] && [RealPath(shown[@"path"]) isEqualToString:RealPath(folder)]);
}

// Whether an element is within another, a few levels down at most.
static BOOL Within(id element, id container) {
    id at = element;
    for (int up = 0; at && up < 6; up++) {
        CFTypeRef parent = NULL;
        at = AXUIElementCopyAttributeValue((__bridge AXUIElementRef)at, kAXParentAttribute, &parent) == kAXErrorSuccess
                 && parent ? (__bridge_transfer id)parent : nil;
        if (at && CFEqual((__bridge CFTypeRef)at, (__bridge CFTypeRef)container)) return YES;
    }
    return NO;
}

// The button for one of these environments among the recent ones the new conversation's page lists, or nil. The one
// chosen isn't a button there.
static id RecentEnvironment(id box, NSArray<NSString *> *names) {
    if (!names.count) return nil;
    id list = nil;
    for (NSDictionary *one in NamedInColumn(box, 200)) {
        if ([one[@"role"] isEqual:@"AXList"] && [one[@"name"] isEqual:kClaudeDesktopRecentEnvironmentsLabel])
            list = one[@"element"];
        else if (list && [one[@"role"] isEqual:@"AXButton"] && [names containsObject:one[@"name"]]
                 && Within(one[@"element"], list))
            return one[@"element"];
    }
    return nil;
}

// A new conversation's first message while its folder is chosen (chooseFolder:) and Send is pressed for it
// (pressSend:).
@interface DesktopFirstMessage : NSObject
@property (copy) NSString *words, *folder;          // and the folder it's for
@property (strong) id box;                          // Claude's message box they're in
@property (assign) int trusts;                      // how many more times "Trust this workspace?" may be answered
@property (assign) int folderChecks, listOpenedAt;  // quarter-seconds choosing the folder; when its list was opened
@property (assign) BOOL chosen;                     // the folder has been chosen in that list (or its environment)
// The names of the folder's environments in Claude, once its newer screen has shown (nil before; empty with none).
@property (copy) NSArray<NSString *> *environments;
@property (assign) int checks, presses, pressedAt;  // half-seconds so far; Send's presses; the check of the last press
@property (assign) int firstPressedAt, wrongFolderAt;  // the checks of the first press, and of another folder seen
@property (assign) double firstPressAt;             // ms since 1970
@property (assign) BOOL lookedAfter;                // what Claude shows after the press has gone in the log
@property (copy) void (^done)(NSString *why);
@end

@implementation DesktopFirstMessage
@end

// Text for a link's query. Claude reads the query as a form would, where "+" is a space and "&", "=" and "#" end a
// value, so those are encoded too (a link's own encoding leaves them be).
static NSString *QueryText(NSString *text) {
    NSMutableCharacterSet *plain = [NSCharacterSet.URLQueryAllowedCharacterSet mutableCopy];
    [plain removeCharactersInString:@"+&=#"];
    return [text stringByAddingPercentEncodingWithAllowedCharacters:plain];
}

NSURL *NewConversationLink(NSString *words) {
    NSURLComponents *url = [NSURLComponents componentsWithString:kClaudeDesktopNewLink];
    if (words.length && words.length <= kClaudeDesktopLinkWordsMax)
        url.percentEncodedQuery = [@"q=" stringByAppendingString:QueryText(words)];
    return url.URL;
}

@interface DesktopNewConversation ()
@property (weak) Core *core;
@property (strong) DesktopLog *log;
@property (strong) DesktopMessageBox *messageBox;
@end

@implementation DesktopNewConversation

- (instancetype)initWithCore:(Core *)core log:(DesktopLog *)log messageBox:(DesktopMessageBox *)messageBox {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.log = log;
    self.messageBox = messageBox;
    return self;
}

- (void)startIn:(NSString *)folder words:(NSString *)words trusted:(BOOL)trusted done:(void (^)(NSString *why))done {
    // The panel's box had the keyboard; it goes to Claude, which is about to come forward.
    if ([self.core.window releaseKeyboard]) ActivateClaudeDesktop();
    BOOL opened = [NSWorkspace.sharedWorkspace openURL:NewConversationLink(words)];
    PanelLog(@"new desktop conversation in %@ -> %@", folder, opened ? @"sent" : @"failed");
    if (!opened) return done(@"Claude didn't open: is Claude Desktop installed?");
    // With no words, the conversation is only opened, in its folder, with the caret in its box, where Whozmove may; it
    // isn't asked for that permission just for this.
    if (!words.length) {
        if (AXIsProcessTrusted()) [self sendFirst:words in:folder trusts:trusted ? 2 : 0 tries:0 filled:0 done:done];
        else done(nil);
        return;
    }
    if (!MayUseAccessibility())
        return done(words.length <= kClaudeDesktopLinkWordsMax
                    ? [NSString stringWithFormat:@"Your words are in Claude's message box: choose %@ there, then press "
                       "Send", folder.lastPathComponent]
                    : @"Allow Whozmove in Accessibility, then try again");
    [self sendFirst:words in:folder trusts:trusted ? 2 : 0 tries:0 filled:0 done:done];
}

// Waits for Claude to show the new conversation's page (no conversation open, one message box), then, once the box
// shows exactly the words, makes sure it's for the folder (chooseFolder:) and presses Send (pressSend:). Claude can ask
// "Trust this workspace?" on the way, for a folder Claude Code's record trusts already: its button is pressed then, up
// to `trusts` times in all. Words the link carried are put in by Claude a moment after its page shows (`filled` counts
// the wait); longer ones are written in. A box with other words in it is never touched. With no words, the folder is
// chosen and the caret goes in the box.
- (void)sendFirst:(NSString *)words in:(NSString *)folder trusts:(int)trusts tries:(int)tries filled:(int)filled
             done:(void (^)(NSString *why))done {
    void (^again)(int) = ^(int nextFilled) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self sendFirst:words in:folder trusts:trusts tries:tries + 1 filled:nextFilled done:done];
        });
    };
    if (trusts && [self pressTrust]) {
        // Saving the trust has Claude load the folder's commands again, and a press of Send meanwhile goes by
        // unnoticed: the words wait a second for that.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self sendFirst:words in:folder trusts:trusts - 1 tries:tries + 5 filled:filled done:done];
        });
        return;
    }
    [self.log catchUp];
    NSArray *boxes = self.log.loggedFocusId ? @[] : [self.messageBox promptBoxes];
    if (boxes.count != 1) {
        if (tries < 100) return again(filled);  // up to 20s: Claude may be starting
        PanelLog(@"new desktop conversation -> not sent: Claude never showed its page (%lu message boxes)",
                 (unsigned long)boxes.count);
        return done(words.length ? @"Claude didn't show the new conversation: if your words are in its box, press Send there"
                                 : nil);
    }
    DesktopFirstMessage *message = [DesktopFirstMessage new];
    message.words = words;
    message.folder = folder;
    message.box = boxes[0];
    message.trusts = trusts;
    message.pressedAt = message.wrongFolderAt = message.listOpenedAt = -1;
    message.done = done;
    if (!words.length) {
        return [self chooseFolder:message then:^{
            AXUIElementSetAttributeValue((__bridge AXUIElementRef)message.box, kAXFocusedAttribute, kCFBooleanTrue);
            done(nil);
        }];
    }
    id box = message.box;
    NSCharacterSet *space = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    NSString *shown = [ElementText((__bridge AXUIElementRef)box, kAXValueAttribute) ?: @"" stringByTrimmingCharactersInSet:space];
    if (!shown.length) {
        if (words.length <= kClaudeDesktopLinkWordsMax && filled < 15) return again(filled + 1);
        AXUIElementSetAttributeValue((__bridge AXUIElementRef)box, kAXFocusedAttribute, kCFBooleanTrue);
        AXUIElementSetAttributeValue((__bridge AXUIElementRef)box, kAXValueAttribute, (__bridge CFStringRef)words);
    } else if (![shown isEqualToString:[words stringByTrimmingCharactersInSet:space]]) {
        PanelLog(@"new desktop conversation -> not sent: its message box has other words in it");
        return done(@"There's a message half-written in Claude's new conversation: send or clear it there");
    }
    [self chooseFolder:message then:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self pressSend:message];
        });
    }];
}

// Makes sure Claude will start the new conversation in its folder. A folder that comes in its link gets lost, so the
// folder is chosen in Claude, as you would choose it: on its newer screen, the folder's environment
// (chooseEnvironment:, below); on its older one, with its folder button, which shows the folder it will start in.
// Claude often shows it already (the last one it started in); else its folder list is opened, and the folder chosen
// from its Recent ones by its path. Then `ready` once Claude has it ready: its branch box shows a branch, in a git
// repository. A folder that isn't among the Recent ones, or that Claude doesn't get ready, is left for you to choose
// there, with the words in its box. The checks are a quarter of a second apart, for up to 10s.
- (void)chooseFolder:(DesktopFirstMessage *)message then:(void (^)(void))ready {
    NSString *name = message.folder.lastPathComponent;
    void (^again)(double) = ^(double seconds) {
        message.folderChecks++;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(),
                       ^{ [self chooseFolder:message then:ready]; });
    };
    if (message.trusts && [self pressTrust]) {
        message.trusts--;
        return again(1);
    }
    NSDictionary *environment = EnvironmentShown(message.box);
    if (environment) return [self chooseEnvironment:environment for:message then:ready again:again];
    NSString *left = [self leftToYou:message];
    NSDictionary *shown = FolderShown(message.box, name);
    if ([shown[@"folder"] isEqual:name]) {
        NSString *branch = shown[@"branch"];
        if (![branch isEqual:kClaudeDesktopNoBranchLabel]) {
            PanelLog(@"new desktop conversation -> Claude shows %@%@", name,
                     branch ? [@" on " stringByAppendingString:branch] : @" (no branch)");
            return ready();
        }
    } else if (shown && message.listOpenedAt < 0) {
        PanelLog(@"new desktop conversation -> Claude shows %@ as its folder: choosing %@ in its folder list",
                 shown[@"folder"], name);
        AXUIElementPerformAction((__bridge AXUIElementRef)shown[@"button"], kAXPressAction);
        message.listOpenedAt = message.folderChecks;
        return again(0.25);
    } else if (message.listOpenedAt >= 0 && !message.chosen) {
        NSMutableArray *listed = [NSMutableArray array];
        id item = [self folderListItem:message.folder named:name listed:listed];
        if (item) {
            AXUIElementPerformAction((__bridge AXUIElementRef)item, kAXPressAction);
            message.chosen = YES;
            PanelLog(@"new desktop conversation -> chose %@ in Claude's folder list", message.folder);
            return again(0.25);
        }
        if (message.folderChecks - message.listOpenedAt >= 8) {
            PanelLog(@"new desktop conversation -> not sent: %@ isn't in Claude's folder list (it lists %@)",
                     message.folder, listed.count ? [listed componentsJoinedByString:@", "] : @"nothing");
            if (shown[@"button"]) AXUIElementPerformAction((__bridge AXUIElementRef)shown[@"button"], kAXPressAction);
            return message.done(left);
        }
        return again(0.25);
    }
    if (message.folderChecks >= 40) {
        PanelLog(@"new desktop conversation -> not sent: Claude didn't get %@ ready; it shows: %@", name,
                 ScreenAround(message.box));
        return message.done(left);
    }
    again(0.25);
}

// On Claude's newer screen a new conversation starts in the environment named on the button beside Send: one of its
// saved folders. When that's the folder's (Claude often shows it already: the last one it started in), it's ready. Else
// the folder's environment is chosen among the recent ones the page lists, as you would choose it, and it's ready once
// the button names it. One that isn't among them, or a folder Claude has no environment for, is left for you to choose
// there, with the words in its box: after 4s, or 5s once one was chosen.
- (void)chooseEnvironment:(NSDictionary *)shown for:(DesktopFirstMessage *)message then:(void (^)(void))ready
                    again:(void (^)(double))again {
    if (!message.environments) message.environments = EnvironmentsFor(message.folder);
    if (EnvironmentIsFor(shown, message.folder, message.environments)) {
        PanelLog(@"new desktop conversation -> Claude shows the environment %@", shown[@"name"]);
        return ready();
    }
    if (!message.chosen) {
        id item = RecentEnvironment(message.box, message.environments);
        if (item) {
            AXUIElementPerformAction((__bridge AXUIElementRef)item, kAXPressAction);
            message.chosen = YES;
            message.listOpenedAt = message.folderChecks;
            PanelLog(@"new desktop conversation -> Claude shows the environment %@: chose %@ among its recent ones",
                     shown[@"name"], [message.environments componentsJoinedByString:@" or "]);
            return again(0.25);
        }
    }
    if (message.folderChecks - MAX(message.listOpenedAt, 0) >= (message.chosen ? 20 : 16)) {
        PanelLog(@"new desktop conversation -> not sent: Claude shows the environment %@, not %@'s (%@); it shows: %@",
                 shown[@"name"], message.folder,
                 message.environments.count ? [message.environments componentsJoinedByString:@", "] : @"it has none",
                 ScreenAround(message.box));
        return message.done([self leftToYou:message]);
    }
    again(0.25);
}

// What the pending row says when the folder is left for you to choose in Claude, with your words in its box: its
// environment there, or on Claude's older screen the folder in its folder list.
- (NSString *)leftToYou:(DesktopFirstMessage *)message {
    NSString *then = message.words.length ? @", then press Send there" : @"", *name = message.folder.lastPathComponent;
    if (!message.environments)
        return [NSString stringWithFormat:@"Choose %@ in Claude's folder list%@", name, then];
    if (message.environments.count)
        return [NSString stringWithFormat:@"Choose %@ as Claude's environment%@", message.environments[0], then];
    return [NSString stringWithFormat:@"Claude has no environment for %@ yet: choose it in Claude%@", name, then];
}

// What Claude shows it will start the new conversation in when that isn't the conversation's folder, for the log:
// another environment, or on its older screen another folder. Nil when it's the folder's, or Claude shows neither.
- (NSString *)otherPlaceShown:(DesktopFirstMessage *)message {
    NSDictionary *environment = EnvironmentShown(message.box);
    if (environment) {
        if (!message.environments) message.environments = EnvironmentsFor(message.folder);
        return EnvironmentIsFor(environment, message.folder, message.environments)
            ? nil : [NSString stringWithFormat:@"the environment %@", environment[@"name"]];
    }
    NSString *folder = FolderShown(message.box, message.folder.lastPathComponent)[@"folder"];
    return folder && ![folder isEqual:message.folder.lastPathComponent]
        ? [NSString stringWithFormat:@"%@ as its folder", folder] : nil;
}

// The item for a folder in Claude's open folder list: the one with its path as its tooltip, else the only one with its
// name. `listed` gets the names of what the list shows, for the log.
- (id)folderListItem:(NSString *)path named:(NSString *)name listed:(NSMutableArray *)listed {
    pid_t pid = ClaudeDesktopPid();
    if (!pid) return nil;
    AXUIElementRef app = AXUIElementCreateApplication(pid);
    CFTypeRef windows = NULL;
    AXUIElementCopyAttributeValue(app, kAXWindowsAttribute, &windows);
    CFRelease(app);
    NSMutableArray *byPath = [NSMutableArray array], *byName = [NSMutableArray array];
    for (id window in (__bridge_transfer NSArray *)windows)
        CollectElements((__bridge AXUIElementRef)window, 0, ^BOOL(AXUIElementRef el) {
            if ([ElementText(el, kAXHelpAttribute) isEqualToString:path]
                || [ElementText(el, kAXDescriptionAttribute) isEqualToString:path])
                [byPath addObject:(__bridge id)el];
            if ([ElementText(el, kAXRoleAttribute) isEqual:@"AXMenuItem"]) {
                NSString *label = ElementLabel(el) ?: @"";
                if (listed.count < 20) [listed addObject:Clip(label, 40)];
                if ([label isEqualToString:name]) [byName addObject:(__bridge id)el];
            }
            return NO;
        }, [NSMutableArray array]);
    // The tooltip can be on the item's text rather than on the item: it's the item that's pressed, and never anything
    // outside the list (the folder button names the path too).
    for (id found in byPath) {
        id item = found;
        for (int up = 0; item && up < 3 && ![ElementText((__bridge AXUIElementRef)item, kAXRoleAttribute)
                                              isEqual:@"AXMenuItem"]; up++) {
            CFTypeRef parent = NULL;
            item = AXUIElementCopyAttributeValue((__bridge AXUIElementRef)item, kAXParentAttribute, &parent)
                       == kAXErrorSuccess && parent ? (__bridge_transfer id)parent : nil;
        }
        if (item && [ElementText((__bridge AXUIElementRef)item, kAXRoleAttribute) isEqual:@"AXMenuItem"]) return item;
    }
    return byName.count == 1 ? byName[0] : nil;
}

// Claude's "Trust this workspace?" button, pressed if it's up (YES), for a folder Claude Code's record trusts already.
- (BOOL)pressTrust {
    id trust = ControlNamed(ClaudeDesktopPid(), @"AXButton", ^BOOL(NSString *label) {
        return [label isEqualToString:kClaudeDesktopTrustLabel];
    });
    if (!trust) return NO;
    AXUIElementPerformAction((__bridge AXUIElementRef)trust, kAXPressAction);
    PanelLog(@"new desktop conversation -> pressed Claude's \"%@\" for a folder trusted already",
             kClaudeDesktopTrustLabel);
    return YES;
}

// Presses Send for a new conversation's first message, and makes sure it went. Claude can let a press go by while it's
// still getting the folder ready (loading its commands again once its trust is saved, more slowly the more sessions
// it's running), so Send is pressed again 2s after the last press, and only when it can be pressed, until Claude takes
// it: its log says it's starting the conversation, or it shows a conversation, or its box empties. That's for up to
// 15s. Send isn't pressed while Claude shows another environment or folder than the one chosen for it: before the
// first press that's waited out for up to 5s, and then the words are left for you to choose the folder in Claude and
// send them. The words are never taken out of Claude's box: if Send doesn't take, they stay there for you to send. Its
// trust question can still come up meanwhile, and is answered as before. What Claude shows beside its box goes in the
// log as Send is first pressed, and again if it hasn't started the conversation 4s later.
- (void)pressSend:(DesktopFirstMessage *)message {
    NSCharacterSet *space = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    [self.log catchUp];
    // The log's time is to the second, so a start in the second of the first press counts.
    BOOL started = message.presses && self.log.loggedStartAt >= floor(message.firstPressAt / 1000) * 1000;
    BOOL onPage = !self.log.loggedFocusId;
    NSString *shown = [ElementText((__bridge AXUIElementRef)message.box, kAXValueAttribute)
                       stringByTrimmingCharactersInSet:space];
    if (!shown && onPage && !started) {  // Claude built its box again: the one on the page now
        NSArray *boxes = [self.messageBox promptBoxes];
        if (boxes.count == 1) {
            message.box = boxes[0];
            shown = [ElementText((__bridge AXUIElementRef)message.box, kAXValueAttribute)
                     stringByTrimmingCharactersInSet:space];
        }
    }
    int presses = message.presses;
    if (started || !onPage || !shown.length) {
        NSDictionary *went = started ? self.log.loggedStarts.lastObject : nil;
        if (presses)
            PanelLog(@"new desktop conversation -> sent (Send pressed %d time%@)%@", presses, presses == 1 ? @"" : @"s",
                     went ? [NSString stringWithFormat:@": Claude started %@ in %@", went[@"id"], went[@"folder"]] : @"");
        else
            PanelLog(@"new desktop conversation -> Claude's box was emptied there before Send was pressed");
        return message.done(nil);
    }
    NSString *note = @"Your words are in Claude's message box: press Send there";
    if (![shown isEqualToString:[message.words stringByTrimmingCharactersInSet:space]]) {
        PanelLog(@"new desktop conversation -> left to you: the words in Claude's box were changed");
        return message.done(note);
    }
    if (message.checks >= 30) {
        PanelLog(@"new desktop conversation -> not sent: Send didn't take (pressed %d time%@); the words are left in "
                 "Claude's box", presses, presses == 1 ? @"" : @"s");
        return message.done(note);
    }
    if (presses && !message.lookedAfter && message.checks - message.firstPressedAt >= 8) {
        message.lookedAfter = YES;
        PanelLog(@"new desktop conversation -> not started 4s after Send; Claude shows: %@", ScreenAround(message.box));
    }
    if (message.pressedAt < 0 || message.checks - message.pressedAt >= 4) {
        NSString *other = [self otherPlaceShown:message];
        if (message.trusts && [self pressTrust]) {
            message.trusts--;
            message.pressedAt = message.checks;
        } else if (other) {
            if (!presses && message.wrongFolderAt < 0) {
                message.wrongFolderAt = message.checks;
                PanelLog(@"new desktop conversation -> waiting: Claude shows %@", other);
            } else if (!presses && message.checks - message.wrongFolderAt >= 10) {
                PanelLog(@"new desktop conversation -> not sent: Claude still shows %@; the words are left in Claude's "
                         "box", other);
                return message.done([self leftToYou:message]);
            }
        } else {
            NSArray *buttons = DesktopSendButtons(message.box);
            if (buttons.count == 1) {
                if (!presses) PanelLog(@"new desktop conversation -> Claude shows: %@", ScreenAround(message.box));
                AXUIElementPerformAction((__bridge AXUIElementRef)buttons[0], kAXPressAction);
                if (!presses) {
                    message.firstPressAt = NSDate.date.timeIntervalSince1970 * 1000;
                    message.firstPressedAt = message.checks;
                }
                message.presses = ++presses;
                message.pressedAt = message.checks;
                PanelLog(@"new desktop conversation -> pressed Send%@",
                         presses > 1 ? [NSString stringWithFormat:@" again (%d)", presses] : @"");
            }
        }
    }
    message.checks++;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self pressSend:message];
    });
}

@end
