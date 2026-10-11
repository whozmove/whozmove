// Terminal: the shape every terminal the panel works with fills in, and typing a command into a session through it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// A terminal finds a session's tab, brings it forward, opens a new one, and puts text and keys into a tab
// (Ghostty.m fills it in). A session in any other terminal app is opened by bringing that app forward, and isn't
// typed into. Whether it's safe to type is the session's own state, the same in every terminal (WhyNotTypeInto).
#import <Foundation/Foundation.h>

@class Row, Reason;

// The keys the panel presses in a session's prompt.
typedef NS_ENUM(NSInteger, TerminalKey) {
    TerminalKeyReturn,
    TerminalKeyBackspace,
    TerminalKeyShiftTab,
    TerminalKeyControlS,
};

@protocol Terminal <NSObject>
// The terminal's app id, and its name as the panel says it.
@property (readonly) NSString *appId;
@property (readonly) NSString *name;
// The tab a session runs in, or nil. *unique says whether nothing else in its folder fits as well: keys go only
// into a tab that's certainly the session's.
- (NSString *)tabFor:(Row *)row unique:(BOOL *)unique;
// Brings a session's tab forward. NO if its tab can't be found.
- (BOOL)focus:(Row *)row;
// A new tab in a folder, running `claude`.
- (void)newTabIn:(NSString *)folder;
// Puts text into a tab, or presses a key there `times` times.
- (void)type:(NSString *)text inTab:(NSString *)tab;
- (void)press:(TerminalKey)key times:(NSInteger)times inTab:(NSString *)tab;
@end

// The terminal among these with this app id, or nil.
id<Terminal> TerminalFor(NSArray<id<Terminal>> *terminals, NSString *appId);

// Types a slash command into a session's prompt, keeping any draft there, a keystroke at a time and each only while
// `whyNot` returns nil. `done` gets nil once every keystroke is in, or why typing stopped and after how many.
// DeleteFiller takes out the filler it leaves at the end of the draft, once the draft is back.
void TypeCommand(id<Terminal> terminal, NSString *tab, NSString *command, Reason *(^whyNot)(void),
                 void (^done)(Reason *why, NSUInteger typed, NSUInteger steps));
void DeleteFiller(id<Terminal> terminal, NSString *tab);
