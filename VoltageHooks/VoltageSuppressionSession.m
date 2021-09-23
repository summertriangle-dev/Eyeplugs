#include <dlfcn.h>
#include <objc/runtime.h>
#import <UIKit/UIKit.h>
#import "VoltageSuppressionSession.h"

#ifndef IS_BUILD_FOR_SIMULATOR
#define IS_BUILD_FOR_SIMULATOR 0
#endif

#if IS_BUILD_FOR_SIMULATOR
#warning "This is a simulator build, don't release it."
#define MY_PREFERENCE_BUNDLE_PATH (@"/opt/simject/Library/PreferenceBundles/VoltagePreferences.bundle")
#else
#define MY_PREFERENCE_BUNDLE_PATH (@"/Library/PreferenceBundles/VoltagePreferences.bundle")
#endif

void *VoltageNotificationIconOverride = &VoltageNotificationIconOverride;

@class NCMutableNotificationOptions,
       NCMutableNotificationContent,
       NCMutableNotificationRequest;

// @interface NCMutableNotificationContent : NSObject
// - (void)setIcon:(UIImage *)img;
// @end;

@implementation VoltageSuppressionSession

- (instancetype) init {
    if (self = [super init]) {
        self.senderBundleIdentifiers = [[NSMutableOrderedSet alloc] init];
        self.bundleForTranslations = [[NSBundle alloc] initWithPath:MY_PREFERENCE_BUNDLE_PATH];
        self.prefs = [[NSUserDefaults alloc] initWithSuiteName:@"ca.kirara.Voltage.preferences"];
        if (NSClassFromString(@"DNDStateService")) {
            self.supportsDND = YES;
        }
        self.notificationInterfaceVariant = 0;
    }
    return self;
}

- (NSString *)translateString:(NSString *)key {
    if (!self.bundleForTranslations) {
        return key;
    }
    return [self.bundleForTranslations localizedStringForKey:key value:nil table:@"VoltageInSpringBoard"];
}

- (void) logSuppressedBulletin:(id)bbb {
    if (!self.isLogging && ![self.prefs boolForKey:@"native-dnd"]) {
        NSLog(@"VoltageSuppressionSession: not bumping the count because DND enabled (LEGACY BEHAVIOUR)");
        return;
    }

    [self _observeNotificationFromBundleID:[bbb sectionID]];
}

- (void) logSuppressedNotification:(id)req withSystemDNDState:(BOOL)isDND {
    if (isDND && ![self.prefs boolForKey:@"native-dnd"]) {
        NSLog(@"VoltageSuppressionSession: not bumping the count because source told us quiet mode was enabled");
        return;
    }

    [self _observeNotificationFromBundleID:[req sectionIdentifier]];
}

- (void) _observeNotificationFromBundleID:(NSString *)bundle {
    // Never log the sticky DND notification.
    if ([bundle isEqualToString:@"com.apple.donotdisturb"]) {
        return;
    }

    self.suppressedCount++;

    if ([self.senderBundleIdentifiers count] < 5) {
        if (bundle) {
            [self.senderBundleIdentifiers addObject:bundle];
        }
    } else {
        self.hasMoreSenders = 1;
    }
}

- (BOOL) shouldSuppressNotificationsInApplication:(NSString *)bundleID {
#if IS_BUILD_FOR_SIMULATOR
    NSArray *hardcodeBundles = @[@"com.apple.mobilesafari", @"com.apple.MobileSMS"];

    if ([hardcodeBundles containsObject:bundleID]) {
        return YES;
    }
    return NO;
#else
    if (!bundleID) return NO;

    if ([self.prefs boolForKey:[@"Suppress-" stringByAppendingString:bundleID]]) {
        return YES;
    }

    return NO;
#endif
}

- (void) beginLoggingSuppressedNotifications {
    self.isLogging = YES;
}

- (void) stopLoggingSuppressedNotifications {
    self.isLogging = NO;
}

- (void) beginSuppressingBanners {
    NSLog(@"VoltageSuppressionSession: beginSuppressingBanners");
    [self enterDoNotDisturb];
    self.isSuppressing = YES;
}

- (void) stopSuppressingBanners {
    NSLog(@"VoltageSuppressionSession: stopSuppressingBanners");
    self.isSuppressing = NO;
    [self exitDoNotDisturb];
}

- (void) sendStatisticsNotificationIfWanted {
    NSUserDefaults *defs = [[NSUserDefaults alloc] initWithSuiteName:@"ca.kirara.Voltage.preferences"];
    BOOL send;
    if ([defs objectForKey:@"send-summary"] != nil) {
        send = [defs boolForKey:@"send-summary"];
    } else {
        send = YES;
    }
    [defs release];

    if (self.suppressedCount > 0 && send) {
        [self _sendStatisticsNotification];
    }
}

- (NSString *)awayNotificationTitle {
    return [self translateString:@"While you were away..."];
}

- (NSString *)awayNotificationBodyText {
    if (self.suppressedCount == 0) {
        return @"1 notification was sent by... you. This is a test.";
    }

    NSString *fragStart = [self translateString:@"TL_BODY_START_FRAGMENT"];
    NSString *fmtCount;
    if (self.suppressedCount == 0) {
        fmtCount = [self translateString:@"TL_BODY_ZERO_NOTIFICATIONS"];
    } else if (self.suppressedCount == 1) {
        fmtCount = [self translateString:@"TL_BODY_ONE_NOTIFICATION"];
    } else {
        fmtCount = [self translateString:@"TL_BODY_SEVERAL_NOTIFICATIONS"];
    }
    NSString *fmtAppList = [self translateString:@"TL_BODY_APP_LIST_FRAGMENT"];
    NSString *fragEnd = [self translateString:@"TL_BODY_END_FRAGMENT"];

    return [NSString stringWithFormat:@"%@%@ %@%@",
        fragStart,
        [NSString stringWithFormat:fmtCount, (unsigned long)self.suppressedCount],
        [NSString stringWithFormat:fmtAppList, [self _suppressedSenderListAsString]],
        fragEnd];
}

- (void) _sendStatisticsNotification {
    Class haveNotificationRequest = NSClassFromString(@"NCNotificationRequest");
    if (haveNotificationRequest) {
        [self _sendStatisticsNotificationWithUserNotificationsKitPresent];
    } else {
        [self _sendStatisticsNotificationWithoutUserNotificationsKitPresentAndHideTitle:NO];
    }
}

- (void) _sendStatisticsNotificationWithoutUserNotificationsKitPresentAndHideTitle:(BOOL)hideTitle {
    Class _BBBulletinRequest = NSClassFromString(@"BBBulletinRequest");
    Class _SBBulletinBannerController = NSClassFromString(@"SBBulletinBannerController");

    id bulletin = [[_BBBulletinRequest alloc] init];

    if (!hideTitle) {
        [bulletin setSectionID:@"com.apple.springboard"];
    } else {
        [bulletin setSectionID:@""];
    }

    if (!hideTitle) {
        [bulletin setTitle:[self awayNotificationTitle]];
    } else {
        [bulletin setTitle:@""];
    }

    [bulletin setMessage:[self awayNotificationBodyText]];
    [bulletin setDate:[NSDate date]];

    NSBundle *prefs_bundle = [NSBundle bundleWithPath:MY_PREFERENCE_BUNDLE_PATH];
    UIImage *image = [UIImage imageNamed:@"cSummaryNotificationIcon" inBundle:prefs_bundle compatibleWithTraitCollection:nil];
    objc_setAssociatedObject(bulletin, VoltageNotificationIconOverride, image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    id controller = [_SBBulletinBannerController sharedInstance];
    if ([controller respondsToSelector:@selector(observer:addBulletin:forFeed:playLightsAndSirens:withReply:)]) {
        [controller observer:nil addBulletin:bulletin forFeed:2 playLightsAndSirens:YES withReply:nil];
    } else if ([controller respondsToSelector:@selector(observer:addBulletin:forFeed:)]) {
        [controller observer:nil addBulletin:bulletin forFeed:2];
    }

    [bulletin release];
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincompatible-pointer-types"
/* the compiler gets confused when we send messages to id */

- (void) _sendStatisticsNotificationWithUserNotificationsKitPresent {
    Class _SpringBoard = NSClassFromString(@"SpringBoard");
    id destination = [[[_SpringBoard sharedApplication] notificationDispatcher] bannerDestination];

    NSBundle *prefs_bundle = [NSBundle bundleWithPath:MY_PREFERENCE_BUNDLE_PATH];
    UIImage *image = [UIImage imageNamed:@"cSummaryNotificationIcon" inBundle:prefs_bundle compatibleWithTraitCollection:nil];

    Class _NCNotificationRequest = NSClassFromString(@"NCNotificationRequest");
    Class _NCMutableNotificationOptions = NSClassFromString(@"NCMutableNotificationOptions");

    // this makes it work somehow
    id req = [[_NCNotificationRequest notificationRequestWithSectionId:@"ca.kirara.voltage.CatchupNotification"
            notificationId:@"VoltageSuppressionSessionStatisticsNotification"
                  threadId:@"a thread"
                     title:[self awayNotificationTitle]
                   message:[self awayNotificationBodyText]
                 timestamp:[NSDate date]
               destination:destination] mutableCopy];

    id /* NCMutableNotificationOptions */ opt = [[_NCMutableNotificationOptions alloc] init];
    [opt setDismissAutomatically:YES];
    [opt setOverridesQuietMode:YES];
    // maybe later...
    // if ([opt respondsToSelector:@selector(setPrefersDarkAppearance:)]) {
    //     [opt setPrefersDarkAppearance:YES];
    // }

    id /* NCMutableNotificationContent */ mct = [[req content] mutableCopy];
    [mct setIcon:image];

    [req setOptions:opt];
    [opt release];

    [req setContent:mct];
    [mct release];

    if (!self.notificationInterfaceVariant) {
        if ([destination respondsToSelector:@selector(postNotificationRequest:forCoalescedNotification:)]) {
            self.notificationInterfaceVariant = 1;
        } else {
            self.notificationInterfaceVariant = 2;
        }
    }

    NSLog(@"VoltageHooks: about to send a summary notification.");
    switch(self.notificationInterfaceVariant) {
    case 1: [destination postNotificationRequest:req forCoalescedNotification:nil]; break;
    case 2: [destination postNotificationRequest:req]; break;
    }

    [req release];
}

#pragma clang diagnostic pop

- (NSString *) _controller:(id)controller displayNameFromBundle:(NSString *)cfbundleid {
    NSString *name = [[controller applicationWithBundleIdentifier:cfbundleid] displayName];
    if (name) {
        return name;
    } else {
        return cfbundleid;
    }
}

// "App"
// "App" and "App2"
// "App", "App2", and "App3"
// "App", "App2", "App3", and more
- (NSString *) _suppressedSenderListAsString {
    Class _SBApplicationController = NSClassFromString(@"SBApplicationController");
    id controller = [_SBApplicationController sharedInstance];

    NSString *fmtOneApp = [self translateString:@"TL_APP_LIST_ONLY_ONE"];
    NSString *fmtTwoApps = [self translateString:@"TL_APP_LIST_ONLY_TWO"];
    NSString *fmtManyJoiner = [self translateString:@"TL_APP_LIST_MANY_FRAGMENT"];
    NSString *fmtManyLastJoiner = [self translateString:@"TL_APP_LIST_MANY_FRAGMENT_LAST"];
    NSString *fmtMany = [self translateString:@"TL_APP_LIST_MANY_MORE_END"];

    switch ([self.senderBundleIdentifiers count]) {
        case 1:
            return [NSString stringWithFormat:fmtOneApp, [self _controller:controller displayNameFromBundle:self.senderBundleIdentifiers.firstObject]];
        case 2:
            // kinda bungy but avoids the awkward 'were sent by "bundle1", and "bundle2"'
            return [NSString stringWithFormat:fmtTwoApps,
                [self _controller:controller displayNameFromBundle:self.senderBundleIdentifiers[0]],
                [self _controller:controller displayNameFromBundle:self.senderBundleIdentifiers[1]]];
    }

    NSMutableString *sb = [@"" mutableCopy];
    NSUInteger cnt_m_1 = [self.senderBundleIdentifiers count] - 1;

    [[self.senderBundleIdentifiers array] enumerateObjectsUsingBlock:^(NSString *appB, NSUInteger idx, BOOL *stop) {
        NSString *appN = [self _controller:controller displayNameFromBundle:appB];
        if (idx == cnt_m_1 && !self.hasMoreSenders) {
            [sb appendString:[NSString stringWithFormat:fmtManyLastJoiner, appN]];
        } else {
            [sb appendString:[NSString stringWithFormat:fmtManyJoiner, appN]];
        }
    }];

    if (self.hasMoreSenders) {
        NSString *final = [NSString stringWithFormat:fmtMany, sb];
        [sb release];
        return final;
    }

    return [sb autorelease];
}

- (void) resetStatistics {
    NSMutableOrderedSet *sbi = [[NSMutableOrderedSet alloc] init];
    [_senderBundleIdentifiers release];
    _senderBundleIdentifiers = sbi;

    self.suppressedCount = 0;
    self.suppressedHPPCount = 0;
    self.hasMoreSenders = NO;
}

- (void) dealloc {
    [_senderBundleIdentifiers release];
    _senderBundleIdentifiers = nil;

    [_bundleForTranslations release];
    _bundleForTranslations = nil;

    [self.prefs release];
    _prefs = nil;

    [super dealloc];
}

#pragma mark - DND

- (BOOL) wantsNativeDND {
    // return NO;
    return (self.supportsDND && [self.prefs boolForKey:@"native-dnd"]);
}

- (void) enterDoNotDisturb {
    if (!self.supportsDND) {
        return;
    }

    if (![self.prefs boolForKey:@"native-dnd"]) {
        return;
    }

    NSError *error = nil;

    id serv = [NSClassFromString(@"DNDStateService") serviceForClientIdentifier:@"com.apple.donotdisturb.control-center.module"];
    id state = [serv queryCurrentStateWithError:&error];
    if (error) {
        NSLog(@"VoltageHooks: error getting DND state: %@", error);
    } else {
        NSLog(@"VoltageHooks: current state: %@", state);
        if ([state willSuppressInterruptions]) {
            NSLog(@"VoltageHooks: already in DND, bailing");
            return;
        }
    }

    id theService = [NSClassFromString(@"DNDModeAssertionService") serviceForClientIdentifier:@"com.apple.donotdisturb.control-center.module"];
    id lifetime = [NSClassFromString(@"DNDModeAssertionLifetime") lifetimeForUserRequest];
    id details = [NSClassFromString(@"DNDModeAssertionDetails") detailsWithIdentifier:@"ca.kirara.voltage.AppSession" modeIdentifier:@"com.apple.donotdisturb.mode.default" lifetime:lifetime];
    error = nil;
    id ret = [theService takeModeAssertionWithDetails:details error:&error];
    NSLog(@"VoltageSS asserted DND: %@ error %@", ret, error);
}

- (void) exitDoNotDisturb {
    if (!self.supportsDND) {
        return;
    }

    if (![self.prefs boolForKey:@"native-dnd"]) {
        return;
    }

    id theService = [NSClassFromString(@"DNDModeAssertionService") serviceForClientIdentifier:@"com.apple.donotdisturb.control-center.module"];
    NSError *error = nil;
    id currentAssertion = [theService activeModeAssertionWithError:&error];

    if (currentAssertion) {
        if ([[[currentAssertion details] identifier] isEqualToString:@"ca.kirara.voltage.AppSession"]) {
            error = nil;
            [theService invalidateActiveModeAssertionWithError:&error];
        } else {
            NSLog(@"VoltageSS: Not invalidating assertion: %@", currentAssertion);
        }
    }
}

@end
