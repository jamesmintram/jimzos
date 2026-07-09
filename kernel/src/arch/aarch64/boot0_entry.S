// aarch64 boot stage 0: raw reset entry (MMU off, physical, low VAs).
// Parks secondary cores, sets the boot stack, then branches to boot1_phys.
.section ".text.entry"
.global __start
__start:
  b		__start_ram

.section ".text.boot"
.type __start_ram, %function
__start_ram:
  // Read Aff0 and park secondary processors.
  mrs	  x7, mpidr_el1
  and	  x7, x7, #0xff
  cbz	  x7, __start_master
  b		  __hang

__start_master:
  // Use the dedicated physical bootstrap stack from the linker script.
  adrp	x2, __boot_phys_stack
  mov	  sp, x2

  // Dropping to EL1, page-table setup and enabling the MMU now live in
  // boot1_phys.zig. The post-MMU continuation is boot2_virt.zig:
  // enter_virtual_addressing.
  b boot1_phys

__hang:
  # wait forever in case of exit
	wfe
	b		__hang
