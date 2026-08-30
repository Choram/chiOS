const uart = @import("uart.zig");
const syscall = @import("syscall.zig");

extern fn install_supervisor_trap() void;
extern fn enter_user(tf: *TrapFrame) noreturn;
const EXC_ILLEGAL_INSTRUCTION: usize = 2;
const EXC_ECALL_U: usize = 8;

pub const TrapFrame = extern struct {
    kernel_sp: usize,
    kernel_trap: usize,

    sepc: usize,
    sstatus: usize,

    ra: usize,
    sp: usize,
    gp: usize,
    tp: usize,

    t0: usize,
    t1: usize,
    t2: usize,

    s0: usize,
    s1: usize,

    a0: usize,
    a1: usize,
    a2: usize,
    a3: usize,
    a4: usize,
    a5: usize,
    a6: usize,
    a7: usize,

    s2: usize,
    s3: usize,
    s4: usize,
    s5: usize,
    s6: usize,
    s7: usize,
    s8: usize,
    s9: usize,
    s10: usize,
    s11: usize,

    t3: usize,
    t4: usize,
    t5: usize,
    t6: usize,
};

comptime {
    if (@sizeOf(usize) != 4)
        @compileError("TrapFrame currently requires RV32");

    if (@offsetOf(TrapFrame, "kernel_sp") != 0)
        @compileError("bad TrapFrame.kernel_sp offset");
    if (@offsetOf(TrapFrame, "kernel_trap") != 4)
        @compileError("bad TrapFrame.kernel_trap offset");

    if (@offsetOf(TrapFrame, "sepc") != 8)
        @compileError("bad TrapFrame.sepc offset");
    if (@offsetOf(TrapFrame, "sstatus") != 12)
        @compileError("bad TrapFrame.sstatus offset");

    if (@offsetOf(TrapFrame, "ra") != 16)
        @compileError("bad TrapFrame.ra offset");
    if (@offsetOf(TrapFrame, "sp") != 20)
        @compileError("bad TrapFrame.sp offset");
    if (@offsetOf(TrapFrame, "gp") != 24)
        @compileError("bad TrapFrame.gp offset");
    if (@offsetOf(TrapFrame, "tp") != 28)
        @compileError("bad TrapFrame.tp offset");

    if (@offsetOf(TrapFrame, "t0") != 32)
        @compileError("bad TrapFrame.t0 offset");
    if (@offsetOf(TrapFrame, "a0") != 52)
        @compileError("bad TrapFrame.a0 offset");
    if (@offsetOf(TrapFrame, "s2") != 84)
        @compileError("bad TrapFrame.s2 offset");
    if (@offsetOf(TrapFrame, "t3") != 124)
        @compileError("bad TrapFrame.t3 offset");
    if (@offsetOf(TrapFrame, "t6") != 136)
        @compileError("bad TrapFrame.t6 offset");

    if (@sizeOf(TrapFrame) != 140)
        @compileError("bad TrapFrame size");
}

pub fn init() void {
    install_supervisor_trap();
}

pub export fn supervisorTrap(
    cause: usize,
    epc: usize,
    tval: usize,
) noreturn {
    uart.puts("\nS-mode trap\n");

    uart.puts("scause = ");
    uart.putHex(cause);
    uart.putc('\n');

    uart.puts("sepc   = ");
    uart.putHex(epc);
    uart.putc('\n');

    uart.puts("stval  = ");
    uart.putHex(tval);
    uart.putc('\n');

    while (true) {}
}

// ABI : a0 = TrapFrame, a1 = scause, a2 = stval
pub export fn trapDispatch(
    tf: *TrapFrame,
    scause: usize,
    stval: usize,
) *TrapFrame {
    switch (scause) {
        EXC_ECALL_U => {
            tf.a0 = syscall.dispatch(
                tf.a7,
                tf.a0,
                tf.a1,
                tf.a2,
                tf.a3,
                tf.a4,
                tf.a5,
            );

            tf.sepc += 4;
            return tf;
        },

        EXC_ILLEGAL_INSTRUCTION => {
            uart.puts("Illegal instruction from U-mode");
            uart.putc('\n');
            while (true) {}
            unreachable;
        },

        else => {
            uart.puts("Unexpected U-mode trap\n");
            uart.puts("scause = ");
            uart.putHex(scause);
            uart.putc('\n');

            uart.puts("sepc   = ");
            uart.putHex(tf.sepc);
            uart.putc('\n');

            uart.puts("stval  = ");
            uart.putHex(stval);
            uart.putc('\n');

            while (true) {}
            unreachable;
        },
    }
}
