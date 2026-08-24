#import "NXTMC68040.h"
#include <string.h>

@implementation NXTMC68040

- (id)initWithMemory:(NXTMemory *)memory
{
    self = [super init];
    if (self != nil) {
        _memory = [memory retain];
        _stopped = YES;
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

    memset(_dataRegisters, 0, sizeof(_dataRegisters));
    memset(_addressRegisters, 0, sizeof(_addressRegisters));
    _statusRegister = 0x2700;
    if ([_memory readLong:&initialStackPointer atAddress:0] != NXTMemoryResultOK ||
        [_memory readLong:&initialProgramCounter atAddress:4] != NXTMemoryResultOK) {
        _stopped = YES;
        return NO;
    }
    _addressRegisters[7] = initialStackPointer;
    _programCounter = initialProgramCounter;
    _stopped = NO;
    return YES;
}

- (NXTUInt32)dataRegister:(unsigned int)index
{
    return index < 8 ? _dataRegisters[index] : 0;
}

- (NXTUInt32)addressRegister:(unsigned int)index
{
    return index < 8 ? _addressRegisters[index] : 0;
}

- (NXTUInt32)programCounter { return _programCounter; }
- (NXTUInt16)statusRegister { return _statusRegister; }
- (BOOL)isStopped { return _stopped; }

@end
