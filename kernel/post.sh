#!/bin/sh

mkdir -p zig-cache/dumps

echo "Dumping asm"
llvm-objdump-13 $1 -d > zig-cache/dumps/kernel.S

echo "Dumping syms"
llvm-objdump-13 $1 --syms > zig-cache/dumps/kernel.syms

# hexdump zig-cache/bin/kernel8 > zig-cache/dumps/bindump.hex
