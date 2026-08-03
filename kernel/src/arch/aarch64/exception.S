#include "asm_offsets.h"

.macro vempty
  .align 7
  //mov     x0, #3
  mrs     x0, esr_el1
  mrs     x1, elr_el1
  mrs     x2, spsr_el1
  mrs     x3, far_el1
  b       exception_panic
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
  vector el1h_irq  //IRQ EL1h
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

.align 7
handle_el1h_irq:
  // Preserve the complete integer context. Kernel FP/SIMD generation is
  // disabled, so there is no vector-register state to save here.
  sub sp, sp, #(CPUFrame__size)

  stp x0,  x1,  [sp, #(CPUFrame_tf_x + 0  * 8)]
  stp x2,  x3,  [sp, #(CPUFrame_tf_x + 2  * 8)]
  stp x4,  x5,  [sp, #(CPUFrame_tf_x + 4  * 8)]
  stp x6,  x7,  [sp, #(CPUFrame_tf_x + 6  * 8)]
  stp x8,  x9,  [sp, #(CPUFrame_tf_x + 8  * 8)]
  stp x10, x11, [sp, #(CPUFrame_tf_x + 10 * 8)]
  stp x12, x13, [sp, #(CPUFrame_tf_x + 12 * 8)]
  stp x14, x15, [sp, #(CPUFrame_tf_x + 14 * 8)]
  stp x16, x17, [sp, #(CPUFrame_tf_x + 16 * 8)]
  stp x18, x19, [sp, #(CPUFrame_tf_x + 18 * 8)]
  stp x20, x21, [sp, #(CPUFrame_tf_x + 20 * 8)]
  stp x22, x23, [sp, #(CPUFrame_tf_x + 22 * 8)]
  stp x24, x25, [sp, #(CPUFrame_tf_x + 24 * 8)]
  stp x26, x27, [sp, #(CPUFrame_tf_x + 26 * 8)]
  stp x28, x29, [sp, #(CPUFrame_tf_x + 28 * 8)]
  str x30, [sp, #(CPUFrame_tf_lr)]

  add x0, sp, #(CPUFrame__size)
  str x0, [sp, #(CPUFrame_tf_sp)]
  mrs x0, elr_el1
  str x0, [sp, #(CPUFrame_tf_elr)]
  mrs x0, spsr_el1
  str w0, [sp, #(CPUFrame_tf_spsr)]
  str wzr, [sp, #(CPUFrame_tf_esr)]

  mov x0, sp
  bl irq_dispatch

  ldr x0, [sp, #(CPUFrame_tf_elr)]
  msr elr_el1, x0
  ldr w0, [sp, #(CPUFrame_tf_spsr)]
  msr spsr_el1, x0

  ldr x30, [sp, #(CPUFrame_tf_lr)]
  ldp x28, x29, [sp, #(CPUFrame_tf_x + 28 * 8)]
  ldp x26, x27, [sp, #(CPUFrame_tf_x + 26 * 8)]
  ldp x24, x25, [sp, #(CPUFrame_tf_x + 24 * 8)]
  ldp x22, x23, [sp, #(CPUFrame_tf_x + 22 * 8)]
  ldp x20, x21, [sp, #(CPUFrame_tf_x + 20 * 8)]
  ldp x18, x19, [sp, #(CPUFrame_tf_x + 18 * 8)]
  ldp x16, x17, [sp, #(CPUFrame_tf_x + 16 * 8)]
  ldp x14, x15, [sp, #(CPUFrame_tf_x + 14 * 8)]
  ldp x12, x13, [sp, #(CPUFrame_tf_x + 12 * 8)]
  ldp x10, x11, [sp, #(CPUFrame_tf_x + 10 * 8)]
  ldp x8,  x9,  [sp, #(CPUFrame_tf_x + 8  * 8)]
  ldp x6,  x7,  [sp, #(CPUFrame_tf_x + 6  * 8)]
  ldp x4,  x5,  [sp, #(CPUFrame_tf_x + 4  * 8)]
  ldp x2,  x3,  [sp, #(CPUFrame_tf_x + 2  * 8)]
  ldp x0,  x1,  [sp, #(CPUFrame_tf_x + 0  * 8)]

  add sp, sp, #(CPUFrame__size)
  eret
