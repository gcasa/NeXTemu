#import "NXTMachine.h"

/* Temporary bootstrap map. Device-accurate NeXT physical decoding follows. */
#define NXT_ROM_BASE 0x00000000U
#define NXT_ROM_SIZE 0x00020000U
#define NXT_RAM_BASE 0x04000000U

@implementation NXTMachine

- (id)initWithModel:(NXTMachineModel)model ramSize:(NXTUInt32)ramSize
{
    self = [super init];
    if (self != nil) {
        _model = model;
        _memory = [[NXTMemory alloc] init];
        _romRegion = [[NXTMemoryRegion alloc] initWithBaseAddress:NXT_ROM_BASE
                                                          length:NXT_ROM_SIZE
                                                        readOnly:YES];
        _ramRegion = [[NXTMemoryRegion alloc] initWithBaseAddress:NXT_RAM_BASE
                                                          length:ramSize
                                                        readOnly:NO];
        if (_memory == nil || _romRegion == nil || _ramRegion == nil ||
            ![_memory addRegion:_romRegion] || ![_memory addRegion:_ramRegion]) {
            [self release];
            return nil;
        }
        _processor = [[NXTMC68040 alloc] initWithMemory:_memory];
        if (_processor == nil) {
            [self release];
            return nil;
        }
    }
    return self;
}

- (void)dealloc
{
    [_processor release];
    [_ramRegion release];
    [_romRegion release];
    [_memory release];
    [super dealloc];
}

- (BOOL)loadROMAtPath:(NSString *)path error:(NSString **)errorMessage
{
    NSData *data;
    if (errorMessage != NULL) *errorMessage = nil;
    data = [NSData dataWithContentsOfFile:path];
    if (data == nil) {
        if (errorMessage != NULL) *errorMessage = @"Unable to read ROM image";
        return NO;
    }
    if ([data length] != NXT_ROM_SIZE) {
        if (errorMessage != NULL) *errorMessage = @"ROM image must be exactly 128 KiB";
        return NO;
    }
    if ([_memory loadData:data atAddress:NXT_ROM_BASE] != NXTMemoryResultOK) {
        if (errorMessage != NULL) *errorMessage = @"Unable to map ROM image";
        return NO;
    }
    return YES;
}

- (BOOL)reset { return [_processor reset]; }
- (NXTMachineModel)model { return _model; }
- (unsigned int)clockSpeedMHz
{
    return _model == NXTMachineModelNeXTcubeTurbo ? 33 : 25;
}
- (NXTMemory *)memory { return _memory; }
- (NXTMC68040 *)processor { return _processor; }

@end
