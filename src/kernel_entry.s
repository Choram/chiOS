.section .text
.global kernel_entry
.extern kernelMain
.extern supervisor_trap

kernel_entry:
    # a0 = boot hart IO
    # a1 = FDT physucal address
    la sp, kernel_stack_top
    call kernelMain
1:
    j 1b

.section .bss
.balign 16

kernel_stack:
    .space 4096
kernel_stack_top:
