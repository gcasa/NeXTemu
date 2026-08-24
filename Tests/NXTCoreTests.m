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

int main(void)
{
    NSAutoreleasePool *pool;
    pool = [[NSAutoreleasePool alloc] init];
    NXTTestMemory();
    NXTTestResetVectors();
    if (failures == 0) printf("All core tests passed.\n");
    [pool drain];
    return failures == 0 ? 0 : 1;
}
