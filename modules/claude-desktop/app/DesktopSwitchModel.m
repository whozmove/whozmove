// DesktopSwitchModel: Claude Desktop's "Switch model?".
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "DesktopSwitchModel.h"
#import <Cocoa/Cocoa.h>
#import "ClaudeDesktopFacts.h"
#import "Accessibility.h"
#import "Row.h"

// Switching model re-reads a conversation whose cache is warm, one with a reply in the last hour (the cache keeps
// for up to an hour), so Claude asks first, unless "Don't ask again" was chosen.
BOOL ClaudeMayAskToSwitch(Row *row) {
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"neverAskSwitch"]) return NO;
    double last = MAX(row.lastReplyAt.doubleValue, row.messageAt.doubleValue);
    return NSDate.date.timeIntervalSince1970 * 1000 - last < 3600 * 1000;
}

void StopClaudeAskingToSwitch(void) {
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"neverAskSwitch"];
}

// Claude's own "Switch model?" box, if it's up: its Switch model and Cancel buttons and the Don't ask again box, by
// their labels.
static id SwitchControl(NSString *role, BOOL (^named)(NSString *label)) {
    return ControlNamed(ClaudeDesktopPid(), role, named);
}

BOOL ClaudeShowsSwitchBox(void) {
    return SwitchControl(@"AXButton", ^BOOL(NSString *l) {
        return [l isEqualToString:kClaudeDesktopSwitchModelLabel];
    }) != nil;
}

BOOL AnswerClaudeSwitchBox(BOOL switchModel, BOOL dontAskAgain) {
    id go = SwitchControl(@"AXButton", ^BOOL(NSString *l) {
        return [l isEqualToString:kClaudeDesktopSwitchModelLabel];
    });
    if (!go) return NO;
    if (switchModel) {
        if (dontAskAgain) {
            id never = SwitchControl(@"AXCheckBox", ^BOOL(NSString *l) {
                return [l hasSuffix:kClaudeDesktopDontAskSuffix];
            });
            if (never) AXUIElementPerformAction((__bridge AXUIElementRef)never, kAXPressAction);
        }
        AXUIElementPerformAction((__bridge AXUIElementRef)go, kAXPressAction);
    } else {
        id cancel = SwitchControl(@"AXButton", ^BOOL(NSString *l) {
            return [l isEqualToString:kClaudeDesktopCancelLabel];
        });
        if (cancel) AXUIElementPerformAction((__bridge AXUIElementRef)cancel, kAXPressAction);
    }
    return YES;
}
