// AppDelegate: the app itself: the page, the panel's window, the pawn and the core, made and started.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "AppDelegate.h"
#import "Log.h"
#import "Files.h"
#import "Page.h"
#import "PanelWindow.h"
#import "MenuBar.h"
#import "Builds.h"
#import "Core.h"
#import "Modules.h"
#import "Rows.h"
#import "Focus.h"

@interface AppDelegate ()
@property (strong) Page *page;
@property (strong) PanelWindow *window;
@property (strong) MenuBar *menuBar;
@property (strong) Core *core;  // the core's services, and the modules
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    // Whozmove's folder holds the prompts, Claude's replies and the requests waiting for an answer (with what a
    // tool would write), so only its owner may read it, as with Claude Code's own files. The hooks make it too,
    // but the panel may start first.
    NSString *home = AppDir(nil);
    [NSFileManager.defaultManager createDirectoryAtPath:home withIntermediateDirectories:YES
                                             attributes:@{NSFilePosixPermissions: @0700} error:nil];
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @0700} ofItemAtPath:home error:nil];
    // The permission hook asks here only while the panel runs; this tells it the panel does.
    [[NSString stringWithFormat:@"%d", getpid()] writeToFile:AppDir(@"panel.pid") atomically:YES
                                                 encoding:NSUTF8StringEncoding error:nil];
    self.page = [Page new];
    self.window = [[PanelWindow alloc] initWithPage:self.page];
    self.menuBar = [[MenuBar alloc] initWithWindow:self.window page:self.page];
    self.core = [[Core alloc] initWithPage:self.page window:self.window menuBar:self.menuBar];
    __weak typeof(self) weakSelf = self;
    [self.core.focus start];
    [self.core.modules launch];
    [self.menuBar addEntries:self.core.modules.menuEntries];
    self.page.onLoad = ^{ [weakSelf pageLoaded]; };
    // Each of the page's messages to the core or the one module that answers it (Modules).
    self.page.onMessage = ^(NSString *type, NSDictionary *msg) {
        if (![weakSelf.core.modules route:type message:msg])
            LogProblem([@"a message nothing answers: " stringByAppendingString:type]);
    };
    [self.page load];
    [self.window show];
    [self.core.rows start];
}

- (void)applicationWillTerminate:(NSNotification *)note {
    NSString *pidFile = AppDir(@"panel.pid");
    if ([[NSString stringWithContentsOfFile:pidFile encoding:NSUTF8StringEncoding error:nil] intValue] == getpid())
        [NSFileManager.defaultManager removeItemAtPath:pidFile error:nil];
}

// A freshly loaded page (at the start, or after a reload) learns how tall it can grow, how it's grouped, the menu's
// switches and the build running, and gets each module's part and its rows at once.
- (void)pageLoaded {
    [self.window resendRoom];
    [self.menuBar applySavedGrouping];
    [self.menuBar applySavedSwitches];
    [self.page setRunningBuild:RunningBuild()];
    [self.core.modules pageLoaded];
    [self.core.rows refresh];
}

@end
