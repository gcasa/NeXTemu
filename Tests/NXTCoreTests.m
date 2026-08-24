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

int main(void)
{
    NSAutoreleasePool *pool;
    pool = [[NSAutoreleasePool alloc] init];
    NXTTestMemory();
    NXTTestResetVectors();
    NXTTestInstructionExecution();
    if (failures == 0) printf("All core tests passed.\n");
    [pool drain];
    return failures == 0 ? 0 : 1;
}
