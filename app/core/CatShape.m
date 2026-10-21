// CatShape: the cat's shapes, for drawing it natively (CatShape.h).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "CatShape.h"

NSString *const kCatHead =
    @"M0 74C-46 74 -84 50 -84 10C-84 -20 -76 -40 -64 -52C-62 -64 -54 -72 -42 -72C-34 -72 -28 -68 -24 -64C-8 -68 8 -68 "
    @"24 -64C28 -68 34 -72 42 -72C54 -72 62 -64 64 -52C76 -40 84 -20 84 10C84 50 46 74 0 74Z";
NSString *const kCatEars =
    @"M-70 -44C-68 -60 -54 -72 -36 -70C-30 -69 -26 -66 -24 -62L-45 -43C-49 -39 -54 -38 -58 -40ZM70 -44C68 -60 54 -72 "
    @"36 -70C30 -69 26 -66 24 -62L45 -43C49 -39 54 -38 58 -40Z";
NSString *const kCatEarLeft =
    @"M-70 -44C-68 -60 -54 -72 -36 -70C-30 -69 -26 -66 -24 -62L-45 -43C-49 -39 -54 -38 -58 -40Z";
NSString *const kCatEarRight =
    @"M70 -44C68 -60 54 -72 36 -70C30 -69 26 -66 24 -62L45 -43C49 -39 54 -38 58 -40Z";
NSString *const kCatNose = @"M-7 22C-7 18 7 18 7 22C7 26 3 28 0 30C-3 28 -7 26 -7 22Z";
NSString *const kCatShut = @"M-44 2Q-30 16 -16 2M16 2Q30 16 44 2";
const CGFloat kCatEyeX = 30, kCatEyeY = 6, kCatEyeR = 13, kCatMiddleY = 1, kCatWide = 168;

NSBezierPath *CatPath(NSString *svg) {
    NSBezierPath *path = [NSBezierPath bezierPath];
    NSScanner *scan = [NSScanner scannerWithString:svg];
    scan.charactersToBeSkipped = [NSCharacterSet characterSetWithCharactersInString:@" ,"];
    NSCharacterSet *letters = [NSCharacterSet characterSetWithCharactersInString:@"MLQCZ"];
    unichar command = 'M';
    double v[6];
    while (!scan.isAtEnd) {
        NSString *next = nil;
        if ([scan scanCharactersFromSet:letters intoString:&next]) {
            for (NSUInteger i = 0; i + 1 < next.length; i++)
                if ([next characterAtIndex:i] == 'Z') [path closePath];
            command = [next characterAtIndex:next.length - 1];
            if (command == 'Z') {
                [path closePath];
                continue;
            }
        }
        int count = command == 'C' ? 6 : command == 'Q' ? 4 : 2;
        for (int i = 0; i < count; i++)
            if (![scan scanDouble:&v[i]]) return path;
        if (command == 'M') [path moveToPoint:NSMakePoint(v[0], v[1])];
        else if (command == 'L') [path lineToPoint:NSMakePoint(v[0], v[1])];
        else if (command == 'Q') {
            // A quadratic curve, as the cubic one it is: its control point two thirds of the way from each end.
            NSPoint from = path.currentPoint, control = NSMakePoint(v[0], v[1]), to = NSMakePoint(v[2], v[3]);
            [path curveToPoint:to
                 controlPoint1:NSMakePoint(from.x + 2 * (control.x - from.x) / 3, from.y + 2 * (control.y - from.y) / 3)
                 controlPoint2:NSMakePoint(to.x + 2 * (control.x - to.x) / 3, to.y + 2 * (control.y - to.y) / 3)];
        } else [path curveToPoint:NSMakePoint(v[4], v[5]) controlPoint1:NSMakePoint(v[0], v[1])
                    controlPoint2:NSMakePoint(v[2], v[3])];
        // More points after a move are lines, as in SVG.
        if (command == 'M') command = 'L';
    }
    return path;
}

CGPathRef CatCGPath(NSString *svg) {
    NSBezierPath *path = CatPath(svg);
    CGMutablePathRef out = CGPathCreateMutable();
    NSPoint p[3];
    for (NSInteger i = 0; i < path.elementCount; i++) {
        switch ([path elementAtIndex:i associatedPoints:p]) {
            case NSBezierPathElementMoveTo: CGPathMoveToPoint(out, NULL, p[0].x, p[0].y); break;
            case NSBezierPathElementLineTo: CGPathAddLineToPoint(out, NULL, p[0].x, p[0].y); break;
            case NSBezierPathElementCubicCurveTo:
                CGPathAddCurveToPoint(out, NULL, p[0].x, p[0].y, p[1].x, p[1].y, p[2].x, p[2].y);
                break;
            case NSBezierPathElementClosePath: CGPathCloseSubpath(out); break;
            default: break;
        }
    }
    return out;
}
