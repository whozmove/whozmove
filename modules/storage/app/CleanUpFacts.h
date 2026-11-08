// CleanUpFacts: what Clean up relies on about the tools developers use, which they could change: where each keeps what
// it downloads or builds and makes again when it's needed, and the commands that clean what only the tool itself
// should. Paths are within the home folder. docs/using/install.md ("What it's tested with") names this file.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// A tool's cache, fetched again when it's needed, each {name, path, where}, `where` saying how when it isn't fetched by
// itself (Playwright's browsers); and models downloaded to run on this Mac, fetched again the next time one's used, the
// same way (Hugging Face's only from its hub folder, as its own folder also keeps its sign-in and settings).
extern NSArray<NSDictionary<NSString *, NSString *> *> *const kCaches;
extern NSArray<NSDictionary<NSString *, NSString *> *> *const kModels;

// Xcode's built files for every project, and its support files for each iOS version a phone it debugged ran.
extern NSString *const kDerivedData, *const kDeviceSupport;

// In a checkout, the folders a build or an install makes again: by name, wherever they are in it (but inside one
// another); by their path within a folder of the checkout (an app's ios/build); and Rust's `target`, only beside the
// Cargo.toml that says it's Rust's.
extern NSArray<NSString *> *const kBuiltNames, *const kBuiltPaths;
extern NSString *const kCargoTarget, *const kCargoManifest;

// Homebrew: the command that takes out its old downloads and versions, and the folder its downloads are in.
extern NSArray<NSString *> *const kBrewCleanup;
extern NSString *const kBrewDownloads;

// Docker: its app, opened for it to say what it can free; how it says what it can free (each kind of thing it keeps
// and how much of it isn't used, a line each), the kinds counted, and the commands that free them: images no container
// uses, and its build cache. Containers, running or stopped, and their images stay.
extern NSString *const kDockerApp;
extern NSArray<NSString *> *const kDockerSays;
extern NSArray<NSString *> *const kDockerKinds;
extern NSArray<NSArray<NSString *> *> *const kDockerPrune;

// Xcode's simulators: listing those no longer available (for an iOS Xcode no longer has), deleting them, and the folder
// each one's kept in, by its id.
extern NSArray<NSString *> *const kSimulatorsGone, *const kSimulatorsDelete;
extern NSString *const kSimulatorDevices;
