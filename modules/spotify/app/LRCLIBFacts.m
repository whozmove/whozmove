// LRCLIBFacts: the facts about LRCLIB that LRCLIBFacts.h describes.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "LRCLIBFacts.h"

NSString *const kLRCLIBGet = @"https://lrclib.net/api/get";
NSString *const kLRCLIBTrack = @"track_name", *const kLRCLIBArtist = @"artist_name",
         *const kLRCLIBAlbum = @"album_name", *const kLRCLIBDuration = @"duration";
const double kLRCLIBLeeway = 2;
const long kLRCLIBLongest = 3600;
NSString *const kLRCLIBSynced = @"syncedLyrics", *const kLRCLIBPlain = @"plainLyrics",
         *const kLRCLIBInstrumental = @"instrumental";
NSString *const kLRCLIBSearch = @"https://lrclib.net/api/search";
NSString *const kLRCLIBFoundName = @"trackName";
NSString *const kLRCLIBRetryAfter = @"Retry-After";

NSString *LRCLIBUserAgent(void) {
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    return version.length ? [NSString stringWithFormat:@"Whozmove v%@ (https://github.com/whozmove/whozmove)", version]
                          : @"Whozmove (https://github.com/whozmove/whozmove)";
}
