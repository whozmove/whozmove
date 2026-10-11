// ClaudeDesktop: Claude Desktop through its links and the Accessibility API: opening a conversation, writing in
// its message box, pressing Send, and answering "Switch model?".
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "ClaudeDesktop.h"
#import "Row.h"
#import "DesktopConversations.h"
#import "PanelWindow.h"
#import "Log.h"
#import "Upstream.h"

// Claude Desktop takes no outside input for a conversation's settings: no link, file or tool reaches them. So the
// panel sends the slash command that would be typed by hand, in the conversation's own message box. It writes the
// text there through the Accessibility API and presses Submit, with no menus opening; Return is pressed only if
// there's no Submit button, and only with Claude in front (submit:). The conversation has to be the one
// Claude shows, because only that one has a message box, so it's opened first if it isn't. A half-written message
// is never touched: then nothing is sent.

static NSString *AXText(AXUIElementRef el, CFStringRef attribute) {
    CFTypeRef value = NULL;
    if (AXUIElementCopyAttributeValue(el, attribute, &value) != kAXErrorSuccess || !value) return nil;
    id object = (__bridge_transfer id)value;  // owned from here, so it outlives the return
    return [object isKindOfClass:NSString.class] ? object : nil;
}

static void AXCollect(AXUIElementRef el, int depth, BOOL (^match)(AXUIElementRef), NSMutableArray *found) {
    if (depth > 80) return;
    if (match(el)) [found addObject:(__bridge id)el];
    CFTypeRef children = NULL;
    if (AXUIElementCopyAttributeValue(el, kAXChildrenAttribute, &children) == kAXErrorSuccess && children) {
        for (id child in (__bridge NSArray *)children)
            AXCollect((__bridge AXUIElementRef)child, depth + 1, match, found);
        CFRelease(children);
    }
}

static pid_t ClaudePid(void) {
    return [NSRunningApplication runningApplicationsWithBundleIdentifier:kClaudeDesktopAppId].firstObject
        .processIdentifier;
}

@interface ClaudeDesktop ()
@property (strong) DesktopConversations *conversations;  // only its log is read here: the files are the list's
@property (strong) PanelWindow *window;
@end

@implementation ClaudeDesktop

- (instancetype)initWithConversations:(DesktopConversations *)conversations window:(PanelWindow *)window {
    if (!(self = [super init])) return nil;
    self.conversations = conversations;
    self.window = window;
    return self;
}

#pragma mark Conversations

- (void)open:(Row *)row {
    // Claude Desktop's handler only accepts its own sidebar id (local_…), not the CLI session id.
    NSString *hostId = row.hostSessionId;
    NSURLComponents *url = [NSURLComponents componentsWithString:kClaudeDesktopOpenLink];
    url.queryItems = @[[NSURLQueryItem queryItemWithName:@"session"
                                                   value:[hostId hasPrefix:kClaudeDesktopConversationPrefix]
                                                             ? hostId : @"last"]];
    // When a text box in the panel had the keyboard, it goes to Claude.
    if ([self.window releaseKeyboard]) [self activate];
    BOOL opened = [NSWorkspace.sharedWorkspace openURL:url.URL];
    PanelLog(@"open desktop session %@ -> %@", hostId, opened ? @"sent" : @"failed");
    if (opened && [hostId hasPrefix:kClaudeDesktopConversationPrefix]) [self focusBoxFor:hostId tries:0];
}

- (void)show:(Row *)row {
    [self.conversations readFocusLog];
    if (!ClaudePid() || ![self.conversations.loggedFocusId isEqual:row.hostSessionId]) [self open:row];
    // Claude shows its page to the Accessibility API only while it's the active app, and the panel's menu has just
    // taken that away, so Claude comes forward, as it does when the row is clicked.
    else [self activate];
}

- (void)activate {
    [[NSRunningApplication runningApplicationsWithBundleIdentifier:kClaudeDesktopAppId].firstObject
        activateWithOptions:0];
}

- (void)newConversationIn:(NSString *)folder {
    NSURLComponents *url = [NSURLComponents componentsWithString:kClaudeDesktopNewLink];
    url.queryItems = @[[NSURLQueryItem queryItemWithName:@"folder" value:folder]];
    // Claude reads the query as a form would, where "+" is a space: a "+" in the name has to be encoded.
    url.percentEncodedQuery = [url.percentEncodedQuery stringByReplacingOccurrencesOfString:@"+"
                                                                                 withString:@"%2B"];
    BOOL opened = [NSWorkspace.sharedWorkspace openURL:url.URL];
    PanelLog(@"new desktop session in %@ -> %@", folder, opened ? @"sent" : @"failed");
}

// Once Claude shows the conversation opened from a row, its message box gets the focus, so typing can start
// straight away: the panel never took the keyboard from Claude (FloatingPanel), so it's Claude's to use. Claude
// builds the conversation's page a moment after it switches, so this waits for the box (up to 5s).
- (void)focusBoxFor:(NSString *)hostId tries:(int)tries {
    if (!AXIsProcessTrusted()) return;
    [self.conversations readFocusLog];
    NSArray *boxes = [self.conversations.loggedFocusId isEqual:hostId] ? [self promptBoxes] : @[];
    if (boxes.count == 1) {
        AXError error = AXUIElementSetAttributeValue((__bridge AXUIElementRef)boxes[0], kAXFocusedAttribute,
                                                     kCFBooleanTrue);
        PanelLog(@"open desktop session %@ -> message box focused (AX %d)", hostId, error);
        return;
    }
    if (tries >= 50) {
        PanelLog(@"open desktop session %@ -> message box not focused: %lu found", hostId, (unsigned long)boxes.count);
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self focusBoxFor:hostId tries:tries + 1];
    });
}

// Claude's message boxes ("Prompt" text areas). Electron builds a page's accessibility tree only once
// something asks for it (AXManualAccessibility), so the first look can come back empty.
- (NSArray *)promptBoxes {
    pid_t pid = ClaudePid();
    if (!pid) return @[];
    AXUIElementRef app = AXUIElementCreateApplication(pid);
    AXUIElementSetAttributeValue(app, (__bridge CFStringRef)kElectronManualAccessibility, kCFBooleanTrue);
    CFTypeRef windows = NULL;
    AXUIElementCopyAttributeValue(app, kAXWindowsAttribute, &windows);
    CFRelease(app);
    NSMutableArray *boxes = [NSMutableArray array];
    for (id window in (__bridge_transfer NSArray *)windows)
        AXCollect((__bridge AXUIElementRef)window, 0, ^BOOL(AXUIElementRef el) {
            return [AXText(el, kAXRoleAttribute) isEqual:@"AXTextArea"]
                && [AXText(el, kAXDescriptionAttribute) isEqual:kClaudeDesktopPromptLabel];
        }, boxes);
    return boxes;
}

#pragma mark Sending a command

- (BOOL)mayControl {
    if (AXIsProcessTrusted()) return YES;
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES});
    return NO;
}

- (void)send:(NSString *)command toConversation:(NSString *)hostId done:(void (^)(NSString *why))done {
    [self write:command inConversation:hostId tries:0 done:done];
}

- (void)write:(NSString *)command inConversation:(NSString *)hostId tries:(int)tries
         done:(void (^)(NSString *why))done {
    [self.conversations readFocusLog];
    NSArray *boxes = [self.conversations.loggedFocusId isEqual:hostId] ? [self promptBoxes] : @[];
    if (boxes.count != 1) {
        if (tries < 100) {  // up to 10s: Claude may be starting, or switching to the conversation
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [self write:command inConversation:hostId tries:tries + 1 done:done];
            });
            return;
        }
        PanelLog(@"%@ -> %@ not sent: %@ (Claude shows %@, %lu message boxes)", hostId, command,
                 boxes.count > 1 ? @"several message boxes" : @"Claude never showed the conversation's message box",
                 self.conversations.loggedFocusId ?: @"no conversation", (unsigned long)[self promptBoxes].count);
        AXUIElementRef app = AXUIElementCreateApplication(ClaudePid());
        CFTypeRef windows = NULL;
        AXError error = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute, &windows);
        // What Claude was showing instead: its text boxes (by label) and anything modal (a popover, a menu, a
        // dialog).
        NSMutableArray *seen = [NSMutableArray array];
        for (id window in (__bridge NSArray *)windows)
            AXCollect((__bridge AXUIElementRef)window, 0, ^BOOL(AXUIElementRef el) {
                NSString *role = AXText(el, kAXRoleAttribute), *sub = AXText(el, kAXSubroleAttribute);
                if (![@[@"AXTextArea", @"AXTextField", @"AXSheet", @"AXPopover", @"AXMenu"] containsObject:role ?: @""]
                    && ![sub isEqual:@"AXDialog"])
                    return NO;
                [seen addObject:[NSString stringWithFormat:@"%@%@ \"%@\"", role,
                                 sub ? [@"/" stringByAppendingString:sub] : @"",
                                 AXText(el, kAXDescriptionAttribute) ?: AXText(el, kAXTitleAttribute) ?: @""]];
                return NO;
            }, [NSMutableArray array]);
        PanelLog(@"   Claude pid %d, trusted %d, windows %ld (AX %d), in front: %@; showing: %@", ClaudePid(),
                 AXIsProcessTrusted(), windows ? CFArrayGetCount(windows) : -1L, error,
                 NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier,
                 seen.count ? [seen componentsJoinedByString:@", "] : @"no text boxes, popovers or dialogs");
        if (windows) CFRelease(windows);
        CFRelease(app);
        done(boxes.count > 1
             ? @"Claude showed more than one message box: try again in Claude"
             : @"Couldn't reach Claude's message box: close any popover or menu in Claude, then try again");
        return;
    }
    id box = boxes[0];
    NSString *draft = [AXText((__bridge AXUIElementRef)box, kAXValueAttribute) ?: @""
                       stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (draft.length) {
        PanelLog(@"%@ -> %@ not sent: there's a message being written in Claude", hostId, command);
        NSBeep();
        done(@"There's a message half-written in Claude: send or clear it first");
        return;
    }
    AXUIElementSetAttributeValue((__bridge AXUIElementRef)box, kAXFocusedAttribute, kCFBooleanTrue);
    AXError error = AXUIElementSetAttributeValue((__bridge AXUIElementRef)box, kAXValueAttribute,
                                                 (__bridge CFStringRef)command);
    PanelLog(@"%@ -> \"%@\" in Claude's message box (AX %d)", hostId, command, error);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self submit:command box:box inConversation:hostId done:done];
    });
}

// Presses the composer's Submit button; if there isn't one to press and Claude is in front, Return.
- (void)submit:(NSString *)command box:(id)box inConversation:(NSString *)hostId
          done:(void (^)(NSString *why))done {
    AXUIElementRef field = (__bridge AXUIElementRef)box;
    if (![AXText(field, kAXValueAttribute) ?: @"" containsString:command]) {
        PanelLog(@"%@ -> Claude's message box didn't take the text; nothing sent", hostId);
        done(@"Claude's message box didn't take the command: try again");
        return;
    }
    // The composer's own Submit, looked for from the message box outward a level at a time: the first level
    // that has one is the composer, so a Submit elsewhere in the window (a question Claude is asking has
    // one) is never the one pressed.
    BOOL (^submit)(AXUIElementRef) = ^BOOL(AXUIElementRef el) {
        if (![AXText(el, kAXRoleAttribute) isEqual:@"AXButton"]) return NO;
        CFTypeRef enabled = NULL;
        AXUIElementCopyAttributeValue(el, kAXEnabledAttribute, &enabled);
        BOOL on = enabled == kCFBooleanTrue;
        if (enabled) CFRelease(enabled);
        NSString *label = AXText(el, kAXDescriptionAttribute).length ? AXText(el, kAXDescriptionAttribute)
                                                                      : AXText(el, kAXTitleAttribute);
        return on && [ClaudeDesktopSendLabels() containsObject:label ?: @""];
    };
    NSMutableArray *buttons = [NSMutableArray array];
    id searched = box;  // each level adds only what's beside the level below, which has been searched already
    for (int up = 0; up < 12 && !buttons.count; up++) {
        CFTypeRef parent = NULL;
        if (AXUIElementCopyAttributeValue((__bridge AXUIElementRef)searched, kAXParentAttribute, &parent)
                != kAXErrorSuccess || !parent)
            break;
        id level = (__bridge_transfer id)parent;
        if ([AXText((__bridge AXUIElementRef)level, kAXRoleAttribute) isEqual:@"AXApplication"]) break;
        if (submit((__bridge AXUIElementRef)level)) [buttons addObject:level];
        CFTypeRef children = NULL;
        AXUIElementCopyAttributeValue((__bridge AXUIElementRef)level, kAXChildrenAttribute, &children);
        for (id child in (__bridge_transfer NSArray *)children)
            if (!CFEqual((__bridge CFTypeRef)child, (__bridge CFTypeRef)searched))
                AXCollect((__bridge AXUIElementRef)child, 0, submit, buttons);
        searched = level;
    }
    BOOL front = [NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier isEqual:kClaudeDesktopAppId];
    if (buttons.count == 1) {
        AXUIElementPerformAction((__bridge AXUIElementRef)buttons[0], kAXPressAction);
        PanelLog(@"%@ -> submitted with Claude's Submit button", hostId);
    } else if (front) {
        // Return, pressed and let go.
        CGEventRef down = CGEventCreateKeyboardEvent(NULL, 36, true), up = CGEventCreateKeyboardEvent(NULL, 36, false);
        CGEventPost(kCGHIDEventTap, down);
        CGEventPost(kCGHIDEventTap, up);
        CFRelease(down);
        CFRelease(up);
        PanelLog(@"%@ -> submitted with Return (%lu Submit buttons found)", hostId, (unsigned long)buttons.count);
    } else {
        AXUIElementSetAttributeValue(field, kAXValueAttribute, CFSTR(""));
        PanelLog(@"%@ -> no Submit button and Claude isn't in front; cleared the box, nothing sent", hostId);
        done(@"Couldn't press Send in Claude: try again with Claude in front");
        return;
    }
    // If the command is still sitting in the box later, it wasn't taken, so it's cleared away. (The block holds
    // `box`, which keeps the element alive; a bare AXUIElementRef captured here would dangle.)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        AXUIElementRef later = (__bridge AXUIElementRef)box;
        if ([[AXText(later, kAXValueAttribute) ?: @""
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
                isEqualToString:command]) {
            AXUIElementSetAttributeValue(later, kAXValueAttribute, CFSTR(""));
            PanelLog(@"%@ -> %@ was still in Claude's message box; cleared it", hostId, command);
        }
    });
    done(nil);
}

- (BOOL)shows:(NSString *)value as:(NSString *)field inRecord:(NSDictionary *)record {
    NSString *key = @{@"model": @"model", @"effort": @"effort", @"mode": @"permissionMode"}[field];
    if (!key) return NO;  // nothing in Claude's record says a compaction happened; its transcript does
    NSString *now = record[key];
    return [field isEqual:@"model"] ? [now hasPrefix:value] : [now isEqual:value];
}

#pragma mark "Switch model?"

// Switching model re-reads a conversation whose cache is warm, one with a reply in the last hour (the cache keeps
// for up to an hour), so Claude asks first, unless "Don't ask again" was chosen.
- (BOOL)mayAskToSwitch:(Row *)row {
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"neverAskSwitch"]) return NO;
    double last = MAX(row.lastReplyAt.doubleValue, row.messageAt.doubleValue);
    return NSDate.date.timeIntervalSince1970 * 1000 - last < 3600 * 1000;
}

- (void)stopAskingToSwitch {
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"neverAskSwitch"];
}

- (BOOL)showsSwitchBox {
    return [self claudeControl:@"AXButton" named:^BOOL(NSString *l) {
        return [l isEqualToString:kClaudeDesktopSwitchModelLabel];
    }] != nil;
}

// Answers Claude's "Switch model?" box. Returns NO if the box isn't up.
- (BOOL)answerSwitchBox:(BOOL)switchModel dontAskAgain:(BOOL)dontAskAgain {
    id go = [self claudeControl:@"AXButton" named:^BOOL(NSString *l) {
        return [l isEqualToString:kClaudeDesktopSwitchModelLabel];
    }];
    if (!go) return NO;
    if (switchModel) {
        if (dontAskAgain) {
            id never = [self claudeControl:@"AXCheckBox" named:^BOOL(NSString *l) {
                return [l hasSuffix:kClaudeDesktopDontAskSuffix];
            }];
            if (never) AXUIElementPerformAction((__bridge AXUIElementRef)never, kAXPressAction);
        }
        AXUIElementPerformAction((__bridge AXUIElementRef)go, kAXPressAction);
    } else {
        id cancel = [self claudeControl:@"AXButton" named:^BOOL(NSString *l) {
            return [l isEqualToString:kClaudeDesktopCancelLabel];
        }];
        if (cancel) AXUIElementPerformAction((__bridge AXUIElementRef)cancel, kAXPressAction);
    }
    return YES;
}

// Claude's own "Switch model?" box, if it's up: its Switch model and Cancel buttons and the Don't ask again
// box, by their labels.
- (id)claudeControl:(NSString *)role named:(BOOL (^)(NSString *label))named {
    pid_t pid = ClaudePid();
    if (!pid) return nil;
    AXUIElementRef app = AXUIElementCreateApplication(pid);
    CFTypeRef windows = NULL;
    AXUIElementCopyAttributeValue(app, kAXWindowsAttribute, &windows);
    CFRelease(app);
    NSMutableArray *found = [NSMutableArray array];
    for (id window in (__bridge_transfer NSArray *)windows)
        AXCollect((__bridge AXUIElementRef)window, 0, ^BOOL(AXUIElementRef el) {
            if (![AXText(el, kAXRoleAttribute) isEqual:role]) return NO;
            NSString *label = AXText(el, kAXTitleAttribute).length ? AXText(el, kAXTitleAttribute)
                                                                    : AXText(el, kAXDescriptionAttribute);
            return label && named(label);
        }, found);
    return found.count == 1 ? found[0] : nil;
}

@end
