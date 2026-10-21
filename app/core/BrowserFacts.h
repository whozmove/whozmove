// BrowserFacts: what a Browser relies on about Safari to introduce itself as this Mac's Safari (Browser.m): where
// Safari is, and the words it introduces itself with. Last checked with Safari 26.2.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// Safari, found by its bundle id; its version is its bundle's short version.
static NSString *const kSafariBundleId = @"com.apple.Safari";

// Safari's words on a Mac, its version where %@ is. Safari gives the same system and engine on every Mac (macOS 10.15.7
// on Intel, WebKit 605.1.15) whatever the real ones, so only its version changes.
static NSString *const kSafariIntroduction = @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
                                             @"(KHTML, like Gecko) Version/%@ Safari/605.1.15";

// The version given when Safari isn't where macOS says it is (it's always on a Mac, but can be moved).
static NSString *const kSafariVersionMissing = @"26.0";
