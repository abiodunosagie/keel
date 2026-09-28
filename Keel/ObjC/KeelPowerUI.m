#import "KeelPowerUI.h"

// Selectors verified on macOS 27.0 (26A428) with class_copyMethodList.
@interface PowerUISmartChargeClient : NSObject
- (instancetype)initWithClientName:(NSString *)name;
- (BOOL)isMCLSupported;
- (unsigned long long)isMCLCurrentlyEnabled:(NSError **)error;
- (unsigned char)getMCLLimitWithError:(NSError **)error;
- (BOOL)enableMCL:(NSError **)error;
- (BOOL)disableMCL:(NSError **)error;
- (BOOL)setMCLLimit:(unsigned char)limit error:(NSError **)error;
@end

static NSString *const KeelPowerUIErrorDomain = @"com.abiodunosagie.Keel.PowerUI";

@implementation KeelPowerUI {
  PowerUISmartChargeClient *_client;
}

+ (NSInteger)minimumLimit { return 80; }
+ (NSInteger)maximumLimit { return 100; }

+ (nullable instancetype)shared {
  static KeelPowerUI *shared = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSBundle *bundle = [NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/PowerUI.framework"];
    if (![bundle load]) { return; }
    Class clientClass = NSClassFromString(@"PowerUISmartChargeClient");
    SEL required[] = {
      @selector(initWithClientName:), @selector(isMCLSupported), @selector(isMCLCurrentlyEnabled:),
      @selector(getMCLLimitWithError:), @selector(enableMCL:), @selector(disableMCL:),
      @selector(setMCLLimit:error:)
    };
    for (size_t i = 0; i < sizeof(required) / sizeof(required[0]); i++) {
      if (![clientClass instancesRespondToSelector:required[i]]) { return; }
    }
    PowerUISmartChargeClient *client = [[clientClass alloc] initWithClientName:@"Keel"];
    if (client == nil) { return; }
    shared = [[KeelPowerUI alloc] init];
    shared->_client = client;
  });
  return shared;
}

// Calls are serialized: the client is shared between the main thread and background writes,
// and nothing documents PowerUISmartChargeClient as thread-safe.
- (BOOL)isSupported {
  @synchronized (self) {
    return [_client isMCLSupported];
  }
}

- (nullable NSNumber *)limitEnabled:(NSError **)error {
  NSError *failure = nil;
  unsigned long long enabled;
  @synchronized (self) {
    enabled = [_client isMCLCurrentlyEnabled:&failure];
  }
  if (failure) {
    if (error) { *error = failure; }
    return nil;
  }
  return @(enabled == 1);
}

- (nullable NSNumber *)limitPercent:(NSError **)error {
  NSError *failure = nil;
  unsigned char limit;
  @synchronized (self) {
    limit = [_client getMCLLimitWithError:&failure];
  }
  if (failure) {
    if (error) { *error = failure; }
    return nil;
  }
  return @(limit);
}

- (BOOL)setLimit:(NSInteger)percent error:(NSError **)error {
  if (percent < KeelPowerUI.minimumLimit || percent > KeelPowerUI.maximumLimit) {
    if (error) {
      *error = [NSError errorWithDomain:KeelPowerUIErrorDomain code:1 userInfo:@{
        NSLocalizedDescriptionKey: [NSString stringWithFormat:@"macOS accepts charge limits from %ld to %ld%%.",
                                    (long)KeelPowerUI.minimumLimit, (long)KeelPowerUI.maximumLimit]
      }];
    }
    return NO;
  }
  if (percent == KeelPowerUI.maximumLimit) {
    return [self disableLimit:error];
  }
  @synchronized (self) {
    // A failed read counts as "off", which only costs a harmless extra enableMCL.
    if ([_client isMCLCurrentlyEnabled:nil] != 1 && ![_client enableMCL:error]) {
      return NO;
    }
    return [_client setMCLLimit:(unsigned char)percent error:error];
  }
}

- (BOOL)disableLimit:(NSError **)error {
  @synchronized (self) {
    return [_client disableMCL:error];
  }
}

@end
