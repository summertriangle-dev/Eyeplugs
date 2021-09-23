#import <Foundation/Foundation.h>

extern void *VoltageNotificationIconOverride;

@class NCNotificationRequest;

@interface VoltageSuppressionSession : NSObject

@property NSUInteger suppressedCount;
@property NSUInteger suppressedHPPCount;

@property (strong) NSMutableOrderedSet *senderBundleIdentifiers;
@property (strong) NSBundle *bundleForTranslations;

@property BOOL isSuppressing;
@property BOOL isLogging;
@property BOOL hasMoreSenders;
@property BOOL supportsDND;
@property int notificationInterfaceVariant;

@property (readonly) BOOL wantsNativeDND;

@property (strong) NSUserDefaults *prefs;

- (BOOL) shouldSuppressNotificationsInApplication:(NSString *)bundleID;

- (void) logSuppressedBulletin:(id /* BBBulletin */)bbb;
- (void) logSuppressedNotification:(id /* NCNotificationRequest */)req withSystemDNDState:(BOOL)isDND;

- (void) beginLoggingSuppressedNotifications;
- (void) stopLoggingSuppressedNotifications;

- (void) beginSuppressingBanners;
- (void) stopSuppressingBanners;
- (void) sendStatisticsNotificationIfWanted;
- (void) resetStatistics;

// debug only!!
- (void) _sendStatisticsNotification;

@end
