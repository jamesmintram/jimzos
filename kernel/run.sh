qemu-system-aarch64 -s -S -d int -M raspi3  -semihosting -serial stdio -device loader,file=zig-cache/bin/kernel8,addr=0x0


