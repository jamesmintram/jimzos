set debug aarch64

target remote localhost:1234
file zig-cache/bin/kernel8.elf

set scheduler-locking on

b  *0x00000000000801f4


layout next 
layout next 