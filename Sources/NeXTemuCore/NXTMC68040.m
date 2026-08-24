#import "NXTMC68040.h"
#include <string.h>

#define NXT_SR_C 0x0001
#define NXT_SR_V 0x0002
#define NXT_SR_Z 0x0004
#define NXT_SR_N 0x0008

static BOOL NXTConditionTrue(NXTUInt16 condition, NXTUInt16 sr)
{
    BOOL c = (sr & NXT_SR_C) != 0;
    BOOL v = (sr & NXT_SR_V) != 0;
    BOOL z = (sr & NXT_SR_Z) != 0;
    BOOL n = (sr & NXT_SR_N) != 0;
    switch (condition) {
        case 0: return YES;             /* T / BRA */
        case 1: return NO;              /* F / BSR is handled separately */
        case 2: return !c && !z;        /* HI */
        case 3: return c || z;          /* LS */
        case 4: return !c;              /* CC */
        case 5: return c;               /* CS */
        case 6: return !z;              /* NE */
        case 7: return z;               /* EQ */
        case 8: return !v;              /* VC */
        case 9: return v;               /* VS */
        case 10: return !n;             /* PL */
        case 11: return n;              /* MI */
        case 12: return n == v;         /* GE */
        case 13: return n != v;         /* LT */
        case 14: return !z && n == v;   /* GT */
        case 15: return z || n != v;    /* LE */
    }
    return NO;
}

@implementation NXTMC68040

- (id)initWithMemory:(NXTMemory *)memory
{
    self = [super init];
    if (self != nil) {
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

    memset(_dataRegisters, 0, sizeof(_dataRegisters));
    memset(_addressRegisters, 0, sizeof(_addressRegisters));
    _statusRegister = 0x2700;
    if ([_memory readLong:&initialStackPointer atAddress:0] != NXTMemoryResultOK ||
        [_memory readLong:&initialProgramCounter atAddress:4] != NXTMemoryResultOK) {
        _stopped = YES;
        _lastResult = NXTProcessorResultBusError;
        return NO;
    }
    _addressRegisters[7] = initialStackPointer;
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
    if ([_memory readWord:value atAddress:_programCounter] != NXTMemoryResultOK) return NO;
    _programCounter += 2;
    return YES;
}

- (BOOL)fetchLong:(NXTUInt32 *)value
{
    if ([_memory readLong:value atAddress:_programCounter] != NXTMemoryResultOK) return NO;
    _programCounter += 4;
    return YES;
}

- (BOOL)pushLong:(NXTUInt32)value
{
    _addressRegisters[7] -= 4;
    return [_memory writeLong:value atAddress:_addressRegisters[7]] == NXTMemoryResultOK;
}

- (BOOL)popLong:(NXTUInt32 *)value
{
    if ([_memory readLong:value atAddress:_addressRegisters[7]] != NXTMemoryResultOK) return NO;
    _addressRegisters[7] += 4;
    return YES;
}

- (void)setNZForLong:(NXTUInt32)value
{
    _statusRegister &= (NXTUInt16)~(NXT_SR_N | NXT_SR_Z | NXT_SR_V | NXT_SR_C);
    if (value == 0) _statusRegister |= NXT_SR_Z;
    if ((value & 0x80000000U) != 0) _statusRegister |= NXT_SR_N;
}

- (NXTProcessorResult)fail:(NXTProcessorResult)result
{
    _lastResult = result;
    _stopped = YES;
    return result;
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

    if (_stopped) return _lastResult == NXTProcessorResultOK
        ? NXTProcessorResultStopped : _lastResult;
    _lastOpcodeAddress = _programCounter;
    if (![self fetchWord:&opcode]) return [self fail:NXTProcessorResultBusError];
    _lastOpcode = opcode;
    _instructionsExecuted++;

    if (opcode == 0x4e71 || opcode == 0x4e70) return NXTProcessorResultOK; /* NOP, RESET */
    if (opcode == 0x4e72) { /* STOP */
        if (![self fetchWord:&extension]) return [self fail:NXTProcessorResultBusError];
        _statusRegister = extension;
        _stopped = YES;
        _lastResult = NXTProcessorResultStopped;
        return _lastResult;
    }
    if (opcode == 0x4e75) { /* RTS */
        if (![self popLong:&value]) return [self fail:NXTProcessorResultBusError];
        _programCounter = value;
        return NXTProcessorResultOK;
    }
    if (opcode == 0x4ef9 || opcode == 0x4eb9) { /* JMP/JSR absolute long */
        if (![self fetchLong:&value]) return [self fail:NXTProcessorResultBusError];
        returnAddress = _programCounter;
        if (opcode == 0x4eb9 && ![self pushLong:returnAddress])
            return [self fail:NXTProcessorResultBusError];
        _programCounter = value;
        return NXTProcessorResultOK;
    }
    if ((opcode & 0xf100) == 0x7000) { /* MOVEQ */
        registerIndex = (opcode >> 9) & 7;
        value = (NXTUInt32)(int32_t)(int8_t)(opcode & 0xff);
        _dataRegisters[registerIndex] = value;
        [self setNZForLong:value];
        return NXTProcessorResultOK;
    }
    if ((opcode & 0xf1ff) == 0x203c) { /* MOVE.L #imm,Dn */
        registerIndex = (opcode >> 9) & 7;
        if (![self fetchLong:&value]) return [self fail:NXTProcessorResultBusError];
        _dataRegisters[registerIndex] = value;
        [self setNZForLong:value];
        return NXTProcessorResultOK;
    }
    if ((opcode & 0xf1ff) == 0x41f9) { /* LEA absolute long,An */
        registerIndex = (opcode >> 9) & 7;
        if (![self fetchLong:&value]) return [self fail:NXTProcessorResultBusError];
        _addressRegisters[registerIndex] = value;
        return NXTProcessorResultOK;
    }
    if ((opcode & 0xf000) == 0x6000) { /* Bcc, BRA and BSR */
        NXTUInt16 condition = (opcode >> 8) & 15;
        NXTUInt8 byteDisplacement = (NXTUInt8)opcode;
        if (byteDisplacement == 0) {
            if (![self fetchWord:&extension]) return [self fail:NXTProcessorResultBusError];
            displacement = (int16_t)extension;
        } else if (byteDisplacement == 0xff) {
            if (![self fetchLong:&value]) return [self fail:NXTProcessorResultBusError];
            displacement = (int32_t)value;
        } else {
            displacement = (int8_t)byteDisplacement;
        }
        returnAddress = _programCounter;
        if (condition == 1) {
            if (![self pushLong:returnAddress]) return [self fail:NXTProcessorResultBusError];
            _programCounter = (NXTUInt32)(_programCounter + displacement);
        } else if (NXTConditionTrue(condition, _statusRegister)) {
            _programCounter = (NXTUInt32)(_programCounter + displacement);
        }
        return NXTProcessorResultOK;
    }
    if ((opcode & 0xf1f8) == 0x5080 || (opcode & 0xf1f8) == 0x5180) { /* ADDQ/SUBQ.L Dn */
        registerIndex = opcode & 7;
        quickValue = (opcode >> 9) & 7;
        if (quickValue == 0) quickValue = 8;
        if ((opcode & 0x0100) != 0) _dataRegisters[registerIndex] -= quickValue;
        else _dataRegisters[registerIndex] += quickValue;
        [self setNZForLong:_dataRegisters[registerIndex]];
        return NXTProcessorResultOK;
    }
    if ((opcode & 0xfff8) == 0x4280) { /* CLR.L Dn */
        _dataRegisters[opcode & 7] = 0;
        [self setNZForLong:0];
        return NXTProcessorResultOK;
    }
    return [self fail:NXTProcessorResultIllegalInstruction];
}

- (NXTProcessorResult)runForInstructionCount:(NXTUInt32)count
{
    NXTUInt32 index;
    NXTProcessorResult result;
    if (_stopped) return _lastResult;
    for (index = 0; index < count; index++) {
        result = [self step];
        if (result != NXTProcessorResultOK) return result;
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

- (NXTUInt32)programCounter { return _programCounter; }
- (NXTUInt16)statusRegister { return _statusRegister; }
- (BOOL)isStopped { return _stopped; }
- (NXTProcessorResult)lastResult { return _lastResult; }
- (NXTUInt32)lastOpcodeAddress { return _lastOpcodeAddress; }
- (NXTUInt16)lastOpcode { return _lastOpcode; }
- (NXTUInt64)instructionsExecuted { return _instructionsExecuted; }

@end
