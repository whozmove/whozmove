// StorageFacts: what the map relies on about macOS and the tools that keep big stores in your home folder, which they
// could change: the folders macOS protects, those kept in the cloud, the folders that stay though what's in them can
// go, and the stores a tool keeps that only it should clean. Paths are within the home folder unless they start with /.
// The version these were last checked with is in docs/using/install.md ("What it's tested with").
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// Folders macOS protects. Opening one without Full Disk Access makes macOS ask you (Desktop, Documents, Downloads,
// iCloud Drive, other apps' data, since macOS 14) or refuses: so the map opens none of them without it, and shows each
// as one it can't look inside.
extern NSArray<NSString *> *const kProtectedFolders;
// Folders kept in the cloud by an app (File Provider: iCloud Drive, and the folders of others such as Dropbox):
// looking through one can make its app fetch it, so the map never does, Full Disk Access or not. Anything else kept
// only in the cloud (Desktop and Documents in iCloud) reads as one it can't look inside (MeasureTop).
extern NSArray<NSString *> *const kCloudFolders;
// Folders that stay, though what's in them can go: the home folder itself (""), its Library and the places apps keep
// their data, Applications, Claude Code's own folder.
extern NSArray<NSString *> *const kKeptFolders;
// The folders outside the home folder the map measures, beside it and its Applications.
extern NSArray<NSString *> *const kSharedFolders;
// A tool's own store, by its folder, and what to say of it: only the tool should clean it (Docker's disk, Xcode's
// simulators), which Clean up does with the tool's own command.
extern NSDictionary<NSString *, NSString *> *const kToolStores;
