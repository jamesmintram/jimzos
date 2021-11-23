!#/bin/sh
# qemu-system-aarch64 -s -S -d int -M raspi3  -semihosting -serial stdio -device loader,file=zig-out/bin/kernel8,addr=0x0
qemu-system-aarch64 -d int -M raspi3  -semihosting -serial stdio -device loader,file=zig-out/bin/kernel8,addr=0x0
