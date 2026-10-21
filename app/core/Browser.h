// Browser: web pages that aren't the panel's own, each Browser in a web view of its own in the panel's window: a
// website kept as an app, or a page a session wrote, beside its files. It knows nothing of either. Its owner gives it a
// setup (what it may load, whether what it's signed in to is kept, where a link that goes somewhere else opens, and how
// it introduces itself), places its view, says where to go, and is asked what the Browser can't decide alone.
// It never has a bridge: nothing it shows can send the app a message, and an owner has no way to give it one.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>

@class Browser, BrowserAsk;

// What a Browser may load, what it keeps, and how it introduces itself. Copied as a Browser is made, so changing one
// afterwards changes no Browser.
@interface BrowserSetup : NSObject <NSCopying>
// Pages anywhere on the web, http and https.
+ (instancetype)web;
// One folder's files and nothing else, read from there: its pages can show its other files, but never read what's in
// them, nor anything outside it. Nil for a folder too wide to be one page's: the disk's top, a volume's, or your home
// folder itself.
+ (instancetype)folder:(NSURL *)folder;
// The folder, or nil for the web.
@property (readonly) NSURL *folder;
// A folder's pages may take what they use from the web (scripts, fonts, pictures, a frame of another site's) while
// never going there themselves (YES); or nothing comes from the network at all (NO, the start). Either way, what came
// from the web can't read the folder's files any more than its pages can.
@property (assign) BOOL webParts;
// What it's signed in to, its cookies and whatever sites store, kept between launches under this name, apart from
// every other name's; or nil (the start), keeping nothing: all of it goes with the Browser. Only on macOS 14 and later,
// which keeps each name apart; before that, nothing is kept.
@property (copy) NSString *keptAs;
// A link you press to somewhere else opens in your default browser (YES), or here, if it may load here (NO, the start).
// Somewhere else is outside the folder, or, on the web, outside `sites`. From a folder, that's a site, or a page
// (.html) elsewhere on this Mac, which opens in the app that opens web pages; any other file there goes nowhere. A page
// going somewhere by itself (a sign-in passing from site to site) is never somewhere else, but a new tab a page opens
// (a window that asks for no size) is: it's followed out of sight until it settles, as a link often passes through the
// site's own address on its way, and goes to your default browser if it ends up off the sites. A window that asks for a
// size (a sign-in's, which talks back to the page that opened it) stays, wherever it goes.
@property (assign) BOOL linksOut;
// On the web, the sites it stays on, each a host with its subdomains ("google.com" takes in mail.google.com): with none
// (the start), nowhere on the web is somewhere else.
@property (copy) NSArray<NSString *> *sites;
// Introduces itself to sites as this Mac's Safari, of the version installed (YES, the start), or as WebKit's own
// built-in browser, which names no browser (NO).
@property (assign) BOOL asSafari;
// The panel's glass shows through where a page draws nothing (YES), or pages are on white, as in any browser (NO, the
// start).
@property (assign) BOOL seeThrough;
@end

// Where an address goes from a Browser with this setup (BrowserWhereTo).
typedef NS_ENUM(NSInteger, BrowserGoes) {
    BrowserLoads,           // here
    BrowserRefuses,         // nowhere: it may not load here, and isn't sent anywhere else
    BrowserOpensOutside,    // in your default browser (a pressed link to somewhere else, with linksOut)
    BrowserAsksOwner,       // a link for another app (mailto:, an app's own): its owner is asked (BrowserAskOtherApp)
};

// Where `address` goes, from a page of this setup: as the main page (`page`), or as a frame in one, and pressed or
// not. A plain function, so the print mode can show every case (--print-browsing).
BrowserGoes BrowserWhereTo(BrowserSetup *setup, NSURL *address, BOOL page, BOOL pressed);
// The store what's kept under a name is in: the same one for the same name on every launch, so it can never change
// (a name given another store is signed out of everything).
NSUUID *BrowserStoreFor(NSString *keptAs);
// How a Browser of this setup introduces itself, with Safari's version given; nil for WebKit's own words.
NSString *BrowserIntroduction(BrowserSetup *setup, NSString *safariVersion);

// What a Browser's owner hears, each optional. Whatever it's asked and doesn't answer is refused.
@protocol BrowserOwner <NSObject>
@optional
// Its address, title, whether it can go back or forward, whether it's loading, how far, whether it's secure, or why a
// page didn't load: one or more has changed. Read them on the Browser.
- (void)browserChanged:(Browser *)browser;
// A page wants a window of its own (a link meant for a new one, or a sign-in's window, which talks to the page that
// opened it): a Browser to show it in, made with `ask`'s window and placed where the owner chooses, or nil for none.
// A new tab followed until it settles (linksOut) is asked about once it has, with its page already there.
- (Browser *)browser:(Browser *)browser opensWindow:(BrowserAsk *)ask;
// The page in a window it opened closed it (window.close()): the owner takes that Browser away.
- (void)browserClosedItself:(Browser *)browser;
// What a page asks that only you can answer: an alert, a confirm or a prompt, files to pick, where a download goes,
// the camera or the microphone, or another app to open a link in. Answered once, with one of `ask`'s answers, now or
// later; the page waits meanwhile. An ask that's never answered is refused once it's let go of. (Whozmove doesn't name
// the camera or the microphone to macOS yet, so sites see neither, and nothing asks for them.)
- (void)browser:(Browser *)browser asks:(BrowserAsk *)ask;
// A download has finished: the file it's in, or why it isn't.
- (void)browser:(Browser *)browser downloaded:(NSURL *)file problem:(NSString *)problem;
// A link you pressed that goes nowhere from here (a file outside the folder that isn't a page, say): nothing else
// happens, so the owner may say why.
- (void)browser:(Browser *)browser refusedLink:(NSURL *)address;
@end

typedef NS_ENUM(NSInteger, BrowserAskKind) {
    BrowserAskWindow,       // a window of its own (browser:opensWindow:)
    BrowserAskAlert,        // a message, with OK
    BrowserAskConfirm,      // a question, OK or Cancel
    BrowserAskPrompt,       // a question with a box to type the answer in, `text` in it to start
    BrowserAskFiles,        // files to pick: one, or `multiple`
    BrowserAskDownload,     // where a file goes, `text` the name it suggests
    BrowserAskCamera,       // the camera, the microphone, or both
    BrowserAskMicrophone,
    BrowserAskCameraAndMicrophone,
    BrowserAskOtherApp,     // `address`, a link for another app, to open there
};

// One thing a page asks. Where it shows the asker is the owner's choice; what it says comes from the page, so it's
// only ever shown as the page's words.
@interface BrowserAsk : NSObject
@property (readonly) BrowserAskKind kind;
// Who asks: the asking page's host, or its file's name in the folder.
@property (readonly) NSString *from;
// A window's address, a download's, or the other app's link.
@property (readonly) NSURL *address;
// What an alert, a confirm or a prompt says, as the page wrote it.
@property (readonly) NSString *message;
// A prompt's answer to start with, or the name a download suggests.
@property (readonly) NSString *text;
// Files: whether more than one may be picked.
@property (readonly) BOOL multiple;
// A window: whether a press asked for it (a link, a button), rather than the page by itself.
@property (readonly) BOOL pressed;
// A window: the size the page asks for, or zero for none.
@property (readonly) NSSize size;
// The answers; the first one given counts. allow is OK, yes to the camera or microphone, or opening the other app;
// refuse is Cancel, or no.
- (void)allow;
- (void)refuse;
- (void)answer:(NSString *)text;
- (void)pick:(NSArray<NSURL *> *)files;
- (void)saveTo:(NSURL *)file;
// A window: the Browser it shows in, of the asking Browser's setup and kept with it; made only while it's asked
// (browser:opensWindow:), else nil.
- (Browser *)window;
@end

@interface Browser : NSObject
// A module has one from Core's browserWith:owner:. Its view placed in the panel's window, the pointer and the
// keyboard come to it from there (PanelWindow). Nothing loads until it's told where to go.
- (instancetype)initWithSetup:(BrowserSetup *)setup owner:(id<BrowserOwner>)owner;
@property (readonly, copy) BrowserSetup *setup;
@property (weak) id<BrowserOwner> owner;
// The view it shows in, for its owner to place in the panel's window. Its pages are light or dark as the panel is.
@property (readonly) NSView *view;
// How large pages are drawn: 1 (the start) as they are, less to fit a page made for a wider screen.
@property (assign) double zoom;
// Goes to an address it may load as its page (BrowserLoads); NO for one it may not, and it stays where it is.
- (BOOL)goTo:(NSURL *)address;
- (void)goBack;
- (void)goForward;
- (void)reload;
- (void)stop;
// What it shows, as told to its owner (browserChanged:).
@property (readonly) NSURL *address;
@property (readonly) NSString *title;
@property (readonly) BOOL canGoBack;
@property (readonly) BOOL canGoForward;
@property (readonly) BOOL loading;
@property (readonly) double progress;          // 0 to 1
// Over https with nothing on the page that isn't, or a file in its folder.
@property (readonly) BOOL secure;
// Why the last page didn't load, in plain words, or nil.
@property (readonly) NSString *problem;
// Whether it has the keyboard: a click into it takes it, and a click in the list, the panel folding, or closing it
// gives it back.
@property (readonly) BOOL hasKeyboard;
// Done with it: it stops, gives the keyboard back if it has it, and its view goes. What's kept under its name stays.
- (void)close;
// Everything kept under a name, gone (an app taken away); `then` runs once it has, with nil, or with why it couldn't
// (a Browser still showing what's kept there).
+ (void)forget:(NSString *)keptAs then:(void (^)(NSString *problem))then;
// The Browsers whose views are in a window, for the panel's window to pass the pointer into and give the keyboard to.
+ (NSArray<Browser *> *)inWindow:(NSWindow *)window;
@end
