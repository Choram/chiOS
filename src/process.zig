const std = @import("std");
const trap = @import("trap.zig");
const mem = @import("memory.zig");

pub const Pid = u32;

pub const INVALID_PID = 0;
pub const MAX_PROCESSES: usize = 16;

pub const Priority = u8;
pub const PRIORITY_COUNT: usize = 16;
pub const PRIORITY_HIGHEST: Priority = 0;
pub const PRIORITY_LOWEST: Priority = 15;

var process_table: [MAX_PROCESSES]Process = undefined;
var next_pid: Pid = 1;

const PAGE_SIZE = mem.PAGE_SIZE;

pub const State = enum {
    unused,
    ready,
    running,
    blocked,
    exited,
};

pub const Context = extern struct {
    ra: usize,
    sp: usize,

    s0: usize,
    s1: usize,
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
};

comptime {
    if (@offsetOf(Context, "ra") != 0) @compileError("bad Context.ra offset");
    if (@offsetOf(Context, "sp") != 4) @compileError("bad Context.sp offset");
    if (@offsetOf(Context, "s0") != 8) @compileError("bad Context.s0 offset");
    if (@offsetOf(Context, "s1") != 12) @compileError("bad Context.s1 offset");
    if (@offsetOf(Context, "s2") != 16) @compileError("bad Context.s2 offset");
    if (@offsetOf(Context, "s3") != 20) @compileError("bad Context.s3 offset");
    if (@offsetOf(Context, "s4") != 24) @compileError("bad Context.s4 offset");
    if (@offsetOf(Context, "s5") != 28) @compileError("bad Context.s5 offset");
    if (@offsetOf(Context, "s6") != 32) @compileError("bad Context.s6 offset");
    if (@offsetOf(Context, "s7") != 36) @compileError("bad Context.s7 offset");
    if (@offsetOf(Context, "s8") != 40) @compileError("bad Context.s8 offset");
    if (@offsetOf(Context, "s9") != 44) @compileError("bad Context.s9 offset");
    if (@offsetOf(Context, "s10") != 48) @compileError("bad Context.s10 offset");
    if (@offsetOf(Context, "s11") != 52) @compileError("bad Context.s11 offset");

    if (@sizeOf(Context) != 56) @compileError("bad Context size");
}

pub const KernelStack = struct {
    base: usize,
    top: usize,
};

pub const Process = struct {
    pid: Pid,
    state: State,
    priority: Priority,
    run_next: ?*Process,
    trap_frame: trap.TrapFrame,
    context: Context,
    kernel_stack: KernelStack,
};

pub fn initUnused() Process {
    return .{
        .pid = INVALID_PID,
        .state = .unused,
        .priority = PRIORITY_LOWEST,
        .run_next = null,
        .trap_frame = std.mem.zeroes(trap.TrapFrame),
        .context = std.mem.zeroes(Context),
        .kernel_stack = .{
            .base = 0,
            .top = 0,
        },
    };
}

pub fn init() void {
    for (&process_table) |*p| {
        p.* = initUnused();
    }

    next_pid = 1;
}

fn findUnusedSlot() ?*Process {
    for (&process_table) |*p| {
        if (p.state == .unused) {
            return p;
        }
    }

    return null;
}

fn allocatePid() Pid {
    const pid = next_pid;
    next_pid += 1;
    return pid;
}

fn allocKernelStack() ?KernelStack {
    const base = mem.allocPage() orelse return null;

    return .{
        .base = base,
        .top = base + PAGE_SIZE,
    };
}

pub fn create(
    user_entry: usize,
    user_stack_top: usize,
    priority: Priority,
) ?*Process {
    const p = findUnusedSlot() orelse return null;
    const kernel_stack = allocKernelStack() orelse return null;

    p.* = initUnused();
    p.pid = allocatePid();
    p.kernel_stack = kernel_stack;
    p.trap_frame.kernel_sp = kernel_stack.top;
    p.trap_frame.kernel_trap = @intFromPtr(&trap.trapDispatch);
    p.trap_frame.sepc = user_entry;
    p.trap_frame.sstatus = 0;
    p.trap_frame.sp = user_stack_top;

    p.state = .ready;

    p.priority = priority;

    return p;
}
