const std = @import("std");

const fdt = @import("fdt.zig");
const mem = @import("memory.zig");
const sv32 = @import("sv32.zig");
const trap = @import("trap.zig");
const uart = @import("uart.zig");
const process = @import("process.zig");
const scheduler = @import("scheduler.zig");

const PAGE_SIZE: usize = mem.PAGE_SIZE;

extern var __kernel_end: u8;
extern fn install_supervisor_trap() void;

export fn kernelMain(hart_id: usize, fdt_ptr: usize) noreturn {
    _ = hart_id;

    // initialize trap
    trap.init();

    uart.puts("Kernel OK\n");

    // read FDT data and extract the essentials
    const fdt_size = fdt.totalSize(fdt_ptr) orelse {
        uart.puts("Invalid FDT\n");
        while (true) {}
    };

    const ram = fdt.findMemory(fdt_ptr) orelse {
        uart.puts("Memory not found\n");
        while (true) {}
    };

    const kernel_end = @intFromPtr(&__kernel_end);

    uart.puts("RAM base : ");
    uart.putHex(ram.base);
    uart.putc('\n');

    uart.puts("RAM size : ");
    uart.putHex(ram.size);
    uart.putc('\n');

    // set the Region of memory that we are going to protect
    // Like: kernel region and FDT region
    const reserved = [_]mem.Region{
        .{
            .start = ram.base,
            .end = kernel_end,
        },
        .{
            .start = fdt_ptr,
            .end = fdt_ptr + fdt_size,
        },
    };

    // initialize the memory
    mem.init(ram.base, ram.size, &reserved);
    uart.puts("Physical memory initialization OK\n");
    uart.puts("Pages : ");
    uart.putDec(mem.freePageCount());
    uart.putc('\n');

    // initialize SV32
    const root = sv32.init(ram) orelse {
        while (true) {}
    };

    // no use right now
    _ = root;

    // initialize process
    process.init();

    if (!scheduler.contextSwitchSelfTest()) {
        @panic("context switch self-test failed");
    }

    uart.puts("context switch OK\n");

    while (true) {}
}
