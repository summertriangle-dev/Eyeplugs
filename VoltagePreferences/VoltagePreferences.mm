@interface PSListController : UIViewController {
	NSArray *_specifiers;
}
- (id)loadSpecifiersFromPlistName:(id)arg1 target:(id)arg2;
- (void)removeSpecifier:(id)arg1 animated:(BOOL)arg2;
- (void)setPreferenceValue:(id)arg1 specifier:(id)arg2;
- (void)removeSpecifierAtIndex:(int)arg1 animated:(BOOL)arg2;
- (void)addSpecifier:(id)arg1 animated:(BOOL)arg2;
@end

@interface VoltagePreferencesListController: PSListController
@end

@implementation VoltagePreferencesListController
- (id)specifiers {
    if (_specifiers == nil) {
        NSMutableArray *pspecs = [[self loadSpecifiersFromPlistName:@"VoltagePreferences" target:self] mutableCopy];
        NSPredicate *filter = [NSPredicate predicateWithBlock:^BOOL(id specifier, id bindings) {
            if ([[specifier identifier] hasPrefix:@"TL_NATIVE_DND"]) {
                return NO;
            }
            return YES;
        }];

        if (![[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){12, 0, 0}]) {
            [pspecs filterUsingPredicate:filter];
        }
        _specifiers = pspecs;
    }
    return _specifiers;
}

- (void)voltageprefsOpenPayPalLink:(id)specifier {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://paypal.me/triangularservices"] options:@{} completionHandler:nil];
}

- (void)voltageprefsTestSummaryNotification:(id)specifier {
    CFNotificationCenterRef centre = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterPostNotification(centre, CFSTR("ca.kirara.Voltage.519C730E-3F9E-461E-9C88-E574D7CCD787"), NULL, NULL, YES);
}
@end

// vim:ft=objc
