// DesktopMessageBox: writing in a conversation's message box, and sending what's written.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "DesktopMessageBox.h"
#import "DesktopLog.h"
#import "ClaudeDesktopFacts.h"
#import "Accessibility.h"
#import "Log.h"

// Claude Desktop takes no outside input for a conversation's settings: no link, file or tool reaches them. So the
// panel sends the slash command that would be typed by hand, in the conversation's own message box. It writes the
// text there through the Accessibility API and presses Submit, with no menus opening; Return is pressed only if
// there's no Submit button, and only with Claude in front (submit:). The conversation has to be the one
// Claude shows, because only that one has a message box, so it's opened first if it isn't. A half-written message
// is never touched: then nothing is sent.

// The composer's own Submit, one that can be pressed now, looked for from the message box outward a level at a time:
// the first level that has one is the composer, so a Submit elsewhere in the window (a question Claude is asking has
// one) is never the one pressed.
NSArray *DesktopSendButtons(id box) {
    BOOL (^submit)(AXUIElementRef) = ^BOOL(AXUIElementRef el) {
        if (![ElementText(el, kAXRoleAttribute) isEqual:@"AXButton"]) return NO;
        CFTypeRef enabled = NULL;
        AXUIElementCopyAttributeValue(el, kAXEnabledAttribute, &enabled);
        BOOL on = enabled == kCFBooleanTrue;
        if (enabled) CFRelease(enabled);
        NSString *label = ElementText(el, kAXDescriptionAttribute).length ? ElementText(el, kAXDescriptionAttribute)
                                                                          : ElementText(el, kAXTitleAttribute);
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
        if ([ElementText((__bridge AXUIElementRef)level, kAXRoleAttribute) isEqual:@"AXApplication"]) break;
        if (submit((__bridge AXUIElementRef)level)) [buttons addObject:level];
        CFTypeRef children = NULL;
        AXUIElementCopyAttributeValue((__bridge AXUIElementRef)level, kAXChildrenAttribute, &children);
        for (id child in (__bridge_transfer NSArray *)children)
            if (!CFEqual((__bridge CFTypeRef)child, (__bridge CFTypeRef)searched))
                CollectElements((__bridge AXUIElementRef)child, 0, submit, buttons);
        searched = level;
    }
    return buttons;
}

@interface DesktopMessageBox ()
@property (strong) DesktopLog *log;
@end

@implementation DesktopMessageBox

- (instancetype)initWithLog:(DesktopLog *)log {
    if (!(self = [super init])) return nil;
    self.log = log;
    return self;
}

// Once Claude shows the conversation opened from a row, its message box gets the focus, so typing can start
// straight away: the panel never took the keyboard from Claude (FloatingPanel), so it's Claude's to use. Claude
// builds the conversation's page a moment after it switches, so this waits for the box (up to 5s).
- (void)focusBoxFor:(NSString *)hostId tries:(int)tries {
    if (!AXIsProcessTrusted()) return;
    [self.log catchUp];
    NSArray *boxes = [self.log.loggedFocusId isEqual:hostId] ? [self promptBoxes] : @[];
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
    pid_t pid = ClaudeDesktopPid();
    if (!pid) return @[];
    AXUIElementRef app = AXUIElementCreateApplication(pid);
    AXUIElementSetAttributeValue(app, (__bridge CFStringRef)kElectronManualAccessibility, kCFBooleanTrue);
    CFTypeRef windows = NULL;
    AXUIElementCopyAttributeValue(app, kAXWindowsAttribute, &windows);
    CFRelease(app);
    NSMutableArray *boxes = [NSMutableArray array];
    for (id window in (__bridge_transfer NSArray *)windows)
        CollectElements((__bridge AXUIElementRef)window, 0, ^BOOL(AXUIElementRef el) {
            return [ElementText(el, kAXRoleAttribute) isEqual:@"AXTextArea"]
                && [ElementText(el, kAXDescriptionAttribute) isEqual:kClaudeDesktopPromptLabel];
        }, boxes);
    return boxes;
}

- (void)send:(NSString *)command toConversation:(NSString *)hostId done:(void (^)(NSString *why))done {
    [self write:command inConversation:hostId tries:0 done:done];
}

- (void)write:(NSString *)command inConversation:(NSString *)hostId tries:(int)tries
         done:(void (^)(NSString *why))done {
    [self.log catchUp];
    NSArray *boxes = [self.log.loggedFocusId isEqual:hostId] ? [self promptBoxes] : @[];
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
                 self.log.loggedFocusId ?: @"no conversation", (unsigned long)[self promptBoxes].count);
        AXUIElementRef app = AXUIElementCreateApplication(ClaudeDesktopPid());
        CFTypeRef windows = NULL;
        AXError error = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute, &windows);
        // What Claude was showing instead: its text boxes (by label) and anything modal (a popover, a menu, a
        // dialog).
        NSMutableArray *seen = [NSMutableArray array];
        for (id window in (__bridge NSArray *)windows)
            CollectElements((__bridge AXUIElementRef)window, 0, ^BOOL(AXUIElementRef el) {
                NSString *role = ElementText(el, kAXRoleAttribute), *sub = ElementText(el, kAXSubroleAttribute);
                if (![@[@"AXTextArea", @"AXTextField", @"AXSheet", @"AXPopover", @"AXMenu"] containsObject:role ?: @""]
                    && ![sub isEqual:@"AXDialog"])
                    return NO;
                [seen addObject:[NSString stringWithFormat:@"%@%@ \"%@\"", role,
                                 sub ? [@"/" stringByAppendingString:sub] : @"",
                                 ElementText(el, kAXDescriptionAttribute) ?: ElementText(el, kAXTitleAttribute) ?: @""]];
                return NO;
            }, [NSMutableArray array]);
        PanelLog(@"   Claude pid %d, trusted %d, windows %ld (AX %d), in front: %@; showing: %@", ClaudeDesktopPid(),
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
    NSString *draft = [ElementText((__bridge AXUIElementRef)box, kAXValueAttribute) ?: @""
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
    if (![ElementText(field, kAXValueAttribute) ?: @"" containsString:command]) {
        PanelLog(@"%@ -> Claude's message box didn't take the text; nothing sent", hostId);
        done(@"Claude's message box didn't take the command: try again");
        return;
    }
    NSArray *buttons = DesktopSendButtons(box);
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
        if ([[ElementText(later, kAXValueAttribute) ?: @""
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
                isEqualToString:command]) {
            AXUIElementSetAttributeValue(later, kAXValueAttribute, CFSTR(""));
            PanelLog(@"%@ -> %@ was still in Claude's message box; cleared it", hostId, command);
        }
    });
    done(nil);
}

@end
