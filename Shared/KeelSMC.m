#import "KeelSMC.h"
#import <IOKit/IOKitLib.h>

// The AppleSMC user client's call layout (selector 2, one 80-byte struct in and out).
typedef struct {
  char major, minor, build, reserved;
  UInt16 release;
} KeelSMCVersion;

typedef struct {
  UInt16 version, length;
  UInt32 cpuPLimit, gpuPLimit, memPLimit;
} KeelSMCPLimit;

typedef struct {
  UInt32 dataSize;
  UInt32 dataType;
  UInt8 dataAttributes;
} KeelSMCKeyInfo;

typedef struct {
  UInt32 key;
  KeelSMCVersion vers;
  KeelSMCPLimit pLimitData;
  KeelSMCKeyInfo keyInfo;
  UInt8 result;
  UInt8 status;
  UInt8 data8;
  UInt32 data32;
  UInt8 bytes[32];
} KeelSMCParam;

_Static_assert(sizeof(KeelSMCParam) == 80, "AppleSMC expects an 80-byte parameter block");

static const uint32_t KeelSMCSelector = 2;
static const UInt8 KeelSMCReadBytes = 5;
static const UInt8 KeelSMCWriteBytes = 6;
static const UInt8 KeelSMCReadKeyInfo = 9;

static UInt32 KeelFourCC(NSString *string) {
  const char *chars = string.UTF8String;
  if (chars == NULL || strlen(chars) != 4) { return 0; }
  return ((UInt32)(UInt8)chars[0] << 24) | ((UInt32)(UInt8)chars[1] << 16) |
         ((UInt32)(UInt8)chars[2] << 8) | (UInt32)(UInt8)chars[3];
}

static NSString *KeelFourCCString(UInt32 value) {
  char chars[5] = {(char)(value >> 24), (char)(value >> 16), (char)(value >> 8), (char)value, 0};
  return [NSString stringWithUTF8String:chars] ?: @"";
}

@implementation KeelSMC {
  io_connect_t _connection;
  NSLock *_lock;
}

+ (nullable instancetype)shared {
  static KeelSMC *shared = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (service == IO_OBJECT_NULL) { return; }
    io_connect_t connection = IO_OBJECT_NULL;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &connection);
    IOObjectRelease(service);
    if (result != KERN_SUCCESS) { return; }
    shared = [[KeelSMC alloc] init];
    shared->_connection = connection;
    shared->_lock = [[NSLock alloc] init];
  });
  return shared;
}

- (BOOL)call:(KeelSMCParam *)input output:(KeelSMCParam *)output {
  size_t outputSize = sizeof(KeelSMCParam);
  kern_return_t result = IOConnectCallStructMethod(_connection, KeelSMCSelector, input, sizeof(KeelSMCParam),
                                                   output, &outputSize);
  return result == KERN_SUCCESS && output->result == 0;
}

- (nullable NSData *)bytesForKey:(NSString *)key type:(NSString **)type {
  UInt32 code = KeelFourCC(key);
  if (code == 0) { return nil; }
  [_lock lock];
  KeelSMCParam input = {0}, output = {0};
  input.key = code;
  input.data8 = KeelSMCReadKeyInfo;
  if (![self call:&input output:&output] || output.keyInfo.dataSize == 0 || output.keyInfo.dataSize > 32) {
    [_lock unlock];
    return nil;
  }
  KeelSMCKeyInfo info = output.keyInfo;
  memset(&input, 0, sizeof(input));
  memset(&output, 0, sizeof(output));
  input.key = code;
  input.keyInfo.dataSize = info.dataSize;
  input.data8 = KeelSMCReadBytes;
  BOOL ok = [self call:&input output:&output];
  [_lock unlock];
  if (!ok) { return nil; }
  if (type) { *type = KeelFourCCString(info.dataType); }
  return [NSData dataWithBytes:output.bytes length:info.dataSize];
}

- (BOOL)writeBytes:(NSData *)data forKey:(NSString *)key {
  UInt32 code = KeelFourCC(key);
  if (code == 0 || data.length == 0 || data.length > 32) { return NO; }
  [_lock lock];
  KeelSMCParam input = {0}, output = {0};
  input.key = code;
  input.data8 = KeelSMCReadKeyInfo;
  if (![self call:&input output:&output] || output.keyInfo.dataSize != data.length) {
    [_lock unlock];
    return NO;
  }
  KeelSMCKeyInfo info = output.keyInfo;
  memset(&input, 0, sizeof(input));
  memset(&output, 0, sizeof(output));
  input.key = code;
  input.keyInfo = info;
  input.data8 = KeelSMCWriteBytes;
  memcpy(input.bytes, data.bytes, data.length);
  BOOL ok = [self call:&input output:&output];
  [_lock unlock];
  return ok;
}

- (double)floatForKey:(NSString *)key {
  NSString *type = nil;
  NSData *data = [self bytesForKey:key type:&type];
  if (data.length != sizeof(float) || ![type isEqualToString:@"flt "]) { return NAN; }
  float value;
  memcpy(&value, data.bytes, sizeof(float));
  return value;
}

@end
