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
    BOOL _kernelEventCounterMode;
    NXTUInt32 _scr2Value;
    NXTUInt8 _rtcRegisters[64];
    NXTUInt32 _rtcSeconds;
    NXTUInt8 _rtcShiftIn;
    NXTUInt8 _rtcShiftOut;
    NXTUInt8 _rtcAddress;
    unsigned int _rtcPhase;
    unsigned int _rtcBitCount;
    BOOL _rtcIsWrite;
    BOOL _rtcDataBit;
    BOOL _rtcPreviousClock;
    NSFileHandle *_scsiFile;
    NXTUInt64 _scsiSize;
    NXTUInt8 _espRegisters[16];
    NXTUInt8 _espFIFO[32];
    unsigned int _espFIFOCount;
    NXTUInt8 _espInterrupt;
    NXTUInt8 _scsiPhase;
    NXTUInt8 _scsiStatus;
    NSData *_scsiData;
    NSUInteger _scsiDataOffset;
    NXTUInt32 _dmaRegisters[9];
    NXTUInt8 _dmaState;
    NXTUInt8 _dmaCSR[12];
    NXTUInt8 _enetRegisters[16];
    NXTUInt32 _bmapRegisters[16];
    NXTUInt32 _adbRegisters[35];
    NXTUInt8 _sccRegisterPointer[2];
    NXTUInt8 _sccRegisters[2][16];
    NXTUInt8 _sccReceiveData[2];
    BOOL _sccReceiveAvailable[2];
    NXTUInt32 _interruptStatus;
    NXTUInt32 _interruptMask;
    unsigned int _scsiInterruptDelay;
    BOOL _verboseBoot;
    NXTUInt16 _hardclockStaging;
    NXTUInt16 _hardclockReload;
    NXTUInt8 _hardclockCSR;
    unsigned int _hardclockTicks;
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
- (void)setVerboseBoot:(BOOL)verbose;
- (void)setKernelEventCounterMode;
- (unsigned int)pendingInterruptLevel;
- (BOOL)attachSCSIDiskAtPath:(NSString *)path error:(NSString **)errorMessage;

@end

#endif
