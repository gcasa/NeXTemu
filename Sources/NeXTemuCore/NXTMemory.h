/*
 * Copyright (C) 2026 Gregory Casamento
 *
 * This file is part of NeXTemu.
 *
 * NeXTemu is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free
 * Software Foundation, either version 3 of the License, or (at your option)
 * any later version.
 *
 * NeXTemu is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
 * more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with NeXTemu.  If not, see <https://www.gnu.org/licenses/>.
 */

#ifndef NXT_MEMORY_H
#define NXT_MEMORY_H

#import <Foundation/Foundation.h>
#import "NXTTypes.h"

/** A contiguous region in the emulated physical address space. */
@interface NXTMemoryRegion : NSObject
{
  NXTUInt32 _baseAddress;
  NXTUInt32 _length;
  BOOL _readOnly;
  NXTUInt8 *_bytes;
}

/** Initializes a region with an address, size, and write-protection state. */
- (id)initWithBaseAddress:(NXTUInt32)baseAddress
                   length:(NXTUInt32)length
                 readOnly:(BOOL)readOnly;
/** Returns the first physical address mapped by the region. */
- (NXTUInt32)baseAddress;
/** Returns the size of the region in bytes. */
- (NXTUInt32)length;
/** Returns whether writes to the region are prohibited. */
- (BOOL)isReadOnly;
/** Returns whether the complete address range lies inside the region. */
- (BOOL)containsAddress:(NXTUInt32)address length:(NXTUInt32)length;
/** Returns the region's mutable backing store. */
- (NXTUInt8 *)mutableBytes;

@end

/** The NeXT machine's sparse physical-memory bus and device register map. */
@interface NXTMemory : NSObject
{
  NSMutableArray *_regions;
  NXTUInt32 _eventCounter;
  NXTUInt32 _eventLatch;
  BOOL _kernelEventCounterMode;
  NXTUInt32 _mmuTranslationControl;
  NXTUInt32 _mmuUserRootPointer;
  NXTUInt32 _mmuSupervisorRootPointer;
  BOOL _mmuBypassTranslation;
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
  NXTUInt8 _espDMAControl;
  NXTUInt8 _scsiDMAPack[16];
  unsigned int _scsiDMAPackSize;
  NXTUInt8 _scsiPhase;
  NXTUInt8 _scsiStatus;
  BOOL _scsiSelectionTimeout;
  BOOL _scsiBusResetPending;
  NXTUInt32 _scsiBusResetDelay;
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

/** Adds a non-overlapping region to the physical address space. */
- (BOOL)addRegion:(NXTMemoryRegion *)region;
/** Finds the region containing the complete requested address range. */
- (NXTMemoryRegion *)regionContainingAddress:(NXTUInt32)address
                                      length:(NXTUInt32)length;
/** Reads an 8-bit value from a physical address. */
- (NXTMemoryResult)readByte:(NXTUInt8 *)value atAddress:(NXTUInt32)address;
/** Reads a big-endian 16-bit value from a physical address. */
- (NXTMemoryResult)readWord:(NXTUInt16 *)value atAddress:(NXTUInt32)address;
/** Reads a big-endian 32-bit value from a physical address. */
- (NXTMemoryResult)readLong:(NXTUInt32 *)value atAddress:(NXTUInt32)address;
/** Writes an 8-bit value to a physical address. */
- (NXTMemoryResult)writeByte:(NXTUInt8)value atAddress:(NXTUInt32)address;
/** Writes a big-endian 16-bit value to a physical address. */
- (NXTMemoryResult)writeWord:(NXTUInt16)value atAddress:(NXTUInt32)address;
/** Writes a big-endian 32-bit value to a physical address. */
- (NXTMemoryResult)writeLong:(NXTUInt32)value atAddress:(NXTUInt32)address;
/** Copies data into mapped memory, including read-only ROM regions. */
- (NXTMemoryResult)loadData:(NSData *)data atAddress:(NXTUInt32)address;
/** Resets the emulated NeXT device registers for the selected machine. */
- (void)resetNeXTDevicesForTurbo:(BOOL)turbo;
/** Enables or disables firmware verbose-boot behavior. */
- (void)setVerboseBoot:(BOOL)verbose;
/** Selects the kernel-compatible event-counter behavior. */
- (void)setKernelEventCounterMode;
/** Updates the supervisor MMU registers used for kernel virtual addresses. */
- (void)setMMUTranslationControl:(NXTUInt32)control
                 userRootPointer:(NXTUInt32)userRootPointer
           supervisorRootPointer:(NXTUInt32)rootPointer;
/** Reads values through the user MMU translation tree. */
- (NXTMemoryResult)readByte:(NXTUInt8 *)value
              atUserAddress:(NXTUInt32)address;
- (NXTMemoryResult)readWord:(NXTUInt16 *)value
              atUserAddress:(NXTUInt32)address;
- (NXTMemoryResult)readLong:(NXTUInt32 *)value
              atUserAddress:(NXTUInt32)address;
/** Writes values through the user MMU translation tree. */
- (NXTMemoryResult)writeByte:(NXTUInt8)value
               atUserAddress:(NXTUInt32)address;
- (NXTMemoryResult)writeWord:(NXTUInt16)value
               atUserAddress:(NXTUInt32)address;
- (NXTMemoryResult)writeLong:(NXTUInt32)value
               atUserAddress:(NXTUInt32)address;
/** Returns the highest pending, unmasked interrupt level. */
- (unsigned int)pendingInterruptLevel;
/** Attaches a raw SCSI disk image and reports a failure message if needed. */
- (BOOL)attachSCSIDiskAtPath:(NSString *)path error:(NSString **)errorMessage;

@end

#endif
