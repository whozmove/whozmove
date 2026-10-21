// CatShape: the cat's shapes, in its own units (panel/scripts/cat.js, 448 to 92 points folded), for what draws it
// natively: the mark in the menu bar (MenuBar.m) and Whozmove beside the panel (SideCat.m). Keep them matching
// cat.js's, and the app icon's (icon/make-icon.m).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>

// Its head, its folded ears (both, and each), its nose, and its eyes shut, as SVG paths, y down.
extern NSString *const kCatHead, *const kCatEars, *const kCatEarLeft, *const kCatEarRight, *const kCatNose,
    *const kCatShut;
// Its eyes' middles and size, and its shape's middle and width, in its units.
extern const CGFloat kCatEyeX, kCatEyeY, kCatEyeR, kCatMiddleY, kCatWide;

// An SVG path's absolute M, L, Q, C and Z, as an NSBezierPath, and as a CGPath (the caller releases it).
NSBezierPath *CatPath(NSString *svg);
CGPathRef CatCGPath(NSString *svg) CF_RETURNS_RETAINED;
