const std = @import("std");
const trap = @import("trap.zig");
const mem = @import("memory.zig");

pub const Pid = u32;

pub const INVALID_PID = 0;
pub const MAX_PROCESSES: usize = 16;

var process_table: [MAX_PROCESSES]Process = undefined;
var next_pid: Pid = 1;

pub var current_process: ?*Process = null;

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

pub const KernelStack = struct {
    base: usize,
    top: usize,
};

pub const Process = struct {
    pid: Pid,
    state: State,
    trap_frame: trap.TrapFrame,
    context: Context,
    kernel_stack: KernelStack,
};

pub fn initUnused() Process {
    return .{
        .pid = INVALID_PID,
        .state = .unused,
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
    current_process = null;
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

    return p;
}
