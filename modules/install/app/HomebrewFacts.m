// HomebrewFacts: what Whozmove relies on about Homebrew (HomebrewFacts.h).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "HomebrewFacts.h"

NSString *const kHomebrewPrefix = @"/opt/homebrew";
NSString *const kWhozmoveCask = @"whozmove";

NSString *HomebrewReceipt(NSString *prefix, NSString *cask) {
    return [NSString pathWithComponents:@[prefix, @"Caskroom", cask, @".metadata", @"INSTALL_RECEIPT.json"]];
}

// "owner/name" is the repo owner/homebrew-name, which Homebrew keeps in Library/Taps.
static NSArray<NSString *> *TapParts(NSString *tap) {
    NSArray *parts = [tap componentsSeparatedByString:@"/"];
    if (parts.count != 2 || ![parts[0] length] || ![parts[1] length]) return nil;
    for (NSString *part in parts)
        if ([part rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"./ "]].location
            != NSNotFound) return nil;
    return @[parts[0], [@"homebrew-" stringByAppendingString:parts[1]]];
}

NSString *BrewUpgradeCommand(NSString *tap, NSString *cask) {
    return [NSString stringWithFormat:@"brew upgrade --cask %@/%@", tap, cask];
}

NSString *TapCaskFile(NSString *prefix, NSString *tap, NSString *cask) {
    NSArray *parts = TapParts(tap);
    if (!parts) return nil;
    return [NSString pathWithComponents:@[prefix, @"Library", @"Taps", parts[0], parts[1], @"Casks",
                                          [cask stringByAppendingPathExtension:@"rb"]]];
}

NSURL *TapCaskOnGitHub(NSString *tap, NSString *cask) {
    NSArray *parts = TapParts(tap);
    if (!parts) return nil;
    return [NSURL URLWithString:[NSString stringWithFormat:@"https://raw.githubusercontent.com/%@/%@/HEAD/Casks/%@.rb",
                                                           parts[0], parts[1], cask]];
}

NSString *CaskVersion(NSString *rubyFile) {
    if (!rubyFile.length) return nil;
    NSString *pattern = @"^\\s*version\\s+\"([0-9][0-9A-Za-z.,_-]*)\"";
    NSRegularExpression *line = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                          options:NSRegularExpressionAnchorsMatchLines
                                                                            error:nil];
    NSTextCheckingResult *found = [line firstMatchInString:rubyFile options:0 range:NSMakeRange(0, rubyFile.length)];
    return found ? [rubyFile substringWithRange:[found rangeAtIndex:1]] : nil;
}
