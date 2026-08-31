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
extern fn enable_sv32(root_pa: usize) void;
extern fn install_supervisor_trap() void;

export fn kernelMain(hart_id: usize, fdt_ptr: usize) noreturn {
    _ = hart_id;

    trap.init();

    uart.puts("Kernel OK\n");

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

    mem.init(ram.base, ram.size, &reserved);
    uart.puts("Physical memory initialization OK\n");
    uart.puts("Pages : ");
    uart.putDec(mem.freePageCount());
    uart.putc('\n');

    const root = sv32.createRoot() orelse {
        uart.puts("Cannot allocate root page table\n");
        while (true) {}
    };

    uart.puts("Root page table OK\n");

    const root_pa = @intFromPtr(root);

    uart.puts("Root page table: ");
    uart.putHex(root_pa);
    uart.putc('\n');

    const ram_flag: usize = sv32.PTE_R | sv32.PTE_W | sv32.PTE_X;
    if (!sv32.identityMapRange(root, ram.base, ram.size, ram_flag)) {
        uart.puts("RAM mapping failed\n");
        while (true) {}
    }

    uart.puts("RAM mapping OK\n");

    const uart_flag: usize = sv32.PTE_R | sv32.PTE_W;
    if (!sv32.identityMapRange(root, uart.UART_BASE, mem.PAGE_SIZE, uart_flag)) {
        uart.puts("UART mapping failed\n");
        while (true) {}
    }

    uart.puts("UART mapping OK\n");

    uart.puts("Enabling Sv32...\n");

    enable_sv32(root_pa);

    uart.puts("Sv32 OK\n");

    process.init();

    if (!scheduler.contextSwitchSelfTest()) {
        @panic("context switch self-test failed");
    }

    uart.puts("context switch OK\n");

    while (true) {}
}
