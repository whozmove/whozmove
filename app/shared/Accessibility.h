// Accessibility: reading another app's windows through the Accessibility API, finding its controls, and pressing them
// or posting keys. Plain helpers, any app's: each module keeps what it knows of its own app's window.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>

// Whether Whozmove may use the Accessibility API; when it may not, macOS is asked to offer the permission.
BOOL MayUseAccessibility(void);
// Performs an action on an element (a press), or sets one of its attributes (a box's words, its focus): what macOS
// says, or kAXErrorAPIDisabled, doing nothing, while Whozmove may not act on other apps (MayActOnOtherApps). That
// answer is the gate's own: kAXErrorCannotComplete can mean a press went in (iTerm2 holds one while it asks you).
AXError PressElement(AXUIElementRef el, CFStringRef action);
AXError SetElementAttribute(AXUIElementRef el, CFStringRef attribute, CFTypeRef value);
// Posts a keyboard or mouse event where `tap` delivers it, or to the process `pid` alone: NO, posting nothing, while
// Whozmove may not act on other apps.
BOOL PostEvent(CGEventTapLocation tap, CGEventRef event);
BOOL PostEventTo(pid_t pid, CGEventRef event);
// An element's attribute, when it's text; else nil.
NSString *ElementText(AXUIElementRef el, CFStringRef attribute);
// The elements from `el` down (`depth` counts how far down it is already; at most 80 levels) that `match` takes, added
// to `found` in order.
void CollectElements(AXUIElementRef el, int depth, BOOL (^match)(AXUIElementRef), NSMutableArray *found);
// What an element is called on screen: its title, else its description, else a text's own words.
NSString *ElementLabel(AXUIElementRef el);
// Where an element is on screen, into *frame; NO when it doesn't say.
BOOL ElementFrame(AXUIElementRef el, CGRect *frame);
// The one control of `role` in the app's windows whose title (else its description) `named` takes; nil when there's
// none, or more than one.
id ControlNamed(pid_t pid, NSString *role, BOOL (^named)(NSString *label));
