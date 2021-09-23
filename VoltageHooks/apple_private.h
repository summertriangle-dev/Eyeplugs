#import <Foundation/Foundation.h>

@interface DNDEventBehaviorResolutionService : NSObject {
    NSString * _clientIdentifier;
}

+ (void)initialize;
+ (id)serviceForClientIdentifier:(id)arg1;

// - (void).cxx_destruct;
- (id)_initWithClientIdentifier:(id)arg1;
- (id)resolveBehaviorForEventDetails:(id)arg1 error:(id*)arg2;

@end
