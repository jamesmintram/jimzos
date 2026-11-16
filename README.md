# jimzos

JimZOS is a work-in-progress AArch64 kernel written in Zig. The default target
is QEMU's generic Arm `virt` machine.

## MacOS setup

```sh
brew install qemu
brew install llvm
brew install dtc
```

The build searches `PATH` for LLVM tools first. On macOS it also checks
`/opt/homebrew/opt/llvm/bin` (Apple Silicon) and `/usr/local/opt/llvm/bin` (Intel),
so Homebrew LLVM does not need to be added to `PATH`. For other LLVM
installations, add their `bin` directory to `PATH`.

## Build and run

The kernel currently builds with Zig 0.16.0 and also requires
`qemu-system-aarch64`, `dtc`, `llvm-objcopy`, and `llvm-objdump`.

```sh
cd kernel
zig build test
zig build qemu
```

`zig build` and `zig build dump` generate the flat binary at
`zig-out/bin/kernel8`, plus disassembly and symbols at `zig-out/dumps/kernel.S`
and `zig-out/dumps/kernel.syms`.

Exit QEMU with <kbd>Ctrl-A</kbd>, then <kbd>X</kbd>.

The Raspberry Pi 3 target is available explicitly:

```sh
zig build qemu -Dplatform=raspi3
```

That target currently boots through memory initialization and the ext2 probe,
then exits because its minimal device tree does not yet describe a supported
interrupt controller or system timer.

## Debugging

Start QEMU paused with a GDB server:

```sh
zig build qemu -Dgdb=true
```

Then connect an AArch64-capable GDB to `localhost:1234` using
`zig-out/bin/kernel8.elf` for symbols. Prefer symbolic breakpoints such as
`break __start` rather than fixed addresses.

## Status

The `virt` target reaches the higher-half kernel, installs FDT-derived memory
maps, initializes the physical allocator, attaches PL011 and GICv3 devices,
mounts the bundled ext2 test image, and receives generic timer interrupts.
Threads, processes, userspace, and most ext2 operations remain experimental.
