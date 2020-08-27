
#!/bin/bash

~/software/aarch64-none-elf/bin/aarch64-elf-gdb --command="$(dirname "$0")/qemu_attach.gdb"

