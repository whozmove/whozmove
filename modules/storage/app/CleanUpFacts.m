// CleanUpFacts: what Clean up relies on about developers' tools (CleanUpFacts.h).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "CleanUpFacts.h"

NSArray<NSDictionary<NSString *, NSString *> *> *const kCaches = @[
    @{@"name": @"npm's cache", @"path": @".npm/_cacache", @"where": @"~/.npm"},
    @{@"name": @"Yarn's cache", @"path": @"Library/Caches/Yarn", @"where": @"Library/Caches/Yarn"},
    @{@"name": @"pnpm's store", @"path": @"Library/pnpm/store", @"where": @"Library/pnpm/store"},
    @{@"name": @"Bun's cache", @"path": @".bun/install/cache", @"where": @"~/.bun/install/cache"},
    @{@"name": @"pip's cache", @"path": @"Library/Caches/pip", @"where": @"Library/Caches/pip"},
    @{@"name": @"Gradle's cache", @"path": @".gradle/caches", @"where": @"~/.gradle/caches"},
    @{@"name": @"Go's modules", @"path": @"go/pkg/mod", @"where": @"~/go/pkg/mod"},
    @{@"name": @"Go's build cache", @"path": @"Library/Caches/go-build", @"where": @"Library/Caches/go-build"},
    @{@"name": @"Cargo's downloads", @"path": @".cargo/registry", @"where": @"~/.cargo/registry"},
    @{@"name": @"CocoaPods' cache", @"path": @"Library/Caches/CocoaPods", @"where": @"Library/Caches/CocoaPods"},
    @{@"name": @"Playwright's browsers", @"path": @"Library/Caches/ms-playwright",
      @"where": @"Installed again with npx playwright install"},
];

NSArray<NSDictionary<NSString *, NSString *> *> *const kModels = @[
    @{@"name": @"Ollama's models", @"path": @".ollama/models", @"where": @"~/.ollama/models"},
    @{@"name": @"Hugging Face's cache", @"path": @".cache/huggingface/hub", @"where": @"~/.cache/huggingface/hub"},
];

NSString *const kDerivedData = @"Library/Developer/Xcode/DerivedData";
NSString *const kDeviceSupport = @"Library/Developer/Xcode/iOS DeviceSupport";

NSArray<NSString *> *const kBuiltNames = @[@"node_modules", @".next"];
NSArray<NSString *> *const kBuiltPaths = @[@"ios/build", @"android/build"];
NSString *const kCargoTarget = @"target";
NSString *const kCargoManifest = @"Cargo.toml";

NSArray<NSString *> *const kBrewCleanup = @[@"brew", @"cleanup", @"--prune=all"];
NSString *const kBrewDownloads = @"Library/Caches/Homebrew";

NSString *const kDockerApp = @"com.docker.docker";
NSArray<NSString *> *const kDockerSays = @[@"docker", @"system", @"df", @"--format", @"{{.Type}}\t{{.Reclaimable}}"];
NSArray<NSString *> *const kDockerKinds = @[@"Images", @"Build Cache"];
NSArray<NSArray<NSString *> *> *const kDockerPrune = @[@[@"docker", @"image", @"prune", @"-a", @"-f"],
                                                        @[@"docker", @"builder", @"prune", @"-a", @"-f"]];

NSArray<NSString *> *const kSimulatorsGone = @[@"xcrun", @"simctl", @"list", @"devices", @"unavailable", @"--json"];
NSArray<NSString *> *const kSimulatorsDelete = @[@"xcrun", @"simctl", @"delete", @"unavailable"];
NSString *const kSimulatorDevices = @"Library/Developer/CoreSimulator/Devices";
