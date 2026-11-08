// Links: opening an address.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Links.h"
#import "OtherApps.h"

BOOL OpenInOtherApp(NSURL *url) {
    return url && MayActOnOtherApps() && [NSWorkspace.sharedWorkspace openURL:url];
}

BOOL OpenInOtherAppWith(NSArray<NSURL *> *urls, NSURL *app, NSWorkspaceOpenConfiguration *configuration,
                        void (^done)(NSRunningApplication *opened, NSError *error)) {
    if (!app || !MayActOnOtherApps()) {
        if (done) done(nil, [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]);
        return NO;
    }
    [NSWorkspace.sharedWorkspace openURLs:urls withApplicationAtURL:app configuration:configuration
                        completionHandler:done];
    return YES;
}

BOOL OpenLink(NSString *address) {
    return OpenInOtherApp([NSURL URLWithString:address]);
}

BOOL OpenInWebBrowser(NSURL *page) {
    NSURL *web = [NSURL URLWithString:@"https://example.com"];
    NSURL *browser = [NSWorkspace.sharedWorkspace URLForApplicationToOpenURL:web];
    if (!page || !browser) return NO;
    return OpenInOtherAppWith(@[page], browser, [NSWorkspaceOpenConfiguration configuration], nil);
}
