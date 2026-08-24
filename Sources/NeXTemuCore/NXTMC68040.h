#ifndef NXT_MC68040_H
#define NXT_MC68040_H

#import <Foundation/Foundation.h>
#import "NXTMemory.h"

typedef enum {
    NXTProcessorResultOK = 0,
    NXTProcessorResultStopped,
    NXTProcessorResultBusError,
    NXTProcessorResultIllegalInstruction,
    NXTProcessorResultInstructionLimit
} NXTProcessorResult;

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
}

- (id)initWithMemory:(NXTMemory *)memory;
- (BOOL)reset;
- (NXTProcessorResult)step;
- (NXTProcessorResult)runForInstructionCount:(NXTUInt32)count;
- (NXTUInt32)dataRegister:(unsigned int)index;
- (NXTUInt32)addressRegister:(unsigned int)index;
- (NXTUInt32)programCounter;
- (NXTUInt16)statusRegister;
- (BOOL)isStopped;
- (NXTProcessorResult)lastResult;
- (NXTUInt32)lastOpcodeAddress;
- (NXTUInt16)lastOpcode;
- (NXTUInt64)instructionsExecuted;

@end

#endif
