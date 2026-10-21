// Browser: web pages that aren't the panel's own, each in a web view of its own (Browser.h says what it offers).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// Its web view has no script message handler, and nothing here gives one out: its configuration is made here and never
// handed on, and its view goes out as a plain NSView, so a page in it has nothing to send the app a message through.
//
// A folder's pages are plain file: pages, with WebKit's own rules for them, which nothing here loosens: a page may show
// its folder's files but never read what's in them (a fetch of another file, or a frame of one, is another origin's),
// and can read nothing outside the folder it was given. Letting a folder's pages take parts from the web (webParts) is
// safe only because of those rules, so the two file preferences WebKit has (one file reading another, and a file
// reading anything) must never be turned on.
#import "Browser.h"
#import "BrowserFacts.h"
#import "Files.h"
#import "Links.h"
#import "Log.h"
#import <CommonCrypto/CommonDigest.h>
#import <WebKit/WebKit.h>

#pragma mark Where an address goes

// Where a file's address really is: its path with links followed and . and .. taken out, as far as it's there (a page
// can link to a file that isn't, yet). Nil when that can't be said: a .. past what's there.
static NSString *RealFilePath(NSURL *address) {
    NSString *path = address.path;
    if (!path.isAbsolutePath) return nil;
    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    while (path.length > 1) {
        char *real = realpath(path.fileSystemRepresentation, NULL);
        if (real) {
            NSString *found = [NSFileManager.defaultManager stringWithFileSystemRepresentation:real
                                                                                         length:strlen(real)];
            free(real);
            for (NSString *part in missing.reverseObjectEnumerator) {
                if ([part isEqual:@".."]) return nil;
                if (![part isEqual:@"."]) found = [found stringByAppendingPathComponent:part];
            }
            return found;
        }
        [missing addObject:path.lastPathComponent];
        path = path.stringByDeletingLastPathComponent;
    }
    return nil;
}

static BOOL InFolder(NSString *path, NSURL *folder) {
    NSString *top = folder.path;
    return [path isEqualToString:top] || [path hasPrefix:[top stringByAppendingString:@"/"]];
}

// A file a web browser shows as a page, by its name.
static BOOL IsWebPage(NSString *path) {
    NSString *kind = path.pathExtension.lowercaseString;
    return [kind isEqualToString:@"html"] || [kind isEqualToString:@"htm"];
}

// A host on one of the sites, or a subdomain of one; any trailing dot and case aside, as a host can be written either
// way.
static BOOL OnSites(NSString *host, NSArray<NSString *> *sites) {
    NSCharacterSet *dots = [NSCharacterSet characterSetWithCharactersInString:@"."];
    host = [host.lowercaseString stringByTrimmingCharactersInSet:dots];
    for (NSString *each in sites) {
        NSString *site = [each.lowercaseString stringByTrimmingCharactersInSet:dots];
        if (site.length && ([host isEqualToString:site] || [host hasSuffix:[@"." stringByAppendingString:site]]))
            return YES;
    }
    return NO;
}

// A web address off the setup's sites, for one that has some.
static BOOL OffSites(NSURL *address, BrowserSetup *setup) {
    NSString *scheme = address.scheme.lowercaseString;
    BOOL web = [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"];
    return web && address.host.length && setup.sites.count && !OnSites(address.host, setup.sites);
}

BrowserGoes BrowserWhereTo(BrowserSetup *setup, NSURL *address, BOOL page, BOOL pressed) {
    NSString *scheme = address.scheme.lowercaseString;
    if (!scheme.length) return BrowserRefuses;
    BOOL folder = setup.folder != nil;
    // What a page makes for itself goes where it is: its own script (a javascript: link, run on the page), an empty
    // page or a frame of its own words (about:blank, about:srcdoc), a frame of words carried in its address (data:,
    // which WebKit never shows as a page), and a file it put together (blob:, a picture or a document it made).
    if ([scheme isEqualToString:@"javascript"] || [scheme isEqualToString:@"blob"]) return BrowserLoads;
    if ([scheme isEqualToString:@"about"]) {
        NSString *which = address.resourceSpecifier.lowercaseString;
        return [which isEqualToString:@"blank"] || [which isEqualToString:@"srcdoc"] ? BrowserLoads : BrowserRefuses;
    }
    if ([scheme isEqualToString:@"data"]) return page ? BrowserRefuses : BrowserLoads;
    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) {
        if (!address.host.length) return BrowserRefuses;
        BOOL elsewhere = folder || OffSites(address, setup);
        if (page && pressed && elsewhere && setup.linksOut) return BrowserOpensOutside;
        if (!folder) return BrowserLoads;
        return !page && setup.webParts ? BrowserLoads : BrowserRefuses;
    }
    if ([scheme isEqualToString:@"file"]) {
        if (!folder) return BrowserRefuses;
        NSString *real = RealFilePath(address);
        if (!real) return BrowserRefuses;
        if (InFolder(real, setup.folder)) return BrowserLoads;
        // A page elsewhere on this Mac that you press a link to is somewhere else, as a site is: it opens in your web
        // browser, where it's what it would be had you opened it yourself. Any other file there goes nowhere, as a web
        // browser may hand it to whichever app opens its kind.
        return page && pressed && setup.linksOut && IsWebPage(real) ? BrowserOpensOutside : BrowserRefuses;
    }
    // Anything else is another app's (an email to write, a call, a meeting app's own link): only a link you press, and
    // only once its owner says yes.
    return page && pressed ? BrowserAsksOwner : BrowserRefuses;
}

// A name's store is found from the name alone: the first 16 bytes of its SHA-256, after Whozmove's own words, marked as
// a UUID an app made by a rule of its own (version 8).
NSUUID *BrowserStoreFor(NSString *keptAs) {
    if (!keptAs.length) return nil;
    NSData *name = [[@"Whozmove browser: " stringByAppendingString:keptAs] dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(name.bytes, (CC_LONG)name.length, hash);
    hash[6] = (hash[6] & 0x0F) | 0x80;
    hash[8] = (hash[8] & 0x3F) | 0x80;
    return [[NSUUID alloc] initWithUUIDBytes:hash];
}

NSString *BrowserIntroduction(BrowserSetup *setup, NSString *safariVersion) {
    if (!setup.asSafari) return nil;
    return [kSafariIntroduction stringByReplacingOccurrencesOfString:@"%@"
                                                          withString:safariVersion.length ? safariVersion
                                                                                          : kSafariVersionMissing];
}

// The version of the Safari installed, read once a launch: Safari runs the same WebKit as every web view on the Mac, so
// its version is what this one is too.
static NSString *SafariVersion(void) {
    static NSString *version;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *safari = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:kSafariBundleId];
        version = AsText(safari ? [NSBundle bundleWithURL:safari].infoDictionary[@"CFBundleShortVersionString"] : nil);
    });
    return version;
}

#pragma mark The setup

@interface BrowserSetup ()
@property (readwrite) NSURL *folder;
@end

@implementation BrowserSetup

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _asSafari = YES;
    _sites = @[];
    return self;
}

+ (instancetype)web {
    return [self new];
}

// A folder that is your home folder, holds it, or is a disk's top would let a page show anything there: one page's
// folder is never as wide as that.
+ (instancetype)folder:(NSURL *)folder {
    if (!folder.isFileURL) return nil;
    NSString *path = RealPath(folder.path.stringByStandardizingPath);
    BOOL isFolder = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isFolder] || !isFolder) return nil;
    NSString *home = RealPath(Home());
    BOOL holdsHome = [home hasPrefix:[path stringByAppendingString:@"/"]];
    if ([path isEqualToString:@"/"] || [path isEqualToString:home] || holdsHome) return nil;
    NSNumber *volume = nil;
    [[NSURL fileURLWithPath:path isDirectory:YES] getResourceValue:&volume forKey:NSURLIsVolumeKey error:nil];
    if (volume.boolValue) return nil;
    BrowserSetup *setup = [self new];
    setup.folder = [NSURL fileURLWithPath:path isDirectory:YES];
    return setup;
}

- (id)copyWithZone:(NSZone *)zone {
    BrowserSetup *copy = [BrowserSetup new];
    copy.folder = self.folder;
    copy.webParts = self.webParts;
    copy.keptAs = self.keptAs;
    copy.linksOut = self.linksOut;
    copy.sites = self.sites;
    copy.asSafari = self.asSafari;
    copy.seeThrough = self.seeThrough;
    return copy;
}

@end

#pragma mark What a page asks

typedef void (^Answered)(BOOL yes, NSString *text, NSArray<NSURL *> *files, NSURL *file);

@interface Browser ()
- (instancetype)initWithSetup:(BrowserSetup *)setup owner:(id<BrowserOwner>)owner
                configuration:(WKWebViewConfiguration *)configuration;
@end

@interface BrowserAsk ()
@property (readwrite) BrowserAskKind kind;
@property (readwrite, copy) NSString *from;
@property (readwrite, copy) NSURL *address;
@property (readwrite, copy) NSString *message;
@property (readwrite, copy) NSString *text;
@property (readwrite) BOOL multiple;
@property (readwrite) BOOL pressed;
@property (readwrite) NSSize size;
@property (copy) Answered done;
// A window's: what WebKit gives to make it with, the asking Browser's setup and owner, and the Browser made.
@property (strong) WKWebViewConfiguration *configuration;
@property (copy) BrowserSetup *setup;
@property (weak) id<BrowserOwner> owner;
@property (strong) Browser *made;
@end

@implementation BrowserAsk

- (instancetype)initWithKind:(BrowserAskKind)kind from:(NSString *)from done:(Answered)done {
    if (!(self = [super init])) return nil;
    _kind = kind;
    _from = [from copy] ?: @"";
    _done = [done copy];
    return self;
}

// The first answer counts; WebKit waits for exactly one, on the main thread.
- (void)finish:(BOOL)yes text:(NSString *)text files:(NSArray<NSURL *> *)files file:(NSURL *)file {
    Answered done = self.done;
    self.done = nil;
    if (!done) return;
    if (NSThread.isMainThread) done(yes, text, files, file);
    else dispatch_async(dispatch_get_main_queue(), ^{ done(yes, text, files, file); });
}

- (void)allow { [self finish:YES text:nil files:nil file:nil]; }
- (void)refuse { [self finish:NO text:nil files:nil file:nil]; }
- (void)answer:(NSString *)text { [self finish:YES text:text ?: @"" files:nil file:nil]; }
- (void)pick:(NSArray<NSURL *> *)files { [self finish:files.count > 0 text:nil files:files file:nil]; }
- (void)saveTo:(NSURL *)file { [self finish:file != nil text:nil files:nil file:file]; }

- (Browser *)window {
    if (self.kind != BrowserAskWindow) return nil;
    if (self.made) return self.made;  // a new tab, already followed to where it settled
    if (!self.configuration) return nil;
    if (!self.made)
        self.made = [[Browser alloc] initWithSetup:self.setup owner:self.owner configuration:self.configuration];
    return self.made;
}

// An ask let go of without an answer is refused, so the page asking never waits for ever.
- (void)dealloc {
    [self refuse];
}

@end

// Who asks: the asking page's host, or its file's name.
static NSString *AskerOf(WKFrameInfo *frame) {
    if (frame.securityOrigin.host.length) return frame.securityOrigin.host;
    NSURL *address = frame.request.URL;
    return address.isFileURL ? address.lastPathComponent : address.host;
}

// Who asks for a download: the frame it came from, which macOS names from 15.2 on, else the page its web view shows.
static NSString *DownloadAskerOf(WKDownload *download) {
    if (@available(macOS 15.2, *)) return AskerOf(download.originatingFrame);
    NSURL *address = download.webView.URL;
    return address.isFileURL ? address.lastPathComponent : address.host;
}

// Why a page didn't load, in plain words, or nil when it only stopped: you stopped it, it became a download, or it was
// refused here.
static NSString *ProblemOf(NSError *error) {
    if ([error.domain isEqualToString:@"WebKitErrorDomain"] && (error.code == 101 || error.code == 102)) return nil;
    if (![error.domain isEqualToString:NSURLErrorDomain]) return error.localizedDescription;
    NSURL *failing = error.userInfo[NSURLErrorFailingURLErrorKey];
    NSString *host = ([failing isKindOfClass:NSURL.class] ? failing.host : nil) ?: @"the site";
    switch (error.code) {
        case NSURLErrorCancelled: return nil;
        case NSURLErrorNotConnectedToInternet:
        case NSURLErrorNetworkConnectionLost: return @"You're not connected to the internet.";
        case NSURLErrorCannotFindHost:
        case NSURLErrorDNSLookupFailed: return [NSString stringWithFormat:@"Couldn't find %@.", host];
        case NSURLErrorCannotConnectToHost: return [NSString stringWithFormat:@"Couldn't connect to %@.", host];
        case NSURLErrorTimedOut: return [NSString stringWithFormat:@"%@ took too long to answer.", host];
        case NSURLErrorSecureConnectionFailed:
        case NSURLErrorServerCertificateHasBadDate:
        case NSURLErrorServerCertificateUntrusted:
        case NSURLErrorServerCertificateHasUnknownRoot:
        case NSURLErrorServerCertificateNotYetValid:
            return [NSString stringWithFormat:@"%@'s secure connection couldn't be checked, so it wasn't opened.",
                                              host];
        case NSURLErrorFileDoesNotExist: return @"That file isn't there.";
        case NSURLErrorNoPermissionsToReadFile: return @"That file can't be read from here.";
        default: return error.localizedDescription;
    }
}

#pragma mark The view

// Whozmove has no Edit menu, where an app's ⌘C and the rest come from: in a page, they're the page's own.
static SEL EditFor(NSEvent *event) {
    NSEventModifierFlags mods = event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagShift |
                                                       NSEventModifierFlagOption | NSEventModifierFlagControl);
    NSString *key = event.charactersIgnoringModifiers.lowercaseString;
    if (mods == (NSEventModifierFlagCommand | NSEventModifierFlagShift))
        return [key isEqualToString:@"z"] ? @selector(redo:) : NULL;
    if (mods != NSEventModifierFlagCommand) return NULL;
    NSDictionary<NSString *, NSString *> *edits = @{@"c": @"copy:", @"x": @"cut:", @"v": @"paste:",
                                                    @"a": @"selectAll:", @"z": @"undo:"};
    return edits[key] ? NSSelectorFromString(edits[key]) : NULL;
}

@interface BrowserView : WKWebView
@end

@implementation BrowserView

// The panel's window is seldom the one you type in: a click goes straight to the page, as in the browser you're using.
- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    return YES;
}

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    NSResponder *first = self.window.firstResponder;
    BOOL typing = self.window.isKeyWindow && [first isKindOfClass:NSView.class]
                  && [(NSView *)first isDescendantOf:self];
    SEL edit = typing && event.type == NSEventTypeKeyDown ? EditFor(event) : NULL;
    if (edit && [self tryToPerform:edit with:nil]) return YES;
    return [super performKeyEquivalent:event];
}

@end

#pragma mark The Browser

// Every Browser there is, for the window each is in to find (inWindow:).
static NSHashTable<Browser *> *Browsers(void) {
    static NSHashTable *all;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ all = [NSHashTable weakObjectsHashTable]; });
    return all;
}

// New tabs followed out of sight until they settle (createWebViewWithConfiguration:), kept here meanwhile, as nothing
// else holds them.
static NSMutableSet<Browser *> *Unshown(void) {
    static NSMutableSet *unshown;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ unshown = [NSMutableSet set]; });
    return unshown;
}

// What its owner is told about as it changes (browserChanged:).
static NSArray<NSString *> *Watched(void) {
    return @[@"URL", @"title", @"canGoBack", @"canGoForward", @"loading", @"estimatedProgress",
             @"hasOnlySecureContent"];
}
static void *const kWatching = (void *)&kWatching;

// The one rule list a folder's pages have without webParts: nothing from the network, whatever asks for it. Made once
// a launch, and handed to all who wait for it; nil if WebKit can't make it, and then nothing loads.
// (WebKit's filters take no "or", so each kind of address has its own.)
static NSString *const kNoNetwork = @"[{\"trigger\": {\"url-filter\": \"^https?://\"}, "
                                    @"\"action\": {\"type\": \"block\"}}, "
                                    @"{\"trigger\": {\"url-filter\": \"^wss?://\"}, "
                                    @"\"action\": {\"type\": \"block\"}}]";

static void WithNoNetwork(void (^then)(WKContentRuleList *list)) {
    static WKContentRuleList *made;
    static BOOL tried;
    static NSMutableArray *waiting;
    if (tried && !waiting) return then(made);
    if (!waiting) waiting = [NSMutableArray array];
    [waiting addObject:[then copy]];
    if (waiting.count > 1) return;
    [WKContentRuleListStore.defaultStore compileContentRuleListForIdentifier:@"whozmove-no-network"
                                                       encodedContentRuleList:kNoNetwork
                                                            completionHandler:^(WKContentRuleList *list,
                                                                                NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!list) LogProblem([NSString stringWithFormat:@"couldn't keep a folder's pages off the network: %@",
                                                             error.localizedDescription]);
            made = list;
            tried = YES;
            NSArray *all = waiting;
            waiting = nil;
            for (void (^each)(WKContentRuleList *) in all) each(made);
        });
    }];
}

// What's kept under a name, in a store of its own (macOS 14 on); nothing kept otherwise.
static WKWebsiteDataStore *StoreFor(NSString *keptAs) {
    if (keptAs.length) {
        if (@available(macOS 14.0, *)) return [WKWebsiteDataStore dataStoreForIdentifier:BrowserStoreFor(keptAs)];
    }
    return WKWebsiteDataStore.nonPersistentDataStore;
}

@interface Browser () <WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate>
@property (readwrite, copy) BrowserSetup *setup;
@property (strong) BrowserView *web;
@property (assign) BOOL closed;
@property (assign) BOOL watching;
// A folder's pages wait for the rule that keeps them off the network: where it goes once that's in, and whether it is.
@property (strong) NSURL *waiting;
@property (assign) BOOL offNetwork;
@property (assign) BOOL changeComing;
@property (readwrite, copy) NSString *problem;
@property (assign) NSTimeInterval endedAt;
// Each download on its way, and where it's going.
@property (strong) NSMapTable<WKDownload *, NSURL *> *downloads;
// A new tab followed out of sight until it settles: what its opener's owner will be asked with, its opener, and which
// wait for it to settle is the live one (each page it starts on begins another).
@property (strong) BrowserAsk *unshown;
@property (weak) Browser *opener;
@property (assign) NSUInteger settling;
@end

@implementation Browser

- (instancetype)initWithSetup:(BrowserSetup *)setup owner:(id<BrowserOwner>)owner {
    return [self initWithSetup:setup owner:owner configuration:nil];
}

// A window a page opens is made with what WebKit gives for it, so it shares its opener's store and rules, and the two
// can talk, as a sign-in's window and the page that opened it do.
- (instancetype)initWithSetup:(BrowserSetup *)setup owner:(id<BrowserOwner>)owner
                configuration:(WKWebViewConfiguration *)given {
    if (!(self = [super init])) return nil;
    self.setup = setup ?: [BrowserSetup web];
    self.owner = owner;
    self.downloads = [NSMapTable strongToStrongObjectsMapTable];
    WKWebViewConfiguration *config = given;
    if (!config) {
        config = [WKWebViewConfiguration new];
        config.userContentController = [WKUserContentController new];
        config.websiteDataStore = StoreFor(self.setup.keptAs);
        // A window only from a press; sounds only once you've pressed play, as Safari has it; and Safari's warning
        // about sites known to be fraudulent.
        config.preferences.javaScriptCanOpenWindowsAutomatically = NO;
        config.preferences.fraudulentWebsiteWarningEnabled = YES;
        config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeAudio;
    }
    self.offNetwork = given != nil;  // its opener's rules came with it
    self.web = [[BrowserView alloc] initWithFrame:NSMakeRect(0, 0, 400, 400) configuration:config];
    self.web.navigationDelegate = self;
    self.web.UIDelegate = self;
    self.web.allowsBackForwardNavigationGestures = YES;
    NSString *introduction = BrowserIntroduction(self.setup, SafariVersion());
    if (introduction) self.web.customUserAgent = introduction;
    if (self.setup.seeThrough) [self.web setValue:@NO forKey:@"drawsBackground"];
    for (NSString *key in Watched()) [self.web addObserver:self forKeyPath:key options:0 context:kWatching];
    self.watching = YES;
    [Browsers() addObject:self];
    return self;
}

- (void)dealloc {
    [self stopWatching];
}

- (void)stopWatching {
    if (!self.watching) return;
    self.watching = NO;
    for (NSString *key in Watched()) [self.web removeObserver:self forKeyPath:key context:kWatching];
    self.web.navigationDelegate = nil;
    self.web.UIDelegate = nil;
}

- (NSView *)view {
    return self.web;
}

+ (NSArray<Browser *> *)inWindow:(NSWindow *)window {
    NSMutableArray *found = [NSMutableArray array];
    for (Browser *browser in Browsers())
        if (!browser.closed && window && browser.web.window == window) [found addObject:browser];
    return found;
}

#pragma mark Going places

- (BOOL)goTo:(NSURL *)address {
    if (self.closed || !address || BrowserWhereTo(self.setup, address, YES, NO) != BrowserLoads) return NO;
    self.problem = nil;
    if (self.setup.folder && !self.setup.webParts && !self.offNetwork) {
        BOOL asked = self.waiting != nil;
        self.waiting = address;
        __weak Browser *weakSelf = self;
        if (!asked) WithNoNetwork(^(WKContentRuleList *list) { [weakSelf keepOffNetwork:list]; });
        return YES;
    }
    [self load:address];
    return YES;
}

- (void)keepOffNetwork:(WKContentRuleList *)list {
    NSURL *address = self.waiting;
    self.waiting = nil;
    if (self.closed) return;
    if (!list) {
        self.problem = @"This page can't be shown, as it couldn't be kept off the network.";
        [self changed];
        return;
    }
    [self.web.configuration.userContentController addContentRuleList:list];
    self.offNetwork = YES;
    if (address) [self load:address];
}

- (void)load:(NSURL *)address {
    if (address.isFileURL) [self.web loadFileURL:address allowingReadAccessToURL:self.setup.folder];
    else [self.web loadRequest:[NSURLRequest requestWithURL:address]];
}

- (void)goBack { [self.web goBack]; }
- (void)goForward { [self.web goForward]; }
- (void)reload { [self.web reload]; }
- (void)stop { [self.web stopLoading]; }

- (double)zoom {
    return self.web.pageZoom;
}

- (void)setZoom:(double)zoom {
    self.web.pageZoom = zoom > 0 ? zoom : 1;
}

- (void)close {
    if (self.closed) return;
    self.closed = YES;
    self.waiting = nil;
    [self stopWatching];
    // What it shows goes now, sound and all, rather than whenever its owner lets go of it; the panel's window sees
    // its view go and gives the keyboard back.
    [self.web stopLoading];
    [self.web loadHTMLString:@"" baseURL:nil];
    [self.web removeFromSuperview];
    [Browsers() removeObject:self];
}

+ (void)forget:(NSString *)keptAs then:(void (^)(NSString *problem))then {
    void (^done)(NSString *) = ^(NSString *problem) { if (then) then(problem); };
    NSUUID *store = BrowserStoreFor(keptAs);
    if (@available(macOS 14.0, *)) {
        if (store) {
            [WKWebsiteDataStore removeDataStoreForIdentifier:store completionHandler:^(NSError *error) {
                NSString *problem = error ? error.localizedDescription : nil;
                if (problem) LogProblem([@"couldn't forget what a browser kept: " stringByAppendingString:problem]);
                dispatch_async(dispatch_get_main_queue(), ^{ done(problem); });
            }];
            return;
        }
    }
    done(nil);
}

#pragma mark What it shows

- (NSURL *)address { return self.web.URL; }
- (NSString *)title { return self.web.title; }
- (BOOL)canGoBack { return self.web.canGoBack; }
- (BOOL)canGoForward { return self.web.canGoForward; }
- (BOOL)loading { return self.web.loading; }
- (double)progress { return self.web.estimatedProgress; }

- (BOOL)secure {
    NSURL *address = self.web.URL;
    if (address.isFileURL) return YES;
    return [address.scheme.lowercaseString isEqualToString:@"https"] && self.web.hasOnlySecureContent;
}

- (BOOL)hasKeyboard {
    NSResponder *first = self.web.window.firstResponder;
    return self.web.window.isKeyWindow && [first isKindOfClass:NSView.class]
           && [(NSView *)first isDescendantOf:self.web];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change
                       context:(void *)context {
    if (context != kWatching) return [super observeValueForKeyPath:keyPath ofObject:object change:change
                                                           context:context];
    [self changed];
}

// Changes come several at once (a page's address, title and loading, as it starts): its owner hears once for them all.
- (void)changed {
    if (self.changeComing) return;
    self.changeComing = YES;
    __weak Browser *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        Browser *browser = weakSelf;
        if (!browser) return;
        browser.changeComing = NO;
        if (!browser.closed && [browser.owner respondsToSelector:@selector(browserChanged:)])
            [browser.owner browserChanged:browser];
    });
}

#pragma mark Asking its owner

- (void)ask:(BrowserAsk *)ask {
    if (!self.closed && [self.owner respondsToSelector:@selector(browser:asks:)]) [self.owner browser:self asks:ask];
}

// A link pressed that goes nowhere: nothing else happens, so its owner hears of it, to say so.
- (void)refusedLink:(NSURL *)address {
    if (!self.closed && [self.owner respondsToSelector:@selector(browser:refusedLink:)])
        [self.owner browser:self refusedLink:address];
}

- (void)askToOpenElsewhere:(NSURL *)address from:(WKFrameInfo *)frame {
    BrowserAsk *ask = [[BrowserAsk alloc] initWithKind:BrowserAskOtherApp from:AskerOf(frame)
                                                  done:^(BOOL yes, NSString *text, NSArray *files, NSURL *file) {
        if (yes) [NSWorkspace.sharedWorkspace openURL:address];
    }];
    ask.address = address;
    ask.pressed = YES;
    [self ask:ask];
}

// Somewhere else: a site in your default browser, and a page on this Mac in the app that opens web pages, never in
// whichever app its kind of file opens in (an editor, often, for .html).
static void OpenOutside(NSURL *address) {
    if (address.isFileURL) OpenInWebBrowser(address);
    else [NSWorkspace.sharedWorkspace openURL:address];
}

#pragma mark WebKit: going places

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action
    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *address = action.request.URL;
    // No frame to go to is a window of its own, asked for next (createWebViewWithConfiguration:), here as a page.
    BOOL page = !action.targetFrame || action.targetFrame.isMainFrame;
    BOOL pressed = action.navigationType == WKNavigationTypeLinkActivated;
    // A new tab not shown yet that's going off its sites, through a link or forwarded there, goes to your default
    // browser instead, and is never shown.
    if (self.unshown && page && OffSites(address, self.setup)) {
        [NSWorkspace.sharedWorkspace openURL:address];
        decisionHandler(WKNavigationActionPolicyCancel);
        [self dropUnshown];
        return;
    }
    switch (BrowserWhereTo(self.setup, address, page, pressed)) {
        case BrowserLoads:
            decisionHandler(action.shouldPerformDownload ? WKNavigationActionPolicyDownload
                                                         : WKNavigationActionPolicyAllow);
            return;
        case BrowserOpensOutside:
            OpenOutside(address);
            break;
        case BrowserAsksOwner:
            [self askToOpenElsewhere:address from:action.sourceFrame];
            break;
        case BrowserRefuses:
            PanelLog(@"kept a browser from going to a %@: address", address.scheme ?: @"?");
            if (pressed) [self refusedLink:address];
            break;
    }
    decisionHandler(WKNavigationActionPolicyCancel);
}

// What a page can't show as a page, it hands over as a download; a frame doesn't.
- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)response
    decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    if (response.canShowMIMEType) return decisionHandler(WKNavigationResponsePolicyAllow);
    decisionHandler(response.isForMainFrame ? WKNavigationResponsePolicyDownload : WKNavigationResponsePolicyCancel);
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    self.settling++;
    self.problem = nil;
    [self changed];
}

// A new tab has settled once its page has loaded and stayed a moment (a page that forwards you on does so as it
// loads), or a while after its page came in, however long the rest takes.
- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
    if (self.unshown) [self showAfter:2];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    if (self.unshown) [self showAfter:0.4];
}

- (void)showAfter:(NSTimeInterval)delay {
    NSUInteger settling = self.settling;
    __weak Browser *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (weakSelf.settling == settling) [weakSelf showUnshown];
    });
}

// Settled on its sites: its opener's owner is asked to show it, as for any window, and it goes if the owner doesn't.
- (void)showUnshown {
    BrowserAsk *ask = self.unshown;
    if (!ask) return;
    self.unshown = nil;
    Browser *opener = self.opener, *shown = nil;
    ask.made = self;
    if (opener && !opener.closed && [self.owner respondsToSelector:@selector(browser:opensWindow:)])
        shown = [self.owner browser:opener opensWindow:ask];
    ask.made = nil;
    if (shown != self) [self close];
    [self letGoUnshown];
}

- (void)dropUnshown {
    self.unshown = nil;
    [self close];
    [self letGoUnshown];
}

// Not straight away: WebKit may be in the middle of telling it something.
- (void)letGoUnshown {
    Browser *browser = self;
    dispatch_async(dispatch_get_main_queue(), ^{ [Unshown() removeObject:browser]; });
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation
       withError:(NSError *)error {
    [self failed:error];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self failed:error];
}

- (void)failed:(NSError *)error {
    NSString *problem = ProblemOf(error);
    if (!problem) return;
    self.problem = problem;
    [self changed];
    if (self.unshown) [self showUnshown];  // it shows why
}

// Its page's process ended (WebKit let it go to free memory, say): the page loads again, unless that keeps happening.
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
    BOOL again = now - self.endedAt < 10;
    self.endedAt = now;
    PanelLog(@"a browser's page stopped%@", again ? @" again, so it stays stopped" : @"; loading it again");
    if (!again) {
        [self.web reload];
        return;
    }
    self.problem = @"This page stopped working.";
    [self changed];
}

#pragma mark WebKit: downloads

- (void)webView:(WKWebView *)webView navigationAction:(WKNavigationAction *)action
    didBecomeDownload:(WKDownload *)download {
    download.delegate = self;
}

- (void)webView:(WKWebView *)webView navigationResponse:(WKNavigationResponse *)response
    didBecomeDownload:(WKDownload *)download {
    download.delegate = self;
}

- (void)download:(WKDownload *)download decideDestinationUsingResponse:(NSURLResponse *)response
    suggestedFilename:(NSString *)suggestedFilename completionHandler:(void (^)(NSURL *))completionHandler {
    __weak Browser *weakSelf = self;
    BrowserAsk *ask = [[BrowserAsk alloc] initWithKind:BrowserAskDownload from:DownloadAskerOf(download)
                                                  done:^(BOOL yes, NSString *text, NSArray *files, NSURL *file) {
        if (yes && file) [weakSelf.downloads setObject:file forKey:download];
        completionHandler(yes ? file : nil);
    }];
    ask.address = download.originalRequest.URL;
    ask.text = suggestedFilename;
    [self ask:ask];
}

- (void)downloadDidFinish:(WKDownload *)download {
    [self download:download endedWith:nil];
}

- (void)download:(WKDownload *)download didFailWithError:(NSError *)error resumeData:(NSData *)resumeData {
    [self download:download endedWith:ProblemOf(error) ?: @"It was stopped."];
}

// Only a download that had somewhere to go is told of: one refused never started.
- (void)download:(WKDownload *)download endedWith:(NSString *)problem {
    NSURL *file = [self.downloads objectForKey:download];
    [self.downloads removeObjectForKey:download];
    if (file && [self.owner respondsToSelector:@selector(browser:downloaded:problem:)])
        [self.owner browser:self downloaded:file problem:problem];
}

#pragma mark WebKit: windows and questions

- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
    forNavigationAction:(WKNavigationAction *)action windowFeatures:(WKWindowFeatures *)features {
    // Pages may open windows only from a press (javaScriptCanOpenWindowsAutomatically), so this one was pressed for,
    // unless it's a form sent to a window of its own. On the web, one that asks for a size is a sign-in's (another
    // site's, which talks back to the page that opened it), so wherever it goes, it stays, as a page going somewhere
    // by itself does.
    NSURL *address = action.request.URL;
    BOOL sized = features.width || features.height;
    BOOL pressed = action.navigationType != WKNavigationTypeFormSubmitted &&
                   action.navigationType != WKNavigationTypeFormResubmitted;
    if (address.absoluteString.length) {  // window.open() with no address starts empty
        BrowserGoes goes = BrowserWhereTo(self.setup, address, YES, pressed && !(sized && !self.setup.folder));
        if (goes == BrowserOpensOutside) OpenOutside(address);
        if (goes == BrowserAsksOwner) [self askToOpenElsewhere:address from:action.sourceFrame];
        if (goes == BrowserRefuses && pressed) [self refusedLink:address];
        if (goes != BrowserLoads) return nil;
    }
    if (self.closed) return nil;
    BrowserAsk *ask = [[BrowserAsk alloc] initWithKind:BrowserAskWindow from:AskerOf(action.sourceFrame) done:nil];
    ask.address = address;
    ask.pressed = pressed;
    ask.size = NSMakeSize(features.width.doubleValue, features.height.doubleValue);
    ask.setup = self.setup;
    ask.owner = self.owner;
    // A new tab (a window that asks for no size) from a site that sends other sites out is followed out of sight until
    // it settles: a link often passes through the site's own address on its way somewhere else (a mail's links, through
    // the mail's site), so only where it ends up says whether it's the site's. A window that asks for a size (a
    // sign-in's) shows at once.
    if (!sized && self.setup.linksOut && self.setup.sites.count) {
        Browser *unseen = [[Browser alloc] initWithSetup:self.setup owner:self.owner configuration:configuration];
        unseen.opener = self;
        unseen.unshown = ask;
        [Unshown() addObject:unseen];
        // One that never settles on a page (a download, say) isn't kept for ever.
        __weak Browser *weakUnseen = unseen;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weakUnseen.unshown) [weakUnseen dropUnshown];
        });
        return unseen.web;
    }
    if (![self.owner respondsToSelector:@selector(browser:opensWindow:)]) return nil;
    ask.configuration = configuration;
    Browser *window = [self.owner browser:self opensWindow:ask];
    Browser *made = ask.made;
    ask.configuration = nil;
    ask.made = nil;
    // WebKit takes only a view made with the configuration it gave.
    return window && window == made ? window.web : nil;
}

- (void)webViewDidClose:(WKWebView *)webView {
    if (!self.closed && [self.owner respondsToSelector:@selector(browserClosedItself:)])
        [self.owner browserClosedItself:self];
}

- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message
    initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler {
    BrowserAsk *ask = [[BrowserAsk alloc] initWithKind:BrowserAskAlert from:AskerOf(frame)
                                                  done:^(BOOL yes, NSString *text, NSArray *files, NSURL *file) {
        completionHandler();
    }];
    ask.message = message;
    [self ask:ask];
}

- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message
    initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL))completionHandler {
    BrowserAsk *ask = [[BrowserAsk alloc] initWithKind:BrowserAskConfirm from:AskerOf(frame)
                                                  done:^(BOOL yes, NSString *text, NSArray *files, NSURL *file) {
        completionHandler(yes);
    }];
    ask.message = message;
    [self ask:ask];
}

- (void)webView:(WKWebView *)webView runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt
    defaultText:(NSString *)defaultText initiatedByFrame:(WKFrameInfo *)frame
    completionHandler:(void (^)(NSString *))completionHandler {
    BrowserAsk *ask = [[BrowserAsk alloc] initWithKind:BrowserAskPrompt from:AskerOf(frame)
                                                  done:^(BOOL yes, NSString *text, NSArray *files, NSURL *file) {
        completionHandler(yes ? text ?: defaultText ?: @"" : nil);
    }];
    ask.message = prompt;
    ask.text = defaultText;
    [self ask:ask];
}

- (void)webView:(WKWebView *)webView runOpenPanelWithParameters:(WKOpenPanelParameters *)parameters
    initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(NSArray<NSURL *> *))completionHandler {
    BrowserAsk *ask = [[BrowserAsk alloc] initWithKind:BrowserAskFiles from:AskerOf(frame)
                                                  done:^(BOOL yes, NSString *text, NSArray *files, NSURL *file) {
        completionHandler(yes ? files : nil);
    }];
    ask.multiple = parameters.allowsMultipleSelection;
    [self ask:ask];
}

- (void)webView:(WKWebView *)webView requestMediaCapturePermissionForOrigin:(WKSecurityOrigin *)origin
    initiatedByFrame:(WKFrameInfo *)frame type:(WKMediaCaptureType)type
    decisionHandler:(void (^)(WKPermissionDecision))decisionHandler {
    BrowserAskKind kind = type == WKMediaCaptureTypeCamera ? BrowserAskCamera
                        : type == WKMediaCaptureTypeMicrophone ? BrowserAskMicrophone : BrowserAskCameraAndMicrophone;
    BrowserAsk *ask = [[BrowserAsk alloc] initWithKind:kind from:origin.host.length ? origin.host : AskerOf(frame)
                                                  done:^(BOOL yes, NSString *text, NSArray *files, NSURL *file) {
        decisionHandler(yes ? WKPermissionDecisionGrant : WKPermissionDecisionDeny);
    }];
    [self ask:ask];
}

@end
