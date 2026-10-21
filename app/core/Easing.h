// Easing: the curves the panel moves on, each a cubic Bézier from (0,0) to (1,1) as CSS writes one, for what moves with
// the panel natively (PanelWindow.m, EdgeIcon.m, SideCat.m), so they all keep to the glass's own curve.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>

typedef struct { CGFloat x1, y1, x2, y2; } Easing;
// The reader's: quick, then settling. Folding and opening: gentle at both ends, as the cat changes size with the glass.
extern const Easing kSettle, kFoldEasing;
// How far along the curve it is `x` of the way through, from 0 to 1.
CGFloat Eased(Easing e, CGFloat x);
