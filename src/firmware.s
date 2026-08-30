.section .text
.global _start

.equ UART_BASE,             0x10000000
.equ UART_LSR,              5
.equ UART_LSR_THRE,         0x20

.equ KERNEL_ENTRY,          0x80200000

.equ MEDELEG_ILLEGAL_INST,  (1 << 2)
.equ MSTATUS_MPP_MASK,      (3 << 11)
.equ MSTATUS_MPP_S,         (1 << 11)

.equ MEDELEG_ECALL,         (1 << 8)
.equ MEDELEG_INST_PAGE,     (1 << 12)
.equ MEDELEG_LOAD_PAGE,     (1 << 13)
.equ MEDELEG_STORE_PAGE,    (1 << 15)

_start:
    # Establish firmware stack
    la sp, firmware_stack_top

    # a0 = boot hart ID
    # a1 = FDT physical address
    mv s0, a0
    mv s1, a1

    la t0, machine_trap
    csrw mtvec, t0

    la a0, firmware_ok
    call uart_puts

    # PMP entry 0:
    # allow S-mode RWX accross over the physical address space.
    li t0, -1
    csrw pmpaddr0, t0
    li t0, 0x0f
    csrw pmpcfg0, t0

    # Delegate page faults to S-mode
    li t0, (MEDELEG_INST_PAGE | MEDELEG_LOAD_PAGE | MEDELEG_STORE_PAGE | MEDELEG_ILLEGAL_INST | MEDELEG_ECALL)
    csrw medeleg, t0

    # mret will continue at the S-mode kernel entry
    li t0, KERNEL_ENTRY
    csrw mepc, t0

    # mstatus.MPP <- S-mode
    li t0, MSTATUS_MPP_MASK
    csrrc zero, mstatus, t0
    li t0, MSTATUS_MPP_S
    csrrs zero, mstatus, t0

    mv a0, s0
    mv a1, s1

    # M-mode -> S-mode
    mret

# a0 = character
uart_putc:
    li t0, UART_BASE
1:
    lbu t1, UART_LSR(t0)
    andi t1, t1, UART_LSR_THRE
    beqz t1, 1b
    sb a0, 0(t0)
    ret

# a0 = pointer to null-terminated string
uart_puts:
    addi sp, sp, -16
    sw ra, 12(sp)
    sw s0, 8(sp)
    mv s0, a0
1:
    lbu a0, 0(s0)
    beqz a0, 2f
    call uart_putc
    addi s0, s0, 1
    j 1b
2:
    lw s0, 8(sp)
    lw ra, 12(sp)
    addi sp, sp, 16
    ret

.balign 4
machine_trap:
    la a0, machine_trap_msg
    call uart_puts
1:
    j 1b


.section .rodata
firmware_ok:
    .asciz "Firmware OK\n"
machine_trap_msg:
    .asciz "M-mode trap\n"

.section .bss
.align 4

firmware_stack:
    .space 4096
firmware_stack_top:
