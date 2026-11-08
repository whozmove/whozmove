// HeldKeys: telling a hold of two keys apart, from looks at which modifier keys are down and at how many keys macOS
// has counted pressed (neither needs a permission, nor says which key you type), and whether you're at the Mac's
// screen. Plain functions, which the tests run.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// How long the keys are held, with no other key pressed meanwhile, before the session comes forward: long enough to
// tell them from a shortcut typed with them (⌥fn⌫ deletes the next word), and well before you've said much.
extern const double kHeldFor;

// The modifier keys a hold is told apart by, left and right alike; Caps Lock and the keypad's mark aren't among them.
extern const CGEventFlags kHeldModifiers;

// A hold of the keys, as looked at again and again: the modifier keys down at the last look, whether the keys are held
// and since when, how many keys macOS had counted pressed as the hold began, and whether it's done with (it counted,
// or a key pressed during it, or another modifier, means it's a shortcut).
typedef struct {
    CGEventFlags last;
    BOOL holding, done, looked;
    double since;
    uint32_t presses, lastPresses;
} Hold;

// One look at the keyboard, at `at` seconds: the modifier keys down now (`now`), and how many keys macOS has counted
// pressed (`presses`). YES the once a hold of `keys` counts: exactly those keys came down, from none or some of them,
// and stayed down for kHeldFor with no other key pressed, nor one pressed since the look before (an arrow or a
// function key, which may set Fn's bit too, came down with them). Letting go of one of them, or another modifier coming
// down, ends the hold; going back to them from more keys doesn't start one.
BOOL HoldLooked(Hold *hold, CGEventFlags now, uint32_t presses, double at, CGEventFlags keys);

// Whether you're on the Mac's screen, unlocked: your session is the one on it, and it isn't locked (macOS's record of
// the session says so in a key it doesn't document).
BOOL OnTheScreen(void);
