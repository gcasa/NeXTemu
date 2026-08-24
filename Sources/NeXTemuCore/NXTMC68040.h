#ifndef NXT_MC68040_H
#define NXT_MC68040_H

#import <Foundation/Foundation.h>
#import "NXTMemory.h"

@interface NXTMC68040 : NSObject
{
    NXTMemory *_memory;
    NXTUInt32 _dataRegisters[8];
    NXTUInt32 _addressRegisters[8];
    NXTUInt32 _programCounter;
    NXTUInt16 _statusRegister;
    BOOL _stopped;
}

- (id)initWithMemory:(NXTMemory *)memory;
- (BOOL)reset;
- (NXTUInt32)dataRegister:(unsigned int)index;
- (NXTUInt32)addressRegister:(unsigned int)index;
- (NXTUInt32)programCounter;
- (NXTUInt16)statusRegister;
- (BOOL)isStopped;

@end

#endif
