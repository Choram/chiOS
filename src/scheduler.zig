const std = @import("std");
const process = @import("process.zig");

const Process = process.Process;

pub const weights = [_]u32{ 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1 };

const RunQueue = struct {
    head: ?*Process = null,
    tail: ?*Process = null,
    count: usize = 0,
};

// ready queue
var ready: [process.PRIORITY_COUNT]RunQueue = [_]RunQueue{.{}} ** process.PRIORITY_COUNT;

// calculate current value
var current: [process.PRIORITY_COUNT]i32 = [_]i32{0} ** process.PRIORITY_COUNT;

pub fn enquene(p: *Process) void {
    std.debug.assert(p.state == .ready);
    std.debug.assert(p.priority <= process.PRIORITY_LOWEST);
    const index: usize = @intCast(p.priority);

    // pick the queue of priority of the process
    var queue = &ready[index];
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

pub fn pickNext() ?*Process {
    var total_weight: i32 = 0;
    var selected: ?usize = null;
    var selected_current: i32 = 0;

    for (&ready, 0..) |*queue, p| {
        if (queue.count == 0) {
            current[p] = 0;
            continue;
        }

        const class_weight: i32 = @intCast(queue.count * weights[p]);
        total_weight += class_weight;
        current[p] += class_weight;

        if (selected == null or current[p] > selected_current) {
            selected = p;
            selected_current = current[p];
        }
    }

    const q = selected orelse return null;
    current[q] -= total_weight;
    const next = popFront(&ready[q]).?;
    next.state = .running;
    return next;
}
