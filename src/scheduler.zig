const std = @import("std");
const process = @import("process.zig");
const trap = @import("trap.zig");

const Process = process.Process;

pub const weights = [_]u32{ 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1 };

const RunQueue = struct {
    head: ?*Process = null,
    tail: ?*Process = null,
    count: usize = 0,
};

const Candidate = struct {
    queue: usize,
    current: i32,
};

extern fn context_switch(
    old: *process.Context,
    new: *const process.Context,
) void;

pub fn switchContext(
    old: *process.Context,
    new: *const process.Context,
) void {
    context_switch(old, new);
}

// ready queue
var ready: [process.PRIORITY_COUNT]RunQueue = [_]RunQueue{.{}} ** process.PRIORITY_COUNT;

// calculate current value
var current: [process.PRIORITY_COUNT]i32 = [_]i32{0} ** process.PRIORITY_COUNT;

// current process
var current_process: ?*Process = null;

var scheduler_context: process.Context = undefined;
var bootstrap_context: process.Context = undefined;

// stack for scheduler (yeah we need that)
const SCHEDULER_STACK_SIZE: usize = 4096;
var scheduler_stack: [SCHEDULER_STACK_SIZE]u8 align(16) = undefined;

fn pushBack(queue: *RunQueue, p: *Process) void {
    p.run_next = null;
    if (queue.tail) |tail| {
        tail.run_next = p;
    } else {
        queue.head = p;
    }

    queue.tail = p;
    queue.count += 1;
}

fn popFront(queue: *RunQueue) ?*Process {
    const p = queue.head orelse return null;

    queue.head = p.run_next;

    if (queue.head == null) {
        queue.tail = null;
    }

    p.run_next = null;
    queue.count -= 1;

    return p;
}

pub fn enqueue(p: *Process) void {
    std.debug.assert(p.state == .ready);
    std.debug.assert(p.priority <= process.PRIORITY_LOWEST);
    const index: usize = @intCast(p.priority);
    pushBack(&ready[index], p);
}

// Modified SWRR :3
pub fn pickNext() ?*Process {
    var total_weight: i32 = 0;
    var best: ?Candidate = null;

    for (&ready, 0..) |*queue, p| {
        if (queue.count == 0) {
            current[p] = 0;
            continue;
        }

        const class_weight: i32 = @intCast(queue.count * weights[p]);
        total_weight += class_weight;
        current[p] += class_weight;

        if (best == null or current[p] > best.?.current) {
            best = .{
                .queue = p,
                .current = current[p],
            };
        }
    }

    const selected = best orelse return null;
    current[selected.queue] -= total_weight;
    const next = popFront(&ready[selected.queue]).?;
    next.state = .running;
    return next;
}

// stack grows top-down
fn schedulerStackTop() usize {
    return @intFromPtr(&scheduler_stack) + scheduler_stack.len;
}

// make Context
// if the process is not processed before, there is no context;
// hence we need to initialize
fn initSchedulerContext() void {
    scheduler_context = std.mem.zeroes(process.Context);
    scheduler_context.sp = schedulerStackTop();
    scheduler_context.ra = @intFromPtr(&schedulerLoop);
}

fn schedulerLoop() noreturn {
    while (true) {
        const next = pickNext() orelse { continue; };
        current_process = next;
        switchContext(&scheduler_context, &next.context);
    }
}

// new process does not have
// Process.Context.ra = "kernel address that has been terminated before"
// Hence we need to make "fake" kernel address, processBootstrap()
fn processBootstrap() noreturn {
    const p = current_process orelse @panic("no current process");
    trap.enterUser(&p.trap_frame);
}

pub fn prepareProcess(p: *Process) void {
    p.context = std.mem.zeroes(process.Context);
    p.context.sp = p.kernel_stack.top;
    p.context.ra = @intFromPtr(&processBootstrap);
}

pub fn start() noreturn {
    initSchedulerContext();
    switchContext(&bootstrap_context, &scheduler_context);
    unreachable;
}



// this is temporary test helper function; I'll delete them later
var context_test_hit: bool = false;

fn contextSwitchTestEntry() noreturn {
    context_test_hit = true;
    switchContext(&scheduler_context, &bootstrap_context);
    unreachable;
}

pub fn contextSwitchSelfTest() bool {
    context_test_hit = false;
    scheduler_context = std.mem.zeroes(process.Context);
    scheduler_context.sp = schedulerStackTop();
    scheduler_context.ra = @intFromPtr(&contextSwitchTestEntry);
    switchContext(&bootstrap_context, &scheduler_context);
    return context_test_hit;
}
