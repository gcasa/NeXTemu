#import "NXTMachine.h"

/* The boot ROM is visible at zero during reset and at its normal address. */
#define NXT_ROM_BOOT_BASE 0x00000000U
#define NXT_ROM_BASE 0x01000000U
#define NXT_ROM_SIZE 0x00020000U
#define NXT_RAM_BASE 0x04000000U

static BOOL NXTAddRegisterBank(NXTMemory *memory, NXTUInt32 base, NXTUInt32 length)
{
    NXTMemoryRegion *region;
    BOOL result;
    region = [[NXTMemoryRegion alloc] initWithBaseAddress:base
                                                  length:length
                                                readOnly:NO];
    if (region == nil) return NO;
    result = [memory addRegion:region];
    [region release];
    return result;
}

@implementation NXTMachine

- (id)initWithModel:(NXTMachineModel)model ramSize:(NXTUInt32)ramSize
{
    self = [super init];
    if (self != nil) {
        _model = model;
        _memory = [[NXTMemory alloc] init];
        _romRegion = [[NXTMemoryRegion alloc] initWithBaseAddress:NXT_ROM_BOOT_BASE
                                                          length:NXT_ROM_SIZE
                                                        readOnly:YES];
        _romAliasRegion = [[NXTMemoryRegion alloc] initWithBaseAddress:NXT_ROM_BASE
                                                               length:NXT_ROM_SIZE
                                                             readOnly:YES];
        _ramRegion = [[NXTMemoryRegion alloc] initWithBaseAddress:NXT_RAM_BASE
                                                          length:ramSize
                                                        readOnly:NO];
        if (_memory == nil || _romRegion == nil || _romAliasRegion == nil ||
            _ramRegion == nil || ![_memory addRegion:_romRegion] ||
            ![_memory addRegion:_romAliasRegion] || ![_memory addRegion:_ramRegion]) {
            [self release];
            return nil;
        }
        /* Sparse stand-ins keep early firmware probing on the physical bus.
           Device-specific side effects can replace these banks independently. */
        if (!NXTAddRegisterBank(_memory, 0x02000000U, 0x00005000U) || /* DMA */
            !NXTAddRegisterBank(_memory, 0x02005000U, 0x00009000U) || /* system */
            !NXTAddRegisterBank(_memory, 0x0200e000U, 0x00000020U) || /* keyboard */
            !NXTAddRegisterBank(_memory, 0x020c0000U, 0x00000040U) || /* BMAP */
            !NXTAddRegisterBank(_memory, 0x02100000U, 0x00000020U) || /* ethernet */
            !NXTAddRegisterBank(_memory, 0x02106000U, 0x00000020U) ||
            !NXTAddRegisterBank(_memory, 0x02110000U, 0x00000010U) ||
            !NXTAddRegisterBank(_memory, 0x02112000U, 0x00000010U) ||
            !NXTAddRegisterBank(_memory, 0x02114000U, 0x00000020U) || /* SCSI */
            !NXTAddRegisterBank(_memory, 0x02114108U, 0x00000004U) ||
            !NXTAddRegisterBank(_memory, 0x02116000U, 0x00000008U) || /* timer */
            !NXTAddRegisterBank(_memory, 0x02118000U, 0x00000014U) || /* serial */
            !NXTAddRegisterBank(_memory, 0x0211a000U, 0x00000004U) || /* timer */
            !NXTAddRegisterBank(_memory, 0x02200000U, 0x00010000U) || /* TMC */
            !NXTAddRegisterBank(_memory, 0x02210000U, 0x00010000U) || /* Turbo slot */
            !NXTAddRegisterBank(_memory,
                model == NXTMachineModelNeXTcubeTurbo ? 0x0c000000U : 0x0b000000U,
                0x001cb100U) || /* display */
            !NXTAddRegisterBank(_memory, 0x820c0000U, 0x00000040U)) {
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
    [_romAliasRegion release];
    [_romRegion release];
    [_diskImagePath release];
    [_memory release];
    [super dealloc];
}

- (BOOL)attachDiskImageAtPath:(NSString *)path error:(NSString **)errorMessage
{
    NSDictionary *attributes;
    NSNumber *sizeNumber;
    NXTUInt64 size;
    if (errorMessage != NULL) *errorMessage = nil;
    attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
    if (attributes == nil || ![[attributes objectForKey:NSFileType]
                               isEqualToString:NSFileTypeRegular]) {
        if (errorMessage != NULL) *errorMessage = @"Unable to read disk image";
        return NO;
    }
    sizeNumber = [attributes objectForKey:NSFileSize];
    size = [sizeNumber unsignedLongLongValue];
    if (size == 0 || (size & 511U) != 0) {
        if (errorMessage != NULL)
            *errorMessage = @"Disk image must be a non-empty raw image with 512-byte sectors";
        return NO;
    }
    [path retain];
    [_diskImagePath release];
    _diskImagePath = path;
    _diskImageSize = size;
    if (![_memory attachSCSIDiskAtPath:path error:errorMessage]) {
        [_diskImagePath release]; _diskImagePath = nil; _diskImageSize = 0;
        return NO;
    }
    return YES;
}

- (NSString *)diskImagePath { return _diskImagePath; }
- (NXTUInt64)diskImageSize { return _diskImageSize; }

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
    if ([_memory loadData:data atAddress:NXT_ROM_BOOT_BASE] != NXTMemoryResultOK ||
        [_memory loadData:data atAddress:NXT_ROM_BASE] != NXTMemoryResultOK) {
        if (errorMessage != NULL) *errorMessage = @"Unable to map ROM image";
        return NO;
    }
    return YES;
}

- (BOOL)reset
{
    /* NeXT peripheral-controller power-on values used for board/model and
       RTC detection by the ROM. */
    NXTUInt32 scr1;
    NXTUInt32 scr2;
    scr1 = _model == NXTMachineModelNeXTcubeTurbo ? 0xf0004000U : 0x00011102U;
    scr2 = _model == NXTMachineModelNeXTcubeTurbo ? 0x000f1080U : 0x00ff0c80U;
    [_memory resetNeXTDevicesForTurbo:_model == NXTMachineModelNeXTcubeTurbo];
    if ([_memory writeLong:scr1 atAddress:0x0200c000U] != NXTMemoryResultOK ||
        [_memory writeLong:scr2 atAddress:0x0200d000U] != NXTMemoryResultOK ||
        (_model == NXTMachineModelNeXTcubeTurbo &&
         [_memory writeLong:0x0fff4fafU atAddress:0x02200000U] != NXTMemoryResultOK))
        return NO;
    return [_processor reset];
}
- (NXTProcessorResult)runForInstructionCount:(NXTUInt32)count
{
    return [_processor runForInstructionCount:count];
}
- (NXTMachineModel)model { return _model; }
- (unsigned int)clockSpeedMHz
{
    return _model == NXTMachineModelNeXTcubeTurbo ? 33 : 25;
}
- (NXTMemory *)memory { return _memory; }
- (NXTMC68040 *)processor { return _processor; }

@end
