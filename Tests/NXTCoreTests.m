/*
 * Copyright (C) 2026 Gregory Casamento
 *
 * This file is part of NeXTemu.
 *
 * NeXTemu is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free
 * Software Foundation, either version 3 of the License, or (at your option)
 * any later version.
 *
 * NeXTemu is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
 * more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with NeXTemu.  If not, see <https://www.gnu.org/licenses/>.
 */

#import <Foundation/Foundation.h>
#import "NXTMachine.h"
#include <stdio.h>

static int failures = 0;

static void
NXTAssert (BOOL condition, const char *message)
{
  if (!condition)
    {
      fprintf (stderr, "FAIL: %s\n", message);
      failures++;
    }
}

static void
NXTTestMemory (void)
{
  NXTMemory *memory;
  NXTMemoryRegion *region;
  NXTUInt32 value;

  memory = [[NXTMemory alloc] init];
  region = [[NXTMemoryRegion alloc] initWithBaseAddress:0x1000
                                                 length:16
                                               readOnly:NO];
  NXTAssert ([memory addRegion:region], "adds a memory region");
  NXTAssert ([memory writeLong:0x12345678 atAddress:0x1004]
                 == NXTMemoryResultOK,
             "writes a big-endian long");
  value = 0;
  NXTAssert ([memory readLong:&value atAddress:0x1004] == NXTMemoryResultOK,
             "reads a big-endian long");
  NXTAssert (value == 0x12345678, "long value round trips");
  NXTAssert ([memory readLong:&value atAddress:0x2000]
                 == NXTMemoryResultUnmapped,
             "rejects unmapped reads");
  [region release];
  [memory release];
}

static void
NXTTestResetVectors (void)
{
  NXTMemory *memory;
  NXTMemoryRegion *vectors;
  NXTMC68040 *processor;
  NXTUInt8 bytes[8] = { 0x04, 0x00, 0x10, 0x00, 0x00, 0x01, 0x00, 0x20 };
  NSData *data;

  memory = [[NXTMemory alloc] init];
  vectors = [[NXTMemoryRegion alloc] initWithBaseAddress:0
                                                  length:8
                                                readOnly:YES];
  [memory addRegion:vectors];
  data = [NSData dataWithBytes:bytes length:8];
  [memory loadData:data atAddress:0];
  processor = [[NXTMC68040 alloc] initWithMemory:memory];
  NXTAssert ([processor reset], "loads reset vectors");
  NXTAssert ([processor addressRegister:7] == 0x04001000,
             "loads supervisor stack pointer");
  NXTAssert ([processor programCounter] == 0x00010020,
             "loads program counter");
  NXTAssert ([processor statusRegister] == 0x2700,
             "enters supervisor state at interrupt level 7");
  [processor release];
  [vectors release];
  [memory release];
}

static void
NXTTestInstructionExecution (void)
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
  image = [[NXTMemoryRegion alloc] initWithBaseAddress:0
                                                length:0x200
                                              readOnly:YES];
  stack = [[NXTMemoryRegion alloc] initWithBaseAddress:0x1f00
                                                length:0x100
                                              readOnly:NO];
  [memory addRegion:image];
  [memory addRegion:stack];
  [memory loadData:[NSData dataWithBytes:vectors length:8] atAddress:0];
  [memory loadData:[NSData dataWithBytes:bytes length:14] atAddress:0x100];
  processor = [[NXTMC68040 alloc] initWithMemory:memory];
  NXTAssert ([processor reset], "resets instruction test processor");
  NXTAssert ([processor runForInstructionCount:20]
                 == NXTProcessorResultStopped,
             "runs until STOP");
  NXTAssert ([processor dataRegister:0] == 7,
             "executes arithmetic and subroutine");
  NXTAssert ([processor addressRegister:7] == 0x2000,
             "balances the return stack");
  NXTAssert ([processor instructionsExecuted] == 6,
             "counts executed instructions");
  [processor release];
  [stack release];
  [image release];
  [memory release];
}

static void
NXTTestMovesAlternateSpace (void)
{
  NXTMemory *memory;
  NXTMemoryRegion *image;
  NXTMemoryRegion *ram;
  NXTMC68040 *processor;
  NXTUInt32 value = 0;
  NXTUInt8 vectors[8] = { 0x00, 0x00, 0x20, 0x00,
                          0x00, 0x00, 0x01, 0x00 };
  NXTUInt8 code[] = {
    0x20, 0x7c, 0x00, 0x00, 0x10, 0x00, /* MOVEA.L #$1000,A0 */
    0x22, 0x3c, 0x12, 0x34, 0x56, 0x78, /* MOVE.L #value,D1 */
    0x70, 0x01,                         /* MOVEQ #1,D0 */
    0x4e, 0x7b, 0x00, 0x01,             /* MOVEC D0,DFC */
    0x0e, 0x90, 0x18, 0x00,             /* MOVES.L D1,(A0) */
    0x4e, 0x7b, 0x00, 0x00,             /* MOVEC D0,SFC */
    0x0e, 0x90, 0x20, 0x00,             /* MOVES.L (A0),D2 */
    0x4e, 0x72, 0x27, 0x00              /* STOP #$2700 */
  };

  memory = [[NXTMemory alloc] init];
  image = [[NXTMemoryRegion alloc] initWithBaseAddress:0
                                                length:0x200
                                              readOnly:YES];
  ram = [[NXTMemoryRegion alloc] initWithBaseAddress:0x1000
                                              length:0x1000
                                            readOnly:NO];
  [memory addRegion:image];
  [memory addRegion:ram];
  [memory loadData:[NSData dataWithBytes:vectors length:sizeof (vectors)]
         atAddress:0];
  [memory loadData:[NSData dataWithBytes:code length:sizeof (code)]
         atAddress:0x100];
  processor = [[NXTMC68040 alloc] initWithMemory:memory];
  NXTAssert ([processor reset], "resets MOVES instruction test");
  NXTAssert ([processor runForInstructionCount:20]
                 == NXTProcessorResultStopped,
             "executes MOVES in both directions");
  [memory readLong:&value atAddress:0x1000];
  NXTAssert (value == 0x12345678U,
             "MOVES writes through the destination function code");
  NXTAssert ([processor dataRegister:2] == 0x12345678U,
             "MOVES reads through the source function code");
  [processor release];
  [ram release];
  [image release];
  [memory release];
}

static void
NXTTestMachineROMAliases (void)
{
  NXTMachine *machine;
  NSString *path;
  NSMutableData *rom;
  NXTUInt8 *bytes;
  NXTUInt32 low;
  NXTUInt32 high;
  NXTUInt8 peripheralValue;

  machine = [[NXTMachine alloc] initWithModel:NXTMachineModelNeXTcube
                                      ramSize:16U * 1024U * 1024U];
  rom = [NSMutableData dataWithLength:128U * 1024U];
  bytes = (NXTUInt8 *)[rom mutableBytes];
  bytes[0] = 0x04;
  bytes[1] = 0x00;
  bytes[2] = 0x10;
  bytes[3] = 0x00;
  bytes[4] = 0x01;
  bytes[5] = 0x00;
  bytes[6] = 0x00;
  bytes[7] = 0x08;
  path = [NSTemporaryDirectory ()
      stringByAppendingPathComponent:@"nextemu-test.rom"];
  [rom writeToFile:path atomically:YES];
  NXTAssert ([machine loadROMAtPath:path error:NULL], "loads a machine ROM");
  NXTAssert ([[machine memory] readLong:&low atAddress:0] == NXTMemoryResultOK,
             "maps ROM at the reset address");
  NXTAssert ([[machine memory] readLong:&high atAddress:0x01000000]
                 == NXTMemoryResultOK,
             "maps ROM at its runtime address");
  NXTAssert (low == high && low == 0x04001000,
             "ROM aliases contain identical data");
  NXTAssert ([[machine memory] readByte:&peripheralValue atAddress:0x0200f807U]
                 == NXTMemoryResultOK,
             "maps the kernel peripheral-probe window");
  NXTAssert ([[machine memory] writeLong:0x12345678U atAddress:0x11846008U]
                 == NXTMemoryResultOK,
             "maps the kernel virtual-allocation window");
  NXTAssert ([machine reset] &&
                 [[machine processor] programCounter] == 0x01000008,
             "resets into the high ROM alias");
  [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
  [machine release];
}

static void
NXTTestMovesAccessErrorFrame (void)
{
  NXTMemory *memory;
  NXTMemoryRegion *image;
  NXTMemoryRegion *ram;
  NXTMC68040 *processor;
  NXTUInt16 format = 0;
  NXTUInt16 specialStatus = 0;
  NXTUInt32 faultAddress = 0;
  NXTUInt8 imageBytes[0x200] = { 0 };
  NXTUInt8 code[] = {
    0x70, 0x01,                         /* MOVEQ #1,D0 */
    0x4e, 0x7b, 0x00, 0x01,             /* MOVEC D0,DFC */
    0x20, 0x7c, 0x00, 0x00, 0x30, 0x00, /* MOVEA.L #$3000,A0 */
    0x72, 0x01,                         /* MOVEQ #1,D1 */
    0x0e, 0x90, 0x18, 0x00              /* MOVES.L D1,(A0) */
  };

  imageBytes[0] = 0x00;
  imageBytes[1] = 0x00;
  imageBytes[2] = 0x21;
  imageBytes[3] = 0x00;
  imageBytes[6] = 0x01;
  imageBytes[8] = 0x00;
  imageBytes[9] = 0x00;
  imageBytes[10] = 0x01;
  imageBytes[11] = 0x80;
  memcpy (imageBytes + 0x100, code, sizeof (code));
  memory = [[NXTMemory alloc] init];
  image = [[NXTMemoryRegion alloc] initWithBaseAddress:0
                                                length:sizeof (imageBytes)
                                              readOnly:YES];
  ram = [[NXTMemoryRegion alloc] initWithBaseAddress:0x2000
                                              length:0x1000
                                            readOnly:NO];
  [memory addRegion:image];
  [memory addRegion:ram];
  [memory loadData:[NSData dataWithBytes:imageBytes length:sizeof (imageBytes)]
         atAddress:0];
  processor = [[NXTMC68040 alloc] initWithMemory:memory];
  NXTAssert ([processor reset], "resets MOVES access-error test");
  NXTAssert ([processor runForInstructionCount:5]
                 == NXTProcessorResultInstructionLimit,
             "vectors an invalid MOVES access");
  [memory readWord:&format atAddress:0x20c4 + 6];
  [memory readWord:&specialStatus atAddress:0x20c4 + 12];
  [memory readLong:&faultAddress atAddress:0x20c4 + 20];
  NXTAssert ([processor programCounter] == 0x180 && format == 0x7008U,
             "builds a 68040 format-7 access-error frame");
  NXTAssert ((specialStatus & 0x0767U) == 0x0441U
                 && faultAddress == 0x3000U,
             "records the ATC fault direction, space, and address");
  [processor release];
  [ram release];
  [image release];
  [memory release];
}

static void
NXTTestEffectiveAddresses (void)
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
  image = [[NXTMemoryRegion alloc] initWithBaseAddress:0
                                                length:0x200
                                              readOnly:YES];
  ram = [[NXTMemoryRegion alloc] initWithBaseAddress:0x1000
                                              length:0x100
                                            readOnly:NO];
  [memory addRegion:image];
  [memory addRegion:ram];
  [memory loadData:[NSData dataWithBytes:vectors length:8] atAddress:0];
  [memory loadData:[NSData dataWithBytes:code length:22] atAddress:0x100];
  processor = [[NXTMC68040 alloc] initWithMemory:memory];
  NXTAssert ([processor reset], "resets effective-address test processor");
  NXTAssert ([processor runForInstructionCount:20]
                 == NXTProcessorResultStopped,
             "runs generalized effective-address instructions");
  [memory readLong:&stored atAddress:0x1000];
  NXTAssert (stored == 0x12345679, "updates a memory effective address");
  NXTAssert ([processor dataRegister:1] == 0x12345678,
             "moves memory into a register");
  NXTAssert ([processor addressRegister:0] == 0x1004,
             "postincrements once on read-modify-write");
  NXTAssert ([processor addressRegister:1] == 0x1000,
             "computes displacement effective address");
  [processor release];
  [ram release];
  [image release];
  [memory release];
}

static void
NXTTestExtendedBranches (void)
{
  NXTMemory *memory;
  NXTMemoryRegion *image;
  NXTMemoryRegion *stack;
  NXTMC68040 *processor;
  NXTUInt8 vectors[8] = { 0x00, 0x00, 0x20, 0x00, 0x00, 0x00, 0x01, 0x00 };
  NXTUInt8 code[24] = {
    0x60, 0x00, 0x00, 0x04, /* BRA.W, relative to extension address */
    0xff, 0xff, 0x70, 0x01, 0x60, 0xff, 0x00, 0x00, 0x00, 0x08, /* BRA.L */
    0xff, 0xff, 0xff, 0xff, 0x72, 0x02, 0x4e, 0x72, 0x27, 0x00
  };
  memory = [[NXTMemory alloc] init];
  image = [[NXTMemoryRegion alloc] initWithBaseAddress:0
                                                length:0x200
                                              readOnly:YES];
  stack = [[NXTMemoryRegion alloc] initWithBaseAddress:0x1f00
                                                length:0x100
                                              readOnly:NO];
  [memory addRegion:image];
  [memory addRegion:stack];
  [memory loadData:[NSData dataWithBytes:vectors length:8] atAddress:0];
  [memory loadData:[NSData dataWithBytes:code length:24] atAddress:0x100];
  processor = [[NXTMC68040 alloc] initWithMemory:memory];
  NXTAssert ([processor reset], "resets extended-branch test processor");
  NXTAssert ([processor runForInstructionCount:10]
                 == NXTProcessorResultStopped,
             "bases word and long branches at the extension address");
  NXTAssert ([processor dataRegister:0] == 1 &&
                 [processor dataRegister:1] == 2,
             "extended branches land on instruction boundaries");
  [processor release];
  [stack release];
  [image release];
  [memory release];
}

static void
NXTTestImmediateCompareCarry (void)
{
  NXTMemory *memory;
  NXTMemoryRegion *image;
  NXTMemoryRegion *stack;
  NXTMC68040 *processor;
  NXTUInt8 vectors[8] = { 0x00, 0x00, 0x20, 0x00, 0x00, 0x00, 0x01, 0x00 };
  NXTUInt8 code[]
      = { 0x20, 0x3c, 0x12, 0x34, 0x56, 0x78, /* MOVE.L #$12345678,D0 */
          0x0c, 0x80, 0x89, 0xab, 0xcd, 0xef, /* CMPI.L #$89abcdef,D0 */
          0x62, 0x02, /* BHI skips only if C=0 && Z=0 */
          0x72, 0x01, /* Correct borrow path. */
          0x4e, 0x72, 0x27, 0x00 };
  memory = [[NXTMemory alloc] init];
  image = [[NXTMemoryRegion alloc] initWithBaseAddress:0
                                                length:0x200
                                              readOnly:YES];
  stack = [[NXTMemoryRegion alloc] initWithBaseAddress:0x1f00
                                                length:0x100
                                              readOnly:NO];
  [memory addRegion:image];
  [memory addRegion:stack];
  [memory loadData:[NSData dataWithBytes:vectors length:8] atAddress:0];
  [memory loadData:[NSData dataWithBytes:code length:sizeof (code)]
         atAddress:0x100];
  processor = [[NXTMC68040 alloc] initWithMemory:memory];
  NXTAssert ([processor reset], "resets immediate-compare flag test");
  NXTAssert ([processor step] == NXTProcessorResultOK &&
                 [processor step] == NXTProcessorResultOK,
             "executes immediate comparison");
  NXTAssert (([processor statusRegister] & 1U) != 0,
             "CMPI sets carry when unsigned subtraction borrows");
  NXTAssert ([processor runForInstructionCount:10]
                 == NXTProcessorResultStopped,
             "runs immediate-compare branch test");
  NXTAssert ([processor dataRegister:1] == 1, "BHI observes carry from CMPI");
  [processor release];
  [stack release];
  [image release];
  [memory release];
}

static void
NXTTestFMoveLong (void)
{
  NXTMemory *memory;
  NXTMemoryRegion *image;
  NXTMemoryRegion *stack;
  NXTMC68040 *processor;
  NXTUInt8 vectors[8] = { 0x00, 0x00, 0x20, 0x00, 0x00, 0x00, 0x01, 0x00 };
  NXTUInt8 code[]
      = { 0x26, 0x3c, 0x00, 0x00, 0x80, 0x00, /* MOVE.L #$8000,D3 */
          0xf2, 0x03, 0x40, 0x80,             /* FMOVE.L D3,FP1 */
          0xf2, 0x27, 0x60, 0x80,             /* FMOVE.L FP1,-(A7) */
          0xf2, 0x1f, 0x40, 0x80,             /* FMOVE.L (A7)+,FP1 */
          0xf2, 0x04, 0x60, 0x80,             /* FMOVE.L FP1,D4 */
          0x4e, 0x72, 0x27, 0x00 };
  memory = [[NXTMemory alloc] init];
  image = [[NXTMemoryRegion alloc] initWithBaseAddress:0
                                                length:0x200
                                              readOnly:YES];
  stack = [[NXTMemoryRegion alloc] initWithBaseAddress:0x1f00
                                                length:0x100
                                              readOnly:NO];
  [memory addRegion:image];
  [memory addRegion:stack];
  [memory loadData:[NSData dataWithBytes:vectors length:8] atAddress:0];
  [memory loadData:[NSData dataWithBytes:code length:sizeof (code)]
         atAddress:0x100];
  processor = [[NXTMC68040 alloc] initWithMemory:memory];
  NXTAssert ([processor reset], "resets FMOVE test");
  NXTAssert ([processor runForInstructionCount:10]
                 == NXTProcessorResultStopped,
             "executes FMOVE outside the ROM POST address range");
  NXTAssert ([processor dataRegister:4] == 0x8000,
             "round-trips an integer through an FP register");
  [processor release];
  [stack release];
  [image release];
  [memory release];
}

static void
NXTTestFMoveControlRegister (void)
{
  NXTMemory *memory;
  NXTMemoryRegion *image, *ram, *stack;
  NXTMC68040 *processor;
  NXTUInt8 vectors[8] = { 0, 0, 0x20, 0, 0, 0, 1, 0 };
  NXTUInt8 code[] = {
    0x20, 0x7c, 0,    0,    0x10, 0x00, /* MOVEA.L #$1000,A0 */
    0x24, 0x3c, 0x12, 0x34, 0x56, 0x78, /* MOVE.L #$12345678,D2 */
    0xf2, 0x02, 0x90, 0x00,             /* FMOVE.L D2,FPCR */
    0xf2, 0x01, 0xb0, 0x00,             /* FMOVE.L FPCR,D1 */
    0xf2, 0x28, 0xbc, 0x00, 0,    0x10, /* FMOVEM.L FPcr,$10(A0) */
    0xf2, 0x28, 0xf0, 0xff, 0,    0x20, /* FMOVEM.X FP0-FP7,$20(A0) */
    0x4e, 0x72, 0x27, 0x00              /* STOP #$2700 */
  };
  NXTUInt32 value = 0;

  memory = [[NXTMemory alloc] init];
  image = [[NXTMemoryRegion alloc] initWithBaseAddress:0
                                                length:0x200
                                              readOnly:YES];
  ram = [[NXTMemoryRegion alloc] initWithBaseAddress:0x1000
                                              length:0x100
                                            readOnly:NO];
  stack = [[NXTMemoryRegion alloc] initWithBaseAddress:0x1f00
                                                length:0x100
                                              readOnly:NO];
  [memory addRegion:image];
  [memory addRegion:ram];
  [memory addRegion:stack];
  [memory loadData:[NSData dataWithBytes:vectors length:8] atAddress:0];
  [memory loadData:[NSData dataWithBytes:code length:sizeof (code)]
         atAddress:0x100];
  processor = [[NXTMC68040 alloc] initWithMemory:memory];
  NXTAssert ([processor reset], "resets FP control-register test");
  NXTAssert ([processor runForInstructionCount:10]
                 == NXTProcessorResultStopped,
             "executes FPCR transfers");
  NXTAssert ([processor dataRegister:1] == 0x12345678,
             "round-trips FPCR through a data register");
  [memory readLong:&value atAddress:0x1010];
  NXTAssert (value == 0x12345678,
             "saves multiple FP control registers to memory");
  [processor release];
  [stack release];
  [ram release];
  [image release];
  [memory release];
}

static void
NXTTestSCCLocalLoopback (void)
{
  NXTMemory *memory = [[NXTMemory alloc] init];
  NXTUInt8 status, value;
  [memory resetNeXTDevicesForTurbo:YES];

  [memory writeByte:0x0e atAddress:0x02018001U];
  [memory writeByte:0x10 atAddress:0x02018001U];
  [memory writeByte:0x5a atAddress:0x02018003U];
  [memory readByte:&status atAddress:0x02018001U];
  NXTAssert ((status & 1U) != 0,
             "SCC reports received data in local loopback");
  [memory readByte:&value atAddress:0x02018003U];
  NXTAssert (value == 0x5a, "SCC locally loops transmitted data");

  [memory writeByte:0x0e atAddress:0x02018001U];
  [memory writeByte:0x00 atAddress:0x02018001U];
  [memory writeByte:0x69 atAddress:0x02018003U];
  [memory readByte:&status atAddress:0x02018001U];
  NXTAssert ((status & 1U) == 0,
             "SCC stops echoing after local loopback is disabled");
  [memory release];
}

static void
NXTTestGenericDMAControlStatus (void)
{
  NXTMemory *memory = [[NXTMemory alloc] init];
  NXTUInt32 value = 0;
  [memory resetNeXTDevicesForTurbo:YES];
  [memory writeLong:0x00030000U atAddress:0x02000150U];
  [memory readLong:&value atAddress:0x02000150U];
  NXTAssert (value == 0x03000000U,
             "generic DMA CSR exposes enabled/update state in the high byte");
  [memory writeLong:0x00100000U atAddress:0x02000150U];
  [memory readLong:&value atAddress:0x02000150U];
  NXTAssert (value == 0, "generic DMA reset clears its state");
  [memory release];
}

static void
NXTTestSCSIBusResetTiming (void)
{
  NXTMemory *memory = [[NXTMemory alloc] init];
  NXTUInt32 interruptStatus = 0;
  NXTUInt8 value = 0;
  unsigned int tick;

  [memory resetNeXTDevicesForTurbo:YES];
  [memory writeByte:0x57 atAddress:0x02014008U];
  [memory writeByte:0x03 atAddress:0x02014003U];
  [memory readByte:&value atAddress:0x02014008U];
  NXTAssert (value == 0x57,
             "SCSI bus reset preserves the ESP configuration");
  for (tick = 0; tick < 824U; tick++)
    [memory pendingInterruptLevel];
  [memory readByte:&value atAddress:0x02014005U];
  NXTAssert (value == 0, "SCSI bus reset remains active for 25 microseconds");
  [memory pendingInterruptLevel];
  [memory readByte:&value atAddress:0x02014005U];
  NXTAssert (value == 0x80, "SCSI bus reset latches reset completion");
  [memory readLong:&interruptStatus atAddress:0x02007000U];
  NXTAssert (interruptStatus == 0,
             "ESP reset-report suppression prevents an external interrupt");
  [memory release];
}

static void
NXTTestSCSISelectionFailureInterrupt (void)
{
  NXTMemory *memory = [[NXTMemory alloc] init];
  NXTUInt32 interruptStatus = 0;
  [memory resetNeXTDevicesForTurbo:YES];
  [memory writeByte:1 atAddress:0x02014004U];
  [memory writeByte:0 atAddress:0x02014002U];
  [memory writeByte:0x41 atAddress:0x02014003U];
  [memory readLong:&interruptStatus atAddress:0x02007000U];
  NXTAssert (interruptStatus == ((1U << 12) | (1U << 13)),
             "SCSI selection failure raises the controller interrupt");
  [memory release];
}

static void
NXTTestSCSINonzeroLUN (void)
{
  NXTMemory *memory = [[NXTMemory alloc] init];
  NSString *path = [NSTemporaryDirectory ()
      stringByAppendingPathComponent:@"nextemu-scsi-lun.img"];
  NSMutableData *disk = [NSMutableData dataWithLength:512];
  NXTUInt8 cdb[6] = { 0x12, 0x20, 0, 0, 54, 0 };
  NXTUInt8 status = 0;
  unsigned int index;

  [disk writeToFile:path atomically:YES];
  [memory resetNeXTDevicesForTurbo:YES];
  NXTAssert ([memory attachSCSIDiskAtPath:path error:NULL],
             "attaches the SCSI LUN test image");
  [memory writeByte:0 atAddress:0x02014004U];
  for (index = 0; index < sizeof (cdb); index++)
    [memory writeByte:cdb[index] atAddress:0x02014002U];
  [memory writeByte:0x41 atAddress:0x02014003U];
  [memory writeByte:0x11 atAddress:0x02014003U];
  [memory readByte:&status atAddress:0x02014002U];
  NXTAssert (status == 0,
             "reports a nonzero SCSI LUN as absent without failing inquiry");
  [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
  [memory release];
}

static void
NXTTestCompareMemoryPostincrement (void)
{
  NXTMemory *memory;
  NXTMemoryRegion *image, *ram;
  NXTMC68040 *processor;
  NXTUInt8 vectors[8] = { 0, 0, 0x20, 0, 0, 0, 1, 0 };
  NXTUInt8 code[]
      = { 0x20, 0x7c, 0,    0,   0x10, 0x00, /* MOVEA.L #$1000,A0 */
          0x22, 0x7c, 0,    0,   0x10, 0x10, /* MOVEA.L #$1010,A1 */
          0xb3, 0x88,                        /* CMPM.L (A0)+,(A1)+ */
          0x4e, 0x72, 0x27, 0x00 };
  NXTUInt8 equalWords[20]
      = { 0x12, 0x34, 0x56, 0x78, 0, 0, 0,    0,    0,    0,
          0,    0,    0,    0,    0, 0, 0x12, 0x34, 0x56, 0x78 };
  memory = [[NXTMemory alloc] init];
  image = [[NXTMemoryRegion alloc] initWithBaseAddress:0
                                                length:0x200
                                              readOnly:YES];
  ram = [[NXTMemoryRegion alloc] initWithBaseAddress:0x1000
                                              length:0x100
                                            readOnly:NO];
  [memory addRegion:image];
  [memory addRegion:ram];
  [memory loadData:[NSData dataWithBytes:vectors length:8] atAddress:0];
  [memory loadData:[NSData dataWithBytes:code length:sizeof (code)]
         atAddress:0x100];
  [memory loadData:[NSData dataWithBytes:equalWords length:sizeof (equalWords)]
         atAddress:0x1000];
  processor = [[NXTMC68040 alloc] initWithMemory:memory];
  NXTAssert ([processor reset], "resets CMPM test");
  NXTAssert ([processor step] == NXTProcessorResultOK &&
                 [processor step] == NXTProcessorResultOK &&
                 [processor step] == NXTProcessorResultOK,
             "executes CMPM.L");
  NXTAssert (([processor statusRegister] & 4U) != 0,
             "CMPM reports equal memory operands");
  NXTAssert ([processor addressRegister:0] == 0x1004 &&
                 [processor addressRegister:1] == 0x1014,
             "CMPM postincrements both address registers");
  NXTAssert ([processor step] == NXTProcessorResultStopped, "stops CMPM test");
  [processor release];
  [ram release];
  [image release];
  [memory release];
}

static void
NXTTestImmediateBitMemoryDisplacement (void)
{
  NXTMemory *memory;
  NXTMemoryRegion *image, *ram;
  NXTMC68040 *processor;
  NXTUInt8 vectors[8] = { 0, 0, 0x20, 0, 0, 0, 1, 0 };
  NXTUInt8 code[] = {
    0x20, 0x7c, 0,    0,   0x10, 0x00, /* MOVEA.L #$1000,A0 */
    0x08, 0xe8, 0,    4,   0,    0x54, /* BSET #4,$54(A0) */
    0x4e, 0x72, 0x27, 0x00             /* STOP #$2700 */
  };
  NXTUInt8 value = 0;

  memory = [[NXTMemory alloc] init];
  image = [[NXTMemoryRegion alloc] initWithBaseAddress:0
                                                length:0x200
                                              readOnly:YES];
  ram = [[NXTMemoryRegion alloc] initWithBaseAddress:0x1000
                                              length:0x100
                                            readOnly:NO];
  [memory addRegion:image];
  [memory addRegion:ram];
  [memory loadData:[NSData dataWithBytes:vectors length:8] atAddress:0];
  [memory loadData:[NSData dataWithBytes:code length:sizeof (code)]
         atAddress:0x100];
  processor = [[NXTMC68040 alloc] initWithMemory:memory];
  NXTAssert ([processor reset], "resets immediate bit-operation test");
  NXTAssert ([processor step] == NXTProcessorResultOK &&
                 [processor step] == NXTProcessorResultOK,
             "executes BSET with address displacement");
  [memory readByte:&value atAddress:0x1054];
  NXTAssert ([processor programCounter] == 0x10c,
             "decodes the BSET effective address only once");
  NXTAssert (value == 0x10, "sets the selected memory bit");
  [processor release];
  [ram release];
  [image release];
  [memory release];
}

int
main (void)
{
  NSAutoreleasePool *pool;
  pool = [[NSAutoreleasePool alloc] init];
  NXTTestMemory ();
  NXTTestResetVectors ();
  NXTTestInstructionExecution ();
  NXTTestMovesAlternateSpace ();
  NXTTestMovesAccessErrorFrame ();
  NXTTestMachineROMAliases ();
  NXTTestEffectiveAddresses ();
  NXTTestExtendedBranches ();
  NXTTestImmediateCompareCarry ();
  NXTTestFMoveLong ();
  NXTTestFMoveControlRegister ();
  NXTTestSCCLocalLoopback ();
  NXTTestGenericDMAControlStatus ();
  NXTTestSCSIBusResetTiming ();
  NXTTestSCSISelectionFailureInterrupt ();
  NXTTestSCSINonzeroLUN ();
  NXTTestCompareMemoryPostincrement ();
  NXTTestImmediateBitMemoryDisplacement ();
  if (failures == 0)
    printf ("All core tests passed.\n");
  [pool drain];
  return failures == 0 ? 0 : 1;
}
