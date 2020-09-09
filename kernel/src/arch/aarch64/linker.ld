ENTRY(__start)

SECTIONS {
  kernel_va_base = 0xFFFF000000000000;
  kernel_page_size = 4K; 

  kps_less1 = kernel_page_size -1;
  kernel_physical_start = (boot_end + kps_less1) & ~(kps_less1);
  
  kernel_first_page = kernel_va_base + kernel_physical_start;

  __kernel_stack_size = 1M;
  __boot_phys_stack =  __kernel_stack_start - kernel_first_page + kernel_physical_start;
  __heap_phys_start = __heap_start - kernel_first_page + kernel_physical_start;

  __page_tables_size = ((3 + 512) * 0x1000);
  __page_tables_phys_start = __page_tables_start - kernel_first_page + kernel_physical_start;
  __page_tables_phys_end = __page_tables_phys_start + __page_tables_size;

  /*-----------------------------------------------*/
  /* This is the bootstrap
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

  /*-----------------------------------------------*/
  /* This is the kernel
  /*------------------------------------------------*/

  .text kernel_first_page : AT (kernel_physical_start) {
    *.text
  }

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
  
  __kernel_stack_start = .;
  . += __kernel_stack_size;
  __kernel_stack_end = .;

  __page_tables_start = .;
  . += __page_tables_size;
  __page_tables_end = .;

  __heap_start = .;
}