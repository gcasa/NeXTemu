#ifndef NXT_MACHINE_H
#define NXT_MACHINE_H

#import <Foundation/Foundation.h>
#import "NXTMC68040.h"

typedef enum {
    NXTMachineModelNeXTcube = 0,
    NXTMachineModelNeXTcubeTurbo
} NXTMachineModel;

@interface NXTMachine : NSObject
{
    NXTMachineModel _model;
    NXTMemory *_memory;
    NXTMC68040 *_processor;
    NXTMemoryRegion *_romRegion;
    NXTMemoryRegion *_romAliasRegion;
    NXTMemoryRegion *_ramRegion;
}

- (id)initWithModel:(NXTMachineModel)model ramSize:(NXTUInt32)ramSize;
- (BOOL)loadROMAtPath:(NSString *)path error:(NSString **)errorMessage;
- (BOOL)reset;
- (NXTProcessorResult)runForInstructionCount:(NXTUInt32)count;
- (NXTMachineModel)model;
- (unsigned int)clockSpeedMHz;
- (NXTMemory *)memory;
- (NXTMC68040 *)processor;

@end

#endif
