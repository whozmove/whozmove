// Audio: what the Mac's sound is doing, from CoreAudio's objects: its devices and, from macOS 14, the processes using
// them. Reading them asks coreaudiod, quickly, and never shows macOS's question about the microphone: only recording
// from one does.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Audio.h"
#import <CoreAudio/CoreAudio.h>

static AudioObjectPropertyAddress Address(AudioObjectPropertySelector selector, AudioObjectPropertyScope scope) {
    return (AudioObjectPropertyAddress){selector, scope, kAudioObjectPropertyElementMain};
}

static UInt32 Number(AudioObjectID object, AudioObjectPropertySelector selector) {
    AudioObjectPropertyAddress address = Address(selector, kAudioObjectPropertyScopeGlobal);
    UInt32 value = 0, size = sizeof value;
    return AudioObjectGetPropertyData(object, &address, 0, NULL, &size, &value) == noErr ? value : 0;
}

// The objects a property of the system lists (its devices, or its processes).
static NSArray<NSNumber *> *Objects(AudioObjectPropertySelector selector) {
    AudioObjectPropertyAddress address = Address(selector, kAudioObjectPropertyScopeGlobal);
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address, 0, NULL, &size) != noErr) return @[];
    NSMutableData *data = [NSMutableData dataWithLength:size];
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, data.mutableBytes) != noErr)
        return @[];
    NSMutableArray<NSNumber *> *objects = [NSMutableArray array];
    const AudioObjectID *ids = data.bytes;
    for (UInt32 i = 0; i < size / sizeof(AudioObjectID); i++) [objects addObject:@(ids[i])];
    return objects;
}

// The devices with an input: the microphones, and anything else sound comes in by.
static NSArray<NSNumber *> *InputDevices(void) {
    NSMutableArray<NSNumber *> *inputs = [NSMutableArray array];
    for (NSNumber *device in Objects(kAudioHardwarePropertyDevices)) {
        AudioObjectPropertyAddress streams = Address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput);
        UInt32 size = 0;
        if (AudioObjectGetPropertyDataSize(device.unsignedIntValue, &streams, 0, NULL, &size) == noErr && size > 0)
            [inputs addObject:device];
    }
    return inputs;
}

BOOL MicrophoneInUse(void) {
    for (NSNumber *device in InputDevices())
        if (Number(device.unsignedIntValue, kAudioDevicePropertyDeviceIsRunningSomewhere)) return YES;
    return NO;
}

NSArray<NSNumber *> *MicrophoneRecorders(void) {
    if (@available(macOS 14.0, *)) {
        NSMutableArray<NSNumber *> *pids = [NSMutableArray array];
        for (NSNumber *process in Objects(kAudioHardwarePropertyProcessObjectList)) {
            if (!Number(process.unsignedIntValue, kAudioProcessPropertyIsRunningInput)) continue;
            pid_t pid = (pid_t)Number(process.unsignedIntValue, kAudioProcessPropertyPID);
            if (pid > 0) [pids addObject:@(pid)];
        }
        return pids;
    }
    return nil;
}

BOOL ProcessPlaysSound(pid_t pid) {
    if (@available(macOS 14.0, *)) {
        AudioObjectPropertyAddress address = Address(kAudioHardwarePropertyTranslatePIDToProcessObject,
                                                     kAudioObjectPropertyScopeGlobal);
        AudioObjectID process = kAudioObjectUnknown;
        UInt32 size = sizeof process;
        if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, sizeof pid, &pid, &size, &process) != noErr
            || process == kAudioObjectUnknown) return NO;
        return Number(process, kAudioProcessPropertyIsRunningOutput) != 0;
    }
    return NO;
}

// One listener for the device list and every input device's running and, from macOS 14, for the list of processes
// using sound and each one's recording: each change has what's listened to brought up to date (a device or a process
// may have come or gone), then `changed` told. A process's own recording is what tells a dictation starting on a
// headset that's already running for its sound; the devices' running is kept for any process macOS doesn't call back
// for. All of it happens on `queue`, the stop too.
dispatch_block_t ListenToMicrophones(dispatch_queue_t queue, dispatch_block_t changed) {
    NSMutableSet<NSNumber *> *devicesHeard = [NSMutableSet set], *processesHeard = [NSMutableSet set];
    __block BOOL stopped = NO;
    __block AudioObjectPropertyListenerBlock listener = nil;
    AudioObjectPropertyAddress devices = Address(kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal);
    AudioObjectPropertyAddress running = Address(kAudioDevicePropertyDeviceIsRunningSomewhere,
                                                 kAudioObjectPropertyScopeGlobal);
    AudioObjectPropertyAddress processes = Address(kAudioHardwarePropertyProcessObjectList,
                                                   kAudioObjectPropertyScopeGlobal);
    AudioObjectPropertyAddress recording = Address(kAudioProcessPropertyIsRunningInput,
                                                   kAudioObjectPropertyScopeGlobal);
    BOOL byProcess = NO;
    if (@available(macOS 14.0, *)) byProcess = YES;
    // Listens to `property` of each of `now`, and no longer to those of `heard` that have gone.
    void (^follow)(NSArray<NSNumber *> *, NSMutableSet<NSNumber *> *, AudioObjectPropertyAddress) =
        ^(NSArray<NSNumber *> *now, NSMutableSet<NSNumber *> *heard, AudioObjectPropertyAddress property) {
            NSSet<NSNumber *> *still = [NSSet setWithArray:now];
            for (NSNumber *gone in heard.allObjects)
                if (![still containsObject:gone]) {
                    AudioObjectRemovePropertyListenerBlock(gone.unsignedIntValue, &property, queue, listener);
                    [heard removeObject:gone];
                }
            for (NSNumber *object in now) {
                if ([heard containsObject:object]) continue;
                if (AudioObjectAddPropertyListenerBlock(object.unsignedIntValue, &property, queue, listener) == noErr)
                    [heard addObject:object];
            }
        };
    listener = ^(UInt32 count, const AudioObjectPropertyAddress *addresses) {
        if (stopped) return;
        for (UInt32 i = 0; i < count; i++) {
            if (addresses[i].mSelector == kAudioHardwarePropertyDevices) follow(InputDevices(), devicesHeard, running);
            if (byProcess && addresses[i].mSelector == kAudioHardwarePropertyProcessObjectList)
                follow(Objects(kAudioHardwarePropertyProcessObjectList), processesHeard, recording);
        }
        changed();
    };
    dispatch_async(queue, ^{
        AudioObjectAddPropertyListenerBlock(kAudioObjectSystemObject, &devices, queue, listener);
        follow(InputDevices(), devicesHeard, running);
        if (!byProcess) return;
        AudioObjectAddPropertyListenerBlock(kAudioObjectSystemObject, &processes, queue, listener);
        follow(Objects(kAudioHardwarePropertyProcessObjectList), processesHeard, recording);
    });
    return ^{
        dispatch_async(queue, ^{
            if (stopped) return;
            stopped = YES;
            AudioObjectRemovePropertyListenerBlock(kAudioObjectSystemObject, &devices, queue, listener);
            if (byProcess)
                AudioObjectRemovePropertyListenerBlock(kAudioObjectSystemObject, &processes, queue, listener);
            follow(@[], devicesHeard, running);
            follow(@[], processesHeard, recording);
            listener = nil;
        });
    };
}
