#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The macOS charge limit ("Manual Charge Limit" in PowerUI.framework, macOS 26.4 and later).
// PowerUI is a private framework, so it is loaded at runtime and never linked. Every call
// goes to powerd over XPC and blocks, so call these off the main thread.
@interface KeelPowerUI : NSObject

@property (class, readonly) NSInteger minimumLimit;
@property (class, readonly) NSInteger maximumLimit;

// Nil when PowerUI or its charge limit client is missing on this macOS.
+ (nullable instancetype)shared;

- (BOOL)isSupported;
// Boxed so Swift sees these as throwing: nil means powerd returned an error.
// YES or NO.
- (nullable NSNumber *)limitEnabled:(NSError **)error;
// The limit in percent. 100 when no limit is set.
- (nullable NSNumber *)limitPercent:(NSError **)error;
// Turns the limit on at `percent`. Refuses values outside minimumLimit...maximumLimit:
// PowerUI crashes the calling process below 80.
- (BOOL)setLimit:(NSInteger)percent error:(NSError **)error;
- (BOOL)disableLimit:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
