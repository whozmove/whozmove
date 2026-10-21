// Easing: the curves the panel moves on (Easing.h).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Easing.h"

const Easing kSettle = {0.2, 0.8, 0.2, 1}, kFoldEasing = {0.4, 0, 0.2, 1};

CGFloat Eased(Easing e, CGFloat x) {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    // The curve's own time for `x` (Newton's method), then how far along it is there.
    CGFloat t = x;
    for (int i = 0; i < 8; i++) {
        CGFloat u = 1 - t;
        CGFloat off = 3 * u * u * t * e.x1 + 3 * u * t * t * e.x2 + t * t * t - x;
        CGFloat slope = 3 * u * u * e.x1 + 6 * u * t * (e.x2 - e.x1) + 3 * t * t * (1 - e.x2);
        if (fabs(off) < 1e-6 || fabs(slope) < 1e-6) break;
        t = MIN(1, MAX(0, t - off / slope));
    }
    CGFloat u = 1 - t;
    return 3 * u * u * t * e.y1 + 3 * u * t * t * e.y2 + t * t * t;
}
