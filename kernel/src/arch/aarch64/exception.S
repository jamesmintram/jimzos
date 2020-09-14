.macro vempty
  .align 7
  mov     x0, #3
  mrs     x1, esr_el1
  mrs     x2, elr_el1
  mrs     x3, spsr_el1
  mrs     x4, far_el1
  b       exit
.endm

.macro vector name
  .align 7
	b	handle_\name
.endm

.text
.align 12

.align 11
.global _vectors
_vectors:
  //TODO: Eventually we should not use this
  vempty  //Synchronous EL1t
  vempty  //IRQ EL1t
  vempty  //FIQ EL1t
  vempty // vector err_sync  //Error EL1t

  //TODO: Eventually we should use this

  vempty // vector el1h_sync  //Synchronous EL1h
  vempty  //IRQ EL1h
  vempty  //FIQ EL1h
  vempty // vector err_sync  //Error EL1h

  vempty // vector el0_sync  //Synchronous 64bit EL0
  vempty  //IRQ 64bit EL0
  vempty  //FIQ 64bit EL0
  vempty // vector err_sync  //Error 64bit EL0

  vempty  //Synchronous 32bit EL0
  vempty  //IRQ 32bit EL0
  vempty  //FIQ 32bit EL0
  vempty  //Error 32bit EL0