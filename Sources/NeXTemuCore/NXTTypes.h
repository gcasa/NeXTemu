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

#ifndef NXT_TYPES_H
#define NXT_TYPES_H

#include <stdint.h>

/** An unsigned 8-bit integer used by the emulated hardware. */
typedef uint8_t NXTUInt8;
/** An unsigned 16-bit integer used by the emulated hardware. */
typedef uint16_t NXTUInt16;
/** An unsigned 32-bit integer used by the emulated hardware. */
typedef uint32_t NXTUInt32;
/** An unsigned 64-bit integer used by the emulated hardware. */
typedef uint64_t NXTUInt64;

/** Results returned by physical-memory access operations. */
typedef enum
{
  NXTMemoryResultOK = 0,
  NXTMemoryResultUnmapped,
  NXTMemoryResultReadOnly,
  NXTMemoryResultOutOfRange
} NXTMemoryResult;

#endif
