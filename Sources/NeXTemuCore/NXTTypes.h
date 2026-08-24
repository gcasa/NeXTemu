#ifndef NXT_TYPES_H
#define NXT_TYPES_H

#include <stdint.h>

typedef uint8_t NXTUInt8;
typedef uint16_t NXTUInt16;
typedef uint32_t NXTUInt32;
typedef uint64_t NXTUInt64;

typedef enum {
    NXTMemoryResultOK = 0,
    NXTMemoryResultUnmapped,
    NXTMemoryResultReadOnly,
    NXTMemoryResultOutOfRange
} NXTMemoryResult;

#endif
