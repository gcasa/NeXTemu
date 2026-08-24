#ifndef NXT_MEMORY_H
#define NXT_MEMORY_H

#import <Foundation/Foundation.h>
#import "NXTTypes.h"

@interface NXTMemoryRegion : NSObject
{
    NXTUInt32 _baseAddress;
    NXTUInt32 _length;
    BOOL _readOnly;
    NXTUInt8 *_bytes;
}

- (id)initWithBaseAddress:(NXTUInt32)baseAddress
                   length:(NXTUInt32)length
                 readOnly:(BOOL)readOnly;
- (NXTUInt32)baseAddress;
- (NXTUInt32)length;
- (BOOL)isReadOnly;
- (BOOL)containsAddress:(NXTUInt32)address length:(NXTUInt32)length;
- (NXTUInt8 *)mutableBytes;

@end

@interface NXTMemory : NSObject
{
    NSMutableArray *_regions;
}

- (BOOL)addRegion:(NXTMemoryRegion *)region;
- (NXTMemoryRegion *)regionContainingAddress:(NXTUInt32)address
                                      length:(NXTUInt32)length;
- (NXTMemoryResult)readByte:(NXTUInt8 *)value atAddress:(NXTUInt32)address;
- (NXTMemoryResult)readWord:(NXTUInt16 *)value atAddress:(NXTUInt32)address;
- (NXTMemoryResult)readLong:(NXTUInt32 *)value atAddress:(NXTUInt32)address;
- (NXTMemoryResult)writeByte:(NXTUInt8)value atAddress:(NXTUInt32)address;
- (NXTMemoryResult)writeWord:(NXTUInt16)value atAddress:(NXTUInt32)address;
- (NXTMemoryResult)writeLong:(NXTUInt32)value atAddress:(NXTUInt32)address;
- (NXTMemoryResult)loadData:(NSData *)data atAddress:(NXTUInt32)address;

@end

#endif
