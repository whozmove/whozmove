// make-icon: draws the Whozmove app icon, the folded cat in cream on a dark tile like the folded panel's glass, and
// writes AppIcon.icns next to this file.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// It only needs running again when the design changes:
//   clang -fobjc-arc -framework Cocoa icon/make-icon.m -o /tmp/make-icon && /tmp/make-icon
#import <Cocoa/Cocoa.h>

static NSColor *Hex(unsigned hex, CGFloat alpha) {
    return [NSColor colorWithSRGBRed:((hex >> 16) & 0xff) / 255.0 green:((hex >> 8) & 0xff) / 255.0
                                blue:(hex & 0xff) / 255.0 alpha:alpha];
}

// The cat as the logo draws it, in its own units: its head and folded ears one flat shape, its eyes and nose cut out so
// the glass shows through. Its shapes are the folded panel's (panel/scripts/cat.js), as the menu bar's are
// (app/core/MenuBar.m): a change to the cat goes in all three.
static NSString *const kCatHead =
    @"M0 74C-46 74 -84 50 -84 10C-84 -20 -76 -40 -64 -52C-62 -64 -54 -72 -42 -72C-34 -72 -28 -68 -24 -64C-8 -68 8 -68 "
    @"24 -64C28 -68 34 -72 42 -72C54 -72 62 -64 64 -52C76 -40 84 -20 84 10C84 50 46 74 0 74Z";
static NSString *const kCatEars =
    @"M-70 -44C-68 -60 -54 -72 -36 -70C-30 -69 -26 -66 -24 -62L-45 -43C-49 -39 -54 -38 -58 -40ZM70 -44C68 -60 54 -72 "
    @"36 -70C30 -69 26 -66 24 -62L45 -43C49 -39 54 -38 58 -40Z";
static NSString *const kCatNose = @"M-7 22C-7 18 7 18 7 22C7 26 3 28 0 30C-3 28 -7 26 -7 22Z";
// The cat's eyes, as the logo places them; and the cat on the tile, where (kCatX, kCatY) is its own (0, 0), a unit
// above its middle. Its middle sits a little above the tile's (at 509 of 1024), since the head is wider at the bottom
// than at its ears, so it looks centred.
static const CGFloat kCatEyeX = 30, kCatEyeY = 6, kCatEyeR = 13, kCatX = 512, kCatY = 506, kCatScale = 2.9;

// An SVG path's absolute M, L, C and Z, as an NSBezierPath.
static NSBezierPath *PathFrom(NSString *svg) {
    NSBezierPath *path = [NSBezierPath bezierPath];
    NSScanner *scan = [NSScanner scannerWithString:svg];
    scan.charactersToBeSkipped = [NSCharacterSet characterSetWithCharactersInString:@" ,"];
    NSCharacterSet *letters = [NSCharacterSet characterSetWithCharactersInString:@"MLCZ"];
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
        int count = command == 'C' ? 6 : 2;
        for (int i = 0; i < count; i++)
            if (![scan scanDouble:&v[i]]) return path;
        if (command == 'M') [path moveToPoint:NSMakePoint(v[0], v[1])];
        else if (command == 'L') [path lineToPoint:NSMakePoint(v[0], v[1])];
        else [path curveToPoint:NSMakePoint(v[4], v[5]) controlPoint1:NSMakePoint(v[0], v[1])
                  controlPoint2:NSMakePoint(v[2], v[3])];
        // More points after a move are lines, as in SVG.
        if (command == 'M') command = 'L';
    }
    return path;
}

// Draws in a 1024×1024 space with a top-left origin, on Apple's icon grid (824pt body, 100pt margin): the dark glass,
// and the cat on it. The cat's head and ears are filled apiece: as one path, the right ear, drawn the other way round,
// would cancel out where it overlaps the head.
static void DrawIcon(CGFloat pixelScale) {
    NSRect body = NSMakeRect(100, 100, 824, 824);
    NSBezierPath *tile = [NSBezierPath bezierPathWithRoundedRect:body xRadius:185 yRadius:185];

    // Drop shadow (shadow geometry is in device pixels, unaffected by the CTM).
    [NSGraphicsContext saveGraphicsState];
    NSShadow *shadow = [NSShadow new];
    shadow.shadowColor = [NSColor colorWithWhite:0 alpha:0.30];
    shadow.shadowBlurRadius = 28 * pixelScale;
    shadow.shadowOffset = NSMakeSize(0, -12 * pixelScale);
    [shadow set];
    [Hex(0x17171a, 1) setFill];
    [tile fill];
    [NSGraphicsContext restoreGraphicsState];

    // The glass, a shade darker toward the bottom.
    NSGradient *glass = [[NSGradient alloc] initWithStartingColor:Hex(0x2c2c31, 1) endingColor:Hex(0x17171a, 1)];
    [glass drawInBezierPath:tile angle:90];

    // A faint light rim round the tile.
    [Hex(0xffffff, 0.10) setStroke];
    NSBezierPath *rim = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(body, 2, 2) xRadius:183 yRadius:183];
    rim.lineWidth = 4;
    [rim stroke];

    NSAffineTransform *place = [NSAffineTransform transform];
    [place translateXBy:kCatX yBy:kCatY];
    [place scaleBy:kCatScale];
    NSBezierPath *head = PathFrom(kCatHead), *ears = PathFrom(kCatEars), *features = PathFrom(kCatNose);
    for (int side = -1; side <= 1; side += 2)
        [features appendBezierPath:[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(side * kCatEyeX - kCatEyeR,
            kCatEyeY - kCatEyeR, 2 * kCatEyeR, 2 * kCatEyeR)]];
    for (NSBezierPath *path in @[head, ears, features]) [path transformUsingAffineTransform:place];

    [Hex(0xf3ebe2, 1) setFill];
    [head fill];
    [ears fill];
    // The eyes and nose show the glass under them, its gradient where it falls on the tile.
    [NSGraphicsContext saveGraphicsState];
    [features addClip];
    [glass drawInRect:body angle:90];
    [NSGraphicsContext restoreGraphicsState];
}

static NSData *RenderPNG(NSInteger pixels) {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:pixels
                                                                    pixelsHigh:pixels bitsPerSample:8
                                                               samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                colorSpaceName:NSCalibratedRGBColorSpace
                                                                   bytesPerRow:0 bitsPerPixel:0];
    NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = ctx;
    CGFloat scale = pixels / 1024.0;
    CGContextTranslateCTM(ctx.CGContext, 0, pixels);
    CGContextScaleCTM(ctx.CGContext, scale, -scale);  // top-left origin, 1024-unit canvas
    DrawIcon(scale);
    [NSGraphicsContext restoreGraphicsState];
    return [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

int main(void) {
    @autoreleasepool {
        NSString *here = [NSString stringWithUTF8String:__FILE__].stringByDeletingLastPathComponent;
        NSString *iconset = [NSTemporaryDirectory() stringByAppendingPathComponent:@"AppIcon.iconset"];
        [NSFileManager.defaultManager removeItemAtPath:iconset error:nil];
        [NSFileManager.defaultManager createDirectoryAtPath:iconset withIntermediateDirectories:YES attributes:nil
                                                      error:nil];
        for (NSNumber *size in @[@16, @32, @128, @256, @512]) {
            NSInteger pt = size.integerValue;
            [RenderPNG(pt) writeToFile:[iconset stringByAppendingFormat:@"/icon_%ldx%ld.png", pt, pt] atomically:YES];
            [RenderPNG(pt * 2) writeToFile:[iconset stringByAppendingFormat:@"/icon_%ldx%ld@2x.png", pt, pt]
                                atomically:YES];
        }
        NSTask *iconutil = [NSTask launchedTaskWithLaunchPath:@"/usr/bin/iconutil"
                                                    arguments:@[@"-c", @"icns", iconset, @"-o",
                                                                [here stringByAppendingPathComponent:@"AppIcon.icns"]]];
        [iconutil waitUntilExit];
        printf("%s\n", iconutil.terminationStatus == 0 ? "Wrote AppIcon.icns" : "iconutil failed");
        return iconutil.terminationStatus;
    }
}
