.section .text
.global enable_sv32

.equ SATP_MODE_SV32,    0x80000000

enable_sv32:
    # a0 = physical address of root page table

    # Make sure previous page-table writes are visible
    # I still don't know what this ACTUALLY is.
    sfence.vma x0, x0

    # satp.PPN = root_pa >> 12
    srli t0, a0, 12
    # satp.MODE = Sv32, ASID = 0
    li t1, SATP_MODE_SV32
    or t0, t0, t1
    csrw satp, t0

    sfence.vma x0, x0

    ret
