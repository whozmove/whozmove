// Shortcut: ⌃⌥N from any app, which brings up the panel's box for a new conversation.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Shortcut.h"
#import <Carbon/Carbon.h>
#import "Log.h"

@interface Shortcut ()
@property (copy) void (^pressed)(void);
@end

@implementation Shortcut {
    EventHotKeyRef _key;
    EventHandlerRef _handler;
}

// macOS calls this on the main thread when the keys are pressed; the shortcut is the handler's data.
static OSStatus Pressed(EventHandlerCallRef next, EventRef event, void *data) {
    Shortcut *shortcut = (__bridge Shortcut *)data;
    if (shortcut.pressed) shortcut.pressed();
    return noErr;
}

- (instancetype)initWithAction:(void (^)(void))pressed {
    if (!(self = [super init])) return nil;
    self.pressed = pressed;
    EventTypeSpec type = {kEventClassKeyboard, kEventHotKeyPressed};
    InstallEventHandler(GetApplicationEventTarget(), NewEventHandlerUPP(Pressed), 1, &type, (__bridge void *)self,
                        &_handler);
    return self;
}

- (void)setOn:(BOOL)on {
    if (on == _on) return;
    _on = on;
    if (on) {
        EventHotKeyID id = {'wzmv', 1};
        OSStatus status = RegisterEventHotKey(kVK_ANSI_N, controlKey | optionKey, id, GetApplicationEventTarget(), 0,
                                              &_key);
        // Another app may have ⌃⌥N already; the menu still opens the box.
        if (status != noErr) PanelLog(@"⌃⌥N not available (%d): another app may have it", (int)status);
    } else if (_key) {
        UnregisterEventHotKey(_key);
        _key = NULL;
    }
}

- (void)dealloc {
    if (_key) UnregisterEventHotKey(_key);
    if (_handler) RemoveEventHandler(_handler);
}

@end
