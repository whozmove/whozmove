// make-icon: draws the Whozmove app icon, an amber pawn ("your move") on a dark tile with a pill of the panel's
// status colours, and writes AppIcon.icns next to this file.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// It only needs running again when the design changes:
//   clang -fobjc-arc -framework Cocoa icon/make-icon.m -o /tmp/make-icon && /tmp/make-icon
#import <Cocoa/Cocoa.h>

static NSColor *Hex(unsigned hex, CGFloat alpha) {
    return [NSColor colorWithSRGBRed:((hex >> 16) & 0xff) / 255.0 green:((hex >> 8) & 0xff) / 255.0
                                blue:(hex & 0xff) / 255.0 alpha:alpha];
}

static void FillRounded(NSRect rect, CGFloat radius, NSColor *color) {
    [color setFill];
    [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius] fill];
}

// The pawn on a 16-unit grid with a top-left origin: head, collar, flared body, base. The menu-bar symbol
// (app/core/MenuBar.m) and the panel's header mark (panel/panel.html) draw this same shape; keep the
// three in step. It's one path, so it fills as one shape: parts filled separately leave a faint seam where
// their soft edges meet. The parts overlap, so the body runs the same way round as the oval and rounded
// rectangles; run the other way, the overlaps would cancel out. The body's foot lands on the base's flat
// top, inside its rounded corners.
static NSBezierPath *PawnPath(void) {
    NSBezierPath *pawn = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(5.6, 1.5, 4.8, 4.8)];
    [pawn appendBezierPath:[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(4.9, 6.1, 6.2, 1.3) xRadius:0.65
                                                           yRadius:0.65]];
    [pawn moveToPoint:NSMakePoint(9.7, 7.3)];
    [pawn curveToPoint:NSMakePoint(11.6, 12.2) controlPoint1:NSMakePoint(9.7, 9.8)
         controlPoint2:NSMakePoint(11.0, 11.3)];
    [pawn lineToPoint:NSMakePoint(4.4, 12.2)];
    [pawn curveToPoint:NSMakePoint(6.3, 7.3) controlPoint1:NSMakePoint(5.0, 11.3)
         controlPoint2:NSMakePoint(6.3, 9.8)];
    [pawn closePath];
    [pawn appendBezierPath:[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(3.2, 11.9, 9.6, 2.3) xRadius:1.15
                                                           yRadius:1.15]];
    return pawn;
}

// The pawn scaled from its grid so its head's top sits at `top`, centred on `centerX`, one grid unit = `unit`.
// The placement and the gradient both come from the path's own bounds, so reshaping it needs no other change.
static void DrawPawn(CGFloat centerX, CGFloat top, CGFloat unit, NSGradient *fill) {
    NSBezierPath *pawn = PawnPath();
    NSRect grid = pawn.bounds;
    NSAffineTransform *place = [NSAffineTransform transform];
    [place translateXBy:centerX - NSMidX(grid) * unit yBy:top - NSMinY(grid) * unit];
    [place scaleBy:unit];
    [fill drawInBezierPath:[place transformBezierPath:pawn] angle:90];
}

// Draws in a 1024×1024 space with a top-left origin, on Apple's icon grid (824pt body, 100pt margin).
static void DrawIcon(CGFloat pixelScale) {
    NSRect body = NSMakeRect(100, 100, 824, 824);
    NSBezierPath *tile = [NSBezierPath bezierPathWithRoundedRect:body xRadius:185 yRadius:185];

    // Drop shadow (shadow geometry is in device pixels, unaffected by the CTM).
    [NSGraphicsContext saveGraphicsState];
    NSShadow *shadow = [NSShadow new];
    shadow.shadowColor = [NSColor colorWithWhite:0 alpha:0.35];
    shadow.shadowBlurRadius = 28 * pixelScale;
    shadow.shadowOffset = NSMakeSize(0, -12 * pixelScale);
    [shadow set];
    [Hex(0x12141f, 1) setFill];
    [tile fill];
    [NSGraphicsContext restoreGraphicsState];

    // Dark ink body, lighter at the top, with a soft rim.
    NSGradient *ink = [[NSGradient alloc] initWithStartingColor:Hex(0x30354d, 1) endingColor:Hex(0x181b2a, 1)];
    [ink drawInBezierPath:tile angle:90];
    [Hex(0xffffff, 0.10) setStroke];
    NSBezierPath *rim = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(body, 2, 2) xRadius:183 yRadius:183];
    rim.lineWidth = 4;
    [rim stroke];

    // The pawn in the panel's "your move" amber (--turn in panel/styles/tokens.css), with a faint shadow so it lifts
    // off the tile. The gradient fill is clipped to the pawn, and a clipped fill casts no shadow of its own, so
    // it's drawn into a transparency layer, which casts the shadow for it.
    NSShadow *lift = [NSShadow new];
    lift.shadowColor = [NSColor colorWithWhite:0 alpha:0.30];
    lift.shadowBlurRadius = 18 * pixelScale;
    lift.shadowOffset = NSMakeSize(0, -8 * pixelScale);
    [NSGraphicsContext saveGraphicsState];
    [lift set];
    CGContextRef cg = NSGraphicsContext.currentContext.CGContext;
    CGContextBeginTransparencyLayer(cg, NULL);
    DrawPawn(452, 184, 39.4, [[NSGradient alloc] initWithStartingColor:Hex(0xffd76e, 1) endingColor:Hex(0xf2a41f, 1)]);
    CGContextEndTransparencyLayer(cg);
    [NSGraphicsContext restoreGraphicsState];

    // A pill of agent statuses (needs you, working, your turn), tucked into the lower right, a shade lighter
    // than the tile so it reads against it.
    NSRect pill = NSMakeRect(512, 712, 336, 132);
    [NSGraphicsContext saveGraphicsState];
    [lift set];
    FillRounded(pill, 66, Hex(0x2a3047, 0.96));
    [NSGraphicsContext restoreGraphicsState];
    // The panel's --needs, --busy and --turn (panel/styles/tokens.css): keep them matching.
    NSColor *dots[] = {Hex(0xff6b4a, 1), Hex(0x4aa8ff, 1), Hex(0xffc53d, 1)};
    for (int i = 0; i < 3; i++) {
        NSPoint dot = NSMakePoint(NSMinX(pill) + 72 + i * 96, NSMidY(pill));
        [dots[i] setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(dot.x - 32, dot.y - 32, 64, 64)] fill];
    }
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
