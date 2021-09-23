#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import <libkern/OSAtomic.h>
#import <UIKit/UIKit.h>
#import "VoltageSuppressionSession.h"

static char __rcsid[] = "VoltageHooks.x (c) 2017-2019 The Holy Constituency of the Summer Triangle. All rights reserved.";

VoltageSuppressionSession *_VSS;
BOOL voltageWillPresentSummaryNotificationAfterLockScreen;
BOOL voltageWatchForwardEnabled;
int voltageDNDEnabled = -1;

NSArray *_voltageWhitelistedApps = nil;

void alloc_and_set_vss(void) {
    VoltageSuppressionSession *vss = [[VoltageSuppressionSession alloc] init];
    _VSS = vss;
}

BOOL voltage_bulletin_request_is_whitelisted(id bulletinrequest) {
    if ([_voltageWhitelistedApps containsObject:[bulletinrequest sectionID]]) {
        return YES;
    }
    return NO;
}

BOOL voltage_request_is_whitelisted(id request) {
#if IS_BUILD_FOR_SIMULATOR
    if ([[request sectionIdentifier] hasPrefix:@"ca.kirara"]) {
        return YES;
    }
#else
    if ([_voltageWhitelistedApps containsObject:[request sectionIdentifier]]) {
        return YES;
    }
#endif
    return NO;
}

void voltage_tag_whitelisted_request(id request) {
    static Ivar overridesQuietModeIvar = NULL;
    static dispatch_once_t haveOverridesQuietModeIvar = 0;
    dispatch_once(&haveOverridesQuietModeIvar, ^{
       overridesQuietModeIvar = class_getInstanceVariable(%c(NCNotificationOptions), "_overridesQuietMode");
    });

    id options = (id)[request options];
    if ([options respondsToSelector:@selector(setOverridesQuietMode:)]) {
        [options setOverridesQuietMode:YES];
    } else {
        object_setIvar(options, overridesQuietModeIvar, (id)YES);
    }
}

void voltage_tag_whitelisted_bulletin(id bulletin) {
    [bulletin setIgnoresQuietMode:YES];
}

static void voltage_set_dnd_state(BOOL is_dnd) {
    if (is_dnd) {
        NSLog(@"VoltageHooks: Do Not Disturb has been enabled!");
        [_VSS stopLoggingSuppressedNotifications];
        voltageDNDEnabled = 1;
    } else {
        NSLog(@"VoltageHooks: Do Not Disturb has been disabled!");
        [_VSS beginLoggingSuppressedNotifications];
        voltageDNDEnabled = 0;
    }
}

static BOOL voltage_check_dnd_state(void) {
    if (voltageDNDEnabled > -1) {
        return voltageDNDEnabled;
    }

    Class dss = %c(DNDStateService);
    if (dss) {
        id serv = [dss serviceForClientIdentifier:@"com.apple.springboard.donotdisturb.notifications"];
        NSError *error;
        id state = [serv queryCurrentStateWithError:&error];
        if (state) {
            voltage_set_dnd_state((BOOL)[state willSuppressInterruptions]);
        } else {
            NSLog(@"VoltageHooks: can't get initial DND state: %@", error);
            voltage_set_dnd_state(NO);
        }
        return voltageDNDEnabled;
    }

    id sb = [UIApplication sharedApplication];
    if ([sb respondsToSelector:@selector(notificationDispatcher)]) {
        id aggregator = [[sb notificationDispatcher] quietModeStateAggregator];
        voltage_set_dnd_state((BOOL)[aggregator isQuietModeEnabledAndActive]);
        return voltageDNDEnabled;
    }

    // always works on iOS 9 because of BBSettingsGateway
    return voltageDNDEnabled;
}

%group iOS_12

%hook DNDEventBehaviorResolutionService

- (BOOL)sb_shouldSuppressNotificationRequest:(id /* NCNotificationRequest * */)arg1 {
    static Ivar clientIdIvar = NULL;
    static dispatch_once_t haveClientIdentifierIvar = 0;
    dispatch_once(&haveClientIdentifierIvar, ^{
       clientIdIvar = class_getInstanceVariable(%c(DNDEventBehaviorResolutionService), "_clientIdentifier");
    });

    if ([_VSS isSuppressing] && [object_getIvar(self, clientIdIvar) isEqualToString:@"com.apple.springboard.SBNotificationBannerDestination"]) {
        if (voltage_request_is_whitelisted(arg1) || [[arg1 sectionIdentifier] isEqualToString:@"ca.kirara.voltage.CatchupNotification"]) {
            NSLog(@"VoltageHooks: whitelisted request in sb_shouldSuppressNotificationRequest");
            return %orig(arg1);
        } else {
            NSLog(@"VoltageHooks: going to return YES from sb_shouldSuppressNotificationRequest");
            return YES;
        }
    }

    return %orig(arg1);
}

%end

%hook DNDStateService

- (void)remoteService:(id)arg1 didReceiveDoNotDisturbStateUpdate:(id)arg2 {
    %orig;

    if ([[self clientIdentifier] isEqualToString:@"com.apple.springboard.donotdisturb.notifications"]) {
        voltage_set_dnd_state((BOOL)[(id)[arg2 state] willSuppressInterruptions]);
        if (!(BOOL)[(id)[arg2 state] isActive] && (int)[arg2 reason] == 3) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([_VSS shouldSuppressNotificationsInApplication:[[[UIApplication sharedApplication] _accessibilityFrontMostApplication] bundleIdentifier]]) {
                    [_VSS enterDoNotDisturb];
                }
            });
        }
    }
}

%end

%hook SBNotificationBannerDestination
- (void) postNotificationRequest:(id)arg1 forCoalescedNotification:(id)arg2 {
    [self voltage_commonHookForNotificationRequest:arg1];
    %orig(arg1, arg2);
}

- (void) postNotificationRequest:(id)arg1 {
    [self voltage_commonHookForNotificationRequest:arg1];
    %orig(arg1);
}

%new
- (void)voltage_commonHookForNotificationRequest:(id)arg1 {
    if ([_VSS isSuppressing]) {
        if (voltage_request_is_whitelisted(arg1)) {
            // Technically we don't have to do this on iOS 12, but do it anyway so it'll crash if it would on 11/10 too.
            NSLog(@"VoltageHooks: tagging this notification that should override quiet mode: %@.", arg1);
            voltage_tag_whitelisted_request(arg1);
        } else {
            NSLog(@"VoltageHooks: logging suppressed notification.");

            // Our service is hooked so we need to steal someone else's.
            id service = [%c(DNDEventBehaviorResolutionService) serviceForClientIdentifier:@"com.apple.springboard.SBNCScreenController"];
            [service sb_checkSuppressionForNotificationRequest:arg1 andPerformBlockOnMainThread:^(NSUInteger suppress) {
                NSLog(@"VoltageHooks Late DND check returns %ld", (long)suppress);
                [_VSS logSuppressedNotification:arg1 withSystemDNDState:suppress & 0x1];
            }];
        }
    }
}
%end
%end

%group iOS_10

%hook SBQuietModeStateAggregator

- (void)observer:(id)arg1 noteAlertBehaviorOverridesChanged:(NSUInteger)arg2 {
    %orig;
    voltage_set_dnd_state((BOOL)[self isQuietModeEnabledAndActive]);
}

- (void)observer:(id)arg1 noteAlertBehaviorOverrideStateChanged:(NSUInteger)arg2 {
    %orig;
    voltage_set_dnd_state((BOOL)[self isQuietModeEnabledAndActive]);
}

%end

%hook SBNotificationBannerDestination

- (BOOL) _isQuietModeEnabledAndActive {
    if ([_VSS isSuppressing]) {
        NSLog(@"VoltageHooks: suppressing, returning yes for _isQuietModeEnabledAndActive");
        return YES;
    } else {
        return %orig();
    }
}

- (void) postNotificationRequest:(id)arg1 forCoalescedNotification:(id)arg2 {
    if ([_VSS isSuppressing]) {
        if (voltage_request_is_whitelisted(arg1)) {
            NSLog(@"VoltageHooks: tagging this notification that should override quiet mode: %@.", arg1);
            voltage_tag_whitelisted_request(arg1);
        } else {
            NSLog(@"VoltageHooks: logging suppressed notification.");
            BOOL isQuietMode = (BOOL)[[self quietModeStateAggregator] isQuietModeEnabledAndActive];
            [_VSS logSuppressedNotification:arg1 withSystemDNDState:isQuietMode];
        }
    }

    %orig(arg1, arg2);
}

%end
    
%hook BBSettingsGateway

/* XXX: no longer called as of iOS 11 */
- (void) behaviorOverrideStatusChanged:(long long)arg1 source:(unsigned long long)arg2 {
    %orig(arg1, arg2);
    voltage_set_dnd_state((arg2 & 1)? YES : NO);
}

%end
%end // iOS_10

%group iOS_9
%hook SBBulletinBannerController

#define SET_QUIET_MODE_IVAR_ON_SELF(x) *(BOOL *)((uint8_t *)self + quietModeIvarOffset) = (x);
#define READ_QUIET_MODE_IVAR_ON_SELF() (*(BOOL *)((uint8_t *)self + quietModeIvarOffset));

-(void) _queueBulletin:(id)arg1 {
    static uintptr_t quietModeIvarOffset = 0;
    if (!quietModeIvarOffset) {
        Ivar iv = class_getInstanceVariable([self class], "_quietModeEnabled");

        if (!iv) {
            NSLog(@"VoltageHooks: WARNING: cannot find the _quietModeEnabled ivar");

            /* we don't want to kill springboard */
            return %orig(arg1);
        }

        quietModeIvarOffset = ivar_getOffset(iv);
    }

    BOOL save = READ_QUIET_MODE_IVAR_ON_SELF();

    if ([_VSS isSuppressing]) {
        if (voltage_bulletin_request_is_whitelisted(arg1)) {
            NSLog(@"VoltageHooks: tagging this notification that should override quiet mode (LEGACY): %@.", arg1);
            voltage_tag_whitelisted_bulletin(arg1);
        } else {
            NSLog(@"VoltageHooks: suppressing, wrapping _queueBulletin");

            SET_QUIET_MODE_IVAR_ON_SELF(YES);
            %orig(arg1);
            SET_QUIET_MODE_IVAR_ON_SELF(save);

            NSLog(@"VoltageHooks: logging suppressed notification.");
            [_VSS logSuppressedBulletin:arg1];
        }
    } else {
        %orig(arg1);
    }
}

%end

%hook BBSettingsGateway

/* XXX: no longer called as of iOS 11 */
- (void) behaviorOverrideStatusChanged:(long long)arg1 source:(unsigned long long)arg2 {
    %orig(arg1, arg2);
    voltage_set_dnd_state((arg2 & 1)? YES : NO);
}

%end
%end // iOS_9

%group Any

%hook SBBulletinLocalObserverGateway

- (void)observer:(id)arg1 addBulletin:(id)arg2 forFeed:(NSUInteger)arg3 playLightsAndSirens:(BOOL)arg4 withReply:(void (^)(BOOL))arg5 {
    if ([_VSS isSuppressing] && voltageWatchForwardEnabled) {
        // This is funky... if we respond NO it will never go through the normal machinery, so
        // we'll log it and make whitelist decisions here too.
        if (voltage_bulletin_request_is_whitelisted(arg2)) {
            // Go to the normal notification machinery.
            return %orig;
        } else {
            // Otherwise log it, and go directly to the watch.
            // NSLog(@"VoltageHooks: logging *early* suppressed notification.");
            if (voltage_check_dnd_state() && ![_VSS wantsNativeDND]) {
                // DND is enabled outside of our control. Do the normal behaviour
                // Don't even bother logging it...
                // [_VSS logSuppressedBulletin:arg2];
                %orig;
            } else {
                // DND may be enabled within our control, so forward to watch.
                [_VSS logSuppressedBulletin:arg2];
                %orig(arg1, arg2, arg3, arg4, ^(BOOL unused) { arg5(NO); });
            }
        }
    } else {
        return %orig;
    }
}

%end

%hook BBBulletinRequest

- (UIImage *) sectionIconImageWithFormat:(int)aformat {
    UIImage *img = objc_getAssociatedObject(self, VoltageNotificationIconOverride);

    if (img) {
        NSLog(@"VoltageHooks: sectionIconImageWithFormat: returning our cool icon");
        return img;
    } else {
        return %orig(aformat);
    }
}

%end

%hook SpringBoard

static void VoltageSendTestNotification(void);

- (void) frontDisplayDidChange:(id)arg1 {
    %orig(arg1);

    if (!_VSS) {
        NSLog(@"VoltageHooks: it's too early for me to operate");
        return;
    }

    BOOL shouldSuppress;

    if (![arg1 isKindOfClass:%c(SBApplication)]) {
        shouldSuppress = NO;
    } else {
        shouldSuppress = [_VSS shouldSuppressNotificationsInApplication:[arg1 bundleIdentifier]];
    }

    if (!shouldSuppress) {
        BOOL mightSendNotification = voltageWillPresentSummaryNotificationAfterLockScreen? YES : NO;

        if ([_VSS isSuppressing]) {
            [_VSS stopSuppressingBanners];
            mightSendNotification = YES;
        }

        if (mightSendNotification) {
            if ([arg1 isKindOfClass:%c(SBDashBoardViewController)] || [arg1 isKindOfClass:%c(SBLockScreenViewController)]) {
                // then we shall present it later
                NSLog(@"VoltageHooks: front display did change to lock screen");
                voltageWillPresentSummaryNotificationAfterLockScreen = YES;
            } else {
                // or we shall present it now
                dispatch_async(dispatch_get_main_queue(), ^{
                    [_VSS sendStatisticsNotificationIfWanted];
                    [_VSS resetStatistics];
                    voltageWillPresentSummaryNotificationAfterLockScreen = NO;
                });
            }
        }
    } else if (![_VSS isSuppressing]) {
        if (!voltageWillPresentSummaryNotificationAfterLockScreen) {
            [_VSS resetStatistics];
        }

        [_VSS beginSuppressingBanners];
    }
}

%end
%end

static void VoltageSendTestNotification(void) {
    [_VSS _sendStatisticsNotification];
}

static void VoltageReloadDynamicPreferences(void) {
    NSUserDefaults *defs = [[NSUserDefaults alloc] initWithSuiteName:@"ca.kirara.Voltage.preferences"];

    NSMutableArray *whitelistBundles = @[].mutableCopy;
    NSDictionary *everything = defs.dictionaryRepresentation;
    for (NSString *key in everything.allKeys) {
        if ([key hasPrefix:@"Whitelist-"] && [defs boolForKey:key]) {
            [whitelistBundles addObject:[key substringFromIndex:10]];
        }
    }

    int ok = 0;
    for (int i = 0; i < 3; ++i) {
        NSArray *old = _voltageWhitelistedApps;
        if (OSAtomicCompareAndSwapPtr(old, whitelistBundles, (void **)&_voltageWhitelistedApps)) {
            [old release];
            ok = true;
            break;
        }
    }
    if (!ok) {
        NSLog(@"VoltageHooks: You must be doing something wild because I tried three times to replace the whitelist but failed. Oh well, I'll try again next time you change a setting.");
        [whitelistBundles release];
    }

    if ([defs objectForKey:@"dont-suppress-watch"] != nil) {
        voltageWatchForwardEnabled = [defs boolForKey:@"dont-suppress-watch"];
    } else {
        voltageWatchForwardEnabled = YES;
    }
    [defs release];

    NSLog(@"VoltageHooks: reloaded preferences: dont-suppress-watch %d", voltageWatchForwardEnabled);
}

%ctor {
    NSLog(@"VoltageHooks loading.");
    voltageWillPresentSummaryNotificationAfterLockScreen = NO;

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        (CFNotificationCallback)VoltageSendTestNotification,
        CFSTR("ca.kirara.Voltage.519C730E-3F9E-461E-9C88-E574D7CCD787"),
        NULL,
        CFNotificationSuspensionBehaviorCoalesce);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        (CFNotificationCallback)VoltageReloadDynamicPreferences,
        CFSTR("ca.kirara.Voltage.dynamic-preference-changed"),
        NULL,
        CFNotificationSuspensionBehaviorCoalesce);
    VoltageReloadDynamicPreferences();
    alloc_and_set_vss();

    if (NSClassFromString(@"DNDEventBehaviorResolutionService")) {
        NSLog(@"VoltageHooks: DoNotDisturb framework present.");
        %init(iOS_12);
    } else if (kCFCoreFoundationVersionNumber >= 1348) {
        NSLog(@"VoltageHooks: installing iOS 10+ hooks.");
        %init(iOS_10);
    } else {
        NSLog(@"VoltageHooks: installing iOS 9 hooks.");
        %init(iOS_9);
    }
    %init(Any);
}
