#!/bin/sh

set -eu

elf_size=$(wc -c < "$1")
if [ "$elf_size" -gt 4194304 ]; then
    echo "kernel ELF is larger than its 4 MiB boot-module reservation" >&2
    exit 1
fi

mkdir -p zig-cache/dumps

echo "Dumping asm"
llvm-objdump $1 -d > zig-cache/dumps/kernel.S

echo "Dumping syms"
llvm-objdump $1 --syms > zig-cache/dumps/kernel.syms

# hexdump zig-cache/bin/kernel8 > zig-cache/dumps/bindump.hex
