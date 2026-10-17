// Accessibility: reading another app's windows, and finding its controls.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Accessibility.h"

BOOL MayUseAccessibility(void) {
    if (AXIsProcessTrusted()) return YES;
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES});
    return NO;
}

NSString *ElementText(AXUIElementRef el, CFStringRef attribute) {
    CFTypeRef value = NULL;
    if (AXUIElementCopyAttributeValue(el, attribute, &value) != kAXErrorSuccess || !value) return nil;
    id object = (__bridge_transfer id)value;  // owned from here, so it outlives the return
    return [object isKindOfClass:NSString.class] ? object : nil;
}

void CollectElements(AXUIElementRef el, int depth, BOOL (^match)(AXUIElementRef), NSMutableArray *found) {
    if (depth > 80) return;
    if (match(el)) [found addObject:(__bridge id)el];
    CFTypeRef children = NULL;
    if (AXUIElementCopyAttributeValue(el, kAXChildrenAttribute, &children) == kAXErrorSuccess && children) {
        for (id child in (__bridge NSArray *)children)
            CollectElements((__bridge AXUIElementRef)child, depth + 1, match, found);
        CFRelease(children);
    }
}

NSString *ElementLabel(AXUIElementRef el) {
    NSString *label = ElementText(el, kAXTitleAttribute);
    if (!label.length) label = ElementText(el, kAXDescriptionAttribute);
    if (!label.length && [ElementText(el, kAXRoleAttribute) isEqual:@"AXStaticText"])
        label = ElementText(el, kAXValueAttribute);
    return [label stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

BOOL ElementFrame(AXUIElementRef el, CGRect *frame) {
    CFTypeRef position = NULL, size = NULL;
    AXUIElementCopyAttributeValue(el, kAXPositionAttribute, &position);
    AXUIElementCopyAttributeValue(el, kAXSizeAttribute, &size);
    BOOL found = position && size && AXValueGetValue((AXValueRef)position, kAXValueTypeCGPoint, &frame->origin)
                 && AXValueGetValue((AXValueRef)size, kAXValueTypeCGSize, &frame->size);
    if (position) CFRelease(position);
    if (size) CFRelease(size);
    return found;
}

id ControlNamed(pid_t pid, NSString *role, BOOL (^named)(NSString *label)) {
    if (!pid) return nil;
    AXUIElementRef app = AXUIElementCreateApplication(pid);
    CFTypeRef windows = NULL;
    AXUIElementCopyAttributeValue(app, kAXWindowsAttribute, &windows);
    CFRelease(app);
    NSMutableArray *found = [NSMutableArray array];
    for (id window in (__bridge_transfer NSArray *)windows)
        CollectElements((__bridge AXUIElementRef)window, 0, ^BOOL(AXUIElementRef el) {
            if (![ElementText(el, kAXRoleAttribute) isEqual:role]) return NO;
            NSString *label = ElementText(el, kAXTitleAttribute).length ? ElementText(el, kAXTitleAttribute)
                                                                        : ElementText(el, kAXDescriptionAttribute);
            return label && named(label);
        }, found);
    return found.count == 1 ? found[0] : nil;
}
