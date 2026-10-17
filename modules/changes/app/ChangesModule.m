// ChangesModule: the changes view's face for the core (Module): each session's numbers on its row, the view the page
// asks for, a changed file opened in your editor, the pawn menu's Open With, and the print mode the tests check.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import "Module.h"
#import "Core.h"
#import "Modules.h"
#import "Page.h"
#import "Row.h"
#import "Printing.h"
#import "Changes.h"
#import "Editors.h"
#import "Menus.h"

@interface ChangesModule : NSObject <Module, NSMenuDelegate>
@property (weak) Core *core;
@property (strong) Changes *changes;
@property (strong) NSMenu *openWithMenu;  // filled as it opens: the editors on this Mac change
@end

// `Whozmove --print-changes <sessionId> <scope>`: what the changes view would be sent for that session in $HOME (its
// own changes, the whole checkout's, or its commits not on GitHub yet: `session`, `branch` or `commits`), each line
// credited to whoever wrote it, as JSON, then quit.
static int PrintChanges(Core *core, NSArray<NSString *> *arguments) {
    Changes *changes = nil;
    for (id module in core.modules.all)
        if ([module isKindOfClass:ChangesModule.class]) changes = [(ChangesModule *)module changes];
    SettledRows(core);
    NSString *sid = arguments.count > 0 ? arguments[0] : @"", *scope = arguments.count > 1 ? arguments[1] : @"session";
    if (![scope isEqualToString:@"commits"]) return PrintJSON([changes viewOf:sid scope:scope] ?: @{});
    // The commits view is worked out off the main thread, as the page asks for it.
    __block NSDictionary *view = nil;
    __block BOOL done = NO;
    [changes commitsOf:sid done:^(NSDictionary *answer) { view = answer; done = YES; }];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!done && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    return PrintJSON(view ?: @{});
}

@implementation ChangesModule

+ (NSString *)moduleName {
    return @"changes";
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    // What each session edited is its agent's to say.
    self.changes = [Changes new];
    self.changes.core = core;
    return self;
}

+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return @{@"--print-changes": ^(Core *core, NSArray *a) { return PrintChanges(core, a); }};
}

- (void)pageLoaded {
    [self.core.page call:@"setEditors" with:@[EditorChoices()]];
}

- (NSDictionary<NSString *, void (^)(NSDictionary *)> *)messages {
    __weak typeof(self) weakSelf = self;
    return @{
        @"readChanges": ^(NSDictionary *msg) {
            NSString *sid = msg[@"sessionId"], *scope = msg[@"scope"];
            if (![sid isKindOfClass:NSString.class]) return;
            // Built, and made JSON, off the main thread: a large view would hold up everything else here.
            scope = [scope isEqual:@"commits"] ? @"commits" : [scope isEqual:@"branch"] ? @"branch" : @"session";
            [weakSelf.changes viewOf:sid scope:scope done:^(NSString *json) {
                if (json) [weakSelf.core.page call:@"showChanges" arguments:[@"..." stringByAppendingString:json]];
            }];
        },
        @"openFile": ^(NSDictionary *msg) {
            // Only a file among the session's checkout's changes, in the editor you chose (here, the first time).
            NSString *path = [weakSelf.changes fileOf:msg[@"sessionId"] path:msg[@"path"]];
            if ([msg[@"editor"] isKindOfClass:NSString.class]) {
                ChooseEditor(msg[@"editor"]);
                [weakSelf.core.page call:@"setEditors" with:@[EditorChoices()]];
            }
            if (path && !OpenInEditor(path, [msg[@"line"] integerValue])) NSBeep();
        },
    };
}

// Each session's work: whose each changed line is, worked out again where something changed, and the session's own
// numbers.
- (void)rows:(NSArray<Row *> *)rows phase:(RowPhase)phase {
    if (phase != RowPhaseWork) return;
    [self.changes refreshFor:rows];
    for (Row *row in rows) row.changes = [self.changes rowChangesOf:row];
}

- (BOOL)working {
    return self.changes.working;
}

#pragma mark Open With

// Open With ▸ in the pawn menu: the editors a changed file can open in (the changes view's Open in Editor), the chosen
// one ticked.
- (NSArray<MenuEntry *> *)menuEntries {
    self.openWithMenu = [NSMenu new];
    self.openWithMenu.autoenablesItems = NO;
    self.openWithMenu.delegate = self;
    NSMenuItem *openWith = [[NSMenuItem alloc] initWithTitle:@"Open With" action:nil keyEquivalent:@""];
    openWith.submenu = self.openWithMenu;
    return @[[MenuEntry entryIn:MenuSectionFeatures order:30 item:openWith]];
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    NSDictionary *choices = EditorChoices();
    for (NSDictionary *app in choices[@"apps"]) {
        NSMenuItem *item = [menu addItemWithTitle:app[@"name"] action:@selector(chooseEditor:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = app[@"id"];
        item.state = [app[@"id"] isEqual:choices[@"choice"]] ? NSControlStateValueOn : NSControlStateValueOff;
    }
    if (![choices[@"apps"] count]) SayInMenu(menu, @"No Editor Found");
}

- (void)chooseEditor:(NSMenuItem *)item {
    ChooseEditor(item.representedObject);
    [self.core.page call:@"setEditors" with:@[EditorChoices()]];
}

@end
