// Appearance: whether macOS has something light or dark.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Appearance.h"

BOOL IsDark(NSAppearance *appearance) {
    NSAppearanceName name = [appearance bestMatchFromAppearancesWithNames:@[
        NSAppearanceNameAqua, NSAppearanceNameDarkAqua, NSAppearanceNameVibrantLight, NSAppearanceNameVibrantDark]];
    return [name isEqual:NSAppearanceNameDarkAqua] || [name isEqual:NSAppearanceNameVibrantDark];
}
