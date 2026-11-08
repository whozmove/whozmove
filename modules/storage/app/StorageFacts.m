// StorageFacts: what the map relies on about macOS and the tools that keep big stores in your home folder
// (StorageFacts.h).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "StorageFacts.h"

NSArray<NSString *> *const kProtectedFolders = @[
    @"Desktop", @"Documents", @"Downloads", @"Library/Mobile Documents", @"Library/Containers",
    @"Library/Group Containers", @"Library/Daemon Containers", @"Library/Mail", @"Library/Messages", @"Library/Safari",
    @"Library/Calendars", @"Library/Cookies", @"Library/HomeKit", @"Library/IdentityServices", @"Library/Suggestions",
    @"Library/Metadata/CoreSpotlight", @"Library/PersonalizationPortrait", @"Library/Biome", @"Library/Accounts",
    @"Library/Application Support/AddressBook", @"Library/Application Support/CallHistoryDB",
    @"Library/Application Support/com.apple.TCC", @"Library/Application Support/Knowledge",
    @"Library/Application Support/FaceTime", @"Library/Application Support/com.apple.sharedfilelist",
    @"Pictures/Photos Library.photoslibrary", @".Trash",
];

NSArray<NSString *> *const kCloudFolders = @[@"Library/CloudStorage", @"Library/Mobile Documents"];

NSArray<NSString *> *const kKeptFolders = @[
    @"", @"Library", @"Library/Application Support", @"Library/Containers", @"Library/Group Containers",
    @"Library/Caches", @"Library/Developer", @"Library/Preferences", @".claude", @"/Applications",
];

NSArray<NSString *> *const kSharedFolders = @[@"/Applications", @"/Library", @"/opt", @"/usr/local", @"/Users/Shared"];

NSDictionary<NSString *, NSString *> *const kToolStores = @{
    @"Library/Containers/com.docker.docker": @"Docker keeps its images and containers here: Clean up frees what no "
                                             @"container uses",
    @"Library/Developer/CoreSimulator/Devices": @"Xcode keeps its simulators here: Clean up deletes those no longer "
                                                @"available",
};
