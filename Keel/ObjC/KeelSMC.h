#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Read-only access to the System Management Controller. Reading needs no special rights;
// writing needs root and lives in the helper, not in the app.
@interface KeelSMC : NSObject

+ (nullable instancetype)shared;

// The raw bytes of a four-character key, or nil when the key has no data or can't be read.
- (nullable NSData *)bytesForKey:(NSString *)key type:(NSString *_Nullable *_Nullable)type;
// A key of type "flt " as a Double, or NAN.
- (double)floatForKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
