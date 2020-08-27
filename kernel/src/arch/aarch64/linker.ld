ENTRY(__start)

SECTIONS {
  kernel_va_base = 0xFFFF000000000000;
  kernel_page_size = 4K; 

  kps_less1 = kernel_page_size -1;
  kernel_physical_start = (boot_end + kps_less1) & ~(kps_less1);
  
  kernel_first_page = kernel_va_base + kernel_physical_start;

  /* Seems to give me what I need*/
  /*kernel_end = __kernel_stack_end;*/
  bss_phys_end = LOADADDR(.bss) + SIZEOF(.bss);
  bss_end = LOADADDR(.bss) + SIZEOF(.bss);

  __page_tables_size = ((3 + 512) * 0x1000);
  
  __page_tables_phys_start = bss_phys_end;
  __page_tables_phys_end = __page_tables_phys_start + __page_tables_size;
  
  __page_tables_start = bss_end;
  __page_tables_end = __page_tables_start + __page_tables_size;

  __heap_phys_start = __page_tables_phys_end;
  __heap_start = __page_tables_end;

  __boot_stack = __heap_phys_start + 0x100000;

  /*-----------------------------------------------*/
  /* This is the bootstrap
  /*------------------------------------------------*/

  .boot.text 0x0 : {
        KEEP(*(.text.entry))
        . = 0x80000;  /* Space for command line.  */
        KEEP(*(.text.boot))
  }

  .boot.data : {
    
  }

  .bss  (NOLOAD) : {
    
  }

  boot_end = .;
}

SECTIONS {
  .text kernel_first_page : AT (kernel_physical_start) {
  }




  .bss  (NOLOAD) : {
    __bss_start = ALIGN(0x10);
    *(.bss .bss.*)
    *(COMMON)

    __bss_end = ALIGN(0x10);

    __kernel_stack_guard = ALIGN(kernel_page_size);
    . += kernel_page_size;

    /*TODO: Shouldn't really be sticking the stack here*/
    __kernel_stack_start = ALIGN(kernel_page_size);
    . += 0x100000;
    . = ALIGN(kernel_page_size);
    __kernel_stack_end = .;
  }

   __bss_dwords = (__bss_end - __bss_start) >> 3;
}