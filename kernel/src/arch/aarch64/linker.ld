ENTRY(__start)

SECTIONS {
  kernel_va_base = 0xFFFF000000000000;
  kernel_page_size = 4K;

  kps_less1 = kernel_page_size -1;
  kernel_physical_start = (boot_end + kps_less1) & ~(kps_less1);

  kernel_first_page = kernel_va_base + kernel_physical_start;

  __kernel_stack_size = 1M;

  /* Physical alias of a higher-half kernel symbol: VA - kernel_va_base.
     MMU-off boot code sees only physical addresses, so it uses these. */
  __boot_phys_stack = __kernel_stack_top - kernel_va_base;
  __kernel_stack_guard_phys = __kernel_stack_guard - kernel_va_base;
  __heap_phys_start = __heap_start - kernel_va_base;

  __page_tables_size = ((3 + 512) * 0x1000);
  __page_tables_phys_start = __page_tables_start - kernel_va_base;
  __page_tables_phys_end = __page_tables_phys_start + __page_tables_size;

  /*------------------------------------------------*/
  /* This is the bootstrap                          */
  /*------------------------------------------------*/

  .boot.text 0x0 : {
    KEEP(*(.text.entry))
    . = 0x80000;  /* Space for command line.  */
    KEEP(*(.text.boot))
  }

  .boot.data : {
    *(.data.boot)
  }

  .boot.bss  (NOLOAD) : {
    *(.bss.boot)
  }

  boot_end = .;

  /*------------------------------------------------*/
  /* This is the kernel                             */
  /*------------------------------------------------*/

  .text kernel_first_page : AT (kernel_physical_start) {
    *(.text .text*)
  }

  . = ALIGN(kernel_page_size);

  __rodata_start = .;
  .rodata : {*(.rodata .rodata*)}
  __rodata_end = .;

  . = ALIGN(kernel_page_size);

  __data_start = .;
  .data : {*(.data .data*)}
  __data_end = .;

  . = ALIGN(kernel_page_size);

  .bss  (NOLOAD) : {
    __bss_start = ALIGN(0x10);
    *(.bss .bss.*)
    *(COMMON)

    __bss_end = ALIGN(0x10);
  }

  __bss_dwords = (__bss_end - __bss_start) >> 3;


  /*TODO: Shouldn't really be sticking the stack here*/
  . = ALIGN(kernel_page_size);

  __kernel_stack_guard = .;
  . += kernel_page_size;

  /* Full-descending stack: SP starts at _top (high) and grows down toward
     _limit (low). The guard page below _limit catches overflow. */
  __kernel_stack_limit = .;
  . += __kernel_stack_size;
  __kernel_stack_top = .;

  __page_tables_start = .;
  . += __page_tables_size;
  __page_tables_end = .;

  __heap_start = .;
}
