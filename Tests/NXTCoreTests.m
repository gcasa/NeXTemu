#import <Foundation/Foundation.h>
#import "NXTMachine.h"
#include <stdio.h>

static int failures = 0;

static void NXTAssert(BOOL condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        failures++;
    }
}

static void NXTTestMemory(void)
{
    NXTMemory *memory;
    NXTMemoryRegion *region;
    NXTUInt32 value;

    memory = [[NXTMemory alloc] init];
    region = [[NXTMemoryRegion alloc] initWithBaseAddress:0x1000 length:16 readOnly:NO];
    NXTAssert([memory addRegion:region], "adds a memory region");
    NXTAssert([memory writeLong:0x12345678 atAddress:0x1004] == NXTMemoryResultOK,
              "writes a big-endian long");
    value = 0;
    NXTAssert([memory readLong:&value atAddress:0x1004] == NXTMemoryResultOK,
              "reads a big-endian long");
    NXTAssert(value == 0x12345678, "long value round trips");
    NXTAssert([memory readLong:&value atAddress:0x2000] == NXTMemoryResultUnmapped,
              "rejects unmapped reads");
    [region release];
    [memory release];
}

static void NXTTestResetVectors(void)
{
    NXTMemory *memory;
    NXTMemoryRegion *vectors;
    NXTMC68040 *processor;
    NXTUInt8 bytes[8] = { 0x04, 0x00, 0x10, 0x00, 0x00, 0x01, 0x00, 0x20 };
    NSData *data;

    memory = [[NXTMemory alloc] init];
    vectors = [[NXTMemoryRegion alloc] initWithBaseAddress:0 length:8 readOnly:YES];
    [memory addRegion:vectors];
    data = [NSData dataWithBytes:bytes length:8];
    [memory loadData:data atAddress:0];
    processor = [[NXTMC68040 alloc] initWithMemory:memory];
    NXTAssert([processor reset], "loads reset vectors");
    NXTAssert([processor addressRegister:7] == 0x04001000, "loads supervisor stack pointer");
    NXTAssert([processor programCounter] == 0x00010020, "loads program counter");
    NXTAssert([processor statusRegister] == 0x2700, "enters supervisor state at interrupt level 7");
    [processor release];
    [vectors release];
    [memory release];
}

static void NXTTestInstructionExecution(void)
{
    NXTMemory *memory;
    NXTMemoryRegion *image;
    NXTMemoryRegion *stack;
    NXTMC68040 *processor;
    NXTUInt8 bytes[14] = {
        0x70, 0x05,             /* MOVEQ #5,D0 */
        0x56, 0x80,             /* ADDQ.L #3,D0 */
        0x61, 0x04,             /* BSR.S subroutine */
        0x4e, 0x72, 0x27, 0x00, /* STOP #$2700 */
        0x53, 0x80,             /* SUBQ.L #1,D0 */
        0x4e, 0x75              /* RTS */
    };
    NXTUInt8 vectors[8] = { 0x00, 0x00, 0x20, 0x00, 0x00, 0x00, 0x01, 0x00 };

    memory = [[NXTMemory alloc] init];
    image = [[NXTMemoryRegion alloc] initWithBaseAddress:0 length:0x200 readOnly:YES];
    stack = [[NXTMemoryRegion alloc] initWithBaseAddress:0x1f00 length:0x100 readOnly:NO];
    [memory addRegion:image];
    [memory addRegion:stack];
    [memory loadData:[NSData dataWithBytes:vectors length:8] atAddress:0];
    [memory loadData:[NSData dataWithBytes:bytes length:14] atAddress:0x100];
    processor = [[NXTMC68040 alloc] initWithMemory:memory];
    NXTAssert([processor reset], "resets instruction test processor");
    NXTAssert([processor runForInstructionCount:20] == NXTProcessorResultStopped,
              "runs until STOP");
    NXTAssert([processor dataRegister:0] == 7, "executes arithmetic and subroutine");
    NXTAssert([processor addressRegister:7] == 0x2000, "balances the return stack");
    NXTAssert([processor instructionsExecuted] == 6, "counts executed instructions");
    [processor release];
    [stack release];
    [image release];
    [memory release];
}

static void NXTTestMachineROMAliases(void)
{
    NXTMachine *machine;
    NSString *path;
    NSMutableData *rom;
    NXTUInt8 *bytes;
    NXTUInt32 low;
    NXTUInt32 high;

    machine = [[NXTMachine alloc] initWithModel:NXTMachineModelNeXTcube
                                        ramSize:16U * 1024U * 1024U];
    rom = [NSMutableData dataWithLength:128U * 1024U];
    bytes = (NXTUInt8 *)[rom mutableBytes];
    bytes[0] = 0x04; bytes[1] = 0x00; bytes[2] = 0x10; bytes[3] = 0x00;
    bytes[4] = 0x01; bytes[5] = 0x00; bytes[6] = 0x00; bytes[7] = 0x08;
    path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"nextemu-test.rom"];
    [rom writeToFile:path atomically:YES];
    NXTAssert([machine loadROMAtPath:path error:NULL], "loads a machine ROM");
    NXTAssert([[machine memory] readLong:&low atAddress:0] == NXTMemoryResultOK,
              "maps ROM at the reset address");
    NXTAssert([[machine memory] readLong:&high atAddress:0x01000000] == NXTMemoryResultOK,
              "maps ROM at its runtime address");
    NXTAssert(low == high && low == 0x04001000, "ROM aliases contain identical data");
    NXTAssert([machine reset] && [[machine processor] programCounter] == 0x01000008,
              "resets into the high ROM alias");
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    [machine release];
}

static void NXTTestEffectiveAddresses(void)
{
    NXTMemory *memory;
    NXTMemoryRegion *image;
    NXTMemoryRegion *ram;
    NXTMC68040 *processor;
    NXTUInt32 stored;
    NXTUInt8 vectors[8] = { 0x00, 0x00, 0x11, 0x00, 0x00, 0x00, 0x01, 0x00 };
    NXTUInt8 code[22] = {
        0x20, 0x7c, 0x00, 0x00, 0x10, 0x00, /* MOVEA.L #$1000,A0 */
        0x20, 0xbc, 0x12, 0x34, 0x56, 0x78, /* MOVE.L #value,(A0) */
        0x22, 0x10,                         /* MOVE.L (A0),D1 */
        0x52, 0x98,                         /* ADDQ.L #1,(A0)+ */
        0x43, 0xe8, 0xff, 0xfc,             /* LEA -4(A0),A1 */
        0x4e, 0x72                          /* STOP (extension is zero-filled) */
    };

    memory = [[NXTMemory alloc] init];
    image = [[NXTMemoryRegion alloc] initWithBaseAddress:0 length:0x200 readOnly:YES];
    ram = [[NXTMemoryRegion alloc] initWithBaseAddress:0x1000 length:0x100 readOnly:NO];
    [memory addRegion:image];
    [memory addRegion:ram];
    [memory loadData:[NSData dataWithBytes:vectors length:8] atAddress:0];
    [memory loadData:[NSData dataWithBytes:code length:22] atAddress:0x100];
    processor = [[NXTMC68040 alloc] initWithMemory:memory];
    NXTAssert([processor reset], "resets effective-address test processor");
    NXTAssert([processor runForInstructionCount:20] == NXTProcessorResultStopped,
              "runs generalized effective-address instructions");
    [memory readLong:&stored atAddress:0x1000];
    NXTAssert(stored == 0x12345679, "updates a memory effective address");
    NXTAssert([processor dataRegister:1] == 0x12345678, "moves memory into a register");
    NXTAssert([processor addressRegister:0] == 0x1004, "postincrements once on read-modify-write");
    NXTAssert([processor addressRegister:1] == 0x1000, "computes displacement effective address");
    [processor release];
    [ram release];
    [image release];
    [memory release];
}

static void NXTTestExtendedBranches(void)
{
    NXTMemory *memory;
    NXTMemoryRegion *image;
    NXTMemoryRegion *stack;
    NXTMC68040 *processor;
    NXTUInt8 vectors[8] = { 0x00, 0x00, 0x20, 0x00, 0x00, 0x00, 0x01, 0x00 };
    NXTUInt8 code[24] = {
        0x60, 0x00, 0x00, 0x04, /* BRA.W, relative to extension address */
        0xff, 0xff, 0x70, 0x01,
        0x60, 0xff, 0x00, 0x00, 0x00, 0x08, /* BRA.L */
        0xff, 0xff, 0xff, 0xff, 0x72, 0x02,
        0x4e, 0x72, 0x27, 0x00
    };
    memory = [[NXTMemory alloc] init];
    image = [[NXTMemoryRegion alloc] initWithBaseAddress:0 length:0x200 readOnly:YES];
    stack = [[NXTMemoryRegion alloc] initWithBaseAddress:0x1f00 length:0x100 readOnly:NO];
    [memory addRegion:image];
    [memory addRegion:stack];
    [memory loadData:[NSData dataWithBytes:vectors length:8] atAddress:0];
    [memory loadData:[NSData dataWithBytes:code length:24] atAddress:0x100];
    processor = [[NXTMC68040 alloc] initWithMemory:memory];
    NXTAssert([processor reset], "resets extended-branch test processor");
    NXTAssert([processor runForInstructionCount:10] == NXTProcessorResultStopped,
              "bases word and long branches at the extension address");
    NXTAssert([processor dataRegister:0] == 1 && [processor dataRegister:1] == 2,
              "extended branches land on instruction boundaries");
    [processor release];
    [stack release];
    [image release];
    [memory release];
}

static void NXTTestImmediateCompareCarry(void)
{
    NXTMemory *memory;
    NXTMemoryRegion *image;
    NXTMemoryRegion *stack;
    NXTMC68040 *processor;
    NXTUInt8 vectors[8] = { 0x00, 0x00, 0x20, 0x00, 0x00, 0x00, 0x01, 0x00 };
    NXTUInt8 code[] = {
        0x20, 0x3c, 0x12, 0x34, 0x56, 0x78, /* MOVE.L #$12345678,D0 */
        0x0c, 0x80, 0x89, 0xab, 0xcd, 0xef, /* CMPI.L #$89abcdef,D0 */
        0x62, 0x02,                         /* BHI skips only if C=0 && Z=0 */
        0x72, 0x01,                         /* Correct borrow path. */
        0x4e, 0x72, 0x27, 0x00
    };
    memory = [[NXTMemory alloc] init];
    image = [[NXTMemoryRegion alloc] initWithBaseAddress:0 length:0x200 readOnly:YES];
    stack = [[NXTMemoryRegion alloc] initWithBaseAddress:0x1f00 length:0x100 readOnly:NO];
    [memory addRegion:image]; [memory addRegion:stack];
    [memory loadData:[NSData dataWithBytes:vectors length:8] atAddress:0];
    [memory loadData:[NSData dataWithBytes:code length:sizeof(code)] atAddress:0x100];
    processor = [[NXTMC68040 alloc] initWithMemory:memory];
    NXTAssert([processor reset], "resets immediate-compare flag test");
    NXTAssert([processor step] == NXTProcessorResultOK &&
              [processor step] == NXTProcessorResultOK,
              "executes immediate comparison");
    NXTAssert(([processor statusRegister] & 1U) != 0,
              "CMPI sets carry when unsigned subtraction borrows");
    NXTAssert([processor runForInstructionCount:10] == NXTProcessorResultStopped,
              "runs immediate-compare branch test");
    NXTAssert([processor dataRegister:1] == 1,
              "BHI observes carry from CMPI");
    [processor release]; [stack release]; [image release]; [memory release];
}

static void NXTTestFMoveLong(void)
{
    NXTMemory *memory;
    NXTMemoryRegion *image;
    NXTMemoryRegion *stack;
    NXTMC68040 *processor;
    NXTUInt8 vectors[8] = { 0x00, 0x00, 0x20, 0x00, 0x00, 0x00, 0x01, 0x00 };
    NXTUInt8 code[] = {
        0x26, 0x3c, 0x00, 0x00, 0x80, 0x00, /* MOVE.L #$8000,D3 */
        0xf2, 0x03, 0x40, 0x80,             /* FMOVE.L D3,FP1 */
        0xf2, 0x04, 0x60, 0x80,             /* FMOVE.L FP1,D4 */
        0x4e, 0x72, 0x27, 0x00
    };
    memory = [[NXTMemory alloc] init];
    image = [[NXTMemoryRegion alloc] initWithBaseAddress:0 length:0x200 readOnly:YES];
    stack = [[NXTMemoryRegion alloc] initWithBaseAddress:0x1f00 length:0x100 readOnly:NO];
    [memory addRegion:image]; [memory addRegion:stack];
    [memory loadData:[NSData dataWithBytes:vectors length:8] atAddress:0];
    [memory loadData:[NSData dataWithBytes:code length:sizeof(code)] atAddress:0x100];
    processor = [[NXTMC68040 alloc] initWithMemory:memory];
    NXTAssert([processor reset], "resets FMOVE test");
    NXTAssert([processor runForInstructionCount:10] == NXTProcessorResultStopped,
              "executes FMOVE outside the ROM POST address range");
    NXTAssert([processor dataRegister:4] == 0x8000,
              "round-trips an integer through an FP register");
    [processor release]; [stack release]; [image release]; [memory release];
}

int main(void)
{
    NSAutoreleasePool *pool;
    pool = [[NSAutoreleasePool alloc] init];
    NXTTestMemory();
    NXTTestResetVectors();
    NXTTestInstructionExecution();
    NXTTestMachineROMAliases();
    NXTTestEffectiveAddresses();
    NXTTestExtendedBranches();
    NXTTestImmediateCompareCarry();
    NXTTestFMoveLong();
    if (failures == 0) printf("All core tests passed.\n");
    [pool drain];
    return failures == 0 ? 0 : 1;
}
