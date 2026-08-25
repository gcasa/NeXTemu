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
    NXTUInt32 _eventCounter;
    NXTUInt32 _eventLatch;
    NXTUInt32 _scr2Value;
    NXTUInt8 _rtcRegisters[64];
    NXTUInt8 _rtcShiftIn;
    NXTUInt8 _rtcShiftOut;
    NXTUInt8 _rtcAddress;
    unsigned int _rtcPhase;
    unsigned int _rtcBitCount;
    BOOL _rtcIsWrite;
    BOOL _rtcDataBit;
    BOOL _rtcPreviousClock;
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
- (void)resetNeXTDevicesForTurbo:(BOOL)turbo;

@end

#endif
