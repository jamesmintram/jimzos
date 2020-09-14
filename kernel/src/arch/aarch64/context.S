
#include "struct_defs_Thread.h"
#include "struct_defs_CPUFrame.h"

.macro	ctx_switch_save_registers el
	sub	sp, sp, #(CPUFrame__size)
	
    //TODO: User a different darta struct for ctx_switch
    str	x30, [sp, #(CPUFrame_tf_lr)]

	stp	x28, x29, [sp, #(CPUFrame_tf_x + 28 * 8)]
	stp	x26, x27, [sp, #(CPUFrame_tf_x + 26 * 8)]
	stp	x24, x25, [sp, #(CPUFrame_tf_x + 24 * 8)]
    stp	x22, x23, [sp, #(CPUFrame_tf_x + 22 * 8)]
	stp	x20, x21, [sp, #(CPUFrame_tf_x + 20 * 8)]
	stp	x18, x19, [sp, #(CPUFrame_tf_x + 18 * 8)]
	stp	x16, x17, [sp, #(CPUFrame_tf_x + 16 * 8)]
	stp	x14, x15, [sp, #(CPUFrame_tf_x + 14 * 8)]
	stp	x12, x13, [sp, #(CPUFrame_tf_x + 12 * 8)]
	stp	x10, x11, [sp, #(CPUFrame_tf_x + 10 * 8)]
	stp	x8,  x9,  [sp, #(CPUFrame_tf_x + 8  * 8)]
	stp	x6,  x7,  [sp, #(CPUFrame_tf_x + 6  * 8)]
	stp	x4,  x5,  [sp, #(CPUFrame_tf_x + 4  * 8)]
	stp	x2,  x3,  [sp, #(CPUFrame_tf_x + 2  * 8)]
	stp	x0,  x1,  [sp, #(CPUFrame_tf_x + 0  * 8)]

  //TODO: Store the ttib
  //mrs  x19, tpidr_el0
  //mrs  x20, tpidrro_el0
  //stp x19, x20, [sp, #(CPUFrame_tf_x + 0 * 8)] //TODO: NEW STRUCT!
.endm

//-------------------------------------------------------

.macro	ctx_switch_restore_registers el
  // Requires the SP already be set

  //ldp	x19, x20, [sp, #(CPUFrame_tf_x + 0 * 8)] //TODO: NEW STRUCT!
  //msr  tpidr_el0, x19
  //msr  tpidrro_el0, x20

    ldr	x30, [sp, #(CPUFrame_tf_lr)]

	ldp	x28, x29, [sp, #(CPUFrame_tf_x + 28 * 8)]
	ldp	x26, x27, [sp, #(CPUFrame_tf_x + 26 * 8)]
	ldp	x24, x25, [sp, #(CPUFrame_tf_x + 24 * 8)]
	ldp	x22, x23, [sp, #(CPUFrame_tf_x + 22 * 8)]
	ldp	x20, x21, [sp, #(CPUFrame_tf_x + 20 * 8)]
	ldp	x16, x17, [sp, #(CPUFrame_tf_x + 16 * 8)]
	ldp	x14, x15, [sp, #(CPUFrame_tf_x + 14 * 8)]
	ldp	x12, x13, [sp, #(CPUFrame_tf_x + 12 * 8)]
	ldp	x10, x11, [sp, #(CPUFrame_tf_x + 10 * 8)]
	ldp	x8,  x9,  [sp, #(CPUFrame_tf_x + 8  * 8)]
	ldp	x6,  x7,  [sp, #(CPUFrame_tf_x + 6  * 8)]
	ldp	x4,  x5,  [sp, #(CPUFrame_tf_x + 4  * 8)]
	ldp	x2,  x3,  [sp, #(CPUFrame_tf_x + 2  * 8)]
    ldp	x0,  x1,  [sp, #(CPUFrame_tf_x + 0  * 8)]

    add	sp, sp, #(CPUFrame__size)
.endm

//-------------------------------------------------------

.global _ctx_switch_to_initial
_ctx_switch_to_initial:
  // X0 = pointer to the initial thread
  clrex

  // Switch the thread pointer to the next thread block
  msr tpidr_el1, x0
  
  // Switch page tables

  // Load the next thread's SP
  ldr x18, [x0, Thread_stack_pointer]
  mov sp, x18

  //Finally restore the registers
  ctx_switch_restore_registers

  ret