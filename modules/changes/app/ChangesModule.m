// ChangesModule: the changes view's face for the core (Module): each session's numbers on its row, the view the page
// asks for, a changed file opened in your editor, Open Files With in Settings, and the print mode the tests check.
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

@interface ChangesModule : NSObject <Module, FilesAtLines>
@property (weak) Core *core;
@property (strong) Changes *changes;
@end

// The scopes the changes view has, as git splits what it shows: not staged (new files included), staged, and the
// commits not on GitHub yet.
static NSString *ScopeOf(id scope) {
    return [@[@"unstaged", @"staged", @"outgoing"] containsObject:scope] ? scope : @"unstaged";
}

// `Whozmove --print-changes <sessionId> <scope>`: what the changes view would be sent for that session's checkout in
// $HOME (`unstaged`, `staged` or `outgoing`), as JSON, then quit.
static int PrintChanges(Core *core, NSArray<NSString *> *arguments) {
    Changes *changes = nil;
    for (id module in core.modules.all)
        if ([module isKindOfClass:ChangesModule.class]) changes = [(ChangesModule *)module changes];
    SettledRows(core);
    NSString *sid = arguments.count > 0 ? arguments[0] : @"", *scope = ScopeOf(arguments.count > 1 ? arguments[1] : nil);
    // Outgoing is read off the main thread, as the page asks for it.
    __block NSDictionary *view = nil;
    __block BOOL done = NO;
    [changes view:sid scope:scope done:^(NSDictionary *answer) { view = answer; done = YES; }];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!done && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    return PrintJSON(view ?: @{});
}

// `Whozmove --print-count-due`: whether a checkout's changes are due a count for sample states (ChangesCountDue): not
// watched or watched, changed or not, its editors' lines moved or not, seconds since its last count, since the latest
// change and since the first one not counted. As JSON, then quit. The module's tests check it.
static int PrintCountDue(void) {
    NSMutableArray *due = [NSMutableArray array];
    for (NSArray *c in @[@[@NO, @NO, @NO, @1, @0, @0], @[@NO, @NO, @YES, @1, @0, @0], @[@NO, @NO, @NO, @3, @0, @0],
                         @[@YES, @NO, @NO, @3, @0, @0], @[@YES, @YES, @NO, @3, @1, @1],
                         @[@YES, @YES, @YES, @3, @1, @1], @[@YES, @YES, @NO, @3, @2, @2],
                         @[@YES, @YES, @NO, @2, @2, @2], @[@YES, @YES, @NO, @11, @1, @10],
                         @[@YES, @NO, @NO, @1799, @0, @0], @[@YES, @NO, @NO, @1800, @0, @0]]) {
        NSString *what = [c[0] boolValue]
            ? [NSString stringWithFormat:@"watched, %@%@", [c[1] boolValue] ? @"changed" : @"unchanged",
                                        [c[2] boolValue] ? @", edits moved" : @""]
            : [c[2] boolValue] ? @"not watched, edits moved" : @"not watched";
        [due addObject:@[[NSString stringWithFormat:@"%@, %@s since the last count, %@s since the latest change, %@s "
                                                    @"since the first", what, c[3], c[4], c[5]],
                         @(ChangesCountDue([c[0] boolValue], [c[1] boolValue], [c[2] boolValue], [c[3] doubleValue],
                                           [c[4] doubleValue], [c[5] doubleValue], 1800))]];
    }
    return PrintJSON(due);
}

// Names in a sentence: "A, B or C".
static NSString *ListedWithOr(NSArray<NSString *> *names) {
    if (names.count < 2) return names.firstObject ?: @"";
    NSArray *first = [names subarrayWithRange:NSMakeRange(0, names.count - 1)];
    return [NSString stringWithFormat:@"%@ or %@", [first componentsJoinedByString:@", "], names.lastObject];
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
    return @{@"--print-changes": ^(Core *core, NSArray *a) { return PrintChanges(core, a); },
             @"--print-count-due": ^(Core *core, NSArray *a) { return PrintCountDue(); }};
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
            // Made JSON off the main thread: a large view would hold up everything else here.
            [weakSelf.changes viewOf:sid scope:ScopeOf(scope) done:^(NSString *json) {
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
        // The picker's way forward with no editor on this Mac: the one it names, from its download page.
        @"getEditor": ^(NSDictionary *msg) { GetEditor(); },
    };
}

// Each session's work: what isn't committed in its checkout, counted again where something changed, as its row's
// numbers.
- (void)rows:(NSArray<Row *> *)rows phase:(RowPhase)phase {
    if (phase != RowPhaseWork) return;
    [self.changes refreshFor:rows];
    for (Row *row in rows) row.changes = [self.changes rowChangesOf:row];
}

- (BOOL)working {
    return self.changes.working;
}

#pragma mark Open Files With

// Open Files With, in Settings on the panel's back: the editors on this Mac a changed file can open in (the changes
// view's Open in Editor), each with its icon, and the one chosen. Until one is, the changes view asks the first time.
- (NSArray<SettingEntry *> *)settingEntries {
    __weak typeof(self) weakSelf = self;
    NSDictionary *choices = EditorChoices();
    SettingEntry *editor = [SettingEntry choiceWithKey:@"openWith" title:@"Open Files With" glyph:@"file"
        choices:^NSArray<NSDictionary *> * {
            NSMutableArray *apps = [NSMutableArray array];
            for (NSDictionary *app in choices[@"apps"])
                [apps addObject:@{@"id": app[@"id"], @"name": app[@"name"], @"appId": app[@"id"]}];
            return apps;
        }
        picked:^NSString * { return choices[@"choice"]; }
        pick:^(NSString *choice) {
            ChooseEditor(choice);
            [weakSelf.core.page call:@"setEditors" with:@[EditorChoices()]];
        }];
    editor.foot = [choices[@"apps"] count]
        ? @"A changed file in the changes view opens here. Only the editors on this Mac are listed."
        : [NSString stringWithFormat:@"None of the editors Whozmove opens files in is on this Mac: %@.",
                                     ListedWithOr(KnownEditorNames())];
    // With none of them here, the way forward is one to get, by name.
    if (choices[@"get"]) {
        editor.button = [@"Get " stringByAppendingString:choices[@"get"]];
        editor.press = ^{ GetEditor(); };
    }
    editor.group = 10;
    editor.order = 30;
    return @[editor];
}

// Another module's file, at a line, in the editor you chose (FilesAtLines): it has checked the file is its to open.
- (BOOL)openFile:(NSString *)path atLine:(NSInteger)line {
    return path.length && OpenInEditor(path, line);
}

@end
