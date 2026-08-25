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

#import "NXTMemory.h"
#include <string.h>
#if defined(NXT_TRACE_RTC) || defined(NXT_TRACE_SCC)                          \
    || defined(NXT_TRACE_DMA) || defined(NXT_TRACE_SCSI)
#include <stdio.h>
#endif

#define NXT_SCR2_RTCE 0x00000100U
#define NXT_SCR2_RTCLK 0x00000200U
#define NXT_SCR2_RTDATA 0x00000400U

#define NXT_ESP_BASE 0x02014000U
#define NXT_DMA_CSR 0x02000010U
#define NXT_INTR_SCSI (1U << 12)
#define NXT_INTR_DISK (1U << 13)
#define NXT_INTR_SCSI_DMA (1U << 26)
#define NXT_INTR_TIMER (1U << 29)

static NXTUInt32
NXTCanonicalIOAddress (NXTUInt32 address)
{
  address &= 0x7fffffffU;
  if ((address & 0xfff00000U) == 0x02100000U)
    address -= 0x00100000U;
  return address;
}

static int
NXTDMAChannelForAddress (NXTUInt32 address)
{
  static const NXTUInt16 offsets[12]
      = { 0x010, 0x040, 0x050, 0x080, 0x090, 0x0c0,
          0x0d0, 0x110, 0x150, 0x180, 0x1c0, 0x1d0 };
  unsigned int index;
  if (address < 0x02000000U || address >= 0x02000200U)
    return -1;
  for (index = 0; index < 12; index++)
    if (address - 0x02000000U == offsets[index])
      return (int)index;
  return -1;
}

#ifdef NXT_TRACE_MMIO
static void
NXTTraceMMIO (NXTUInt32 address, BOOL writing, NXTUInt32 size)
{
  static NXTUInt8 seenRead[0x30000];
  static NXTUInt8 seenWrite[0x30000];
  NXTUInt32 canonical = NXTCanonicalIOAddress (address);
  if (canonical == 0x02010000U)
    {
      *value = 0;
      return NXTMemoryResultOK;
    }
  if (canonical == 0x02018004U)
    {
      *value = 0;
      return NXTMemoryResultOK;
    }
  NXTUInt32 slot;
  NXTUInt8 *seen;
  if (canonical < 0x02000000U || canonical >= 0x02300000U)
    return;
  slot = (canonical - 0x02000000U) >> 4;
  seen = writing ? seenWrite : seenRead;
  if (!seen[slot])
    {
      seen[slot] = 1;
      fprintf (stderr, "MMIO %c%u %08x\n", writing ? 'W' : 'R', size,
               canonical);
    }
}
#else
#define NXTTraceMMIO(address, writing, size) ((void)0)
#endif

@implementation NXTMemoryRegion

- (id)initWithBaseAddress:(NXTUInt32)baseAddress
                   length:(NXTUInt32)length
                 readOnly:(BOOL)readOnly
{
  self = [super init];
  if (self != nil)
    {
      if (length == 0)
        {
          [self release];
          return nil;
        }
      _bytes = (NXTUInt8 *)calloc ((size_t)length, sizeof (NXTUInt8));
      if (_bytes == NULL)
        {
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
  free (_bytes);
  [super dealloc];
}

- (NXTUInt32)baseAddress
{
  return _baseAddress;
}
- (NXTUInt32)length
{
  return _length;
}
- (BOOL)isReadOnly
{
  return _readOnly;
}
- (NXTUInt8 *)mutableBytes
{
  return _bytes;
}

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

- (void)resetSCSI
{
  memset (_espRegisters, 0, sizeof (_espRegisters));
  memset (_espFIFO, 0, sizeof (_espFIFO));
  memset (_dmaRegisters, 0, sizeof (_dmaRegisters));
  memset (_dmaCSR, 0, sizeof (_dmaCSR));
  memset (_enetRegisters, 0, sizeof (_enetRegisters));
  _enetRegisters[6] = 0x80;
  _enetRegisters[8] = 0x00;
  _enetRegisters[9] = 0x00;
  _enetRegisters[10] = 0x0f;
  _enetRegisters[11] = 0x12;
  _enetRegisters[12] = 0x34;
  _enetRegisters[13] = 0x56;
  _espRegisters[9] = 2;
  _espFIFOCount = 0;
  _espInterrupt = 0;
  _scsiPhase = 3;
  _scsiStatus = 0;
  [_scsiData release];
  _scsiData = nil;
  _scsiDataOffset = 0;
  /* No transfer is pending at power-on.  Advertising COMPLETE here makes
     the ROM's SCSI DMA POST report a stale completion interrupt. */
  _dmaState = 0;
}

- (BOOL)attachSCSIDiskAtPath:(NSString *)path error:(NSString **)errorMessage
{
  NSFileHandle *handle;
  NSDictionary *attributes;
  if (errorMessage != NULL)
    *errorMessage = nil;
  handle = [NSFileHandle fileHandleForReadingAtPath:path];
  attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path
                                                                error:NULL];
  if (handle == nil || attributes == nil)
    {
      if (errorMessage != NULL)
        *errorMessage = @"Unable to open disk image";
      return NO;
    }
  [handle retain];
  [_scsiFile closeFile];
  [_scsiFile release];
  _scsiFile = handle;
  _scsiSize = [[attributes objectForKey:NSFileSize] unsignedLongLongValue];
  [self resetSCSI];
  return YES;
}

- (void)setSCSIResponse:(NSData *)data
                  phase:(NXTUInt8)phase
                 status:(NXTUInt8)status
{
  [data retain];
  [_scsiData release];
  _scsiData = data;
  _scsiDataOffset = 0;
  _scsiPhase = phase;
  _scsiStatus = status;
}

- (void)executeSCSICommandWithIdentify:(BOOL)hasIdentify
{
  NXTUInt8 cdb[16];
  unsigned int start = hasIdentify ? 1 : 0;
  unsigned int count = _espFIFOCount > start ? _espFIFOCount - start : 0;
  NXTUInt32 lba = 0, blocks = 0, allocation = 0;
  NSMutableData *response = nil;
  NXTUInt8 *bytes;
  memset (cdb, 0, sizeof (cdb));
  if (count > sizeof (cdb))
    count = sizeof (cdb);
  if (count != 0)
    memcpy (cdb, _espFIFO + start, count);
  _espFIFOCount = 0;
#ifdef NXT_TRACE_SCSI
  fprintf (stderr,
           "SCSI CDB %02x count=%u id=%u "
           "bytes=%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x\n",
           cdb[0], count, _espRegisters[4] & 7U, cdb[0], cdb[1], cdb[2],
           cdb[3], cdb[4], cdb[5], cdb[6], cdb[7], cdb[8], cdb[9]);
#endif
  /* The monitor's default `sd(0,0,0)` boot selects SCSI target 0.  Register
     4 is the destination ID when written (and the status register when
     read), so do not confuse it with the controller's own ID. */
  if (_scsiFile == nil || (_espRegisters[4] & 7) != 0)
    {
      _espInterrupt = 0x20;
      _interruptStatus |= NXT_INTR_SCSI;
      _scsiInterruptDelay = 10;
      _scsiPhase = 3;
      return;
    }
  switch (cdb[0])
    {
    case 0x00:
    case 0x04:
    case 0x15:
    case 0x1b:
      [self setSCSIResponse:nil phase:3 status:0];
      break;
    case 0x03:
      {
        NXTUInt8 sense[18];
        allocation = cdb[4] ? cdb[4] : 18;
        if (allocation > sizeof (sense))
          allocation = sizeof (sense);
        memset (sense, 0, sizeof (sense));
        sense[0] = 0x70;
        sense[7] = 10;
        [self setSCSIResponse:[NSData dataWithBytes:sense length:allocation]
                        phase:1
                       status:0];
        break;
      }
    case 0x12:
      {
        static const NXTUInt8 inquiry[54]
            = { 0,   0,   1,   2,   49,  0,   0,   0x1c, 'N', 'e', 'X',
                'T', ' ', ' ', ' ', ' ', 'H', 'D', ' ',  ' ', ' ', ' ',
                ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ',  ' ', ' ', '1',
                '.', '0', ' ', ' ', ' ', ' ', ' ', ' ',  ' ', ' ', ' ',
                ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ',  ' ', ' ' };
        allocation = cdb[4];
        if (allocation > sizeof (inquiry))
          allocation = sizeof (inquiry);
        [self setSCSIResponse:[NSData dataWithBytes:inquiry length:allocation]
                        phase:1
                       status:0];
        break;
      }
    case 0x25:
      {
        NXTUInt8 capacity[8];
        NXTUInt32 last = (NXTUInt32)(_scsiSize / 512U - 1U);
        capacity[0] = last >> 24;
        capacity[1] = last >> 16;
        capacity[2] = last >> 8;
        capacity[3] = last;
        capacity[4] = 0;
        capacity[5] = 0;
        capacity[6] = 2;
        capacity[7] = 0;
        [self setSCSIResponse:[NSData dataWithBytes:capacity length:8]
                        phase:1
                       status:0];
        break;
      }
    case 0x1a:
      {
        NXTUInt8 mode[12];
        NXTUInt32 sectors = (NXTUInt32)(_scsiSize / 512U);
        memset (mode, 0, sizeof (mode));
        mode[0] = 11;
        mode[3] = 8;
        mode[5] = sectors >> 16;
        mode[6] = sectors >> 8;
        mode[7] = sectors;
        mode[10] = 2;
        allocation = cdb[4];
        if (allocation > sizeof (mode))
          allocation = sizeof (mode);
        [self setSCSIResponse:[NSData dataWithBytes:mode length:allocation]
                        phase:1
                       status:0];
        break;
      }
    case 0x08:
    case 0x28:
      if (cdb[0] == 0x08)
        {
          lba = ((NXTUInt32)(cdb[1] & 0x1f) << 16) | ((NXTUInt32)cdb[2] << 8)
                | cdb[3];
          blocks = cdb[4] ? cdb[4] : 256;
        }
      else
        {
          lba = ((NXTUInt32)cdb[2] << 24) | ((NXTUInt32)cdb[3] << 16)
                | ((NXTUInt32)cdb[4] << 8) | cdb[5];
          blocks = ((NXTUInt32)cdb[7] << 8) | cdb[8];
        }
      if ((NXTUInt64)lba * 512U + (NXTUInt64)blocks * 512U <= _scsiSize)
        {
          [_scsiFile seekToFileOffset:(unsigned long long)lba * 512ULL];
          response = (NSMutableData *)[_scsiFile
              readDataOfLength:(NSUInteger)blocks * 512U];
          [self setSCSIResponse:response
                          phase:1
                         status:[response length] == blocks * 512U ? 0 : 2];
        }
      else
        [self setSCSIResponse:nil phase:3 status:2];
      break;
    case 0x0a:
    case 0x2a:
      [self setSCSIResponse:nil phase:0 status:0];
      break;
    default:
      [self setSCSIResponse:nil phase:3 status:2];
      break;
    }
  bytes = _espFIFO;
  (void)bytes;
  _espRegisters[6] = 4;
  _espInterrupt = 0x18;
  _interruptStatus |= NXT_INTR_SCSI;
  _scsiInterruptDelay = 10;
}

- (void)performSCSIDMA
{
  NXTUInt32 address = _dmaRegisters[4];
  NXTUInt32 limit = _dmaRegisters[5];
  NXTUInt32 requested
      = (NXTUInt32)_espRegisters[0] | ((NXTUInt32)_espRegisters[1] << 8);
  NXTUInt32 room = limit > address ? limit - address : 0;
  NXTUInt32 available
      = _scsiData == nil ? 0
                         : (NXTUInt32)([_scsiData length] - _scsiDataOffset);
  NXTUInt32 amount = requested == 0 ? 65536U : requested;
  NXTUInt32 i;
  if (amount > room)
    amount = room;
  if (_scsiPhase == 1)
    {
      if (amount > available)
        amount = available;
      for (i = 0; i < amount; i++)
        [self writeByte:((const NXTUInt8 *)
                             [_scsiData bytes])[_scsiDataOffset + i]
              atAddress:address + i];
      _scsiDataOffset += amount;
      if (_scsiDataOffset >= [_scsiData length])
        _scsiPhase = 3;
    }
  else if (_scsiPhase == 0)
    {
      /* Images are opened read-only; consume guest writes so boot-time
       * metadata does not stall. */
      amount = amount > room ? room : amount;
      _scsiPhase = 3;
    }
  else
    amount = 0;
  _dmaRegisters[4] = address + amount;
#ifdef NXT_TRACE_SCSI
  fprintf (stderr,
           "SCSI DMA phase=%u address=%08x limit=%08x requested=%u amount=%u "
           "available=%u\n",
           _scsiPhase, address, limit, requested, amount, available);
#endif
  requested = (requested == 0 ? 65536U : requested) - amount;
  _espRegisters[0] = (NXTUInt8)requested;
  _espRegisters[1] = (NXTUInt8)(requested >> 8);
  /* The initiator's transfer count, rather than the size of the target's
     backing response, terminates this data phase.  Leaving unread response
     padding active makes the following status transfer consume disk bytes
     and causes the ROM to retry every READ indefinitely. */
  if (requested == 0 && (_scsiPhase == 0 || _scsiPhase == 1))
    _scsiPhase = 3;
  _dmaState = 0x08;
  _espInterrupt = 0x08;
  _interruptStatus |= NXT_INTR_SCSI | NXT_INTR_DISK | NXT_INTR_SCSI_DMA;
  _scsiInterruptDelay = 0; /* DMA completion is sampled immediately. */
}

- (void)resetNeXTDevicesForTurbo:(BOOL)turbo
{
  NXTUInt32 sum;
  NXTUInt16 checksum;
  unsigned int index;
  memset (_rtcRegisters, 0, sizeof (_rtcRegisters));
  /* Keep the console on the built-in display.  Bit 27 (0x08 here)
     selects the alternate serial console and leaves the framebuffer
     showing the stale "Testing System" message. */
  _rtcRegisters[0] = 0x94;
  _rtcRegisters[1] = 0x0f;
  _rtcRegisters[2] = 0x40;
  _rtcRegisters[10] = 0x02;
  _rtcRegisters[11] = 0x49;
  _rtcRegisters[14] = 0x21; /* POT enabled, boot without extended tests */
  _rtcRegisters[17] = 0x80; /* MCS1850 clock */
  _rtcRegisters[18] = 's';
  _rtcRegisters[19] = 'd';
  if (_verboseBoot)
    {
      _rtcRegisters[20] = ' ';
      _rtcRegisters[21] = '-';
      _rtcRegisters[22] = 'v';
    }
  _rtcRegisters[30] = 0;
  _rtcRegisters[31] = 0;
  _rtcSeconds = 1704067200U;
  sum = 0;
  for (index = 0; index < 32; index += 2)
    sum += ((NXTUInt16)_rtcRegisters[index] << 8) | _rtcRegisters[index + 1];
  while (sum > 0xffffU)
    sum = (sum & 0xffffU) + (sum >> 16);
  checksum = (NXTUInt16)~sum;
  _rtcRegisters[30] = (NXTUInt8)(checksum >> 8);
  _rtcRegisters[31] = (NXTUInt8)checksum;
  _scr2Value = turbo ? 0x000f1080U : 0x00ff0c80U;
  _rtcPhase = 0;
  _rtcBitCount = 0;
  _rtcDataBit = NO;
  _rtcPreviousClock = NO;
  memset (_bmapRegisters, 0, sizeof (_bmapRegisters));
  _bmapRegisters[13] = 0x20000000U;
  memset (_adbRegisters, 0, sizeof (_adbRegisters));
  memset (_sccRegisterPointer, 0, sizeof (_sccRegisterPointer));
  memset (_sccRegisters, 0, sizeof (_sccRegisters));
  memset (_sccReceiveData, 0, sizeof (_sccReceiveData));
  memset (_sccReceiveAvailable, 0, sizeof (_sccReceiveAvailable));
  _interruptStatus = 0;
  _interruptMask = 0;
  _kernelEventCounterMode = NO;
  _scsiInterruptDelay = 0;
  _hardclockStaging = 0;
  _hardclockReload = 0;
  _hardclockCSR = 0;
  _hardclockTicks = 0;
  [self resetSCSI];
}

- (void)setVerboseBoot:(BOOL)verbose
{
  _verboseBoot = verbose;
}

- (void)setKernelEventCounterMode
{
  _kernelEventCounterMode = YES;
}

- (unsigned int)pendingInterruptLevel
{
  NXTUInt32 pending = _interruptStatus & _interruptMask;
  unsigned int hardclockInterval = (unsigned int)_hardclockReload * 8U;
  if (_kernelEventCounterMode)
    _eventCounter = (_eventCounter + 1U) & 0x000fffffU;
  if (hardclockInterval < 5000U)
    hardclockInterval = 5000U;
  if ((_hardclockCSR & 0x80U) != 0 && _hardclockReload != 0
      && (_interruptMask & NXT_INTR_TIMER) != 0
      && ++_hardclockTicks >= hardclockInterval)
    {
      _hardclockTicks = 0;
      _interruptStatus |= NXT_INTR_TIMER;
      pending = _interruptStatus & _interruptMask;
    }
  if (_scsiInterruptDelay != 0)
    {
      _scsiInterruptDelay--;
      pending &= ~(NXT_INTR_SCSI | NXT_INTR_DISK);
    }
  if (pending & 0xfc7c0000U)
    return 6;
  if (pending & 0x00038000U)
    return 5;
  if (pending & 0x00004000U)
    return 4;
  if (pending & 0x00003ffcU)
    return 3;
  if (pending & 0x00000002U)
    return 2;
  if (pending & 0x00000001U)
    return 1;
  return 0;
}

- (NXTUInt8)rtcRegisterValue:(NXTUInt8)address
{
  NXTUInt32 seconds;
  address &= 0x3f;
  if (address >= 0x20 && address <= 0x23)
    {
      seconds = _rtcSeconds++; /* Advance while the ROM polls the clock. */
      _rtcRegisters[0x20] = (NXTUInt8)(seconds >> 24);
      _rtcRegisters[0x21] = (NXTUInt8)(seconds >> 16);
      _rtcRegisters[0x22] = (NXTUInt8)(seconds >> 8);
      _rtcRegisters[0x23] = (NXTUInt8)seconds;
    }
  if (address == 0x30)
    return 0x80;
  if (address == 0x31)
    return 0x80;
  return _rtcRegisters[address];
}

- (void)rtcSCR2DidChangeFrom:(NXTUInt32)oldValue to:(NXTUInt32)newValue
{
  BOOL enable;
  BOOL oldEnable;
  BOOL clock;
  BOOL falling;
  BOOL rising;
  BOOL data;
  enable = (newValue & NXT_SCR2_RTCE) != 0;
  oldEnable = (oldValue & NXT_SCR2_RTCE) != 0;
  clock = (newValue & NXT_SCR2_RTCLK) != 0;
  data = (newValue & NXT_SCR2_RTDATA) != 0;
  if (enable && !oldEnable)
    {
      _rtcPhase = 1;
      _rtcBitCount = 0;
      _rtcShiftIn = 0;
      _rtcDataBit = NO;
      _rtcPreviousClock = clock;
      return;
    }
  if (!enable)
    {
      _rtcPhase = 0;
      _rtcDataBit = NO;
      _rtcPreviousClock = NO;
      return;
    }
  falling = _rtcPreviousClock && !clock;
  rising = !_rtcPreviousClock && clock;
  _rtcPreviousClock = clock;
  if (_rtcPhase == 1 && falling)
    {
      _rtcShiftIn = (NXTUInt8)((_rtcShiftIn << 1) | (data ? 1 : 0));
      _rtcBitCount++;
      if (_rtcBitCount == 8)
        {
          _rtcAddress = _rtcShiftIn;
          _rtcIsWrite = (_rtcAddress & 0x80) != 0;
          _rtcPhase = 2;
          _rtcBitCount = 0;
          _rtcShiftIn = 0;
          if (!_rtcIsWrite)
            {
              _rtcShiftOut = [self rtcRegisterValue:_rtcAddress];
#ifdef NXT_TRACE_RTC
              fprintf (stderr, "RTC read %02x = %02x\n", _rtcAddress & 0x3f,
                       _rtcShiftOut);
#endif
            }
        }
    }
  else if (_rtcPhase == 2 && _rtcIsWrite && falling)
    {
      _rtcShiftIn = (NXTUInt8)((_rtcShiftIn << 1) | (data ? 1 : 0));
      _rtcBitCount++;
      if (_rtcBitCount == 8)
        {
          _rtcRegisters[_rtcAddress & 0x3f] = _rtcShiftIn;
          _rtcAddress = (NXTUInt8)(0x80 | ((_rtcAddress + 1) & 0x3f));
          _rtcBitCount = 0;
          _rtcShiftIn = 0;
        }
    }
  else if (_rtcPhase == 2 && !_rtcIsWrite && rising)
    {
      if (_rtcBitCount == 8)
        {
          _rtcAddress = (NXTUInt8)((_rtcAddress + 1) & 0x3f);
          _rtcShiftOut = [self rtcRegisterValue:_rtcAddress];
          _rtcBitCount = 0;
        }
      _rtcDataBit = (_rtcShiftOut & 0x80) != 0;
      _rtcShiftOut <<= 1;
      _rtcBitCount++;
    }
}

- (id)init
{
  self = [super init];
  if (self != nil)
    {
      _regions = [[NSMutableArray alloc] init];
    }
  return self;
}

- (void)dealloc
{
  [_scsiFile closeFile];
  [_scsiFile release];
  [_scsiData release];
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

  if (region == nil)
    return NO;
  newStart = [region baseAddress];
  newEnd = newStart + [region length];
  for (index = 0; index < [_regions count]; index++)
    {
      existing = [_regions objectAtIndex:index];
      oldStart = [existing baseAddress];
      oldEnd = oldStart + [existing length];
      if (newStart < oldEnd && oldStart < newEnd)
        return NO;
    }
  [_regions addObject:region];
  return YES;
}

- (NXTMemoryRegion *)regionContainingAddress:(NXTUInt32)address
                                      length:(NXTUInt32)length
{
  NSUInteger index;
  NXTMemoryRegion *region;

  for (index = 0; index < [_regions count]; index++)
    {
      region = [_regions objectAtIndex:index];
      if ([region containsAddress:address length:length])
        return region;
    }
  return nil;
}

- (NXTMemoryResult)readByte:(NXTUInt8 *)value atAddress:(NXTUInt32)address
{
  NXTMemoryRegion *region;
  NXTUInt32 canonical;
  if (value == NULL)
    return NXTMemoryResultOutOfRange;
  NXTTraceMMIO (address, NO, 1);
  canonical = address & 0x7fffffffU;
  if ((canonical & 0xfff00000U) == 0x02100000U)
    canonical -= 0x00100000U;
  if (canonical >= 0x02014100U && canonical <= 0x02014108U)
    {
      *value = canonical == 0x02014104U ? 0x80U : 0;
      return NXTMemoryResultOK;
    }
  if (canonical >= NXT_ESP_BASE && canonical < NXT_ESP_BASE + 16U)
    {
      unsigned int reg = canonical - NXT_ESP_BASE;
      if (reg == 2)
        {
          *value = _espFIFOCount ? _espFIFO[0] : 0;
          if (_espFIFOCount)
            {
              memmove (_espFIFO, _espFIFO + 1, --_espFIFOCount);
            }
        }
      else if (reg == 4)
        {
          *value
              = (NXTUInt8)(0x80U | (_scsiPhase & 7U)
                           | ((_espRegisters[0] == 0 && _espRegisters[1] == 0)
                                  ? 0x10U
                                  : 0));
        }
      else if (reg == 5)
        {
          *value = _espInterrupt;
          _espInterrupt = 0;
          _interruptStatus &= ~(NXT_INTR_SCSI | NXT_INTR_DISK);
          _scsiInterruptDelay = 0;
        }
      else if (reg == 7)
        *value = (NXTUInt8)_espFIFOCount;
      else
        *value = _espRegisters[reg];
#ifdef NXT_TRACE_SCSI
      fprintf (stderr, "ESP R%u=%02x\n", reg, *value);
#endif
      return NXTMemoryResultOK;
    }
  if (canonical == NXT_ESP_BASE + 0x20U)
    {
      *value = _espRegisters[12];
      return NXTMemoryResultOK;
    }
  if (canonical == NXT_ESP_BASE + 0x21U)
    {
      *value = _espInterrupt ? 1 : 0;
      return NXTMemoryResultOK;
    }
  if (canonical >= 0x0200e000U && canonical < 0x0200e010U)
    {
      region = [self regionContainingAddress:canonical length:1];
      *value = canonical == 0x0200e002U
                   ? 0x02U
                   : (region == nil ? 0
                                    : [region mutableBytes]
                                          [canonical - [region baseAddress]]);
      return NXTMemoryResultOK;
    }
  if (canonical >= 0x02018000U && canonical < 0x02018004U)
    {
      switch (canonical - 0x02018000U)
        {
        case 0:
          *value = (NXTUInt8)(0x04U | (_sccReceiveAvailable[1] ? 1U : 0U));
          break;
        case 1:
          *value
              = _sccRegisterPointer[0] == 1
                    ? 0x07
                    : (_sccRegisterPointer[0] == 0
                           ? (NXTUInt8)(0x2cU
                                        | (_sccReceiveAvailable[0] ? 1U : 0U))
                           : 0);
          _sccRegisterPointer[0] = 0;
          break;
        case 2:
          *value = _sccReceiveData[1];
          _sccReceiveAvailable[1] = NO;
          break;
        default:
          *value = _sccReceiveData[0];
          _sccReceiveAvailable[0] = NO;
          break;
        }
      return NXTMemoryResultOK;
    }
  if (canonical >= 0x02006000U && canonical < 0x02006010U)
    {
      unsigned int reg = canonical - 0x02006000U;
      *value = _enetRegisters[reg];
      if (reg == 0 && (_enetRegisters[6] & 0x80U) == 0)
        *value |= 0x80U;
      else if (reg == 1)
        *value &= 0xafU;
      else if (reg == 3)
        *value &= 0x9fU;
      else if (reg == 6)
        *value |= 0x40U;
      return NXTMemoryResultOK;
    }
  if (canonical >= 0x02008000U && canonical < 0x02008008U)
    {
      static const NXTUInt8 dspRegisters[8]
          = { 0x00, 0x00, 0x9f, 0x0f, 0x00, 0x00, 0x00, 0x00 };
      *value = dspRegisters[canonical - 0x02008000U];
      return NXTMemoryResultOK;
    }
  if (canonical >= 0x0201a000U && canonical <= 0x0201a003U)
    {
      if ((canonical & 3) == 0)
        {
          if (_kernelEventCounterMode)
            {
              /* Kernel reads passively latch the free-running counter,
                 which advances with guest execution in the device tick. */
              _eventLatch = _eventCounter;
            }
          else
            {
              /* ROM POST uses the slower board-test calibration scale. */
              _eventCounter += 200U;
              _eventLatch = (_eventCounter / 30U) * 5U;
            }
        }
      *value = (NXTUInt8)(_eventLatch >> ((3 - (canonical & 3)) * 8));
      return NXTMemoryResultOK;
    }
  if (canonical == 0x02016000U || canonical == 0x02016001U)
    {
      *value = (NXTUInt8)(_eventCounter >> (canonical == 0x02016000U ? 8 : 0));
      return NXTMemoryResultOK;
    }
  if (canonical == 0x02016004U)
    {
      *value = (_interruptMask & NXT_INTR_TIMER) != 0 ? _hardclockCSR : 0;
      _interruptStatus &= ~NXT_INTR_TIMER;
      return NXTMemoryResultOK;
    }
  region = [self regionContainingAddress:address length:1];
  if (region == nil)
    return NXTMemoryResultUnmapped;
  *value = [region mutableBytes][address - [region baseAddress]];
  return NXTMemoryResultOK;
}

- (NXTMemoryResult)readWord:(NXTUInt16 *)value atAddress:(NXTUInt32)address
{
  NXTMemoryRegion *region;
  NXTUInt8 *bytes;
  if (value == NULL)
    return NXTMemoryResultOutOfRange;
  NXTTraceMMIO (address, NO, 2);
  if ((address & 0x7ffffffeU) == 0x02008000U)
    {
      *value = (address & 2) != 0 ? 0x9f0fU : 0;
      return NXTMemoryResultOK;
    }
  if (NXTCanonicalIOAddress (address) == 0x02016000U)
    {
      *value = (NXTUInt16)_eventCounter;
      return NXTMemoryResultOK;
    }
  if (NXTCanonicalIOAddress (address) == 0x0201a000U)
    {
      _eventCounter += 1024U;
      *value = (NXTUInt16)_eventCounter;
      return NXTMemoryResultOK;
    }
  region = [self regionContainingAddress:address length:2];
  if (region == nil)
    return NXTMemoryResultUnmapped;
  bytes = [region mutableBytes] + address - [region baseAddress];
  *value = (NXTUInt16)(((NXTUInt16)bytes[0] << 8) | bytes[1]);
  return NXTMemoryResultOK;
}

- (NXTMemoryResult)readLong:(NXTUInt32 *)value atAddress:(NXTUInt32)address
{
  NXTMemoryRegion *region;
  NXTUInt8 *bytes;
  if (value == NULL)
    return NXTMemoryResultOutOfRange;
  NXTTraceMMIO (address, NO, 4);
  {
    NXTUInt32 canonical = NXTCanonicalIOAddress (address);
    int dmaChannel = NXTDMAChannelForAddress (canonical);
    if (canonical == NXT_DMA_CSR)
      {
        *value = ((NXTUInt32)_dmaState << 24) | 0x40U;
        return NXTMemoryResultOK;
      }
    if (dmaChannel > 0)
      {
        *value = (NXTUInt32)_dmaCSR[dmaChannel] << 24;
        return NXTMemoryResultOK;
      }
    if (canonical == 0x02007000U)
      {
        *value = _interruptStatus;
        return NXTMemoryResultOK;
      }
    if (canonical == 0x02007800U)
      {
        *value = _interruptMask;
        return NXTMemoryResultOK;
      }
    if (canonical >= 0x020c0000U && canonical < 0x020c0040U)
      {
        *value = _bmapRegisters[(canonical - 0x020c0000U) >> 2];
        return NXTMemoryResultOK;
      }
    if (canonical == 0x02200010U)
      {
        *value = 0x0d17038fU;
        return NXTMemoryResultOK;
      }
    if (canonical == 0x02200088U)
      {
        *value = 0x304a4118U;
        return NXTMemoryResultOK;
      }
    if (canonical == 0x0220008cU)
      {
        *value = 0x10430340U;
        return NXTMemoryResultOK;
      }
    if (canonical >= 0x02208000U && canonical <= 0x02208088U
        && (canonical & 3U) == 0)
      {
        *value = _adbRegisters[(canonical - 0x02208000U) >> 2];
        return NXTMemoryResultOK;
      }
    if (canonical >= 0x02004000U && canonical <= 0x0200401cU
        && (canonical & 3U) == 0)
      {
        *value = _dmaRegisters[(canonical - 0x02004000U) >> 2];
        return NXTMemoryResultOK;
      }
    if (canonical == 0x02004210U)
      {
        *value = _dmaRegisters[8];
        return NXTMemoryResultOK;
      }
  }
  if ((address & 0x7ffffffcU) == 0x02008000U)
    {
      *value = 0x00009f0fU;
      return NXTMemoryResultOK;
    }
  if ((address & 0x7fffffffU) == 0x0200d000U)
    {
      *value = _scr2Value;
      if (_rtcPhase == 2 && !_rtcIsWrite && (_scr2Value & NXT_SCR2_RTCE) != 0)
        {
          if (_rtcDataBit)
            *value |= NXT_SCR2_RTDATA;
          else
            *value &= ~NXT_SCR2_RTDATA;
        }
      return NXTMemoryResultOK;
    }
  region = [self regionContainingAddress:address length:4];
  if (region == nil)
    return NXTMemoryResultUnmapped;
  bytes = [region mutableBytes] + address - [region baseAddress];
  *value = ((NXTUInt32)bytes[0] << 24) | ((NXTUInt32)bytes[1] << 16)
           | ((NXTUInt32)bytes[2] << 8) | bytes[3];
  return NXTMemoryResultOK;
}

- (NXTMemoryResult)writeByte:(NXTUInt8)value atAddress:(NXTUInt32)address
{
  NXTMemoryRegion *region;
  NXTTraceMMIO (address, YES, 1);
  NXTUInt32 canonical = NXTCanonicalIOAddress (address);
  if (canonical == 0x02010000U)
    return NXTMemoryResultOK;
  if (canonical == 0x02018004U)
    return NXTMemoryResultOK;
  if (canonical >= 0x02014100U && canonical <= 0x02014108U)
    return NXTMemoryResultOK;
  if (canonical >= NXT_ESP_BASE && canonical < NXT_ESP_BASE + 16U)
    {
      unsigned int reg = canonical - NXT_ESP_BASE;
#ifdef NXT_TRACE_SCSI
      fprintf (stderr, "ESP W%u=%02x\n", reg, value);
#endif
      if (reg == 2)
        {
          if (_espFIFOCount < sizeof (_espFIFO))
            _espFIFO[_espFIFOCount++] = value;
        }
      else if (reg == 3)
        {
          NXTUInt8 command = value & 0x7fU;
          if (command == 1)
            _espFIFOCount = 0;
          else if (command == 2 || command == 3)
            [self resetSCSI];
          else if (command == 0x41 || command == 0x42)
            [self executeSCSICommandWithIdentify:command == 0x42];
          else if (command == 0x10)
            {
              if (value & 0x80U)
                [self performSCSIDMA];
              else if (_scsiPhase == 1 && _scsiDataOffset < [_scsiData length])
                {
                  _espFIFO[0] = ((
                      const NXTUInt8 *)[_scsiData bytes])[_scsiDataOffset++];
                  _espFIFOCount = 1;
                  _espInterrupt = 8;
                  _interruptStatus |= NXT_INTR_SCSI | NXT_INTR_DISK;
                  _scsiInterruptDelay = 10;
                }
            }
          else if (command == 0x11)
            {
              _espFIFO[0] = _scsiStatus;
              _espFIFO[1] = 0;
              _espFIFOCount = 2;
              _scsiPhase = 7;
              _espInterrupt = 8;
              _interruptStatus |= NXT_INTR_SCSI | NXT_INTR_DISK;
              _scsiInterruptDelay = 10;
            }
          else if (command == 0x12)
            {
              _scsiPhase = 3;
              _espInterrupt = 0x10;
              _interruptStatus |= NXT_INTR_SCSI | NXT_INTR_DISK;
              _scsiInterruptDelay = 10;
            }
          else if (command == 0x18)
            { /* Transfer pad */
              NXTUInt32 pad = (NXTUInt32)_espRegisters[0]
                              | ((NXTUInt32)_espRegisters[1] << 8);
              NXTUInt32 available
                  = _scsiData == nil
                        ? 0
                        : (NXTUInt32)([_scsiData length] - _scsiDataOffset);
              if (pad == 0)
                pad = 65536U;
              if (pad > available)
                pad = available;
              _scsiDataOffset += pad;
              _espRegisters[0] = 0;
              _espRegisters[1] = 0;
              if (_scsiDataOffset >= [_scsiData length])
                _scsiPhase = 3;
              _espInterrupt = 0x08;
              _interruptStatus |= NXT_INTR_SCSI | NXT_INTR_DISK;
              _scsiInterruptDelay = 10;
            }
          _espRegisters[3] = value;
        }
      else
        _espRegisters[reg] = value;
      return NXTMemoryResultOK;
    }
  if (canonical == NXT_ESP_BASE + 0x20U)
    {
      _espRegisters[12] = value;
      return NXTMemoryResultOK;
    }
  if (canonical >= 0x0200e000U && canonical < 0x0200e010U)
    {
      region = [self regionContainingAddress:canonical length:1];
      if (region != nil)
        [region mutableBytes][canonical - [region baseAddress]] = value;
      return NXTMemoryResultOK;
    }
  if (canonical >= 0x02018000U && canonical < 0x02018004U)
    {
      NXTUInt32 sccOffset = canonical - 0x02018000U;
#ifdef NXT_TRACE_SCC
      fprintf (stderr, "SCC W%u=%02x pA=%u pB=%u wr14A=%02x wr14B=%02x\n",
               (unsigned)sccOffset, value, _sccRegisterPointer[0],
               _sccRegisterPointer[1], _sccRegisters[0][14],
               _sccRegisters[1][14]);
#endif
      if (sccOffset == 0 || sccOffset == 1)
        {
          unsigned int channel = sccOffset == 1 ? 0 : 1;
          if (_sccRegisterPointer[channel] == 0)
            _sccRegisterPointer[channel]
                = (NXTUInt8)((value & 7U)
                             | (((value & 0x38U) == 0x08U) ? 8U : 0U));
          else
            {
              _sccRegisters[channel][_sccRegisterPointer[channel]] = value;
              _sccRegisterPointer[channel] = 0;
            }
        }
      else if (sccOffset == 3)
        {
          if ((_sccRegisters[0][14] & 0x10U) != 0)
            {
              _sccReceiveData[0] = value;
              _sccReceiveAvailable[0] = YES;
            }
        }
      else if (sccOffset == 2)
        {
          if ((_sccRegisters[1][14] & 0x10U) != 0)
            {
              _sccReceiveData[1] = value;
              _sccReceiveAvailable[1] = YES;
            }
        }
      return NXTMemoryResultOK;
    }
  if (canonical == 0x02016000U)
    {
      _eventCounter = (_eventCounter & 0xffff00ffU) | ((NXTUInt32)value << 8);
      _hardclockStaging = (NXTUInt16)((_hardclockStaging & 0x00ffU)
                                      | ((NXTUInt16)value << 8));
      return NXTMemoryResultOK;
    }
  if (canonical == 0x02016001U)
    {
      _eventCounter = (_eventCounter & 0xffffff00U) | value;
      _hardclockStaging = (NXTUInt16)((_hardclockStaging & 0xff00U) | value);
      return NXTMemoryResultOK;
    }
  if (canonical == 0x02016004U)
    {
      _hardclockCSR = value;
      if ((value & 0x40U) != 0)
        {
          _hardclockReload = _hardclockStaging;
          _hardclockCSR &= (NXTUInt8)~0x40U;
        }
      _interruptStatus &= ~NXT_INTR_TIMER;
      _hardclockTicks = 0;
      return NXTMemoryResultOK;
    }
  if (canonical >= 0x02006000U && canonical < 0x02006010U)
    {
      unsigned int reg = canonical - 0x02006000U;
      if (reg == 0)
        _enetRegisters[0] &= (NXTUInt8)~value;
      else if (reg == 2)
        _enetRegisters[2] &= (NXTUInt8) ~(value & 0x8fU);
      else if (reg == 6)
        {
          _enetRegisters[6] = value & 0x80U;
          if (value & 0x80U)
            {
              _enetRegisters[0] = 0;
              _enetRegisters[2] = 0;
            }
          else
            _enetRegisters[0] = 0x80U;
        }
      else
        _enetRegisters[reg] = value;
      return NXTMemoryResultOK;
    }
  region = [self regionContainingAddress:address length:1];
  if (region == nil)
    return NXTMemoryResultUnmapped;
  if ([region isReadOnly])
    return NXTMemoryResultReadOnly;
  [region mutableBytes][address - [region baseAddress]] = value;
  return NXTMemoryResultOK;
}

- (NXTMemoryResult)writeWord:(NXTUInt16)value atAddress:(NXTUInt32)address
{
  NXTMemoryRegion *region;
  NXTTraceMMIO (address, YES, 2);
  NXTUInt8 *bytes;
  region = [self regionContainingAddress:address length:2];
  if (region == nil)
    return NXTMemoryResultUnmapped;
  if ([region isReadOnly])
    return NXTMemoryResultReadOnly;
  bytes = [region mutableBytes] + address - [region baseAddress];
  bytes[0] = (NXTUInt8)(value >> 8);
  bytes[1] = (NXTUInt8)value;
  return NXTMemoryResultOK;
}

- (NXTMemoryResult)writeLong:(NXTUInt32)value atAddress:(NXTUInt32)address
{
  NXTMemoryRegion *region;
  NXTTraceMMIO (address, YES, 4);
  NXTUInt8 *bytes;
  {
    NXTUInt32 canonical = NXTCanonicalIOAddress (address);
#ifdef NXT_TRACE_DMA
    if (canonical >= 0x02004000U && canonical < 0x02004400U)
      fprintf (stderr, "DMAREG W %08x=%08x\n", canonical, value);
#endif
    int dmaChannel = NXTDMAChannelForAddress (canonical);
    if (canonical == NXT_DMA_CSR)
      {
        if (value & 0x00100000U)
          {
            _dmaState &= ~(0x0bU);
            _interruptStatus &= ~NXT_INTR_SCSI_DMA;
          }
        if (value & 0x00010000U)
          _dmaState |= 1U;
        if (value & 0x00020000U)
          _dmaState |= 2U;
        if (value & 0x00080000U)
          {
            _dmaState &= ~8U;
            _interruptStatus &= ~NXT_INTR_SCSI_DMA;
          }
        return NXTMemoryResultOK;
      }
    if (dmaChannel > 0)
      {
#ifdef NXT_TRACE_DMA
        fprintf (stderr, "DMACSR W ch%d=%08x\n", dmaChannel, value);
#endif
        if (value & 0x00100000U)
          _dmaCSR[dmaChannel] &= ~(0x0bU);
        if (value & 0x00010000U)
          _dmaCSR[dmaChannel] |= 1U;
        if (value & 0x00020000U)
          _dmaCSR[dmaChannel] |= 2U;
        if (value & 0x00080000U)
          _dmaCSR[dmaChannel] &= ~8U;
        if (dmaChannel == 7 && (value & 0x00010000U) != 0)
          {
            NXTUInt32 source = 0, sourceLimit = 0, destination = 0,
                      destinationLimit = 0;
            NXTUInt32 count, index;
            NXTUInt8 byteValue;
            BOOL accepted = YES, broadcast = YES;
            [self readLong:&source atAddress:0x02004118U];
            [self readLong:&sourceLimit atAddress:0x02004114U];
            [self readLong:&destination atAddress:0x02004150U];
            [self readLong:&destinationLimit atAddress:0x02004154U];
            count = sourceLimit > source ? sourceLimit - source : 0;
            for (index = 0; index < 6; index++)
              {
                if ([self readByte:&byteValue atAddress:source + index]
                    != NXTMemoryResultOK)
                  {
                    accepted = NO;
                    broadcast = NO;
                    break;
                  }
                if (byteValue != _enetRegisters[8 + index])
                  accepted = NO;
                if (byteValue != 0xffU)
                  broadcast = NO;
              }
            accepted = accepted || broadcast;
            if (count > destinationLimit - destination)
              count = destinationLimit - destination;
            for (index = 0; accepted && index < count; index++)
              {
                if ([self readByte:&byteValue atAddress:source + index]
                        != NXTMemoryResultOK
                    || [self writeByte:byteValue atAddress:destination + index]
                           != NXTMemoryResultOK)
                  break;
              }
            /* The receive DMA completion normally advances the active
               descriptor before raising its interrupt.  The ROM polls
               that descriptor during POST, so complete it synchronously
               for the internal Ethernet loopback packet. */
            for (index = 0x0bff0000U; accepted && index < 0x0c000000U;
                 index += 2U)
              {
                NXTUInt32 descriptorStart;
                if ([self readLong:&descriptorStart atAddress:index]
                        == NXTMemoryResultOK
                    && descriptorStart == destination)
                  {
                    [self writeByte:1 atAddress:index + 8U];
                    [self writeLong:destination + count + 1U
                          atAddress:index + 10U];
                    break;
                  }
              }
            if (accepted)
              {
                NXTUInt32 nextDestination = 0, nextDestinationLimit = 0;
                [self readLong:&nextDestination atAddress:0x02004158U];
                [self readLong:&nextDestinationLimit atAddress:0x0200415cU];
                if (nextDestination != 0
                    && nextDestinationLimit > nextDestination)
                  {
                    [self writeLong:nextDestination atAddress:0x02004150U];
                    [self writeLong:nextDestinationLimit
                          atAddress:0x02004154U];
                  }
              }
            _dmaCSR[7] |= 8U;
            if (accepted)
              {
                _dmaCSR[8] |= 8U;
                _enetRegisters[2] |= 0x80U;
              }
          }
        return NXTMemoryResultOK;
      }
    if (canonical == 0x02007800U)
      {
        _interruptMask = value;
        return NXTMemoryResultOK;
      }
    if (canonical >= 0x020c0000U && canonical < 0x020c0040U)
      {
        _bmapRegisters[(canonical - 0x020c0000U) >> 2] = value;
        return NXTMemoryResultOK;
      }
    if (canonical == 0x02200010U
        || (canonical >= 0x02200080U && canonical < 0x02200090U))
      return NXTMemoryResultOK;
    if (canonical >= 0x02208000U && canonical <= 0x02208088U
        && (canonical & 3U) == 0)
      {
        NXTUInt32 adbOffset = canonical - 0x02208000U;
        if (adbOffset == 0x00U)
          _adbRegisters[0] &= ~value;
        else if (adbOffset == 0x10U)
          _adbRegisters[0] |= value;
        else if (adbOffset == 0x20U)
          {
            if (value & 0x08U)
              {
                _adbRegisters[0x28U >> 2] &= ~0x40U;
                _adbRegisters[0] |= 0x08U;
              }
            if (value & 0x04U)
              {
                _adbRegisters[0x28U >> 2] |= 0x04U;
                _adbRegisters[0] |= 0x04U;
              }
            if (value & 0x02U)
              _adbRegisters[0x28U >> 2] &= ~0x40U;
            if (value & 0x01U)
              _adbRegisters[0x28U >> 2] |= 0x40U;
          }
        else
          _adbRegisters[adbOffset >> 2] = value;
        return NXTMemoryResultOK;
      }
    if (canonical >= 0x02004000U && canonical <= 0x0200401cU
        && (canonical & 3U) == 0)
      {
        _dmaRegisters[(canonical - 0x02004000U) >> 2] = value;
        return NXTMemoryResultOK;
      }
    if (canonical == 0x02004210U)
      {
        _dmaRegisters[8] = value;
        _dmaRegisters[4] = value;
        return NXTMemoryResultOK;
      }
  }
  if ((address & 0x7fffffffU) == 0x0200d000U)
    {
      NXTUInt32 oldValue = _scr2Value;
      _scr2Value = value;
      [self rtcSCR2DidChangeFrom:oldValue to:value];
    }
  region = [self regionContainingAddress:address length:4];
  if (region == nil)
    return NXTMemoryResultUnmapped;
  if ([region isReadOnly])
    return NXTMemoryResultReadOnly;
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
  if (length > UINT32_MAX)
    return NXTMemoryResultOutOfRange;
  region = [self regionContainingAddress:address length:(NXTUInt32)length];
  if (region == nil)
    return NXTMemoryResultUnmapped;
  memcpy ([region mutableBytes] + address - [region baseAddress], [data bytes],
          length);
  return NXTMemoryResultOK;
}

@end
