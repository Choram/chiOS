.section .text
.global supervisor_trap_entry
.global install_supervisor_trap
.global enter_user
.extern supervisorTrap
.extern trapDispatch


.equ TF_KERNEL_SP,      0
.equ TF_KERNEL_TRAP,    4

.equ TF_SEPC,           8
.equ TF_SSTATUS,       12

.equ TF_RA,            16
.equ TF_SP,            20
.equ TF_GP,            24
.equ TF_TP,            28

.equ TF_T0,            32
.equ TF_T1,            36
.equ TF_T2,            40

.equ TF_S0,            44
.equ TF_S1,            48

.equ TF_A0,            52
.equ TF_A1,            56
.equ TF_A2,            60
.equ TF_A3,            64
.equ TF_A4,            68
.equ TF_A5,            72
.equ TF_A6,            76
.equ TF_A7,            80

.equ TF_S2,            84
.equ TF_S3,            88
.equ TF_S4,            92
.equ TF_S5,            96
.equ TF_S6,           100
.equ TF_S7,           104
.equ TF_S8,           108
.equ TF_S9,           112
.equ TF_S10,          116
.equ TF_S11,          120

.equ TF_T3,           124
.equ TF_T4,           128
.equ TF_T5,           132
.equ TF_T6,           136

.equ TF_SIZE,         140


install_supervisor_trap:
    la t0, supervisor_trap_entry
    csrw stvec, t0

    # No U-mode context is running.
    # In S-mode, sscratch is kept zero.
    csrw sscratch, zero
    ret

.balign 4
supervisor_trap_entry:
    # exchange t0 with sscratch.
    # U-mode: t0 <- current *TrapFrame
    # S-mode: t0 <- 0
    csrrw t0, sscratch, t0

    # sscratch is zero while kernel code was running
    beqz t0, supervisor_kernel_trap

    # t0 currently holds *TrapFrame
    # Original user t0 is temporarily stored in sscratch.
    sw ra, TF_RA(t0)
    sw sp, TF_SP(t0)
    sw gp, TF_GP(t0)
    sw tp, TF_TP(t0)
    sw t1, TF_T1(t0)
    sw t2, TF_T2(t0)
    sw s0, TF_S0(t0)
    sw s1, TF_S1(t0)
    sw a0, TF_A0(t0)
    sw a1, TF_A1(t0)
    sw a2, TF_A2(t0)
    sw a3, TF_A3(t0)
    sw a4, TF_A4(t0)
    sw a5, TF_A5(t0)
    sw a6, TF_A6(t0)
    sw a7, TF_A7(t0)
    sw s2, TF_S2(t0)
    sw s3, TF_S3(t0)
    sw s4, TF_S4(t0)
    sw s5, TF_S5(t0)
    sw s6, TF_S6(t0)
    sw s7, TF_S7(t0)
    sw s8, TF_S8(t0)
    sw s9, TF_S9(t0)
    sw s10, TF_S10(t0)
    sw s11, TF_S11(t0)
    sw t3, TF_T3(t0)
    sw t4, TF_T4(t0)
    sw t5, TF_T5(t0)
    sw t6, TF_T6(t0)

    csrr t1, sscratch
    sw t1, TF_T0(t0)

    csrr t1, sepc
    sw t1, TF_SEPC(t0)

    csrr t1, sstatus
    sw t1, TF_SSTATUS(t0)

    lw sp, TF_KERNEL_SP(t0)
    csrw sscratch, zero

    # trapDispatch(a0, a1, a2)
    # a0 now contains the TrapFarme to resume.
    mv a0, t0
    csrr a1, scause
    csrr a2, stval

    # 0(t1) now have the address of trapDispatch.
    lw t1, TF_KERNEL_TRAP(t0)
    jalr ra, 0(t1)

    j supervisor_trap_return

1:
    j 1b


supervisor_trap_return:
    # a0 = *TrapFrame to resume
    mv t0, a0
    lw t1, TF_SEPC(t0)
    csrw sepc, t1

    lw t1, TF_SSTATUS(t0)
    csrw sstatus, t1

    # Back to U-mode; sscratch = *TrapFrame
    csrw sscratch, t0

    lw ra, TF_RA(t0)
    lw gp, TF_GP(t0)
    lw tp, TF_TP(t0)
    lw t1, TF_T1(t0)
    lw t2, TF_T2(t0)
    lw s0, TF_S0(t0)
    lw s1, TF_S1(t0)
    lw a0, TF_A0(t0)
    lw a1, TF_A1(t0)
    lw a2, TF_A2(t0)
    lw a3, TF_A3(t0)
    lw a4, TF_A4(t0)
    lw a5, TF_A5(t0)
    lw a6, TF_A6(t0)
    lw a7, TF_A7(t0)
    lw s2, TF_S2(t0)
    lw s3, TF_S3(t0)
    lw s4, TF_S4(t0)
    lw s5, TF_S5(t0)
    lw s6, TF_S6(t0)
    lw s7, TF_S7(t0)
    lw s8, TF_S8(t0)
    lw s9, TF_S9(t0)
    lw s10, TF_S10(t0)
    lw s11, TF_S11(t0)
    lw t3, TF_T3(t0)
    lw t4, TF_T4(t0)
    lw t5, TF_T5(t0)
    lw t6, TF_T6(t0)

    lw sp, TF_SP(t0)

    # t0 = original user t0
    lw t0, TF_T0(t0)
    sret

1:
    j 1b


supervisor_kernel_trap:
    # Restore the kernel convention (sscratch = 0) before entering Zig.
    csrrw t0, sscratch, t0
    csrr a0, scause
    csrr a1, sepc
    csrr a2, stval
    call supervisorTrap
1:
    j 1b

enter_user:
    # a0 = *TrapFrame
    j supervisor_trap_return
