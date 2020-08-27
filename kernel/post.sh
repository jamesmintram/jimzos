mkdir -p zig-cache/dumps

llvm-objdump-10 zig-cache/bin/kernel8.elf -d > zig-cache/dumps/kernel.S
llvm-objdump-10 zig-cache/bin/kernel8.elf --syms > zig-cache/dumps/kernel.syms
llvm-objcopy-10 zig-cache/bin/kernel8.elf -O binary zig-cache/bin/kernel8
hexdump zig-cache/bin/kernel8 > zig-cache/dumps/bindump.hex
