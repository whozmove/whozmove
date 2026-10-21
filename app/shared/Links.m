// Links: opening an address.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Links.h"
#import <Cocoa/Cocoa.h>

BOOL OpenLink(NSString *address) {
    NSURL *url = [NSURL URLWithString:address];
    return url && [NSWorkspace.sharedWorkspace openURL:url];
}

BOOL OpenInWebBrowser(NSURL *page) {
    NSURL *web = [NSURL URLWithString:@"https://example.com"];
    NSURL *browser = [NSWorkspace.sharedWorkspace URLForApplicationToOpenURL:web];
    if (!page || !browser) return NO;
    [NSWorkspace.sharedWorkspace openURLs:@[page] withApplicationAtURL:browser
                            configuration:[NSWorkspaceOpenConfiguration configuration] completionHandler:nil];
    return YES;
}
