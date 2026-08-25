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

#ifndef NXT_MACHINE_H
#define NXT_MACHINE_H

#import <Foundation/Foundation.h>
#import "NXTMC68040.h"

/** NeXT hardware configurations supported by the emulator. */
typedef enum
{
  NXTMachineModelNeXTcube = 0,
  NXTMachineModelNeXTcubeTurbo
} NXTMachineModel;

/** Composes the processor, memory, ROM, RAM, and devices of a NeXT machine. */
@interface NXTMachine : NSObject
{
  NXTMachineModel _model;
  NXTMemory *_memory;
  NXTMC68040 *_processor;
  NXTMemoryRegion *_romRegion;
  NXTMemoryRegion *_romAliasRegion;
  NXTMemoryRegion *_ramRegion;
  NSString *_diskImagePath;
  NXTUInt64 _diskImageSize;
}

/** Initializes a machine model with the requested amount of RAM. */
- (id)initWithModel:(NXTMachineModel)model ramSize:(NXTUInt32)ramSize;
/** Loads a 128 KiB NeXT ROM image and reports a failure message if needed. */
- (BOOL)loadROMAtPath:(NSString *)path error:(NSString **)errorMessage;
/** Resets the complete machine and begins execution at the ROM reset vector.
 */
- (BOOL)reset;
/** Enables or disables verbose firmware booting. */
- (void)setVerboseBoot:(BOOL)verbose;
/** Attaches a raw disk image to the emulated SCSI bus. */
- (BOOL)attachDiskImageAtPath:(NSString *)path error:(NSString **)errorMessage;
/** Returns the path of the attached disk image, or nil if none is attached. */
- (NSString *)diskImagePath;
/** Returns the attached disk image's size in bytes. */
- (NXTUInt64)diskImageSize;
/** Executes up to the requested number of processor instructions. */
- (NXTProcessorResult)runForInstructionCount:(NXTUInt32)count;
/** Returns the machine's hardware model. */
- (NXTMachineModel)model;
/** Returns the processor clock rate in megahertz. */
- (unsigned int)clockSpeedMHz;
/** Returns the machine's physical-memory bus. */
- (NXTMemory *)memory;
/** Returns the machine's processor. */
- (NXTMC68040 *)processor;

@end

#endif
