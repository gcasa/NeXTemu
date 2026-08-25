# NeXTemu

NeXTemu is an early-stage, portable NeXTcube emulator written in Objective-C
using Objective-C 1.0-era language conventions. Its initial hardware target is
the monochrome 25 MHz Motorola 68040 NeXTcube. The 33 MHz NeXTcube Turbo will
be a configuration of the same machine model.

The project currently provides:

* a sparse, big-endian physical memory bus;
* ROM and RAM regions with bounds and write-protection checks;
* an initial MC68040 interpreter with reset, common effective-address modes,
  branches, subroutines, stack frames, firmware control setup, selected data
  movement/arithmetic instructions, and explicit bus/illegal-opcode stops;
* a NeXTcube machine composition and AppKit ROM loader;
* a native application window shared by Cocoa and GNUstep; and
* core tests runnable without a ROM image.

It executes a deliberately incomplete, tested subset of 68040 instructions and
provides sparse early-boot device register banks. This is enough to load a ROM,
enter its reset path, and exercise initial hardware probes. It does **not** yet
implement the complete CPU, MMU, NeXT chipset, storage, or display pipeline
required to boot NeXTSTEP.

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

## Screenshot

<img width="828" height="720" alt="progress" src="https://github.com/user-attachments/assets/55e78102-af77-4911-b133-2897569195c8" />

## Firmware

No NeXT firmware is included. Firmware startup requires the user to provide a
legally obtained ROM image.

Place legally obtained, uncompressed NeXT ROM dumps in the top-level `roms/`
directory. If that directory exists, `make` copies it into the application
resources as `roms/`. At launch, the application automatically loads the first
valid bundled ROM; a different image can be selected with **Machine > Open
ROM**. ROM images must be exactly 128 KiB (131,072 bytes), and discovery does
not depend on a particular filename.

For the 25 MHz NeXTcube, use a NeXTcube/NeXTstation 68040 ROM such as revision
2.5 v66. For the 33 MHz NeXTcube Turbo, use a Turbo-capable ROM such as revision
3.3 v74 (revision 3.2 v72 is also commonly available). Do not use the 68030
NeXT Computer ROM or a NeXTdimension EEPROM.

## Disk images

Use **Machine > Attach SCSI Disk** after loading a ROM. NeXTemu accepts a raw,
sector-for-sector image of an entire SCSI disk with 512-byte sectors. The image
must include the NeXT disk label and bootable filesystem; a partition-only UFS
image is not sufficient. Container formats such as QCOW2, VMDK, VDI, and sparse
bundle images are not accepted. Common filename extensions are `.img`, `.dsk`,
and `.raw`, but validation uses the file layout rather than its extension.

The selector attaches the image as SCSI target 6 and restarts the machine.
NeXTemu implements the NCR53C90 commands used during boot, including inquiry,
capacity, mode sense, sector reads, and Turbo DMA. Disk writes are accepted but
discarded, so the original image remains unchanged.
