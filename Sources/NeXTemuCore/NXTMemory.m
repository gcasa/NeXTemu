#import "NXTMemory.h"
#include <string.h>

@implementation NXTMemoryRegion

- (id)initWithBaseAddress:(NXTUInt32)baseAddress
                   length:(NXTUInt32)length
                 readOnly:(BOOL)readOnly
{
    self = [super init];
    if (self != nil) {
        if (length == 0) {
            [self release];
            return nil;
        }
        _bytes = (NXTUInt8 *)calloc((size_t)length, sizeof(NXTUInt8));
        if (_bytes == NULL) {
            [self release];
            return nil;
        }
        _baseAddress = baseAddress;
        _length = length;
        _readOnly = readOnly;
    }
    return self;
}

- (void)dealloc
{
    free(_bytes);
    [super dealloc];
}

- (NXTUInt32)baseAddress { return _baseAddress; }
- (NXTUInt32)length { return _length; }
- (BOOL)isReadOnly { return _readOnly; }
- (NXTUInt8 *)mutableBytes { return _bytes; }

- (BOOL)containsAddress:(NXTUInt32)address length:(NXTUInt32)length
{
    NXTUInt64 start;
    NXTUInt64 end;
    NXTUInt64 regionEnd;

    start = (NXTUInt64)address;
    end = start + (NXTUInt64)length;
    regionEnd = (NXTUInt64)_baseAddress + (NXTUInt64)_length;
    return length > 0 && start >= _baseAddress && end <= regionEnd;
}

@end

@implementation NXTMemory

- (id)init
{
    self = [super init];
    if (self != nil) {
        _regions = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [_regions release];
    [super dealloc];
}

- (BOOL)addRegion:(NXTMemoryRegion *)region
{
    NSUInteger index;
    NXTMemoryRegion *existing;
    NXTUInt64 newStart;
    NXTUInt64 newEnd;
    NXTUInt64 oldStart;
    NXTUInt64 oldEnd;

    if (region == nil) return NO;
    newStart = [region baseAddress];
    newEnd = newStart + [region length];
    for (index = 0; index < [_regions count]; index++) {
        existing = [_regions objectAtIndex:index];
        oldStart = [existing baseAddress];
        oldEnd = oldStart + [existing length];
        if (newStart < oldEnd && oldStart < newEnd) return NO;
    }
    [_regions addObject:region];
    return YES;
}

- (NXTMemoryRegion *)regionContainingAddress:(NXTUInt32)address
                                      length:(NXTUInt32)length
{
    NSUInteger index;
    NXTMemoryRegion *region;

    for (index = 0; index < [_regions count]; index++) {
        region = [_regions objectAtIndex:index];
        if ([region containsAddress:address length:length]) return region;
    }
    return nil;
}

- (NXTMemoryResult)readByte:(NXTUInt8 *)value atAddress:(NXTUInt32)address
{
    NXTMemoryRegion *region;
    if (value == NULL) return NXTMemoryResultOutOfRange;
    region = [self regionContainingAddress:address length:1];
    if (region == nil) return NXTMemoryResultUnmapped;
    *value = [region mutableBytes][address - [region baseAddress]];
    return NXTMemoryResultOK;
}

- (NXTMemoryResult)readWord:(NXTUInt16 *)value atAddress:(NXTUInt32)address
{
    NXTMemoryRegion *region;
    NXTUInt8 *bytes;
    if (value == NULL) return NXTMemoryResultOutOfRange;
    region = [self regionContainingAddress:address length:2];
    if (region == nil) return NXTMemoryResultUnmapped;
    bytes = [region mutableBytes] + address - [region baseAddress];
    *value = (NXTUInt16)(((NXTUInt16)bytes[0] << 8) | bytes[1]);
    return NXTMemoryResultOK;
}

- (NXTMemoryResult)readLong:(NXTUInt32 *)value atAddress:(NXTUInt32)address
{
    NXTMemoryRegion *region;
    NXTUInt8 *bytes;
    if (value == NULL) return NXTMemoryResultOutOfRange;
    region = [self regionContainingAddress:address length:4];
    if (region == nil) return NXTMemoryResultUnmapped;
    bytes = [region mutableBytes] + address - [region baseAddress];
    *value = ((NXTUInt32)bytes[0] << 24) | ((NXTUInt32)bytes[1] << 16) |
             ((NXTUInt32)bytes[2] << 8) | bytes[3];
    return NXTMemoryResultOK;
}

- (NXTMemoryResult)writeByte:(NXTUInt8)value atAddress:(NXTUInt32)address
{
    NXTMemoryRegion *region;
    region = [self regionContainingAddress:address length:1];
    if (region == nil) return NXTMemoryResultUnmapped;
    if ([region isReadOnly]) return NXTMemoryResultReadOnly;
    [region mutableBytes][address - [region baseAddress]] = value;
    return NXTMemoryResultOK;
}

- (NXTMemoryResult)writeWord:(NXTUInt16)value atAddress:(NXTUInt32)address
{
    NXTMemoryRegion *region;
    NXTUInt8 *bytes;
    region = [self regionContainingAddress:address length:2];
    if (region == nil) return NXTMemoryResultUnmapped;
    if ([region isReadOnly]) return NXTMemoryResultReadOnly;
    bytes = [region mutableBytes] + address - [region baseAddress];
    bytes[0] = (NXTUInt8)(value >> 8);
    bytes[1] = (NXTUInt8)value;
    return NXTMemoryResultOK;
}

- (NXTMemoryResult)writeLong:(NXTUInt32)value atAddress:(NXTUInt32)address
{
    NXTMemoryRegion *region;
    NXTUInt8 *bytes;
    region = [self regionContainingAddress:address length:4];
    if (region == nil) return NXTMemoryResultUnmapped;
    if ([region isReadOnly]) return NXTMemoryResultReadOnly;
    bytes = [region mutableBytes] + address - [region baseAddress];
    bytes[0] = (NXTUInt8)(value >> 24);
    bytes[1] = (NXTUInt8)(value >> 16);
    bytes[2] = (NXTUInt8)(value >> 8);
    bytes[3] = (NXTUInt8)value;
    return NXTMemoryResultOK;
}

- (NXTMemoryResult)loadData:(NSData *)data atAddress:(NXTUInt32)address
{
    NXTMemoryRegion *region;
    NSUInteger length;
    length = [data length];
    if (length > UINT32_MAX) return NXTMemoryResultOutOfRange;
    region = [self regionContainingAddress:address length:(NXTUInt32)length];
    if (region == nil) return NXTMemoryResultUnmapped;
    memcpy([region mutableBytes] + address - [region baseAddress],
           [data bytes], length);
    return NXTMemoryResultOK;
}

@end
