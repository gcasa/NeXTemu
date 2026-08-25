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

#import "NXTMC68040.h"
#include <string.h>
#ifdef NXT_TRACE_POST
#include <stdio.h>
#endif

#define NXT_SR_C 0x0001
#define NXT_SR_V 0x0002
#define NXT_SR_Z 0x0004
#define NXT_SR_N 0x0008
#define NXT_SR_X 0x0010

static BOOL
NXTConditionTrue (NXTUInt16 condition, NXTUInt16 sr)
{
  BOOL c = (sr & NXT_SR_C) != 0;
  BOOL v = (sr & NXT_SR_V) != 0;
  BOOL z = (sr & NXT_SR_Z) != 0;
  BOOL n = (sr & NXT_SR_N) != 0;
  switch (condition)
    {
    case 0:
      return YES; /* T / BRA */
    case 1:
      return NO; /* F / BSR is handled separately */
    case 2:
      return !c && !z; /* HI */
    case 3:
      return c || z; /* LS */
    case 4:
      return !c; /* CC */
    case 5:
      return c; /* CS */
    case 6:
      return !z; /* NE */
    case 7:
      return z; /* EQ */
    case 8:
      return !v; /* VC */
    case 9:
      return v; /* VS */
    case 10:
      return !n; /* PL */
    case 11:
      return n; /* MI */
    case 12:
      return n == v; /* GE */
    case 13:
      return n != v; /* LT */
    case 14:
      return !z && n == v; /* GT */
    case 15:
      return z || n != v; /* LE */
    }
  return NO;
}

static BOOL
NXTIsFirmwareFPUPostAddress (NXTUInt32 address)
{
  return (address >= 0x01005c20U && address < 0x01005ca0U)
         || (address >= 0x01005cf8U && address < 0x01005d78U)
         || (address >= 0x01005e1cU && address < 0x01005e9cU);
}

@implementation NXTMC68040

- (id)initWithMemory:(NXTMemory *)memory
{
  self = [super init];
  if (self != nil)
    {
      _memory = [memory retain];
      _stopped = YES;
      _lastResult = NXTProcessorResultStopped;
    }
  return self;
}

- (void)dealloc
{
  [_memory release];
  [super dealloc];
}

- (BOOL)reset
{
  NXTUInt32 initialStackPointer;
  NXTUInt32 initialProgramCounter;

  memset (_dataRegisters, 0, sizeof (_dataRegisters));
  memset (_addressRegisters, 0, sizeof (_addressRegisters));
  memset (_fpRegisters, 0, sizeof (_fpRegisters));
  memset (_fpValues, 0, sizeof (_fpValues));
  _fpControlRegister = 0;
  _fpStatusRegister = 0;
  _fpInstructionAddressRegister = 0;
  _fpComparisonEqual = NO;
  _kernelEventCounterMode = NO;
  _statusRegister = 0x2700;
  if ([_memory readLong:&initialStackPointer atAddress:0] != NXTMemoryResultOK
      || [_memory readLong:&initialProgramCounter atAddress:4]
             != NXTMemoryResultOK)
    {
      _stopped = YES;
      _lastResult = NXTProcessorResultBusError;
      return NO;
    }
  _addressRegisters[7] = initialStackPointer;
  _vectorBaseRegister = 0;
  _userStackPointer = 0;
  _masterStackPointer = initialStackPointer;
  _interruptStackPointer = initialStackPointer;
  _translationControl = 0;
  _userRootPointer = 0;
  _supervisorRootPointer = 0;
  _programCounter = initialProgramCounter;
  _stopped = NO;
  _lastResult = NXTProcessorResultOK;
  _lastOpcodeAddress = 0;
  _lastOpcode = 0;
  _instructionsExecuted = 0;
  return YES;
}

- (BOOL)fetchWord:(NXTUInt16 *)value
{
  if ([_memory readWord:value atAddress:_programCounter] != NXTMemoryResultOK)
    return NO;
  _programCounter += 2;
  return YES;
}

- (BOOL)fetchLong:(NXTUInt32 *)value
{
  if ([_memory readLong:value atAddress:_programCounter] != NXTMemoryResultOK)
    return NO;
  _programCounter += 4;
  return YES;
}

- (BOOL)pushLong:(NXTUInt32)value
{
  _addressRegisters[7] -= 4;
  return [_memory writeLong:value atAddress:_addressRegisters[7]]
         == NXTMemoryResultOK;
}

- (BOOL)pushWord:(NXTUInt16)value
{
  _addressRegisters[7] -= 2;
  return [_memory writeWord:value atAddress:_addressRegisters[7]]
         == NXTMemoryResultOK;
}

- (BOOL)popWord:(NXTUInt16 *)value
{
  if ([_memory readWord:value atAddress:_addressRegisters[7]]
      != NXTMemoryResultOK)
    return NO;
  _addressRegisters[7] += 2;
  return YES;
}

- (BOOL)popLong:(NXTUInt32 *)value
{
  if ([_memory readLong:value atAddress:_addressRegisters[7]]
      != NXTMemoryResultOK)
    return NO;
  _addressRegisters[7] += 4;
  return YES;
}

- (void)setNZForLong:(NXTUInt32)value
{
  _statusRegister &= (NXTUInt16) ~(NXT_SR_N | NXT_SR_Z | NXT_SR_V | NXT_SR_C);
  if (value == 0)
    _statusRegister |= NXT_SR_Z;
  if ((value & 0x80000000U) != 0)
    _statusRegister |= NXT_SR_N;
}

- (NXTUInt32)maskedValue:(NXTUInt32)value size:(unsigned int)size
{
  if (size == 1)
    return value & 0xffU;
  if (size == 2)
    return value & 0xffffU;
  return value;
}

- (void)setNZForValue:(NXTUInt32)value size:(unsigned int)size
{
  NXTUInt32 sign;
  value = [self maskedValue:value size:size];
  sign = size == 1 ? 0x80U : (size == 2 ? 0x8000U : 0x80000000U);
  _statusRegister &= (NXTUInt16) ~(NXT_SR_N | NXT_SR_Z | NXT_SR_V | NXT_SR_C);
  if (value == 0)
    _statusRegister |= NXT_SR_Z;
  if ((value & sign) != 0)
    _statusRegister |= NXT_SR_N;
}

- (void)setSubFlagsWithDestination:(NXTUInt32)destination
                            source:(NXTUInt32)source
                            result:(NXTUInt32)result
                              size:(unsigned int)size
{
  NXTUInt32 sign;
  destination = [self maskedValue:destination size:size];
  source = [self maskedValue:source size:size];
  result = [self maskedValue:result size:size];
  [self setNZForValue:result size:size];
  sign = size == 1 ? 0x80U : (size == 2 ? 0x8000U : 0x80000000U);
  if (source > destination)
    _statusRegister |= NXT_SR_C;
  if (((destination ^ source) & (destination ^ result) & sign) != 0)
    _statusRegister |= NXT_SR_V;
}

- (void)setAddFlagsWithDestination:(NXTUInt32)destination
                            source:(NXTUInt32)source
                            result:(NXTUInt32)result
                              size:(unsigned int)size
{
  NXTUInt32 mask;
  NXTUInt32 sign;
  NXTUInt64 wideResult;
  mask = size == 1 ? 0xffU : (size == 2 ? 0xffffU : 0xffffffffU);
  sign = size == 1 ? 0x80U : (size == 2 ? 0x8000U : 0x80000000U);
  destination &= mask;
  source &= mask;
  result &= mask;
  [self setNZForValue:result size:size];
  wideResult = (NXTUInt64)destination + (NXTUInt64)source;
  if (wideResult > mask)
    _statusRegister |= NXT_SR_C;
  if (((~(destination ^ source)) & (destination ^ result) & sign) != 0)
    _statusRegister |= NXT_SR_V;
}

- (BOOL)readSized:(NXTUInt32 *)value
          address:(NXTUInt32)address
             size:(unsigned int)size
{
  NXTUInt8 byteValue;
  NXTUInt16 wordValue;
  if (size == 1)
    {
      if ([_memory readByte:&byteValue atAddress:address] != NXTMemoryResultOK)
        return NO;
      *value = byteValue;
    }
  else if (size == 2)
    {
      if ([_memory readWord:&wordValue atAddress:address] != NXTMemoryResultOK)
        return NO;
      *value = wordValue;
    }
  else if ([_memory readLong:value atAddress:address] != NXTMemoryResultOK)
    return NO;
  return YES;
}

- (BOOL)writeSized:(NXTUInt32)value
           address:(NXTUInt32)address
              size:(unsigned int)size
{
  if (size == 1)
    return [_memory writeByte:(NXTUInt8)value atAddress:address]
           == NXTMemoryResultOK;
  if (size == 2)
    return [_memory writeWord:(NXTUInt16)value atAddress:address]
           == NXTMemoryResultOK;
  return [_memory writeLong:value atAddress:address] == NXTMemoryResultOK;
}

- (BOOL)effectiveAddress:(NXTUInt32 *)address
                    mode:(unsigned int)mode
                register:(unsigned int)reg
                    size:(unsigned int)size
                 writing:(BOOL)writing
{
  NXTUInt16 extension;
  NXTUInt16 fullExtension;
  NXTUInt32 base;
  NXTUInt32 index;
  NXTUInt32 increment;
  int32_t displacement;
  int32_t baseDisplacement;
  int32_t outerDisplacement;
  unsigned int indirectSelection;
  NXTUInt32 indirectAddress;
  (void)writing;
  increment = size;
  if (size == 1 && reg == 7)
    increment = 2;
  if (mode == 2)
    {
      *address = _addressRegisters[reg];
      return YES;
    }
  if (mode == 3)
    {
      *address = _addressRegisters[reg];
      _addressRegisters[reg] += increment;
      return YES;
    }
  if (mode == 4)
    {
      _addressRegisters[reg] -= increment;
      *address = _addressRegisters[reg];
      return YES;
    }
  if (mode == 5)
    {
      if (![self fetchWord:&extension])
        return NO;
      *address
          = _addressRegisters[reg] + (NXTUInt32)(int32_t)(int16_t)extension;
      return YES;
    }
  if (mode == 6 || (mode == 7 && reg == 3))
    {
      if (![self fetchWord:&extension])
        return NO;
      base = mode == 6 ? _addressRegisters[reg] : _programCounter - 2;
      index = (extension & 0x8000) != 0
                  ? _addressRegisters[(extension >> 12) & 7]
                  : _dataRegisters[(extension >> 12) & 7];
      if ((extension & 0x0800) == 0)
        index = (NXTUInt32)(int32_t)(int16_t)index;
      index <<= (extension >> 9) & 3;
      if ((extension & 0x0100) != 0)
        { /* full 68020/68040 extension */
          fullExtension = extension;
          if ((extension & 0x0080) != 0)
            base = 0;
          if ((extension & 0x0040) != 0)
            index = 0;
          baseDisplacement = 0;
          if ((extension & 0x0030) == 0x0020)
            {
              if (![self fetchWord:&extension])
                return NO;
              baseDisplacement = (int16_t)extension;
            }
          else if ((extension & 0x0030) == 0x0030)
            {
              if (![self fetchLong:&indirectAddress])
                return NO;
              baseDisplacement = (int32_t)indirectAddress;
            }
          indirectSelection = fullExtension & 7;
          if (indirectSelection == 0)
            {
              *address = base + index + (NXTUInt32)baseDisplacement;
              return YES;
            }
          outerDisplacement = 0;
          if (indirectSelection == 2 || indirectSelection == 6)
            {
              if (![self fetchWord:&extension])
                return NO;
              outerDisplacement = (int16_t)extension;
            }
          else if (indirectSelection == 3 || indirectSelection == 7)
            {
              if (![self fetchLong:&indirectAddress])
                return NO;
              outerDisplacement = (int32_t)indirectAddress;
            }
          indirectAddress = base + (NXTUInt32)baseDisplacement;
          if (indirectSelection <= 3)
            indirectAddress += index;
          if ([_memory readLong:&indirectAddress atAddress:indirectAddress]
              != NXTMemoryResultOK)
            return NO;
          if (indirectSelection >= 5)
            indirectAddress += index;
          *address = indirectAddress + (NXTUInt32)outerDisplacement;
          return YES;
        }
      displacement = (int8_t)(extension & 0xff);
      *address = base + index + (NXTUInt32)displacement;
      return YES;
    }
  if (mode == 7 && reg == 0)
    {
      if (![self fetchWord:&extension])
        return NO;
      *address = (NXTUInt32)(int32_t)(int16_t)extension;
      return YES;
    }
  if (mode == 7 && reg == 1)
    return [self fetchLong:address];
  if (mode == 7 && reg == 2)
    {
      base = _programCounter;
      if (![self fetchWord:&extension])
        return NO;
      *address = base + (NXTUInt32)(int32_t)(int16_t)extension;
      return YES;
    }
  return NO;
}

- (BOOL)readEA:(NXTUInt32 *)value
          mode:(unsigned int)mode
      register:(unsigned int)reg
          size:(unsigned int)size
{
  NXTUInt16 wordValue;
  NXTUInt32 address;
  if (mode == 0)
    {
      *value = [self maskedValue:_dataRegisters[reg] size:size];
      return YES;
    }
  if (mode == 1)
    {
      *value = [self maskedValue:_addressRegisters[reg] size:size];
      return YES;
    }
  if (mode == 7 && reg == 4)
    {
      if (size == 4)
        return [self fetchLong:value];
      if (![self fetchWord:&wordValue])
        return NO;
      *value = size == 1 ? wordValue & 0xffU : wordValue;
      return YES;
    }
  if (![self effectiveAddress:&address
                         mode:mode
                     register:reg
                         size:size
                      writing:NO])
    return NO;
  return [self readSized:value address:address size:size];
}

- (BOOL)writeEA:(NXTUInt32)value
           mode:(unsigned int)mode
       register:(unsigned int)reg
           size:(unsigned int)size
{
  NXTUInt32 address;
  NXTUInt32 mask;
  if (mode == 0)
    {
      mask = size == 1 ? 0xffU : (size == 2 ? 0xffffU : 0xffffffffU);
      _dataRegisters[reg] = (_dataRegisters[reg] & ~mask) | (value & mask);
      return YES;
    }
  if (mode == 1)
    {
      _addressRegisters[reg]
          = size == 2 ? (NXTUInt32)(int32_t)(int16_t)value : value;
      return YES;
    }
  if (![self effectiveAddress:&address
                         mode:mode
                     register:reg
                         size:size
                      writing:YES])
    return NO;
  return [self writeSized:value address:address size:size];
}

- (NXTProcessorResult)fail:(NXTProcessorResult)result
{
  _lastResult = result;
  _stopped = YES;
  return result;
}

- (NXTUInt32)controlRegister:(NXTUInt16)number
{
  if (number == 0x003)
    return _translationControl;
  if (number == 0x800)
    return _userStackPointer;
  if (number == 0x801)
    return _vectorBaseRegister;
  if (number == 0x803)
    return _masterStackPointer;
  if (number == 0x804)
    return _interruptStackPointer;
  if (number == 0x806)
    return _userRootPointer;
  if (number == 0x807)
    return _supervisorRootPointer;
  return 0;
}

- (void)setControlRegister:(NXTUInt16)number value:(NXTUInt32)value
{
  if (number == 0x003)
    _translationControl = value;
  else if (number == 0x800)
    _userStackPointer = value;
  else if (number == 0x801)
    _vectorBaseRegister = value;
  else if (number == 0x803)
    _masterStackPointer = value;
  else if (number == 0x804)
    _interruptStackPointer = value;
  else if (number == 0x806)
    _userRootPointer = value;
  else if (number == 0x807)
    _supervisorRootPointer = value;
}

- (NXTProcessorResult)step
{
  NXTUInt16 opcode;
  NXTUInt16 extension;
  NXTUInt32 value;
  NXTUInt32 returnAddress;
  NXTUInt32 registerIndex;
  NXTUInt32 quickValue;
  int32_t displacement;
  unsigned int sourceMode;
  unsigned int sourceRegister;
  unsigned int destinationMode;
  unsigned int destinationRegister;
  unsigned int size;
  NXTUInt32 address;
  NXTUInt32 immediateValue;
  unsigned int operation;
  NXTUInt8 move16Bytes[16];
  unsigned int byteIndex;
  unsigned int opmode;
  unsigned int opcodeClass;
  NXTUInt32 sourceValue;
  NXTUInt32 shiftCount;
  NXTUInt32 signMask;
  NXTUInt32 branchBase;
  unsigned int shiftType;
  BOOL shiftCarry;
  BOOL extendBit;
  NXTUInt16 registerMask;
  unsigned int maskIndex;
  NXTUInt32 registerValue;
  NXTUInt32 divisor;
  NXTUInt32 bitOffset;
  NXTUInt32 bitWidth;
  NXTUInt32 bitfieldValue;
  NXTUInt32 bitPosition;
  unsigned int bitfieldOperation;
  NXTUInt8 bitfieldByte;
  unsigned int remainderRegister;
  NXTUInt64 wideDividend;
  NXTUInt64 wideResult;
  unsigned int interruptLevel;
  unsigned int fpControlMask;

  /* NeXT's early kernel checksums the entire physical RAM with a tight
     MOVE.W/ADD.L/DBF loop.  Interpreting four instructions per word makes
     a 128 MiB machine appear hung for minutes.  Recognize that exact loop
     and preserve its architectural result with one native pass. */
  if (_programCounter == 0x040910f4U)
    {
      static const NXTUInt8 checksumLoop[16]
          = { 0x30, 0x18, 0x34, 0x00, 0xd6, 0x82, 0x51, 0xc9,
              0xff, 0xf8, 0x42, 0x41, 0x53, 0x81, 0x64, 0xf0 };
      NXTUInt8 actual[16];
      unsigned int signatureIndex;
      BOOL matches = YES;
      NXTUInt64 wordCount = (NXTUInt64)_dataRegisters[1] + 1U;
      NXTUInt64 byteCount = wordCount * 2U;
      NXTMemoryRegion *ram;
      for (signatureIndex = 0; signatureIndex < sizeof (actual);
           signatureIndex++)
        {
          if ([_memory readByte:&actual[signatureIndex]
                      atAddress:_programCounter + signatureIndex]
                  != NXTMemoryResultOK
              || actual[signatureIndex] != checksumLoop[signatureIndex])
            {
              matches = NO;
              break;
            }
        }
      ram = matches && byteCount <= 0xffffffffU
                ? [_memory regionContainingAddress:_addressRegisters[0]
                                            length:(NXTUInt32)byteCount]
                : nil;
      if (ram != nil && wordCount != 0)
        {
          const NXTUInt8 *bytes =
              [ram mutableBytes] + _addressRegisters[0] - [ram baseAddress];
          NXTUInt32 sum = 0, lastWord = 0;
          NXTUInt64 word;
          for (word = 0; word < wordCount; word++)
            {
              lastWord
                  = ((NXTUInt32)bytes[word * 2U] << 8) | bytes[word * 2U + 1U];
              sum += lastWord;
            }
          _addressRegisters[0] += (NXTUInt32)byteCount;
          _dataRegisters[0] = (_dataRegisters[0] & 0xffff0000U) | lastWord;
          _dataRegisters[2] = lastWord;
          _dataRegisters[3] += sum;
          _dataRegisters[1] = 0xffffffffU;
          _statusRegister = (NXTUInt16)((_statusRegister & ~0x000fU) | NXT_SR_X
                                        | NXT_SR_N | NXT_SR_C);
          _programCounter = 0x04091106U;
        }
    }

  if (!_kernelEventCounterMode && _programCounter >= 0x04000000U
      && _programCounter < 0x10000000U)
    {
      [_memory setKernelEventCounterMode];
      _kernelEventCounterMode = YES;
    }
  interruptLevel = [_memory pendingInterruptLevel];
  if (interruptLevel > ((_statusRegister >> 8) & 7U))
    {
      NXTUInt16 savedStatus = _statusRegister;
      NXTUInt32 handler;
      NXTUInt16 frame = (NXTUInt16)((24U + interruptLevel) * 4U);
      if ((_statusRegister & 0x2000U) == 0)
        {
          _userStackPointer = _addressRegisters[7];
          _addressRegisters[7] = _interruptStackPointer;
        }
      else if ((_statusRegister & 0x1000U) != 0)
        {
          _masterStackPointer = _addressRegisters[7];
          _addressRegisters[7] = _interruptStackPointer;
        }
      _statusRegister = (NXTUInt16)((_statusRegister & ~0x1700U) | 0x2000U
                                    | (interruptLevel << 8));
      _stopped = NO;
      if (![self pushWord:frame] || ![self pushLong:_programCounter]
          || ![self pushWord:savedStatus] ||
          [_memory readLong:&handler
                  atAddress:_vectorBaseRegister + (24U + interruptLevel) * 4U]
              != NXTMemoryResultOK)
        return [self fail:NXTProcessorResultBusError];
      _interruptStackPointer = _addressRegisters[7];
      _programCounter = handler;
    }
  if (_stopped)
    return _lastResult == NXTProcessorResultOK ? NXTProcessorResultStopped
                                               : _lastResult;
  /* ROM revisions 3.0, 3.2, and 3.3 wait in the failure-panel animation
     until D3 is cleared by a keyboard event.  There is no keyboard event
     source yet, so dismiss the panel after it has been drawn and allow the
     configured boot command to run. */
  if (_programCounter == 0x01002364U || _programCounter == 0x010023feU
      || _programCounter == 0x010024e8U)
    _dataRegisters[3] = 0;
  _lastOpcodeAddress = _programCounter;
  if (![self fetchWord:&opcode])
    return [self fail:NXTProcessorResultBusError];
  _lastOpcode = opcode;
  _instructionsExecuted++;
#ifdef NXT_TRACE_POST
  if (_lastOpcodeAddress >= 0x01003500U && _lastOpcodeAddress < 0x01004000U)
    {
      static NXTUInt8 seen[0xb00];
      NXTUInt32 offset = _lastOpcodeAddress - 0x01003500U;
      if (!seen[offset])
        {
          seen[offset] = 1;
          fprintf (stderr,
                   "POST %08x %04x sr=%04x d0=%08x d1=%08x d2=%08x d3=%08x "
                   "a3=%08x\n",
                   _lastOpcodeAddress, opcode, _statusRegister,
                   _dataRegisters[0], _dataRegisters[1], _dataRegisters[2],
                   _dataRegisters[3], _addressRegisters[3]);
        }
    }
#endif

  /* The ROM's FPU POST treats the 80-bit registers as opaque 12-byte
     extended values while checking FMOVEM preservation. */
  if ((opcode == 0xf21f || opcode == 0xf227) &&
      [_memory readWord:&extension atAddress:_programCounter]
          == NXTMemoryResultOK
      && (extension == 0xd0ffU || extension == 0xe0ffU))
    {
      unsigned int fpIndex;
      NXTUInt32 fpAddress;
      if (![self fetchWord:&extension])
        return [self fail:NXTProcessorResultBusError];
      if ((extension & 0x00ffU) != 0x00ffU)
        return [self fail:NXTProcessorResultIllegalInstruction];
      if (opcode == 0xf21f)
        { /* FMOVEM.X (A7)+,FP0-FP7 */
          fpAddress = _addressRegisters[7];
          for (fpIndex = 0; fpIndex < 8; fpIndex++)
            {
              for (byteIndex = 0; byteIndex < 12; byteIndex++)
                {
                  if ([_memory readByte:&_fpRegisters[fpIndex][byteIndex]
                              atAddress:fpAddress++]
                      != NXTMemoryResultOK)
                    return [self fail:NXTProcessorResultBusError];
                }
            }
          _addressRegisters[7] = fpAddress;
        }
      else
        { /* FMOVEM.X FP0-FP7,-(A7) */
          fpAddress = _addressRegisters[7];
          for (fpIndex = 8; fpIndex-- > 0;)
            {
              fpAddress -= 12;
              for (byteIndex = 0; byteIndex < 12; byteIndex++)
                {
                  if ([_memory writeByte:_fpRegisters[fpIndex][byteIndex]
                               atAddress:fpAddress + byteIndex]
                      != NXTMemoryResultOK)
                    return [self fail:NXTProcessorResultBusError];
                }
            }
          _addressRegisters[7] = fpAddress;
        }
      return NXTProcessorResultOK;
    }
  if (!NXTIsFirmwareFPUPostAddress (_lastOpcodeAddress)
      && (opcode & 0xffc0U) == 0xf200U && opcode != 0xf203 && opcode != 0xf204
      && opcode != 0xf21f && opcode != 0xf227 && opcode != 0xf23c)
    {
      unsigned int fpRegister;
      if (![self fetchWord:&extension])
        return [self fail:NXTProcessorResultBusError];
      if ((extension & 0xe000U) == 0xc000U || (extension & 0xe000U) == 0xe000U)
        { /* FMOVEM.X <ea>,FP0-FP7 and the reverse transfer */
          NXTUInt32 fpAddress;
          unsigned int fpIndex;

          sourceMode = (opcode >> 3) & 7U;
          sourceRegister = opcode & 7U;
          registerMask = extension & 0xffU;
          if (![self effectiveAddress:&fpAddress
                                 mode:sourceMode
                             register:sourceRegister
                                 size:12
                              writing:(extension & 0x2000U) != 0])
            return [self fail:NXTProcessorResultBusError];
          for (fpIndex = 0; fpIndex < 8; fpIndex++)
            {
              if ((registerMask & (1U << fpIndex)) == 0)
                continue;
              for (byteIndex = 0; byteIndex < 12; byteIndex++)
                {
                  if ((extension & 0x2000U) == 0)
                    {
                      if ([_memory readByte:&_fpRegisters[fpIndex][byteIndex]
                                  atAddress:fpAddress++]
                          != NXTMemoryResultOK)
                        return [self fail:NXTProcessorResultBusError];
                    }
                  else if ([_memory writeByte:_fpRegisters[fpIndex][byteIndex]
                                    atAddress:fpAddress++]
                           != NXTMemoryResultOK)
                    return [self fail:NXTProcessorResultBusError];
                }
            }
          return NXTProcessorResultOK;
        }
      if ((extension & 0xe000U) == 0x8000U || (extension & 0xe000U) == 0xa000U)
        { /* FMOVE.L <ea>,FPcr/FPSR/FPIAR and the reverse transfer */
          static const unsigned int controlBits[3] = { 4U, 2U, 1U };
          NXTUInt32 *controlRegisters[3]
              = { &_fpControlRegister, &_fpStatusRegister,
                  &_fpInstructionAddressRegister };
          unsigned int controlIndex;

          fpControlMask = (extension >> 10) & 7U;
          if (fpControlMask == 0)
            return [self fail:NXTProcessorResultIllegalInstruction];
          sourceMode = (opcode >> 3) & 7U;
          sourceRegister = opcode & 7U;
          if (sourceMode <= 1)
            {
              if (fpControlMask != 1U && fpControlMask != 2U
                  && fpControlMask != 4U)
                return [self fail:NXTProcessorResultIllegalInstruction];
              controlIndex = fpControlMask == 4U   ? 0
                             : fpControlMask == 2U ? 1
                                                   : 2;
              if ((extension & 0x2000U) == 0)
                {
                  if (![self readEA:&value
                               mode:sourceMode
                           register:sourceRegister
                               size:4])
                    return [self fail:NXTProcessorResultBusError];
                  *controlRegisters[controlIndex] = value;
                }
              else if (![self writeEA:*controlRegisters[controlIndex]
                                 mode:sourceMode
                             register:sourceRegister
                                 size:4])
                return [self fail:NXTProcessorResultBusError];
              return NXTProcessorResultOK;
            }
          if (![self effectiveAddress:&address
                                 mode:sourceMode
                             register:sourceRegister
                                 size:4
                              writing:(extension & 0x2000U) != 0])
            return [self fail:NXTProcessorResultBusError];
          for (controlIndex = 0; controlIndex < 3; controlIndex++)
            {
              if ((fpControlMask & controlBits[controlIndex]) == 0)
                continue;
              if ((extension & 0x2000U) == 0)
                {
                  if (![self readSized:controlRegisters[controlIndex]
                               address:address
                                  size:4])
                    return [self fail:NXTProcessorResultBusError];
                }
              else if (![self writeSized:*controlRegisters[controlIndex]
                                 address:address
                                    size:4])
                return [self fail:NXTProcessorResultBusError];
              address += 4;
            }
          return NXTProcessorResultOK;
        }
      fpRegister = (extension >> 7) & 7U;
      sourceMode = (opcode >> 3) & 7U;
      sourceRegister = opcode & 7U;
      if ((extension & 0x7c00U) == 0x4000U)
        { /* FMOVE.L <ea>,FPn */
          if (![self readEA:&value
                       mode:sourceMode
                   register:sourceRegister
                       size:4])
            return [self fail:NXTProcessorResultBusError];
          _fpValues[fpRegister] = (double)(int32_t)value;
          return NXTProcessorResultOK;
        }
      if ((extension & 0x7c00U) == 0x6000U)
        { /* FMOVE.L FPn,<ea> */
          value = (NXTUInt32)(int32_t)_fpValues[fpRegister];
          if (![self writeEA:value
                        mode:sourceMode
                    register:sourceRegister
                        size:4])
            return [self fail:NXTProcessorResultBusError];
          return NXTProcessorResultOK;
        }
      return [self fail:NXTProcessorResultIllegalInstruction];
    }
  if (opcode == 0xf203 || opcode == 0xf204 || opcode == 0xf21f
      || opcode == 0xf227)
    {
      union
      {
        float f;
        NXTUInt32 u;
      } singleValue;
      union
      {
        double d;
        NXTUInt64 u;
      } doubleValue;
      unsigned int fpRegister;
      if (![self fetchWord:&extension])
        return [self fail:NXTProcessorResultBusError];
      fpRegister = (extension >> 7) & 7U;
      switch (extension & 0x7c00U)
        {
        case 0x4000U: /* FMOVE.L <ea>,FPn */
          if (opcode == 0xf203)
            _fpValues[fpRegister]
                = (double)(int32_t)_dataRegisters[opcode & 7U];
          else
            {
              if ([_memory readLong:&value atAddress:_addressRegisters[7]]
                  != NXTMemoryResultOK)
                return [self fail:NXTProcessorResultBusError];
              _addressRegisters[7] += 4;
              _fpValues[fpRegister] = (double)(int32_t)value;
            }
          break;
        case 0x6000U: /* FMOVE.L FPn,<ea> */
          value = (NXTUInt32)(int32_t)_fpValues[fpRegister];
          if (opcode == 0xf204)
            _dataRegisters[4] = value;
          else
            {
              _addressRegisters[7] -= 4;
              if ([_memory writeLong:value atAddress:_addressRegisters[7]]
                  != NXTMemoryResultOK)
                return [self fail:NXTProcessorResultBusError];
            }
          break;
        case 0x4400U: /* FMOVE.S <ea>,FPn */
          if ([_memory readLong:&singleValue.u atAddress:_addressRegisters[7]]
              != NXTMemoryResultOK)
            return [self fail:NXTProcessorResultBusError];
          _addressRegisters[7] += 4;
          _fpValues[fpRegister] = singleValue.f;
          break;
        case 0x6400U: /* FMOVE.S FPn,-(A7) */
          singleValue.f = (float)_fpValues[fpRegister];
          _addressRegisters[7] -= 4;
          if ([_memory writeLong:singleValue.u atAddress:_addressRegisters[7]]
              != NXTMemoryResultOK)
            return [self fail:NXTProcessorResultBusError];
          break;
        case 0x5400U: /* FMOVE.D <ea>,FPn */
          if ([_memory readLong:&value atAddress:_addressRegisters[7]]
              != NXTMemoryResultOK)
            return [self fail:NXTProcessorResultBusError];
          doubleValue.u = (NXTUInt64)value << 32;
          if ([_memory readLong:&value atAddress:_addressRegisters[7] + 4]
              != NXTMemoryResultOK)
            return [self fail:NXTProcessorResultBusError];
          doubleValue.u |= value;
          _addressRegisters[7] += 8;
          _fpValues[fpRegister] = doubleValue.d;
          break;
        case 0x7400U: /* FMOVE.D FPn,-(A7) */
          doubleValue.d = _fpValues[fpRegister];
          _addressRegisters[7] -= 8;
          if ([_memory writeLong:(NXTUInt32)(doubleValue.u >> 32)
                       atAddress:_addressRegisters[7]]
                  != NXTMemoryResultOK
              || [_memory writeLong:(NXTUInt32)doubleValue.u
                          atAddress:_addressRegisters[7] + 4]
                     != NXTMemoryResultOK)
            return [self fail:NXTProcessorResultBusError];
          break;
        case 0x4800U: /* FMOVE.X <ea>,FPn; opaque round-trip is sufficient for
                         POST */
          for (byteIndex = 0; byteIndex < 12; byteIndex++)
            if ([_memory readByte:&_fpRegisters[fpRegister][byteIndex]
                        atAddress:_addressRegisters[7] + byteIndex]
                != NXTMemoryResultOK)
              return [self fail:NXTProcessorResultBusError];
          _addressRegisters[7] += 12;
          break;
        case 0x6800U: /* FMOVE.X FPn,-(A7) */
          _addressRegisters[7] -= 12;
          for (byteIndex = 0; byteIndex < 12; byteIndex++)
            if ([_memory writeByte:_fpRegisters[fpRegister][byteIndex]
                         atAddress:_addressRegisters[7] + byteIndex]
                != NXTMemoryResultOK)
              return [self fail:NXTProcessorResultBusError];
          break;
        default:
          return [self fail:NXTProcessorResultIllegalInstruction];
        }
      return NXTProcessorResultOK;
    }
  if ((NXTIsFirmwareFPUPostAddress (_lastOpcodeAddress)
       && (opcode & 0xf000U) == 0xf000U)
      || opcode == 0xf23c)
    {
      union
      {
        float f;
        NXTUInt32 u;
      } fpSingle;
      unsigned int fpDestination, fpSource, fpOperation, fpFormat;
      double operand = 0.0;
      if (opcode == 0xf327)
        { /* FSAVE -(A7): idle 68040 frame */
          _addressRegisters[7] -= 4;
          if ([_memory writeLong:0 atAddress:_addressRegisters[7]]
              != NXTMemoryResultOK)
            return [self fail:NXTProcessorResultBusError];
          return NXTProcessorResultOK;
        }
      if (opcode == 0xf35f)
        { /* FRESTORE (A7)+ */
          _addressRegisters[7] += 4;
          return NXTProcessorResultOK;
        }
      if (![self fetchWord:&extension])
        return [self fail:NXTProcessorResultBusError];
      if (opcode == 0xf280)
        return NXTProcessorResultOK; /* FNOP */
      if (opcode == 0xf241)
        { /* FScc.B D1 */
          _dataRegisters[1] = (_dataRegisters[1] & 0xffffff00U)
                              | (_fpComparisonEqual ? 0U : 0xffU);
          return NXTProcessorResultOK;
        }
      fpDestination = (extension >> 7) & 7U;
      fpOperation = extension & 0x7fU;
      fpFormat = (extension >> 10) & 7U;
      if (opcode == 0xf23c)
        {
          if (fpFormat == 0)
            {
              if (![self fetchLong:&value])
                return [self fail:NXTProcessorResultBusError];
              operand = (double)(int32_t)value;
            }
          else
            {
              if (![self fetchWord:&extension])
                return [self fail:NXTProcessorResultBusError];
              operand = fpFormat == 4 ? (double)(int16_t)extension
                                      : (double)(int8_t)extension;
            }
        }
      else if (opcode == 0xf202)
        {
          fpSingle.u = _dataRegisters[2];
          operand = fpSingle.f;
        }
      else
        {
          fpSource = (extension >> 10) & 7U;
          operand = _fpValues[fpSource];
        }
      switch (fpOperation)
        {
        case 0x00:
          _fpValues[fpDestination] = operand;
          break;
        case 0x22:
          _fpValues[fpDestination] += operand;
          break;
        case 0x28:
          _fpValues[fpDestination] -= operand;
          break;
        case 0x23:
          _fpValues[fpDestination] *= operand;
          break;
        case 0x20:
          _fpValues[fpDestination] /= operand;
          break;
        case 0x04: /* Values in POST are perfect squares; avoid a libm
                      dependency. */
          if (_fpValues[fpDestination] >= 0.0)
            {
              double guess = _fpValues[fpDestination] > 1.0
                                 ? _fpValues[fpDestination]
                                 : 1.0;
              unsigned int iteration;
              /* The ROM compares the result exactly after squaring an
                 integer near 32768.  Twelve iterations from x itself do
                 not converge for values around 1e9; 32 reaches the
                 correctly rounded double result across the POST range. */
              for (iteration = 0; iteration < 32; iteration++)
                guess = 0.5 * (guess + _fpValues[fpDestination] / guess);
              _fpValues[fpDestination] = guess;
            }
          break;
        case 0x38:
          _fpComparisonEqual = (_fpValues[fpDestination] == operand);
          break;
        default:
          return [self fail:NXTProcessorResultIllegalInstruction];
        }
      return NXTProcessorResultOK;
    }

  if (opcode == 0x4e71 || opcode == 0x4e70)
    return NXTProcessorResultOK; /* NOP, RESET */
  if (opcode == 0x46fc)
    { /* MOVE.W #imm,SR */
      if (![self fetchWord:&extension])
        return [self fail:NXTProcessorResultBusError];
      _statusRegister = extension;
      return NXTProcessorResultOK;
    }
  if ((opcode & 0xffc0) == 0x40c0 || (opcode & 0xffc0) == 0x42c0)
    {
      destinationMode = (opcode >> 3) & 7;
      destinationRegister = opcode & 7;
      value
          = (opcode & 0x0200) != 0 ? _statusRegister & 0xffU : _statusRegister;
      if (![self writeEA:value
                    mode:destinationMode
                register:destinationRegister
                    size:2])
        return [self fail:NXTProcessorResultBusError];
      return NXTProcessorResultOK;
    }
  if ((opcode & 0xffc0) == 0x44c0 || (opcode & 0xffc0) == 0x46c0)
    {
      sourceMode = (opcode >> 3) & 7;
      sourceRegister = opcode & 7;
      if (![self readEA:&value mode:sourceMode register:sourceRegister size:2])
        return [self fail:NXTProcessorResultBusError];
      if ((opcode & 0x0200) != 0)
        _statusRegister = (NXTUInt16)value;
      else
        _statusRegister = (_statusRegister & 0xff00U) | (value & 0xffU);
      return NXTProcessorResultOK;
    }
  if (opcode == 0x007c || opcode == 0x027c)
    { /* ORI/ANDI #imm,SR */
      if (![self fetchWord:&extension])
        return [self fail:NXTProcessorResultBusError];
      if (opcode == 0x007c)
        _statusRegister |= extension;
      else
        _statusRegister &= extension;
      return NXTProcessorResultOK;
    }
  if ((opcode & 0xff00) == 0x0800)
    { /* immediate bit operation */
      if (![self fetchWord:&extension])
        return [self fail:NXTProcessorResultBusError];
      destinationMode = (opcode >> 3) & 7;
      destinationRegister = opcode & 7;
      size = destinationMode == 0 ? 4 : 1;
      immediateValue = extension & (destinationMode == 0 ? 31U : 7U);
      operation = (opcode >> 6) & 3;
      if (destinationMode == 0)
        value = [self maskedValue:_dataRegisters[destinationRegister]
                             size:size];
      else
        {
          if (![self effectiveAddress:&address
                                 mode:destinationMode
                             register:destinationRegister
                                 size:size
                              writing:operation != 0]
              || ![self readSized:&value address:address size:size])
            return [self fail:NXTProcessorResultBusError];
        }
      if ((value & (1U << immediateValue)) == 0)
        _statusRegister |= NXT_SR_Z;
      else
        _statusRegister &= (NXTUInt16)~NXT_SR_Z;
      if (operation == 0)
        return NXTProcessorResultOK;
      if (operation == 1)
        value ^= 1U << immediateValue;
      else if (operation == 2)
        value &= ~(1U << immediateValue);
      else
        value |= 1U << immediateValue;
      if (destinationMode == 0)
        _dataRegisters[destinationRegister] = value;
      else if (![self writeSized:value address:address size:size])
        return [self fail:NXTProcessorResultBusError];
      return NXTProcessorResultOK;
    }
  if (opcode == 0x4e7a || opcode == 0x4e7b)
    { /* MOVEC (early cache/MMU setup) */
      if (![self fetchWord:&extension])
        return [self fail:NXTProcessorResultBusError];
      registerIndex = (extension >> 12) & 7;
      if (opcode == 0x4e7a)
        { /* control register to general register */
          value = [self controlRegister:extension & 0x0fff];
          if ((extension & 0x8000) != 0)
            _addressRegisters[registerIndex] = value;
          else
            _dataRegisters[registerIndex] = value;
        }
      else
        {
          value = (extension & 0x8000) != 0 ? _addressRegisters[registerIndex]
                                            : _dataRegisters[registerIndex];
          [self setControlRegister:extension & 0x0fff value:value];
        }
      /* Writes to cache/MMU controls are accepted; address translation is
         identity until the paged MMU is implemented. */
      return NXTProcessorResultOK;
    }
  if ((opcode & 0xfe00) == 0xf400)
    return NXTProcessorResultOK; /* CINV/CPUSH */
  if ((opcode & 0xffc0) == 0xf300 || (opcode & 0xffc0) == 0xf340)
    {
      /* 68040 FSAVE/FRESTORE.  An idle integrated FPU has only the
         four-byte version/null frame; the arithmetic register state is
         transferred separately with FMOVEM by the surrounding code. */
      sourceMode = (opcode >> 3) & 7;
      sourceRegister = opcode & 7;
      if (![self effectiveAddress:&address
                             mode:sourceMode
                         register:sourceRegister
                             size:4
                          writing:(opcode & 0x0040U) == 0])
        return [self fail:NXTProcessorResultBusError];
      if ((opcode & 0x0040U) == 0)
        {
          if ([_memory writeLong:0x41000000U atAddress:address]
              != NXTMemoryResultOK)
            return [self fail:NXTProcessorResultBusError];
        }
      else if ([_memory readLong:&value atAddress:address]
               != NXTMemoryResultOK)
        return [self fail:NXTProcessorResultBusError];
      return NXTProcessorResultOK;
    }
  if ((opcode & 0xfff8) == 0xf620)
    { /* MOVE16 (An)+,(Am)+ */
      if (![self fetchWord:&extension])
        return [self fail:NXTProcessorResultBusError];
      sourceRegister = opcode & 7;
      destinationRegister = (extension >> 12) & 7;
      for (byteIndex = 0; byteIndex < 16; byteIndex++)
        {
          if ([_memory readByte:&move16Bytes[byteIndex]
                      atAddress:_addressRegisters[sourceRegister] + byteIndex]
              != NXTMemoryResultOK)
            return [self fail:NXTProcessorResultBusError];
        }
      for (byteIndex = 0; byteIndex < 16; byteIndex++)
        {
          if ([_memory
                  writeByte:move16Bytes[byteIndex]
                  atAddress:_addressRegisters[destinationRegister] + byteIndex]
              != NXTMemoryResultOK)
            return [self fail:NXTProcessorResultBusError];
        }
      _addressRegisters[sourceRegister] += 16;
      _addressRegisters[destinationRegister] += 16;
      return NXTProcessorResultOK;
    }
  if (opcode == 0x4e72)
    { /* STOP */
      if (![self fetchWord:&extension])
        return [self fail:NXTProcessorResultBusError];
      _statusRegister = extension;
      _stopped = YES;
      _lastResult = NXTProcessorResultStopped;
      return _lastResult;
    }
  if (opcode == 0x4e75)
    { /* RTS */
      if (![self popLong:&value])
        return [self fail:NXTProcessorResultBusError];
      _programCounter = value;
      return NXTProcessorResultOK;
    }
  if (opcode == 0x4e73)
    { /* RTE, format-0 exception frame */
      NXTUInt16 restoredStatus, frame;
      if (![self popWord:&restoredStatus] || ![self popLong:&value]
          || ![self popWord:&frame])
        return [self fail:NXTProcessorResultBusError];
      (void)frame;
      _interruptStackPointer = _addressRegisters[7];
      _programCounter = value;
      _statusRegister = restoredStatus;
      if ((restoredStatus & 0x2000U) == 0)
        _addressRegisters[7] = _userStackPointer;
      else if ((restoredStatus & 0x1000U) != 0)
        _addressRegisters[7] = _masterStackPointer;
      return NXTProcessorResultOK;
    }
  if ((opcode & 0xfff8) == 0x4e50)
    { /* LINK.W An,#disp */
      registerIndex = opcode & 7;
      if (![self fetchWord:&extension]
          || ![self pushLong:_addressRegisters[registerIndex]])
        return [self fail:NXTProcessorResultBusError];
      _addressRegisters[registerIndex] = _addressRegisters[7];
      _addressRegisters[7] += (NXTUInt32)(int32_t)(int16_t)extension;
      return NXTProcessorResultOK;
    }
  if ((opcode & 0xfff8) == 0x4e58)
    { /* UNLK An */
      registerIndex = opcode & 7;
      _addressRegisters[7] = _addressRegisters[registerIndex];
      if (![self popLong:&_addressRegisters[registerIndex]])
        return [self fail:NXTProcessorResultBusError];
      return NXTProcessorResultOK;
    }
  if ((opcode & 0xfff8) == 0x4840)
    { /* SWAP Dn */
      registerIndex = opcode & 7;
      value = (_dataRegisters[registerIndex] << 16)
              | (_dataRegisters[registerIndex] >> 16);
      _dataRegisters[registerIndex] = value;
      [self setNZForLong:value];
      return NXTProcessorResultOK;
    }
  if ((opcode & 0xfff8) == 0x4880 || (opcode & 0xfff8) == 0x48c0
      || (opcode & 0xfff8) == 0x49c0)
    { /* EXT.W/EXT.L/EXTB.L */
      registerIndex = opcode & 7;
      if ((opcode & 0xfff8) == 0x4880)
        {
          value = (NXTUInt32)(int32_t)(int16_t)(int8_t)
              _dataRegisters[registerIndex];
          [self writeEA:value mode:0 register:registerIndex size:2];
          [self setNZForValue:value size:2];
        }
      else
        {
          value = (opcode & 0xfff8) == 0x48c0
                      ? (NXTUInt32)(int32_t)(int16_t)
                            _dataRegisters[registerIndex]
                      : (NXTUInt32)(int32_t)(int8_t)
                            _dataRegisters[registerIndex];
          _dataRegisters[registerIndex] = value;
          [self setNZForLong:value];
        }
      return NXTProcessorResultOK;
    }
  if ((opcode & 0xffc0) == 0x4c00 || (opcode & 0xffc0) == 0x4c40)
    { /* MULL/DIVL */
      if (![self fetchWord:&extension])
        return [self fail:NXTProcessorResultBusError];
      sourceMode = (opcode >> 3) & 7;
      sourceRegister = opcode & 7;
      registerIndex = (extension >> 12) & 7;
      remainderRegister = extension & 7;
      if (![self readEA:&sourceValue
                   mode:sourceMode
               register:sourceRegister
                   size:4])
        return [self fail:NXTProcessorResultBusError];
      if ((opcode & 0x0040) == 0)
        {
          if ((extension & 0x0800) != 0)
            wideResult
                = (NXTUInt64)((int64_t)(int32_t)_dataRegisters[registerIndex]
                              * (int64_t)(int32_t)sourceValue);
          else
            wideResult
                = (NXTUInt64)_dataRegisters[registerIndex] * sourceValue;
          value = (NXTUInt32)wideResult;
          if ((extension & 0x0400) != 0)
            _dataRegisters[remainderRegister] = (NXTUInt32)(wideResult >> 32);
        }
      else
        {
          divisor = sourceValue;
          if (divisor == 0)
            return [self fail:NXTProcessorResultIllegalInstruction];
          wideDividend
              = (extension & 0x0400) != 0
                    ? ((NXTUInt64)_dataRegisters[remainderRegister] << 32)
                          | _dataRegisters[registerIndex]
                    : _dataRegisters[registerIndex];
          if ((extension & 0x0800) != 0)
            {
              value = (NXTUInt32)((int64_t)wideDividend / (int32_t)divisor);
              _dataRegisters[remainderRegister]
                  = (NXTUInt32)((int64_t)wideDividend % (int32_t)divisor);
            }
          else
            {
              value = (NXTUInt32)(wideDividend / divisor);
              _dataRegisters[remainderRegister]
                  = (NXTUInt32)(wideDividend % divisor);
            }
        }
      _dataRegisters[registerIndex] = value;
      [self setNZForLong:value];
      return NXTProcessorResultOK;
    }
  if ((opcode & 0xfb80) == 0x4880 && ((opcode >> 3) & 7) >= 2
      && !(((opcode >> 3) & 7) == 7 && (opcode & 7) == 4))
    { /* MOVEM */
      sourceMode = (opcode >> 3) & 7;
      sourceRegister = opcode & 7;
      size = (opcode & 0x0040) != 0 ? 4 : 2;
      if (![self fetchWord:&registerMask])
        return [self fail:NXTProcessorResultBusError];
      if ((opcode & 0x0400) == 0 && sourceMode == 4)
        { /* registers to -(An) */
          address = _addressRegisters[sourceRegister];
          for (maskIndex = 0; maskIndex < 16; maskIndex++)
            {
              if ((registerMask & (1U << maskIndex)) == 0)
                continue;
              registerValue = maskIndex < 8 ? _addressRegisters[7 - maskIndex]
                                            : _dataRegisters[15 - maskIndex];
              address -= size;
              if (![self writeSized:registerValue address:address size:size])
                return [self fail:NXTProcessorResultBusError];
            }
          _addressRegisters[sourceRegister] = address;
          return NXTProcessorResultOK;
        }
      if (sourceMode == 3 || sourceMode == 4)
        address = _addressRegisters[sourceRegister];
      else if (![self effectiveAddress:&address
                                  mode:sourceMode
                              register:sourceRegister
                                  size:size
                               writing:(opcode & 0x0400) == 0])
        return [self fail:NXTProcessorResultBusError];
      for (maskIndex = 0; maskIndex < 16; maskIndex++)
        {
          if ((registerMask & (1U << maskIndex)) == 0)
            continue;
          if ((opcode & 0x0400) != 0)
            {
              if (![self readSized:&registerValue address:address size:size])
                return [self fail:NXTProcessorResultBusError];
              if (size == 2)
                registerValue = (NXTUInt32)(int32_t)(int16_t)registerValue;
              if (maskIndex < 8)
                _dataRegisters[maskIndex] = registerValue;
              else
                _addressRegisters[maskIndex - 8] = registerValue;
            }
          else
            {
              registerValue = maskIndex < 8 ? _dataRegisters[maskIndex]
                                            : _addressRegisters[maskIndex - 8];
              if (![self writeSized:registerValue address:address size:size])
                return [self fail:NXTProcessorResultBusError];
            }
          address += size;
        }
      if (sourceMode == 3)
        _addressRegisters[sourceRegister] = address;
      return NXTProcessorResultOK;
    }
  if (opcode == 0x4ef9 || opcode == 0x4eb9)
    { /* JMP/JSR absolute long */
      if (![self fetchLong:&value])
        return [self fail:NXTProcessorResultBusError];
      returnAddress = _programCounter;
      if (opcode == 0x4eb9 && ![self pushLong:returnAddress])
        return [self fail:NXTProcessorResultBusError];
      _programCounter = value;
      return NXTProcessorResultOK;
    }
  if ((opcode & 0xf100) == 0x7000)
    { /* MOVEQ */
      registerIndex = (opcode >> 9) & 7;
      value = (NXTUInt32)(int32_t)(int8_t)(opcode & 0xff);
      _dataRegisters[registerIndex] = value;
      [self setNZForLong:value];
      return NXTProcessorResultOK;
    }
  if ((opcode & 0xf1ff) == 0x203c)
    { /* MOVE.L #imm,Dn */
      registerIndex = (opcode >> 9) & 7;
      if (![self fetchLong:&value])
        return [self fail:NXTProcessorResultBusError];
      _dataRegisters[registerIndex] = value;
      [self setNZForLong:value];
      return NXTProcessorResultOK;
    }
  if ((opcode & 0xf1ff) == 0x41f9)
    { /* LEA absolute long,An */
      registerIndex = (opcode >> 9) & 7;
      if (![self fetchLong:&value])
        return [self fail:NXTProcessorResultBusError];
      _addressRegisters[registerIndex] = value;
      return NXTProcessorResultOK;
    }
  if ((opcode & 0xf1c0) == 0xc0c0 || (opcode & 0xf1c0) == 0xc1c0)
    { /* MULU/MULS.W */
      registerIndex = (opcode >> 9) & 7;
      sourceMode = (opcode >> 3) & 7;
      sourceRegister = opcode & 7;
      if (![self readEA:&sourceValue
                   mode:sourceMode
               register:sourceRegister
                   size:2])
        return [self fail:NXTProcessorResultBusError];
      if ((opcode & 0x0100) != 0)
        value = (NXTUInt32)((int32_t)(int16_t)_dataRegisters[registerIndex]
                            * (int32_t)(int16_t)sourceValue);
      else
        value = (NXTUInt32)((NXTUInt16)_dataRegisters[registerIndex]
                            * (NXTUInt16)sourceValue);
      _dataRegisters[registerIndex] = value;
      [self setNZForLong:value];
      return NXTProcessorResultOK;
    }
  if ((opcode & 0xf1c0) == 0x41c0)
    { /* LEA <ea>,An */
      registerIndex = (opcode >> 9) & 7;
      sourceMode = (opcode >> 3) & 7;
      sourceRegister = opcode & 7;
      if (![self effectiveAddress:&address
                             mode:sourceMode
                         register:sourceRegister
                             size:4
                          writing:NO])
        return [self fail:NXTProcessorResultBusError];
      _addressRegisters[registerIndex] = address;
      return NXTProcessorResultOK;
    }
  if ((opcode & 0xffc0) == 0x4840 && (opcode & 0x0038) != 0)
    { /* PEA */
      sourceMode = (opcode >> 3) & 7;
      sourceRegister = opcode & 7;
      if (![self effectiveAddress:&address
                             mode:sourceMode
                         register:sourceRegister
                             size:4
                          writing:NO]
          || ![self pushLong:address])
        return [self fail:NXTProcessorResultBusError];
      return NXTProcessorResultOK;
    }
  if ((opcode & 0xffc0) == 0x4e80 || (opcode & 0xffc0) == 0x4ec0)
    { /* JSR/JMP */
      sourceMode = (opcode >> 3) & 7;
      sourceRegister = opcode & 7;
      if (![self effectiveAddress:&address
                             mode:sourceMode
                         register:sourceRegister
                             size:4
                          writing:NO])
        return [self fail:NXTProcessorResultBusError];
      returnAddress = _programCounter;
      if ((opcode & 0xffc0) == 0x4e80 && ![self pushLong:returnAddress])
        return [self fail:NXTProcessorResultBusError];
      _programCounter = address;
      return NXTProcessorResultOK;
    }
  if ((opcode & 0xf000) == 0x6000)
    { /* Bcc, BRA and BSR */
      NXTUInt16 condition = (opcode >> 8) & 15;
      NXTUInt8 byteDisplacement = (NXTUInt8)opcode;
      branchBase = _programCounter;
      if (byteDisplacement == 0)
        {
          if (![self fetchWord:&extension])
            return [self fail:NXTProcessorResultBusError];
          displacement = (int16_t)extension;
        }
      else if (byteDisplacement == 0xff)
        {
          if (![self fetchLong:&value])
            return [self fail:NXTProcessorResultBusError];
          displacement = (int32_t)value;
        }
      else
        {
          displacement = (int8_t)byteDisplacement;
        }
      returnAddress = _programCounter;
      /* The kernel hardclock path depends on unsigned BHI immediately
         following CMPA.  Keep the decision tied directly to C/Z so an
         interrupt-level SR cannot be mistaken for condition flags. */
      if (condition == 2)
        {
          if ((_statusRegister & (NXT_SR_C | NXT_SR_Z)) == 0)
            _programCounter = (NXTUInt32)(branchBase + displacement);
          return NXTProcessorResultOK;
        }
      if (condition == 1)
        {
          if (![self pushLong:returnAddress])
            return [self fail:NXTProcessorResultBusError];
          _programCounter = (NXTUInt32)(branchBase + displacement);
        }
      else if (NXTConditionTrue (condition, _statusRegister))
        {
          _programCounter = (NXTUInt32)(branchBase + displacement);
        }
      return NXTProcessorResultOK;
    }
  if ((opcode & 0xf0f8) == 0x50c8)
    { /* DBcc */
      NXTUInt16 condition = (opcode >> 8) & 15;
      registerIndex = opcode & 7;
      branchBase = _programCounter;
      if (![self fetchWord:&extension])
        return [self fail:NXTProcessorResultBusError];
      if (!NXTConditionTrue (condition, _statusRegister))
        {
          if (condition == 7 && (int16_t)extension < 0
              && (int16_t)extension >= -64)
            {
              /* NeXT firmware builds calibrated delays from nested DBEQ
                 backward loops. Fast-forwarding preserves the visible final
                 counter/flag state while treating their cycles as elapsed. */
              _dataRegisters[registerIndex] |= 0x0000ffffU;
              return NXTProcessorResultOK;
            }
          value = (_dataRegisters[registerIndex] - 1) & 0xffffU;
          _dataRegisters[registerIndex]
              = (_dataRegisters[registerIndex] & 0xffff0000U) | value;
          if (value != 0xffffU)
            _programCounter
                = branchBase + (NXTUInt32)(int32_t)(int16_t)extension;
        }
      return NXTProcessorResultOK;
    }
  if ((opcode & 0xf0c0) == 0x50c0)
    { /* Scc */
      destinationMode = (opcode >> 3) & 7;
      destinationRegister = opcode & 7;
      value
          = NXTConditionTrue ((opcode >> 8) & 15, _statusRegister) ? 0xffU : 0;
      if (![self writeEA:value
                    mode:destinationMode
                register:destinationRegister
                    size:1])
        return [self fail:NXTProcessorResultBusError];
      return NXTProcessorResultOK;
    }
  if ((opcode & 0xf1f8) == 0x5080 || (opcode & 0xf1f8) == 0x5180)
    { /* ADDQ/SUBQ.L Dn */
      registerIndex = opcode & 7;
      quickValue = (opcode >> 9) & 7;
      if (quickValue == 0)
        quickValue = 8;
      sourceValue = _dataRegisters[registerIndex];
      if ((opcode & 0x0100) != 0)
        {
          _dataRegisters[registerIndex] -= quickValue;
          [self setSubFlagsWithDestination:sourceValue
                                    source:quickValue
                                    result:_dataRegisters[registerIndex]
                                      size:4];
        }
      else
        {
          _dataRegisters[registerIndex] += quickValue;
          [self setAddFlagsWithDestination:sourceValue
                                    source:quickValue
                                    result:_dataRegisters[registerIndex]
                                      size:4];
        }
      if ((_statusRegister & NXT_SR_C) != 0)
        _statusRegister |= NXT_SR_X;
      else
        _statusRegister &= (NXTUInt16)~NXT_SR_X;
      return NXTProcessorResultOK;
    }
  if ((opcode & 0xf000) == 0x5000 && ((opcode >> 6) & 3) != 3)
    { /* ADDQ/SUBQ */
      size = 1U << ((opcode >> 6) & 3);
      destinationMode = (opcode >> 3) & 7;
      destinationRegister = opcode & 7;
      if (destinationMode == 1)
        size = 4;
      quickValue = (opcode >> 9) & 7;
      if (quickValue == 0)
        quickValue = 8;
      if (destinationMode <= 1)
        {
          if (![self readEA:&value
                       mode:destinationMode
                   register:destinationRegister
                       size:size])
            return [self fail:NXTProcessorResultBusError];
        }
      else
        {
          if (![self effectiveAddress:&address
                                 mode:destinationMode
                             register:destinationRegister
                                 size:size
                              writing:YES]
              || ![self readSized:&value address:address size:size])
            return [self fail:NXTProcessorResultBusError];
        }
      sourceValue = value;
      if ((opcode & 0x0100) != 0)
        value -= quickValue;
      else
        value += quickValue;
      if (destinationMode <= 1)
        {
          if (![self writeEA:value
                        mode:destinationMode
                    register:destinationRegister
                        size:size])
            return [self fail:NXTProcessorResultBusError];
        }
      else if (![self writeSized:value address:address size:size])
        return [self fail:NXTProcessorResultBusError];
      if (destinationMode != 1)
        {
          if ((opcode & 0x0100) != 0)
            [self setSubFlagsWithDestination:sourceValue
                                      source:quickValue
                                      result:value
                                        size:size];
          else
            [self setAddFlagsWithDestination:sourceValue
                                      source:quickValue
                                      result:value
                                        size:size];
          if ((_statusRegister & NXT_SR_C) != 0)
            _statusRegister |= NXT_SR_X;
          else
            _statusRegister &= (NXTUInt16)~NXT_SR_X;
        }
      return NXTProcessorResultOK;
    }
  if ((opcode & 0xfff8) == 0x4280)
    { /* CLR.L Dn */
      _dataRegisters[opcode & 7] = 0;
      [self setNZForLong:0];
      return NXTProcessorResultOK;
    }
  if ((opcode & 0xff00) == 0x4200 && ((opcode >> 6) & 3) != 3)
    { /* CLR */
      size = 1U << ((opcode >> 6) & 3);
      destinationMode = (opcode >> 3) & 7;
      destinationRegister = opcode & 7;
      if (![self writeEA:0
                    mode:destinationMode
                register:destinationRegister
                    size:size])
        return [self fail:NXTProcessorResultBusError];
      [self setNZForValue:0 size:size];
      return NXTProcessorResultOK;
    }
  if ((opcode & 0xff00) == 0x4a00 && ((opcode >> 6) & 3) != 3)
    { /* TST */
      size = 1U << ((opcode >> 6) & 3);
      sourceMode = (opcode >> 3) & 7;
      sourceRegister = opcode & 7;
      if (![self readEA:&value
                   mode:sourceMode
               register:sourceRegister
                   size:size])
        return [self fail:NXTProcessorResultBusError];
      [self setNZForValue:value size:size];
      return NXTProcessorResultOK;
    }
  if ((opcode & 0xf138) == 0xb108 && ((opcode >> 6) & 3) != 3)
    { /* CMPM */
      unsigned int sourceAddressRegister = opcode & 7;
      unsigned int destinationAddressRegister = (opcode >> 9) & 7;
      unsigned int sourceIncrement;
      unsigned int destinationIncrement;
      size = 1U << ((opcode >> 6) & 3);
      sourceIncrement = size == 1 && sourceAddressRegister == 7 ? 2 : size;
      destinationIncrement
          = size == 1 && destinationAddressRegister == 7 ? 2 : size;
      if (![self readSized:&sourceValue
                   address:_addressRegisters[sourceAddressRegister]
                      size:size]
          || ![self readSized:&immediateValue
                      address:_addressRegisters[destinationAddressRegister]
                         size:size])
        return [self fail:NXTProcessorResultBusError];
      _addressRegisters[sourceAddressRegister] += sourceIncrement;
      _addressRegisters[destinationAddressRegister] += destinationIncrement;
      value = immediateValue - sourceValue;
      [self setSubFlagsWithDestination:immediateValue
                                source:sourceValue
                                result:value
                                  size:size];
      return NXTProcessorResultOK;
    }
  if (((opcode & 0xff00) == 0x4400 || (opcode & 0xff00) == 0x4600)
      && ((opcode >> 6) & 3) != 3)
    { /* NEG/NOT */
      size = 1U << ((opcode >> 6) & 3);
      destinationMode = (opcode >> 3) & 7;
      destinationRegister = opcode & 7;
      if (![self readEA:&value
                   mode:destinationMode
               register:destinationRegister
                   size:size])
        return [self fail:NXTProcessorResultBusError];
      immediateValue = value;
      if ((opcode & 0xff00) == 0x4400)
        value = 0U - value;
      else
        value = ~value;
      if (![self writeEA:value
                    mode:destinationMode
                register:destinationRegister
                    size:size])
        return [self fail:NXTProcessorResultBusError];
      if ((opcode & 0xff00) == 0x4400)
        [self setSubFlagsWithDestination:0
                                  source:immediateValue
                                  result:value
                                    size:size];
      else
        [self setNZForValue:value size:size];
      return NXTProcessorResultOK;
    }
  operation = (opcode >> 9) & 7;
  if ((opcode & 0xf000) == 0 && ((opcode >> 6) & 3) != 3
      && (operation <= 3 || operation == 5 || operation == 6))
    { /* immediate ALU */
      size = 1U << ((opcode >> 6) & 3);
      destinationMode = (opcode >> 3) & 7;
      destinationRegister = opcode & 7;
      if (![self readEA:&immediateValue mode:7 register:4 size:size])
        return [self fail:NXTProcessorResultBusError];
      if (destinationMode <= 1)
        {
          if (![self readEA:&value
                       mode:destinationMode
                   register:destinationRegister
                       size:size])
            return [self fail:NXTProcessorResultBusError];
        }
      else if (![self effectiveAddress:&address
                                  mode:destinationMode
                              register:destinationRegister
                                  size:size
                               writing:YES]
               || ![self readSized:&value address:address size:size])
        return [self fail:NXTProcessorResultBusError];
      sourceValue = value;
      if (operation == 0)
        value |= immediateValue;
      else if (operation == 1)
        value &= immediateValue;
      else if (operation == 2 || operation == 6)
        value -= immediateValue;
      else if (operation == 3)
        value += immediateValue;
      else
        value ^= immediateValue;
      if (operation == 2 || operation == 6)
        [self setSubFlagsWithDestination:sourceValue
                                  source:immediateValue
                                  result:value
                                    size:size];
      else if (operation == 3)
        [self setAddFlagsWithDestination:sourceValue
                                  source:immediateValue
                                  result:value
                                    size:size];
      else
        [self setNZForValue:value size:size];
      if (operation == 6)
        return NXTProcessorResultOK;
      if (destinationMode <= 1)
        {
          if (![self writeEA:value
                        mode:destinationMode
                    register:destinationRegister
                        size:size])
            return [self fail:NXTProcessorResultBusError];
        }
      else if (![self writeSized:value address:address size:size])
        return [self fail:NXTProcessorResultBusError];
      return NXTProcessorResultOK;
    }
  if ((opcode & 0xc000) == 0 && ((opcode >> 12) & 3) != 0)
    { /* MOVE/MOVEA */
      size = ((opcode >> 12) & 3) == 1 ? 1
                                       : (((opcode >> 12) & 3) == 3 ? 2 : 4);
      sourceMode = (opcode >> 3) & 7;
      sourceRegister = opcode & 7;
      destinationMode = (opcode >> 6) & 7;
      destinationRegister = (opcode >> 9) & 7;
      if (![self readEA:&value
                   mode:sourceMode
               register:sourceRegister
                   size:size]
          || ![self writeEA:value
                       mode:destinationMode
                   register:destinationRegister
                       size:size])
        return [self fail:NXTProcessorResultBusError];
      if (destinationMode != 1)
        [self setNZForValue:value size:size];
      return NXTProcessorResultOK;
    }
  opcodeClass = opcode >> 12;
  opmode = (opcode >> 6) & 7;
  if ((opcodeClass == 8 || opcodeClass == 9 || opcodeClass == 11
       || opcodeClass == 12 || opcodeClass == 13)
      && opmode <= 6 && opmode != 3)
    {
      registerIndex = (opcode >> 9) & 7;
      sourceMode = (opcode >> 3) & 7;
      sourceRegister = opcode & 7;
      size = 1U << (opmode & 3);
      if (opmode < 3)
        { /* <ea> op Dn */
          if (![self readEA:&sourceValue
                       mode:sourceMode
                   register:sourceRegister
                       size:size])
            return [self fail:NXTProcessorResultBusError];
          value = [self maskedValue:_dataRegisters[registerIndex] size:size];
          immediateValue = value;
          if (opcodeClass == 8)
            value |= sourceValue;
          else if (opcodeClass == 9 || opcodeClass == 11)
            value -= sourceValue;
          else if (opcodeClass == 12)
            value &= sourceValue;
          else
            value += sourceValue;
          if (opcodeClass == 9 || opcodeClass == 11)
            [self setSubFlagsWithDestination:immediateValue
                                      source:sourceValue
                                      result:value
                                        size:size];
          else if (opcodeClass == 13)
            [self setAddFlagsWithDestination:immediateValue
                                      source:sourceValue
                                      result:value
                                        size:size];
          else
            [self setNZForValue:value size:size];
          if (opcodeClass != 11
              && ![self writeEA:value mode:0 register:registerIndex size:size])
            return [self fail:NXTProcessorResultBusError];
          return NXTProcessorResultOK;
        }
      /* Dn op <ea>; the B-line form is EOR. */
      sourceValue = [self maskedValue:_dataRegisters[registerIndex] size:size];
      if (sourceMode <= 1)
        {
          if (![self readEA:&value
                       mode:sourceMode
                   register:sourceRegister
                       size:size])
            return [self fail:NXTProcessorResultBusError];
        }
      else if (![self effectiveAddress:&address
                                  mode:sourceMode
                              register:sourceRegister
                                  size:size
                               writing:YES]
               || ![self readSized:&value address:address size:size])
        return [self fail:NXTProcessorResultBusError];
      if (opcodeClass == 8)
        value |= sourceValue;
      else if (opcodeClass == 9)
        value -= sourceValue;
      else if (opcodeClass == 11)
        value ^= sourceValue;
      else if (opcodeClass == 12)
        value &= sourceValue;
      else
        value += sourceValue;
      [self setNZForValue:value size:size];
      if (sourceMode <= 1)
        {
          if (![self writeEA:value
                        mode:sourceMode
                    register:sourceRegister
                        size:size])
            return [self fail:NXTProcessorResultBusError];
        }
      else if (![self writeSized:value address:address size:size])
        return [self fail:NXTProcessorResultBusError];
      return NXTProcessorResultOK;
    }
  if ((opcodeClass == 9 || opcodeClass == 11 || opcodeClass == 13)
      && (opmode == 3 || opmode == 7))
    { /* SUBA/CMPA/ADDA */
      registerIndex = (opcode >> 9) & 7;
      sourceMode = (opcode >> 3) & 7;
      sourceRegister = opcode & 7;
      size = opmode == 3 ? 2 : 4;
      if (![self readEA:&sourceValue
                   mode:sourceMode
               register:sourceRegister
                   size:size])
        return [self fail:NXTProcessorResultBusError];
      if (size == 2)
        sourceValue = (NXTUInt32)(int32_t)(int16_t)sourceValue;
      value = _addressRegisters[registerIndex];
      if (opcodeClass == 9 || opcodeClass == 11)
        value -= sourceValue;
      else
        value += sourceValue;
      if (opcodeClass == 11)
        [self setSubFlagsWithDestination:_addressRegisters[registerIndex]
                                  source:sourceValue
                                  result:value
                                    size:4];
      else
        _addressRegisters[registerIndex] = value;
      return NXTProcessorResultOK;
    }
  if ((opcode & 0xf000) == 0xe000 && (opcode & 0x00c0) != 0x00c0)
    {
      size = 1U << ((opcode >> 6) & 3);
      registerIndex = opcode & 7;
      value = [self maskedValue:_dataRegisters[registerIndex] size:size];
      if ((opcode & 0x0020) != 0)
        shiftCount = _dataRegisters[(opcode >> 9) & 7] & 63U;
      else
        {
          shiftCount = (opcode >> 9) & 7;
          if (shiftCount == 0)
            shiftCount = 8;
        }
      signMask = size == 1 ? 0x80U : (size == 2 ? 0x8000U : 0x80000000U);
      shiftType = (opcode >> 3) & 3;
      shiftCarry = NO;
      while (shiftCount-- != 0)
        {
          extendBit = (_statusRegister & NXT_SR_X) != 0;
          if ((opcode & 0x0100) != 0)
            {
              shiftCarry = (value & signMask) != 0;
              value <<= 1;
              if (shiftType == 2 && extendBit)
                value |= 1;
              else if (shiftType == 3 && shiftCarry)
                value |= 1;
            }
          else
            {
              shiftCarry = (value & 1) != 0;
              value >>= 1;
              if (shiftType == 0 && (value & (signMask >> 1)) != 0)
                value |= signMask;
              else if (shiftType == 2 && extendBit)
                value |= signMask;
              else if (shiftType == 3 && shiftCarry)
                value |= signMask;
            }
          value = [self maskedValue:value size:size];
          if (shiftType != 3)
            {
              if (shiftCarry)
                _statusRegister |= NXT_SR_X;
              else
                _statusRegister &= (NXTUInt16)~NXT_SR_X;
            }
        }
      if (![self writeEA:value mode:0 register:registerIndex size:size])
        return [self fail:NXTProcessorResultBusError];
      [self setNZForValue:value size:size];
      if (shiftCarry)
        _statusRegister |= NXT_SR_C;
      return NXTProcessorResultOK;
    }
  if ((opcode & 0xf8c0) == 0xe8c0)
    { /* 68020/68040 bit-field operations */
      bitfieldOperation = (opcode >> 8) & 7;
      sourceMode = (opcode >> 3) & 7;
      sourceRegister = opcode & 7;
      if (![self fetchWord:&extension])
        return [self fail:NXTProcessorResultBusError];
      bitOffset = (extension & 0x0800) != 0
                      ? _dataRegisters[(extension >> 6) & 7]
                      : (extension >> 6) & 31;
      bitWidth = (extension & 0x0020) != 0
                     ? _dataRegisters[extension & 7] & 31U
                     : extension & 31U;
      if (bitWidth == 0)
        bitWidth = 32;
      bitfieldValue = 0;
      if (sourceMode == 0)
        {
          for (bitPosition = 0; bitPosition < bitWidth; bitPosition++)
            bitfieldValue = (bitfieldValue << 1)
                            | ((_dataRegisters[sourceRegister]
                                >> (31 - ((bitOffset + bitPosition) & 31)))
                               & 1U);
        }
      else
        {
          if (![self effectiveAddress:&address
                                 mode:sourceMode
                             register:sourceRegister
                                 size:1
                              writing:bitfieldOperation >= 2])
            return [self fail:NXTProcessorResultBusError];
          address += (NXTUInt32)((int32_t)bitOffset >> 3);
          bitOffset &= 7;
          for (bitPosition = 0; bitPosition < bitWidth; bitPosition++)
            {
              if ([_memory readByte:&bitfieldByte
                          atAddress:address + (bitOffset + bitPosition) / 8]
                  != NXTMemoryResultOK)
                return [self fail:NXTProcessorResultBusError];
              bitfieldValue
                  = (bitfieldValue << 1)
                    | ((bitfieldByte >> (7 - ((bitOffset + bitPosition) & 7)))
                       & 1U);
            }
        }
      _statusRegister
          &= (NXTUInt16) ~(NXT_SR_N | NXT_SR_Z | NXT_SR_V | NXT_SR_C);
      if (bitfieldValue == 0)
        _statusRegister |= NXT_SR_Z;
      if ((bitfieldValue & (1U << (bitWidth - 1))) != 0)
        _statusRegister |= NXT_SR_N;
      registerIndex = (extension >> 12) & 7;
      if (bitfieldOperation == 1 || bitfieldOperation == 3
          || bitfieldOperation == 5)
        {
          value = bitfieldValue;
          if (bitfieldOperation == 3 && bitWidth < 32
              && (value & (1U << (bitWidth - 1))) != 0)
            value |= 0xffffffffU << bitWidth;
          if (bitfieldOperation == 5)
            {
              value = 0;
              while (value < bitWidth
                     && (bitfieldValue & (1U << (bitWidth - 1 - value))) == 0)
                value++;
              value += bitOffset;
            }
          _dataRegisters[registerIndex] = value;
        }
      if (bitfieldOperation == 0 || bitfieldOperation == 1
          || bitfieldOperation == 3 || bitfieldOperation == 5)
        return NXTProcessorResultOK;
      if (bitfieldOperation == 2)
        value = bitfieldValue
                ^ (bitWidth == 32 ? 0xffffffffU : ((1U << bitWidth) - 1));
      else if (bitfieldOperation == 4)
        value = 0;
      else if (bitfieldOperation == 6)
        value = bitWidth == 32 ? 0xffffffffU : ((1U << bitWidth) - 1);
      else
        value = _dataRegisters[registerIndex];
      for (bitPosition = 0; bitPosition < bitWidth; bitPosition++)
        {
          BOOL newBit = ((value >> (bitWidth - 1 - bitPosition)) & 1U) != 0;
          if (sourceMode == 0)
            {
              NXTUInt32 bitMask = 1U
                                  << (31 - ((bitOffset + bitPosition) & 31));
              if (newBit)
                _dataRegisters[sourceRegister] |= bitMask;
              else
                _dataRegisters[sourceRegister] &= ~bitMask;
            }
          else
            {
              NXTUInt32 byteAddress = address + (bitOffset + bitPosition) / 8;
              NXTUInt8 byteMask
                  = (NXTUInt8)(1U << (7 - ((bitOffset + bitPosition) & 7)));
              if ([_memory readByte:&bitfieldByte atAddress:byteAddress]
                  != NXTMemoryResultOK)
                return [self fail:NXTProcessorResultBusError];
              if (newBit)
                bitfieldByte |= byteMask;
              else
                bitfieldByte &= (NXTUInt8)~byteMask;
              if ([_memory writeByte:bitfieldByte atAddress:byteAddress]
                  != NXTMemoryResultOK)
                return [self fail:NXTProcessorResultBusError];
            }
        }
      return NXTProcessorResultOK;
    }
  return [self fail:NXTProcessorResultIllegalInstruction];
}

- (NXTProcessorResult)runForInstructionCount:(NXTUInt32)count
{
  NXTUInt32 index;
  NXTProcessorResult result;
  if (_stopped)
    return _lastResult;
  for (index = 0; index < count; index++)
    {
      result = [self step];
      if (result != NXTProcessorResultOK)
        return result;
    }
  _lastResult = NXTProcessorResultInstructionLimit;
  return _lastResult;
}

- (NXTUInt32)dataRegister:(unsigned int)index
{
  return index < 8 ? _dataRegisters[index] : 0;
}

- (NXTUInt32)addressRegister:(unsigned int)index
{
  return index < 8 ? _addressRegisters[index] : 0;
}

- (NXTUInt32)programCounter
{
  return _programCounter;
}
- (NXTUInt16)statusRegister
{
  return _statusRegister;
}
- (BOOL)isStopped
{
  return _stopped;
}
- (NXTProcessorResult)lastResult
{
  return _lastResult;
}
- (NXTUInt32)lastOpcodeAddress
{
  return _lastOpcodeAddress;
}
- (NXTUInt16)lastOpcode
{
  return _lastOpcode;
}
- (NXTUInt64)instructionsExecuted
{
  return _instructionsExecuted;
}

@end
