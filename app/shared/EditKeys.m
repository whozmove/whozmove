// EditKeys: the edit a key does in a web view that's being typed in, and doing it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "EditKeys.h"

SEL EditFor(NSEvent *event, BOOL typing) {
    if (!typing || event.type != NSEventTypeKeyDown) return NULL;
    NSEventModifierFlags mods = event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagShift |
                                                       NSEventModifierFlagOption | NSEventModifierFlagControl);
    // The letter the key makes with ⌘ held, else the key's own (EditKeys.h says why).
    NSString *withCommand = event.characters.lowercaseString;
    unichar letter = withCommand.length == 1 ? [withCommand characterAtIndex:0] : 0;
    NSString *key = letter >= 'a' && letter <= 'z' ? withCommand : event.charactersIgnoringModifiers.lowercaseString;
    if (mods == (NSEventModifierFlagCommand | NSEventModifierFlagShift))
        return [key isEqualToString:@"z"] ? @selector(redo:) : NULL;
    if (mods != NSEventModifierFlagCommand) return NULL;
    NSDictionary<NSString *, NSString *> *edits = @{@"c": @"copy:", @"x": @"cut:", @"v": @"paste:",
                                                    @"a": @"selectAll:", @"z": @"undo:"};
    return edits[key] ? NSSelectorFromString(edits[key]) : NULL;
}

BOOL DoEditKey(NSView *view, NSEvent *event) {
    NSResponder *first = view.window.firstResponder;
    BOOL typing = view.window.isKeyWindow && [first isKindOfClass:NSView.class]
                  && [(NSView *)first isDescendantOf:view];
    SEL edit = EditFor(event, typing);
    return edit && [view tryToPerform:edit with:nil];
}
