#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Access to the System Management Controller. Reading needs no special rights. Writing
// needs root, so only the helper calls writeBytes; the app only reads.
@interface KeelSMC : NSObject

+ (nullable instancetype)shared;

// Writes a key whose size matches `data` exactly. NO on any failure.
- (BOOL)writeBytes:(NSData *)data forKey:(NSString *)key;

// The raw bytes of a four-character key, or nil when the key has no data or can't be read.
- (nullable NSData *)bytesForKey:(NSString *)key type:(NSString *_Nullable *_Nullable)type;
// A key of type "flt " as a Double, or NAN.
- (double)floatForKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
