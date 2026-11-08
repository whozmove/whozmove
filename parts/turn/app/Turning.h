// Turning: the curve and the transforms the panel turns over on, for anything else that turns about the panel's middle
// as the panel does (PanelWindow+Turn.m).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

// Turning over: gentle at both ends and quickest where the panel is edge-on.
CGFloat TurnEased(CGFloat x);
// Where a view's layer has its anchor point, in its superview's coordinates, which its layer's transform turns about.
CGPoint AnchorOf(NSView *view);
// The turn by `angle` about the upright line through `middle`, seen from kTurnDepth away, as a layer's transform for a
// layer whose anchor point is at `anchor`, after `own` (its own turn about its own `centre`; identity for none).
CATransform3D TurnAbout(CGPoint middle, CGPoint anchor, CGFloat angle, CATransform3D own, CGPoint centre);
