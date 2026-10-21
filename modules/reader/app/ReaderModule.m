// ReaderModule: the reader's part in the app: a prototype a session wrote, shown from its file in a Browser of its own
// (app/core/Browser.h) over the reader's body, and opened in your web browser. Everything else the reader shows is the
// page's (page/writings.js), and reading a session's writings back is its agent's.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import "Module.h"
#import "Core.h"
#import "Page.h"
#import "PanelWindow.h"
#import "Row.h"
#import "Browser.h"
#import "Files.h"
#import "Links.h"
#import "Log.h"
#import "Printing.h"

// How long a prototype takes to come into view once its page has loaded: as long as the reader's own fade (.r-in, in
// panel/styles/reader.css), so it comes in as the rest of the reader does.
static const NSTimeInterval kFadeIn = 0.12;

// Where a prototype can be shown from: its file, read from the folder it's in, which its pages may show the other files
// of, and take what they use from the web; a link you press to anywhere else opens in your browser. Nil, with why in
// the reader's words, for a file that isn't there, or one in a folder too wide to open whole (the home folder itself, a
// disk's top). A plain function, so the print mode can show each case.
static BrowserSetup *PrototypeSetup(NSString *path, NSURL **page, NSString **problem) {
    BrowserSetup *setup = nil;
    NSString *why = nil;
    BOOL isFolder = NO;
    if (![path isKindOfClass:NSString.class] || !path.isAbsolutePath
        || ![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isFolder] || isFolder) {
        why = @"This file isn't there any more.";
    } else {
        NSString *real = RealPath(path);
        setup = [BrowserSetup folder:[NSURL fileURLWithPath:real.stringByDeletingLastPathComponent isDirectory:YES]];
        if (!setup) why = @"It's saved straight into your home folder (or a disk's top), which the panel won't open "
                          @"whole: open it in your browser.";
        // The file in the folder as the Browser has it, symlinks taken out, so it's always inside it.
        else if (page) *page = [setup.folder URLByAppendingPathComponent:real.lastPathComponent isDirectory:NO];
    }
    setup.webParts = YES;
    setup.linksOut = YES;
    if (problem) *problem = why;
    return setup;
}

// A page's ask, as the reader names it.
static NSString *AskWord(BrowserAskKind kind) {
    switch (kind) {
        case BrowserAskWindow: return @"window";
        case BrowserAskAlert:
        case BrowserAskConfirm:
        case BrowserAskPrompt: return @"alert";
        case BrowserAskFiles: return @"files";
        case BrowserAskDownload: return @"download";
        case BrowserAskCamera:
        case BrowserAskMicrophone:
        case BrowserAskCameraAndMicrophone: return @"camera";
        case BrowserAskOtherApp: return @"otherApp";
    }
    return @"other";
}

@interface ReaderModule : NSObject <Module, BrowserOwner>
@property (weak) Core *core;
// Each listed session's writings, by its id, as its row last had them: a prototype is found here, never by a path the
// page sends.
@property (copy) NSDictionary<NSString *, NSArray<NSDictionary *> *> *writings;
// The prototype shown now: its session, its writing, when the file was last written, its Browser, and whether its view
// has come into view. What the page was last told of it, so it's told only of a change; and the last thing it asked.
@property (copy) NSString *sessionId, *writingId;
@property (strong) NSNumber *writtenAt;
@property (strong) Browser *browser;
@property (assign) BOOL appeared;
@property (copy) NSDictionary *told;
@property (copy) NSString *asked;
@property (copy) NSString *problem;
@end

@implementation ReaderModule

+ (NSString *)moduleName {
    return @"reader";
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.writings = @{};
    return self;
}

// A click into the prototype gives the panel the keyboard, and a click anywhere else gives it back: either way the
// panel's window becomes key or stops being, and the line above the prototype says whether you can point and type in
// it now.
- (void)launch {
    __weak typeof(self) weakSelf = self;
    for (NSNotificationName name in @[NSWindowDidBecomeKeyNotification, NSWindowDidResignKeyNotification])
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(NSNotification *note) {
            if (note.object == weakSelf.browser.view.window) [weakSelf tell];
        }];
}

// The page has loaded again (its process ended, say): what it showed has gone, so the prototype goes too.
- (void)pageLoaded {
    [self hide];
}

// The keyboard can also move between the prototype and one of the page's boxes with the window staying key.
- (void)tick {
    [self tell];
}

- (void)rows:(NSArray<Row *> *)rows phase:(RowPhase)phase {
    if (phase != RowPhaseListed) return;
    NSMutableDictionary *writings = [NSMutableDictionary dictionary];
    for (Row *row in rows)
        if (row.sessionId && row.writings) writings[row.sessionId] = row.writings;
    self.writings = writings;
}

- (NSDictionary<NSString *, void (^)(NSDictionary *)> *)messages {
    __weak typeof(self) weakSelf = self;
    return @{
        // The reader's prototype: shown at a place in the page, moved there, gone, or opened in your web browser.
        @"prototype": ^(NSDictionary *msg) {
            NSString *action = msg[@"action"];
            if ([action isEqual:@"show"]) [weakSelf show:msg];
            else if ([action isEqual:@"place"]) [weakSelf place:msg];
            else if ([action isEqual:@"hide"]) [weakSelf hide];
            else if ([action isEqual:@"outside"]) [weakSelf openOutside:msg];
        },
    };
}

#pragma mark Showing it

// The writing a session lists by this id, if it's a prototype.
- (NSDictionary *)prototype:(NSString *)writingId of:(NSString *)sessionId {
    if (![sessionId isKindOfClass:NSString.class] || ![writingId isKindOfClass:NSString.class]) return nil;
    for (NSDictionary *writing in self.writings[sessionId])
        if ([writing[@"id"] isEqual:writingId])
            return [writing[@"kind"] isEqual:@"prototype"] ? writing : nil;
    return nil;
}

// Where in the page the reader's body is: {x, y, width, height}, in points from the page's top-left corner.
static NSRect PageRect(NSDictionary *rect) {
    if (![rect isKindOfClass:NSDictionary.class]) return NSZeroRect;
    double (^number)(NSString *) = ^double(NSString *key) {
        id value = rect[key];
        return [value isKindOfClass:NSNumber.class] ? [value doubleValue] : 0;
    };
    return NSMakeRect(number(@"x"), number(@"y"), MAX(0, number(@"width")), MAX(0, number(@"height")));
}

// A prototype to show at a place in the page. The same one again, written since, loads again where you were in it.
// Another is made a Browser of its own, held over the reader's body out of sight, and loads once the panel has finished
// growing, so it starts in view; it comes into view once its page has loaded.
- (void)show:(NSDictionary *)msg {
    NSString *sessionId = msg[@"sessionId"], *writingId = msg[@"id"];
    NSNumber *at = [msg[@"at"] isKindOfClass:NSNumber.class] ? msg[@"at"] : nil;
    NSRect rect = PageRect(msg[@"rect"]);
    if (self.browser && [sessionId isEqual:self.sessionId] && [writingId isEqual:self.writingId]) {
        [self.core.window hold:self.browser.view overPage:rect];
        if (at && ![at isEqual:self.writtenAt]) {
            self.writtenAt = at;
            [self.browser reload];
        }
        return;
    }
    [self hide];
    if (![sessionId isKindOfClass:NSString.class] || ![writingId isKindOfClass:NSString.class]) return;
    self.sessionId = sessionId;
    self.writingId = writingId;
    self.writtenAt = at;
    NSDictionary *writing = [self prototype:writingId of:sessionId];
    NSURL *page = nil;
    NSString *problem = nil;
    BrowserSetup *setup = writing ? PrototypeSetup(writing[@"path"], &page, &problem) : nil;
    if (!writing) problem = @"This isn't in the session's list any more.";
    Browser *browser = setup ? [self.core browserWith:setup owner:self] : nil;
    if (!browser) {
        self.problem = problem;
        [self tell];
        return;
    }
    self.browser = browser;
    browser.view.alphaValue = 0;
    [self.core.window hold:browser.view overPage:rect];
    [self tell];
    __weak typeof(self) weakSelf = self;
    [self.core.window whenStill:^{
        if (weakSelf.browser == browser && ![browser goTo:page]) {
            weakSelf.problem = @"This page can't be shown here.";
            [weakSelf tell];
        }
    }];
}

// The reader's body has moved or changed size: the prototype goes with it.
- (void)place:(NSDictionary *)msg {
    if (self.browser) [self.core.window hold:self.browser.view overPage:PageRect(msg[@"rect"])];
}

// The reader shows something else now, or has closed: the prototype goes, and with it the keyboard, if it had it.
- (void)hide {
    Browser *browser = self.browser;
    self.browser = nil;
    if (browser) {
        [self.core.window letGo:browser.view];
        [browser close];
    }
    self.sessionId = self.writingId = nil;
    self.writtenAt = nil;
    self.appeared = NO;
    self.told = nil;
    self.asked = self.problem = nil;
}

// Open in Browser: the file a session's row lists, in the app that opens web pages, whether or not it's shown here.
- (void)openOutside:(NSDictionary *)msg {
    NSDictionary *writing = [self prototype:msg[@"id"] of:msg[@"sessionId"]];
    NSString *path = writing[@"path"];
    if (![path isKindOfClass:NSString.class] || ![NSFileManager.defaultManager fileExistsAtPath:path]
        || !OpenInWebBrowser([NSURL fileURLWithPath:path isDirectory:NO])) {
        PanelLog(@"couldn't open a prototype in the web browser");
        NSBeep();
    }
}

// What the line above the prototype says: whether it's loading, why it can't be shown, what it asked for that the
// panel doesn't do, and whether it has the keyboard (and so the pointer); told only when one of those changes.
- (void)tell {
    if (!self.sessionId || !self.writingId) return;
    Browser *browser = self.browser;
    NSString *problem = self.problem ?: browser.problem;
    NSDictionary *state = @{@"loading": @(browser && (browser.loading || !self.appeared) && !problem),
                            @"problem": problem ?: NSNull.null,
                            @"asked": self.asked ?: NSNull.null,
                            @"keyboard": @(browser.hasKeyboard)};
    if ([state isEqual:self.told]) return;
    self.told = state;
    [self.core.page call:@"prototypeState" with:@[self.sessionId, self.writingId, state]];
}

#pragma mark What its Browser tells it

- (void)browserChanged:(Browser *)browser {
    if (browser != self.browser) return;
    // In view once its page has loaded, in the reader's own fade; a page that didn't load stays out of sight, or goes
    // out of it, the reader saying why.
    if (self.appeared && browser.problem) {
        self.appeared = NO;
        browser.view.alphaValue = 0;
    } else if (!self.appeared && !browser.loading && browser.address && !browser.problem) {
        self.appeared = YES;
        if (NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
            browser.view.alphaValue = 1;
        } else {
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
                context.duration = kFadeIn;
                browser.view.animator.alphaValue = 1;
            }];
        }
    }
    [self tell];
}

// A prototype gets no window of its own: the reader says it asked, and Open in Browser is there for it.
- (Browser *)browser:(Browser *)browser opensWindow:(BrowserAsk *)ask {
    if (browser == self.browser) {
        self.asked = AskWord(BrowserAskWindow);
        [self tell];
    }
    return nil;
}

// The prototype closed itself (window.close()): it goes, and the reader says so, until it's chosen again.
- (void)browserClosedItself:(Browser *)browser {
    if (browser != self.browser) return;
    self.browser = nil;
    [self.core.window letGo:browser.view];
    [browser close];
    self.problem = @"This page closed itself.";
    [self tell];
}

// Whatever else a prototype asks (an alert, files, a download, another app) is refused, and the reader says so.
- (void)browser:(Browser *)browser asks:(BrowserAsk *)ask {
    [ask refuse];
    if (browser != self.browser) return;
    self.asked = AskWord(ask.kind);
    [self tell];
}

// A link pressed in a prototype that goes nowhere from the panel (a file outside its folder that isn't a page): the
// reader says so, as nothing else happens.
- (void)browser:(Browser *)browser refusedLink:(NSURL *)address {
    if (browser != self.browser) return;
    self.asked = @"link";
    [self tell];
}

#pragma mark Print mode

+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return @{
        // For each file, as a prototype a session wrote: the folder a Browser would show it from, or why it can't be
        // shown, as the reader would say it.
        @"--print-prototypes": ^int(Core *core, NSArray<NSString *> *arguments) {
            NSMutableArray *out = [NSMutableArray array];
            for (NSString *path in arguments) {
                NSURL *page = nil;
                NSString *problem = nil;
                BrowserSetup *setup = PrototypeSetup(path, &page, &problem);
                [out addObject:@{@"file": path, @"folder": setup.folder.path ?: NSNull.null,
                                 @"page": page.path ?: NSNull.null, @"problem": problem ?: NSNull.null,
                                 @"webParts": @(setup.webParts), @"linksOut": @(setup.linksOut),
                                 @"kept": setup.keptAs ?: NSNull.null}];
            }
            return PrintJSON(out);
        },
    };
}

@end
