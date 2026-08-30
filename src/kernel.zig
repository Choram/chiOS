const std = @import("std");

const fdt = @import("fdt.zig");
const mem = @import("memory.zig");
const sv32 = @import("sv32.zig");
const trap = @import("trap.zig");
const uart = @import("uart.zig");
const process = @import("process.zig");

const PAGE_SIZE: usize = mem.PAGE_SIZE;

extern var __kernel_end: u8;
extern fn enable_sv32(root_pa: usize) void;
extern fn install_supervisor_trap() void;
extern fn enter_user(tf: *trap.TrapFrame) noreturn;

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

    const USER_CODE_VA: usize = 0x0040_0000;
    const USER_STACK_TOP: usize = 0x0080_0000;
    const USER_STACK_VA: usize = USER_STACK_TOP - PAGE_SIZE;

    const p = process.create(
        USER_CODE_VA,
        USER_STACK_TOP,
    ) orelse @panic("failed to create process");

    process.current_process = p;
    p.state = .running;

    const user_code_pa =
        mem.allocPage() orelse @panic("failed to allocate user code page");
    const user_stack_pa =
        mem.allocPage() orelse @panic("failed to allocate user stack page");

    if (!sv32.mapPage(
        root,
        USER_CODE_VA,
        user_code_pa,
        sv32.PTE_R | sv32.PTE_X | sv32.PTE_U,
    )) {
        @panic("failed to map user code");
    }

    if (!sv32.mapPage(
        root,
        USER_STACK_VA,
        user_stack_pa,
        sv32.PTE_R | sv32.PTE_W | sv32.PTE_U,
    )) {
        @panic("failed to map user stack");
    }

    sv32.sfenceVma();

    const code: [*]volatile u32 = @ptrFromInt(user_code_pa);
    code[0] = 0x0410_0513; // addi a0, zero, 65   ; a0 = 'A'
    code[1] = 0x0010_0893; // addi a7, zero, 1    ; SYS_PUTC
    code[2] = 0x0000_0073; // ecall

    code[3] = 0x02a0_0513; // addi a0, zero, 42   ; exit status = 42
    code[4] = 0x0020_0893; // addi a7, zero, 2    ; SYS_EXIT
    code[5] = 0x0000_0073; // ecall

    code[6] = 0xffff_ffff; // should never be reached

    uart.puts("Entering U-mode... \n");
    enter_user(&p.trap_frame);
    unreachable;

    // while (true) {}
}
