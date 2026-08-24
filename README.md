# NeXTemu

NeXTemu is an early-stage, portable NeXTcube emulator written in Objective-C
using Objective-C 1.0-era language conventions. Its initial hardware target is
the monochrome 25 MHz Motorola 68040 NeXTcube. The 33 MHz NeXTcube Turbo will
be a configuration of the same machine model.

The project currently provides:

* a sparse, big-endian physical memory bus;
* ROM and RAM regions with bounds and write-protection checks;
* an initial MC68040 interpreter with reset, branches, subroutines, selected
  data movement/arithmetic instructions, and explicit bus/illegal-opcode stops;
* a NeXTcube machine composition and AppKit ROM loader;
* a native application window shared by Cocoa and GNUstep; and
* core tests runnable without a ROM image.

It executes a deliberately small, tested subset of 68040 instructions. It does
**not** yet implement the complete CPU, NeXT chipset and peripherals required to
boot a NeXT ROM.

## Build on macOS

Install the Xcode command-line tools, then run:

    make
    make test
    open build/NeXTemu.app

## Build with GNUstep on Linux

Install Clang, GNU Make, and the GNUstep Base and GUI development packages. On a shell
where `gnustep-config` is available, run:

    make
    make test
    openapp build/NeXTemu.app

If your GNUstep installation requires its environment script, source
`GNUstep.sh` before building.

## Language compatibility policy

Production source intentionally avoids ARC, properties, dot syntax, blocks,
Objective-C collection literals, subscripting, fast enumeration, lightweight
generics, nullability annotations, class extensions, and modern-runtime-only
features. Ownership follows manual retain/release rules.

## Firmware

No NeXT firmware is included. A future boot-capable build will require the user
to provide a legally obtained ROM image.
