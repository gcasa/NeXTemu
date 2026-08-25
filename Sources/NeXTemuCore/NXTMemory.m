#import "NXTMemory.h"
#include <string.h>

#define NXT_SCR2_RTCE   0x00000100U
#define NXT_SCR2_RTCLK  0x00000200U
#define NXT_SCR2_RTDATA 0x00000400U

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

- (void)resetNeXTDevicesForTurbo:(BOOL)turbo
{
    NXTUInt32 sum;
    NXTUInt16 checksum;
    unsigned int index;
    memset(_rtcRegisters, 0, sizeof(_rtcRegisters));
    _rtcRegisters[0] = 0x9c;
    _rtcRegisters[1] = 0x0f;
    _rtcRegisters[2] = 0x40;
    _rtcRegisters[10] = 0x02;
    _rtcRegisters[11] = 0x49;
    _rtcRegisters[14] = 0x21; /* POT enabled, boot without extended tests */
    _rtcRegisters[17] = 0x80; /* MCS1850 clock */
    _rtcRegisters[18] = 's';
    _rtcRegisters[19] = 'd';
    _rtcRegisters[30] = 0;
    _rtcRegisters[31] = 0;
    sum = 0;
    for (index = 0; index < 32; index += 2)
        sum += ((NXTUInt16)_rtcRegisters[index] << 8) | _rtcRegisters[index + 1];
    while (sum > 0xffffU) sum = (sum & 0xffffU) + (sum >> 16);
    checksum = (NXTUInt16)~sum;
    _rtcRegisters[30] = (NXTUInt8)(checksum >> 8);
    _rtcRegisters[31] = (NXTUInt8)checksum;
    _scr2Value = turbo ? 0x000f1080U : 0x00ff0c80U;
    _rtcPhase = 0;
    _rtcBitCount = 0;
    _rtcDataBit = NO;
    _rtcPreviousClock = NO;
}

- (NXTUInt8)rtcRegisterValue:(NXTUInt8)address
{
    NXTUInt32 seconds;
    address &= 0x3f;
    if (address == 0x20) {
        seconds = 1704067200U; /* 2024-01-01 UTC */
        _rtcRegisters[0x20] = (NXTUInt8)(seconds >> 24);
        _rtcRegisters[0x21] = (NXTUInt8)(seconds >> 16);
        _rtcRegisters[0x22] = (NXTUInt8)(seconds >> 8);
        _rtcRegisters[0x23] = (NXTUInt8)seconds;
    }
    if (address == 0x30) return 0x80;
    if (address == 0x31) return 0x80;
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
    if (enable && !oldEnable) {
        _rtcPhase = 1;
        _rtcBitCount = 0;
        _rtcShiftIn = 0;
        _rtcDataBit = NO;
        _rtcPreviousClock = clock;
        return;
    }
    if (!enable) {
        _rtcPhase = 0;
        _rtcDataBit = NO;
        _rtcPreviousClock = NO;
        return;
    }
    falling = _rtcPreviousClock && !clock;
    rising = !_rtcPreviousClock && clock;
    _rtcPreviousClock = clock;
    if (_rtcPhase == 1 && falling) {
        _rtcShiftIn = (NXTUInt8)((_rtcShiftIn << 1) | (data ? 1 : 0));
        _rtcBitCount++;
        if (_rtcBitCount == 8) {
            _rtcAddress = _rtcShiftIn;
            _rtcIsWrite = (_rtcAddress & 0x80) != 0;
            _rtcPhase = 2;
            _rtcBitCount = 0;
            _rtcShiftIn = 0;
            if (!_rtcIsWrite) _rtcShiftOut = [self rtcRegisterValue:_rtcAddress];
        }
    } else if (_rtcPhase == 2 && _rtcIsWrite && falling) {
        _rtcShiftIn = (NXTUInt8)((_rtcShiftIn << 1) | (data ? 1 : 0));
        _rtcBitCount++;
        if (_rtcBitCount == 8) {
            _rtcRegisters[_rtcAddress & 0x3f] = _rtcShiftIn;
            _rtcAddress = (NXTUInt8)(0x80 | ((_rtcAddress + 1) & 0x3f));
            _rtcBitCount = 0;
            _rtcShiftIn = 0;
        }
    } else if (_rtcPhase == 2 && !_rtcIsWrite && rising) {
        if (_rtcBitCount == 8) {
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
    NXTUInt32 canonical;
    if (value == NULL) return NXTMemoryResultOutOfRange;
    canonical = address & 0x7fffffffU;
    if ((canonical & 0xfff00000U) == 0x02100000U) canonical -= 0x00100000U;
    if (canonical >= 0x02208000U && canonical < 0x02208008U) {
        static const NXTUInt8 dspRegisters[8] = {
            0x00, 0x00, 0x9f, 0x0f, 0x00, 0x00, 0x00, 0x00
        };
        *value = dspRegisters[canonical - 0x02208000U];
        return NXTMemoryResultOK;
    }
    if (canonical >= 0x0201a000U && canonical <= 0x0201a003U) {
        if ((canonical & 3) == 0 || (canonical & 3) == 2) {
            _eventCounter += 1024;
            _eventLatch = _eventCounter;
        }
        *value = (NXTUInt8)(_eventLatch >> ((3 - (canonical & 3)) * 8));
        return NXTMemoryResultOK;
    }
    if (canonical == 0x02016000U || canonical == 0x02016001U) {
        _eventCounter += 1024;
        *value = (NXTUInt8)(_eventCounter >> (canonical == 0x02016000U ? 8 : 0));
        return NXTMemoryResultOK;
    }
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
    if ((address & 0x7ffffffeU) == 0x02208000U) {
        *value = (address & 2) != 0 ? 0x9f0fU : 0;
        return NXTMemoryResultOK;
    }
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
    if ((address & 0x7ffffffcU) == 0x02208000U) {
        *value = 0x0000000fU;
        return NXTMemoryResultOK;
    }
    if ((address & 0x7fffffffU) == 0x0200d000U) {
        *value = _scr2Value;
        if (_rtcPhase == 2 && !_rtcIsWrite && (_scr2Value & NXT_SCR2_RTCE) != 0) {
            if (_rtcDataBit) *value |= NXT_SCR2_RTDATA;
            else *value &= ~NXT_SCR2_RTDATA;
        }
        return NXTMemoryResultOK;
    }
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
    if ((address & 0x7fffffffU) == 0x0200d000U) {
        NXTUInt32 oldValue = _scr2Value;
        _scr2Value = value;
        [self rtcSCR2DidChangeFrom:oldValue to:value];
    }
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
