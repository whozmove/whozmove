// HomebrewFacts: what Whozmove relies on about Homebrew, to tell a new version is out, which a new Homebrew could
// change. When it does, the fix goes here. The version these were last checked with is in the README ("Tested with").
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// Where Homebrew lives on Apple silicon, and its record of an installed cask, in its Caskroom: a JSON file whose
// `source` names the tap it came from (`tap`, "whozmove/tap") and the version installed (`version`).
extern NSString *const kHomebrewPrefix;
NSString *HomebrewReceipt(NSString *prefix, NSString *cask);
// Whozmove's cask, and its file in a tap ("owner/name", the repo github.com/owner/homebrew-name): Homebrew's copy on
// this Mac, as new as your last `brew`, and GitHub's, read from its raw file. The file names the version it installs on
// a line of its own, `version "0.2.1"`.
extern NSString *const kWhozmoveCask;
NSString *TapCaskFile(NSString *prefix, NSString *tap, NSString *cask);
NSURL *TapCaskOnGitHub(NSString *tap, NSString *cask);
NSString *CaskVersion(NSString *rubyFile);
// The command that updates it, as you'd type it in a terminal, naming the cask with its tap ("whozmove/tap/whozmove"):
// so named, Homebrew fetches the tap again first if it's more than 5 minutes old, where a cask's bare name waits a day,
// and would say a version just released is already installed (Homebrew 7.0.10's utils/auto-update.sh).
NSString *BrewUpgradeCommand(NSString *tap, NSString *cask);
