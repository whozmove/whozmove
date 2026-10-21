// AppleEvents: naming an app's properties, sending it Apple events, and whether macOS lets Whozmove.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "AppleEvents.h"
#import <CoreServices/CoreServices.h>

NSAppleEventDescriptor *AppleEventProperty(FourCharCode code, NSAppleEventDescriptor *of) {
    NSAppleEventDescriptor *spec = [NSAppleEventDescriptor recordDescriptor];
    [spec setDescriptor:[NSAppleEventDescriptor descriptorWithTypeCode:cProperty] forKeyword:keyAEDesiredClass];
    [spec setDescriptor:[NSAppleEventDescriptor descriptorWithEnumCode:formPropertyID] forKeyword:keyAEKeyForm];
    [spec setDescriptor:[NSAppleEventDescriptor descriptorWithTypeCode:code] forKeyword:keyAEKeyData];
    [spec setDescriptor:of ?: NSAppleEventDescriptor.nullDescriptor forKeyword:keyAEContainer];
    return [spec coerceToDescriptorType:typeObjectSpecifier];
}

NSAppleEventDescriptor *AppleEventEvery(FourCharCode cls, NSAppleEventDescriptor *of) {
    OSType all = kAEAll;
    NSAppleEventDescriptor *spec = [NSAppleEventDescriptor recordDescriptor];
    [spec setDescriptor:[NSAppleEventDescriptor descriptorWithTypeCode:cls] forKeyword:keyAEDesiredClass];
    [spec setDescriptor:[NSAppleEventDescriptor descriptorWithEnumCode:formAbsolutePosition] forKeyword:keyAEKeyForm];
    [spec setDescriptor:[NSAppleEventDescriptor descriptorWithDescriptorType:typeAbsoluteOrdinal bytes:&all
                                                                      length:sizeof all]
             forKeyword:keyAEKeyData];
    [spec setDescriptor:of ?: NSAppleEventDescriptor.nullDescriptor forKeyword:keyAEContainer];
    return [spec coerceToDescriptorType:typeObjectSpecifier];
}

NSAppleEventDescriptor *AskQuietly(pid_t pid, NSAppleEventDescriptor *specifier, NSTimeInterval timeout) {
    NSAppleEventDescriptor *event =
        [NSAppleEventDescriptor appleEventWithEventClass:kAECoreSuite eventID:kAEGetData
                                        targetDescriptor:[NSAppleEventDescriptor descriptorWithProcessIdentifier:pid]
                                                returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
    [event setParamDescriptor:specifier forKeyword:keyDirectObject];
    NSAppleEventDescriptor *reply =
        [event sendEventWithOptions:NSAppleEventSendWaitForReply | NSAppleEventSendNeverInteract
                                    | (NSAppleEventSendOptions)kAEDoNotPromptForUserConsent
                            timeout:timeout error:nil];
    if (!reply || [reply paramDescriptorForKeyword:keyErrorNumber].int32Value) return nil;
    return [reply paramDescriptorForKeyword:keyDirectObject];
}

NSArray<NSString *> *AskEvery(pid_t pid, FourCharCode cls, FourCharCode property, NSAppleEventDescriptor *of,
                              NSTimeInterval timeout) {
    NSAppleEventDescriptor *list = AskQuietly(pid, AppleEventProperty(property, AppleEventEvery(cls, of)), timeout);
    if (!list) return nil;
    if (list.descriptorType != typeAEList) return @[list.stringValue ?: @""];
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    for (NSInteger i = 1; i <= list.numberOfItems; i++)
        [values addObject:[list descriptorAtIndex:i].stringValue ?: @""];
    return values;
}

NSAppleEventDescriptor *SendAppleEvent(pid_t pid, AEEventClass eventClass, AEEventID eventId,
                                       NSAppleEventDescriptor *object, NSAppleEventDescriptor *data,
                                       NSTimeInterval timeout, OSStatus *status) {
    NSAppleEventDescriptor *event = [NSAppleEventDescriptor
        appleEventWithEventClass:eventClass eventID:eventId
                targetDescriptor:[NSAppleEventDescriptor descriptorWithProcessIdentifier:pid]
                        returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
    if (object) [event setParamDescriptor:object forKeyword:keyDirectObject];
    if (data) [event setParamDescriptor:data forKeyword:keyAEData];
    NSError *error = nil;
    NSAppleEventDescriptor *reply = [event sendEventWithOptions:NSAppleEventSendDefaultOptions timeout:timeout
                                                          error:&error];
    OSStatus failed = reply ? [reply paramDescriptorForKeyword:keyErrorNumber].int32Value : (OSStatus)error.code;
    if (!reply && !failed) failed = errAEEventFailed;
    if (failed) {
        *status = failed;
        return nil;
    }
    return [reply paramDescriptorForKeyword:keyDirectObject] ?: NSAppleEventDescriptor.nullDescriptor;
}

OSStatus AutomationPermission(pid_t pid, BOOL ask) {
    NSAppleEventDescriptor *target = [NSAppleEventDescriptor descriptorWithProcessIdentifier:pid];
    return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask);
}
