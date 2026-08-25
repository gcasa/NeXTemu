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

#ifndef NXT_MC68040_H
#define NXT_MC68040_H

#import <Foundation/Foundation.h>
#import "NXTMemory.h"

/** Outcomes from executing one or more processor instructions. */
typedef enum
{
  NXTProcessorResultOK = 0,
  NXTProcessorResultStopped,
  NXTProcessorResultBusError,
  NXTProcessorResultIllegalInstruction,
  NXTProcessorResultInstructionLimit
} NXTProcessorResult;

/** An interpreter for the Motorola MC68040 processor used by NeXT systems. */
@interface NXTMC68040 : NSObject
{
  NXTMemory *_memory;
  NXTUInt32 _dataRegisters[8];
  NXTUInt32 _addressRegisters[8];
  NXTUInt32 _programCounter;
  NXTUInt16 _statusRegister;
  BOOL _stopped;
  NXTProcessorResult _lastResult;
  NXTUInt32 _lastOpcodeAddress;
  NXTUInt16 _lastOpcode;
  NXTUInt64 _instructionsExecuted;
  NXTUInt32 _vectorBaseRegister;
  NXTUInt32 _userStackPointer;
  NXTUInt32 _masterStackPointer;
  NXTUInt32 _interruptStackPointer;
  NXTUInt32 _translationControl;
  NXTUInt32 _userRootPointer;
  NXTUInt32 _supervisorRootPointer;
  NXTUInt8 _fpRegisters[8][12];
  double _fpValues[8];
  BOOL _fpComparisonEqual;
  BOOL _kernelEventCounterMode;
}

/** Initializes a processor connected to the supplied physical-memory bus. */
- (id)initWithMemory:(NXTMemory *)memory;
/** Loads the reset vectors and restores the processor's reset state. */
- (BOOL)reset;
/** Executes one instruction and returns its result. */
- (NXTProcessorResult)step;
/** Executes up to the requested number of instructions. */
- (NXTProcessorResult)runForInstructionCount:(NXTUInt32)count;
/** Returns the selected data register. */
- (NXTUInt32)dataRegister:(unsigned int)index;
/** Returns the selected address register. */
- (NXTUInt32)addressRegister:(unsigned int)index;
/** Returns the current program counter. */
- (NXTUInt32)programCounter;
/** Returns the current status register. */
- (NXTUInt16)statusRegister;
/** Returns whether instruction execution is stopped. */
- (BOOL)isStopped;
/** Returns the result of the most recent instruction. */
- (NXTProcessorResult)lastResult;
/** Returns the address of the most recently decoded opcode. */
- (NXTUInt32)lastOpcodeAddress;
/** Returns the most recently decoded opcode. */
- (NXTUInt16)lastOpcode;
/** Returns the number of instructions executed since reset. */
- (NXTUInt64)instructionsExecuted;

@end

#endif
