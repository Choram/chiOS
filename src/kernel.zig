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
    // _ = root;

    // initialize process
    process.init();

    const user_a = [_]u32{
        0x04100513, // li a0, 'A'
        0x00100893, // li a7, SYS_PUTC
        0x00000073, // ecall
        0x00300893, // li a7, SYS_YIELD
        0x00000073, // ecall
        0xfedff06f, // j loop
    };

    const user_b = [_]u32{
        0x04200513, // li a0, 'B'
        0x00100893, // li a7, SYS_PUTC
        0x00000073, // ecall
        0x00300893, // li a7, SYS_YIELD
        0x00000073, // ecall
        0xfedff06f, // j loop
    };

    const a = makeTestProcess(
        root,
        &user_a,
        0x0040_0000,
        0x8000_0000,
        0,
    ) orelse {
        uart.puts("Cannot create process A\n");
        while (true) {}
    };

    const b = makeTestProcess(
        root,
        &user_b,
        0x0040_1000,
        0x7fff_f000,
        0,
    ) orelse {
        uart.puts("Cannot create process B\n");
        while (true) {}
    };

    scheduler.enqueue(a);
    scheduler.enqueue(b);

    scheduler.start();

    while (true) {}
}



// This is also a temporary test helper function
fn makeTestProcess(
    root: *sv32.PageTable,
    code: []const u32,
    user_entry: usize,
    user_stack_top: usize,
    priority: process.Priority,
) ?*process.Process {
    const code_size = code.len * @sizeOf(u32);
    if (code_size > PAGE_SIZE) {
        uart.puts("TEST: user code too large\n");
        return null;
    }

    if (user_entry % PAGE_SIZE != 0) {
        uart.puts("TEST: unaligned user entry\n");
        return null;
    }

    if (user_stack_top % PAGE_SIZE != 0) {
        uart.puts("TEST: unaligned user stack\n");
        return null;
    }

    if (priority > process.PRIORITY_LOWEST) {
        uart.puts("TEST: invalud priority\n");
        return null;
    }

    const code_pa = mem.allocPage() orelse {
        uart.puts("TEST: cannot allocate user code page\n");
        return null;
    };

    const code_page: [*]u8 = @ptrFromInt(code_pa);
    const code_bytes = std.mem.sliceAsBytes(code);

    @memset(code_page[0..PAGE_SIZE], 0);
    @memcpy(code_page[0..code_bytes.len], code_bytes);

    const code_flags = sv32.PTE_R | sv32.PTE_X | sv32.PTE_U;
    if (!sv32.mapPage(
        root,
        user_entry,
        code_pa,
        code_flags,
    )) {
        uart.puts("TEST: cannot map user code\n");
        return null;
    }

    const stack_pa = mem.allocPage() orelse {
        uart.puts("TEST: cannot allocate user stack page\n");
        return null;
    };

    const stack_page: [*]u8 = @ptrFromInt(stack_pa);
    @memset(stack_page[0..PAGE_SIZE], 0);

    const stack_flags = sv32.PTE_R | sv32.PTE_W | sv32.PTE_U;

    if(!sv32.mapPage(
        root,
        user_stack_top - PAGE_SIZE,
        stack_pa,
        stack_flags,
    )) {
        uart.puts("TEST: cannot map user stack\n");
        return null;
    }

    sv32.sfenceVma();

    const p = process.create(
        user_entry,
        user_stack_top,
        priority,
    ) orelse {
        uart.puts("TEST: cannot create process\n");
        return null;
    };

    scheduler.prepareProcess(p);
    return p;
}
